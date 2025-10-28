import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';
import '../utils/auto_select_util.dart';
import '../utils/app_localizations.dart';

class ConnectionButton extends StatefulWidget {
  const ConnectionButton({Key? key}) : super(key: key);

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton> {
  // Cancellation token for auto-select operation
  AutoSelectCancellationToken? _autoSelectCancellationToken;

  // Stream controller for status updates
  late final StreamController<String> _autoSelectStatusStream =
      StreamController<String>.broadcast();

  @override
  void dispose() {
    _autoSelectStatusStream.close();
    super.dispose();
  }

  // Helper method to handle async selection and connection
  Future<void> _connectToFirstServer(V2RayProvider provider) async {
    if (provider.configs.isNotEmpty) {
      await provider.selectConfig(provider.configs.first);
      await provider.connectToServer(
        provider.configs.first,
        provider.isProxyMode,
      );
    }
  }

  // Helper method to run auto-select and then connect
  Future<void> _runAutoSelectAndConnect(
    BuildContext context,
    V2RayProvider provider,
  ) async {
    // Create cancellation token for this auto-select operation
    _autoSelectCancellationToken = AutoSelectCancellationToken();

    // Show a loading dialog while auto-select is running with cancel button
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        title: Text(context.tr(TranslationKeys.serverSelectionAutoSelect)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
            const SizedBox(height: 16),
            Text(context.tr(TranslationKeys.serverSelectionTestingServers)),
            const SizedBox(height: 8),
            StreamBuilder<String>(
              stream: _autoSelectStatusStream.stream,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Cancel the auto-select operation
              _autoSelectCancellationToken?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(
              context.tr('common.cancel'),
              style: const TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );

    try {
      // Run auto-select algorithm with cancellation support and status updates
      final result = await AutoSelectUtil.runAutoSelect(
        provider.configs,
        provider.v2rayService,
        (message) {
          // Update status in the dialog
          _autoSelectStatusStream.add(message);
        },
        cancellationToken: _autoSelectCancellationToken,
      );

      // Check if operation was cancelled
      if (result.errorMessage == 'Auto-select cancelled') {
        // Close the dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('common.cancel')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (result.selectedConfig != null && result.bestPing != null) {
        // Select and connect to the best server
        await provider.selectConfig(result.selectedConfig!);
        await provider.connectToServer(
          result.selectedConfig!,
          provider.isProxyMode,
        );
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Auto-select failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-select error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<V2RayProvider>(
      builder: (context, provider, _) {
        // Show loading state while initializing
        if (provider.isInitializing) {
          return Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.cardDark,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
              ),
            ),
          );
        }

        final isConnected = provider.activeConfig != null;
        final isConnecting = provider.isConnecting;
        final selectedConfig = provider.selectedConfig;

        return GestureDetector(
          onTap: () async {
            // Prevent multiple taps while connecting or initializing
            if (isConnecting || provider.isInitializing) {
              return;
            }

            try {
              if (isConnected) {
                await provider.disconnect();
              } else if (selectedConfig != null) {
                await provider.connectToServer(
                  selectedConfig,
                  provider.isProxyMode,
                );
              } else if (provider.configs.isNotEmpty) {
                // No server selected, run auto-select and then connect
                await _runAutoSelectAndConnect(context, provider);
              } else {
                // Show a message if no configs are available
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.tr(TranslationKeys.serverSelectorNoServers),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              // Show error message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${context.tr('home.connection_failed')}: ${e.toString()}',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _getButtonColor(
                    isConnected,
                    isConnecting,
                  ).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer animated ring (only visible when connecting)
                if (isConnecting)
                  Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.connectingBlue,
                            width: 3,
                          ),
                        ),
                      )
                      .animate(onPlay: (controller) => controller.repeat())
                      .scale(
                        duration: 1500.ms,
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1.1, 1.1),
                      )
                      .then()
                      .scale(
                        duration: 1500.ms,
                        begin: const Offset(1.1, 1.1),
                        end: const Offset(0.9, 0.9),
                      ),

                // Middle ring
                if (isConnecting)
                  Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.connectingBlue.withValues(
                              alpha: 0.7,
                            ),
                            width: 2,
                          ),
                        ),
                      )
                      .animate(onPlay: (controller) => controller.repeat())
                      .rotate(duration: 3000.ms, begin: 0, end: 1),

                // Main button
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _getGradientColors(isConnected, isConnecting),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _getButtonIcon(isConnected, isConnecting),
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getButtonColor(bool isConnected, bool isConnecting) {
    if (isConnecting) return AppTheme.connectingBlue;
    return isConnected ? AppTheme.connectedGreen : AppTheme.disconnectedRed;
  }

  List<Color> _getGradientColors(bool isConnected, bool isConnecting) {
    if (isConnecting) {
      return [
        AppTheme.connectingBlue,
        AppTheme.connectingBlue.withOpacity(0.7),
      ];
    } else if (isConnected) {
      return [
        AppTheme.connectedGreen,
        AppTheme.connectedGreen.withValues(alpha: 0.7),
      ];
    } else {
      return [
        AppTheme.disconnectedRed,
        AppTheme.disconnectedRed.withValues(alpha: 0.7),
      ];
    }
  }

  IconData _getButtonIcon(bool isConnected, bool isConnecting) {
    if (isConnecting) return Icons.hourglass_top;
    return isConnected ? Icons.power_settings_new : Icons.power_settings_new;
  }
}

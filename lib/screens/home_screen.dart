import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/v2ray_provider.dart';
import '../widgets/connection_button.dart';
import '../widgets/server_selector.dart';
import '../widgets/background_gradient.dart';
import '../widgets/error_snackbar.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import '../services/v2ray_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = ''; // Default to empty subscription URL
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _showAddLicenseDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add License'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your subscription URL:'),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Subscription URL (can be empty)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final provider = Provider.of<V2RayProvider>(
                    context,
                    listen: false,
                  );
                  final url = _urlController.text.trim();
                  
                  Navigator.pop(context);
                  
                  // Show a loading snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(url.isNotEmpty ? 'Adding subscription...' : 'Using default servers...'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  
                  try {
                    if (url.isNotEmpty) {
                      // Save the subscription URL to SharedPreferences as default
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('default_subscription_url', url);
                      
                      // Remove all existing subscriptions and their configs
                      for (var subscription in provider.subscriptions) {
                        await provider.removeSubscription(subscription);
                      }
                      
                      // Add subscription with URL
                      await provider.addSubscription('Default Subscription', url);
                      
                      // Check if there was an error
                      if (provider.errorMessage.isNotEmpty) {
                        ErrorSnackbar.show(context, provider.errorMessage);
                        provider.clearError();
                      }
                    } else {
                      // Use default URL if empty
                      await provider.fetchServers();
                      
                      // Check if there was an error
                      if (provider.errorMessage.isNotEmpty) {
                        ErrorSnackbar.show(context, provider.errorMessage);
                        provider.clearError();
                      }
                    }
                  } catch (e) {
                    ErrorSnackbar.show(context, 'Error: ${e.toString()}');
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundGradient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Proxy Cloud'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                final provider = Provider.of<V2RayProvider>(
                  context,
                  listen: false,
                );
                provider.fetchServers();
                provider.fetchNotificationStatus();
              },
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.vpn_key),
              onPressed: () {
                _showAddLicenseDialog(context);
              },
              tooltip: 'Add License',
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
              tooltip: 'About',
            ),
          ],
        ),
        body: Column(
          children: [
            // Connection status removed as requested

            // Main content
            Expanded(
              child: Consumer<V2RayProvider>(
                builder: (context, provider, _) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Server selector
                          const ServerSelector(),

                          const SizedBox(height: 40),

                          // Connection button
                          const ConnectionButton(),

                          const SizedBox(height: 40),

                          // Connection stats
                          if (provider.activeConfig != null)
                            _buildConnectionStats(provider),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStats(V2RayProvider provider) {
    // Get the V2RayService instance
    final v2rayService = provider.v2rayService;

    // Use StreamBuilder to update the UI when statistics change
    return StreamBuilder(
      // Create a periodic stream to update the UI every second
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final ipInfo = v2rayService.ipInfo;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connection Statistics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildStatRow(
                Icons.timer,
                'Connected Time',
                v2rayService.getFormattedConnectedTime(),
              ),
              const Divider(height: 24),
              if (v2rayService.isLoadingIpInfo)
                _buildLoadingIpInfoRow()
              else if (ipInfo != null && ipInfo.success)
                _buildIpInfoRow(ipInfo)
              else
                _buildIpErrorRow(
                  'IP Information',
                  ipInfo?.errorMessage ?? 'cant get ip',
                  () async {
                    // Retry fetching IP info
                    await v2rayService.fetchIpInfo();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildIpInfoRow(IpInfo ipInfo) {
    return Row(
      children: [
        ipInfo.flagUrl.isNotEmpty
            ? Image.network(
                ipInfo.flagUrl,
                width: 24,
                height: 24,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.public, size: 18, color: AppTheme.textGrey);
                },
              )
            : const Icon(Icons.public, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${ipInfo.country} - ${ipInfo.ip}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppTheme.textGrey)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryGreen,
          ),
        ),
      ],
    );
  }
  
  Widget _buildIpErrorRow(String label, String errorMessage, VoidCallback onRetry) {
    return Row(
      children: [
        const Icon(Icons.public, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppTheme.textGrey)),
        const Spacer(),
        Text(
          errorMessage,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              Icons.refresh,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildLoadingIpInfoRow() {
    return Row(
      children: [
        const Icon(Icons.public, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 12),
        const Text('IP Information', style: TextStyle(color: AppTheme.textGrey)),
        const Spacer(),
        const Text(
          'Fetching...',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

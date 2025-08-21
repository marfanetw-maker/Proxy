import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/v2ray_service.dart';
import 'package:flutter/foundation.dart';

class PerAppTunnelScreen extends StatefulWidget {
  const PerAppTunnelScreen({super.key});

  @override
  State<PerAppTunnelScreen> createState() => _PerAppTunnelScreenState();
}

class AppInfo {
  final String packageName;
  final String name;
  final bool isSystemApp;

  AppInfo({
    required this.packageName,
    required this.name,
    required this.isSystemApp,
  });
}

class _PerAppTunnelScreenState extends State<PerAppTunnelScreen> {
  final V2RayService _v2rayService = V2RayService();
  List<AppInfo> _availableApps = [];
  List<String> _selectedApps = []; // Selected apps will be tunneled
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterApps(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_availableApps);
      } else {
        _filteredApps = _availableApps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(query.toLowerCase()) ||
                  app.packageName.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load saved blocked apps (existing storage)
      final prefs = await SharedPreferences.getInstance();
      final savedBlockedApps = prefs.getStringList('blocked_apps') ?? [];

      // Get available apps from device
      if (defaultTargetPlatform == TargetPlatform.android) {
        final apps = await _v2rayService.getInstalledApps();

        // Convert the raw data to AppInfo objects
        List<AppInfo> appInfoList = [];

        final appsList = apps as List<dynamic>? ?? [];
        for (var app in appsList) {
          final appMap = app as Map<String, dynamic>? ?? {};
          appInfoList.add(
            AppInfo(
              name: appMap['name'] ?? 'Unknown',
              packageName: appMap['packageName'] ?? '',
              isSystemApp: appMap['isSystemApp'] ?? false,
            ),
          );
        }

        // For "per-app tunnel": selected apps = available - blocked
        final allPackages = appInfoList.map((a) => a.packageName).toSet();
        final blockedSet = savedBlockedApps.toSet();
        final selectedSet = allPackages.difference(blockedSet);

        setState(() {
          _availableApps = appInfoList;
          _filteredApps = List.from(appInfoList);
          _selectedApps = selectedSet.toList();
          _isLoading = false;
        });
      } else {
        // Non-Android platforms
        setState(() {
          _availableApps = [];
          _filteredApps = [];
          // No apps available; default to empty selection
          _selectedApps = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load apps: $e')));
      }
    }
  }

  Future<void> _savePerAppTunnel() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Inverse logic: blocked = allPackages - selected
      final allPackages = _availableApps.map((a) => a.packageName).toSet();
      final selectedSet = _selectedApps.toSet();
      final blockedSet = allPackages.difference(selectedSet);
      final blockedList = blockedSet.where((p) => p.isNotEmpty).toList();

      // If nothing should be blocked, remove key
      if (blockedList.isEmpty) {
        await prefs.remove('blocked_apps');
      } else {
        await prefs.setStringList('blocked_apps', blockedList);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedApps.isEmpty
                  ? 'All apps are blocked from tunnel'
                  : 'Per-app tunnel updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save per-app tunnel: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        title: const Text('Per-App Tunnel'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          // Select all button
          if (_availableApps.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all apps (tunnel all) ',
              onPressed: () {
                setState(() {
                  _selectedApps = _availableApps
                      .map((e) => e.packageName)
                      .toList();
                });
              },
            ),
          // Clear selection button
          if (_selectedApps.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all selections (block all)',
              onPressed: () {
                setState(() {
                  _selectedApps = [];
                });
              },
            ),
          TextButton(
            onPressed: _savePerAppTunnel,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    'Select apps to use the VPN tunnel. Unselected apps will be blocked.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterApps,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search apps...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white70,
                      ),
                      filled: true,
                      fillColor: AppTheme.secondaryDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredApps.isEmpty
                      ? const Center(
                          child: Text(
                            'No apps found',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredApps.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: Color(0xFF323232),
                          ),
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
                            final isSelected = _selectedApps.contains(
                              app.packageName,
                            );
                            return ListTile(
                              title: Text(
                                app.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                app.packageName,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: Checkbox(
                                value: isSelected,
                                activeColor: AppTheme.primaryGreen,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      if (!_selectedApps.contains(
                                        app.packageName,
                                      )) {
                                        _selectedApps.add(app.packageName);
                                      }
                                    } else {
                                      _selectedApps.remove(app.packageName);
                                    }
                                  });
                                },
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedApps.remove(app.packageName);
                                  } else {
                                    _selectedApps.add(app.packageName);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

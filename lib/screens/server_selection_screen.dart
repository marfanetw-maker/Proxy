import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/v2ray_config.dart';
import '../models/subscription.dart';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';

class ServerSelectionScreen extends StatefulWidget {
  final List<V2RayConfig> configs;
  final V2RayConfig? selectedConfig;
  final bool isConnecting;
  final Future<void> Function(V2RayConfig) onConfigSelected;

  const ServerSelectionScreen({
    Key? key,
    required this.configs,
    required this.selectedConfig,
    required this.isConnecting,
    required this.onConfigSelected,
  }) : super(key: key);

  @override
  State<ServerSelectionScreen> createState() => _ServerSelectionScreenState();
}

class _ServerSelectionScreenState extends State<ServerSelectionScreen> {
  String _selectedFilter = 'All';
  
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    final subscriptions = provider.subscriptions;
    
    // Create filter options: All, Default, and subscription names
    final List<String> filterOptions = ['All', 'Default'];
    for (var sub in subscriptions) {
      filterOptions.add(sub.name);
    }
    
    // Filter configs based on selected filter
    List<V2RayConfig> filteredConfigs = [];
    if (_selectedFilter == 'All') {
      filteredConfigs = widget.configs;
    } else if (_selectedFilter == 'Default') {
      // Default configs are those not in any subscription
      final allSubscriptionConfigIds = subscriptions
          .expand((sub) => sub.configIds)
          .toSet();
      filteredConfigs = widget.configs
          .where((config) => !allSubscriptionConfigIds.contains(config.id))
          .toList();
    } else {
      // Find the subscription with the matching name
      final subscription = subscriptions.firstWhere(
        (sub) => sub.name == _selectedFilter,
        orElse: () => Subscription(id: '', name: '', url: '', lastUpdated: DateTime.now(), configIds: []),
      );
      
      // Get configs that belong to this subscription
      filteredConfigs = widget.configs
          .where((config) => subscription.configIds.contains(config.id))
          .toList();
    }
    
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        title: const Text('Select Server'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                // Show loading indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Updating servers...'), duration: Duration(seconds: 1)),
                );
                
                if (_selectedFilter == 'All') {
                  // Update all subscriptions when 'All' is selected
                  await provider.updateAllSubscriptions();
                } else if (_selectedFilter != 'Default') {
                  // Update individual subscription
                  final subscription = subscriptions.firstWhere(
                    (sub) => sub.name == _selectedFilter,
                    orElse: () => Subscription(id: '', name: '', url: '', lastUpdated: DateTime.now(), configIds: []),
                  );
                  
                  if (subscription.id.isNotEmpty) {
                    await provider.updateSubscription(subscription);
                  }
                }
                
                // Refresh the UI to show updated server list
                setState(() {});
                
                // Always check if there was an error
                if (provider.errorMessage.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.errorMessage),
                      backgroundColor: Colors.red.shade700,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  provider.clearError();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Servers updated successfully')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating servers: ${e.toString()}')),
                );
              }
            },
            tooltip: 'Update Servers',
          ),
        ],
      ),
      body: Column(
        children: [
          // Subscription filter
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: filterOptions.length,
              itemBuilder: (context, index) {
                final filter = filterOptions[index];
                final isSelected = _selectedFilter == filter;
                
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 16 : 8,
                    right: index == filterOptions.length - 1 ? 16 : 0,
                  ),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFilter = filter;
                        });
                      }
                    },
                    backgroundColor: AppTheme.cardDark,
                    selectedColor: AppTheme.primaryGreen,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          
          Expanded(
            child: filteredConfigs.isEmpty
                ? Center(
                    child: Text(
                      'No servers available for ${_selectedFilter}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredConfigs.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemBuilder: (context, index) {
                      final config = filteredConfigs[index];
                      final isSelected = widget.selectedConfig?.id == config.id;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: AppTheme.cardDark,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: widget.isConnecting
                        ? null
                        : () async {
                            // Get the provider to check connection status
                            final provider = Provider.of<V2RayProvider>(context, listen: false);
                            
                            // Check if already connected to VPN
                            if (provider.activeConfig != null) {
                              // Show popup to inform user to disconnect first
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: AppTheme.secondaryDark,
                                  title: const Text('Connection Active'),
                                  content: const Text('Please disconnect from VPN before selecting a different server.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK', style: TextStyle(color: AppTheme.primaryGreen)),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              // Not connected, proceed with selection
                              await widget.onConfigSelected(config);
                              Navigator.pop(context);
                            }
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? AppTheme.primaryGreen : AppTheme.textGrey,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config.remark,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${config.address}:${config.port}',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getConfigTypeColor(config.configType).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        config.configType.toUpperCase(),
                                        style: TextStyle(
                                          color: _getConfigTypeColor(config.configType),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _getSubscriptionName(config),
                                        style: const TextStyle(
                                          color: Colors.blueGrey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: isSelected ? AppTheme.primaryGreen : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfigTypeColor(String configType) {
    switch (configType.toLowerCase()) {
      case 'vmess':
        return Colors.blue;
      case 'vless':
        return Colors.purple;
      case 'shadowsocks':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  
  String _getSubscriptionName(V2RayConfig config) {
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    final subscriptions = provider.subscriptions;
    
    // Find which subscription this config belongs to
    String subscriptionName = 'Default';
    for (var subscription in subscriptions) {
      if (subscription.configIds.contains(config.id)) {
        subscriptionName = subscription.name;
        break;
      }
    }
    
    return subscriptionName;
  }
}

// Function to show the server selection screen
void showServerSelectionScreen({
  required BuildContext context,
  required List<V2RayConfig> configs,
  required V2RayConfig? selectedConfig,
  required bool isConnecting,
  required Future<void> Function(V2RayConfig) onConfigSelected,
}) {
  // Get the provider to check connection status
  final provider = Provider.of<V2RayProvider>(context, listen: false);
  
  // Check if already connected to VPN
  if (provider.activeConfig != null) {
    // Show popup to inform user to disconnect first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        title: const Text('Connection Active'),
        content: const Text('Please disconnect from VPN before selecting a different server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppTheme.primaryGreen)),
          ),
        ],
      ),
    );
    return; // Don't show the selection screen
  }
  
  // Not connected, navigate to server selection screen
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ServerSelectionScreen(
        configs: configs,
        selectedConfig: selectedConfig,
        isConnecting: isConnecting,
        onConfigSelected: onConfigSelected,
      ),
    ),
  );
}
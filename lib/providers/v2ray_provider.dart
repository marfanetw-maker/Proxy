import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import '../models/subscription.dart';
import '../services/v2ray_service.dart';
import '../services/server_service.dart';

class V2RayProvider with ChangeNotifier, WidgetsBindingObserver {
  final V2RayService _v2rayService = V2RayService();
  final ServerService _serverService = ServerService();
  
  List<V2RayConfig> _configs = [];
  List<Subscription> _subscriptions = [];
  V2RayConfig? _selectedConfig;
  bool _isConnecting = false;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isLoadingServers = false;

  List<V2RayConfig> get configs => _configs;
  List<Subscription> get subscriptions => _subscriptions;
  V2RayConfig? get selectedConfig => _selectedConfig;
  V2RayConfig? get activeConfig => _v2rayService.activeConfig;
  bool get isConnecting => _isConnecting;
  bool get isLoading => _isLoading;
  bool get isLoadingServers => _isLoadingServers;
  String get errorMessage => _errorMessage;
  V2RayService get v2rayService => _v2rayService;

  V2RayProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    _setLoading(true);
    try {
      await _v2rayService.initialize();
      
      // Set up callback for notification disconnects
      _v2rayService.setDisconnectedCallback(() {
        _handleNotificationDisconnect();
      });
      
      // Load subscriptions
      await loadSubscriptions();
      
      // Check if we have a default subscription URL saved
      final prefs = await SharedPreferences.getInstance();
      final defaultSubscriptionUrl = prefs.getString('default_subscription_url');
      
      if (defaultSubscriptionUrl != null && defaultSubscriptionUrl.isNotEmpty) {
        // If we have a default subscription URL, load it
        print('Loading default subscription URL: $defaultSubscriptionUrl');
        
        // If we don't have any subscriptions or the URL is different from existing ones
        bool shouldAddSubscription = true;
        
        if (_subscriptions.isNotEmpty) {
          // Check if we already have this subscription
          for (var subscription in _subscriptions) {
            if (subscription.url == defaultSubscriptionUrl) {
              // We already have this subscription, just update it
              await updateSubscription(subscription);
              shouldAddSubscription = false;
              break;
            }
          }
          
          // If we have other subscriptions but not this one, remove them and add this one
          if (shouldAddSubscription) {
            // Remove all existing subscriptions
            for (var subscription in List<Subscription>.from(_subscriptions)) {
              await removeSubscription(subscription);
            }
          }
        }
        
        // Add the default subscription if needed
        if (shouldAddSubscription) {
          await addSubscription('Default Subscription', defaultSubscriptionUrl);
        }
      } else {
        // If no default subscription URL, load servers from the default URL
        await fetchServers();
      }
      
      // Fetch the current notification status to sync with the app
      await fetchNotificationStatus();

      // If we have an active config and it's in the saved list, ensure its status is correct
      final activeConfig = _v2rayService.activeConfig;
      if (activeConfig != null) {
        for (var config in _configs) {
          if (config.fullConfig == activeConfig.fullConfig) {
            config.isConnected = true;
            _selectedConfig = config;
            break;
          }
        }
        
        // If we couldn't find the exact active config in our list,
        // try to find a matching one by address and port
        if (_selectedConfig == null && activeConfig != null) {
          for (var config in _configs) {
            if (config.address == activeConfig.address && 
                config.port == activeConfig.port) {
              config.isConnected = true;
              _selectedConfig = config;
              break;
            }
          }
        }
        
        notifyListeners();
      } else {
        // If no active config, try to load the last selected config
        final selectedConfig = await _v2rayService.loadSelectedConfig();
        if (selectedConfig != null) {
          // Find the matching config in our list
          for (var config in _configs) {
            if (config.fullConfig == selectedConfig.fullConfig) {
              _selectedConfig = config;
              break;
            }
          }
          
          // If we couldn't find the exact config, try to match by address and port
          if (_selectedConfig == null) {
            for (var config in _configs) {
              if (config.address == selectedConfig.address && 
                  config.port == selectedConfig.port) {
                _selectedConfig = config;
                break;
              }
            }
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      _setError('Failed to initialize: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadConfigs() async {
    _setLoading(true);
    try {
      _configs = await _v2rayService.loadConfigs();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load configurations: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  Future<void> fetchServers({String? customUrl}) async {
    _isLoadingServers = true;
    _errorMessage = '';
    notifyListeners();
    
    try {
      // Fetch servers from service
      final servers = await _serverService.fetchServers(customUrl: customUrl);
      
      if (servers.isNotEmpty) {
        // Load and display servers immediately
        _configs = servers;
        
        // Save configs and update UI immediately to show servers
        await _v2rayService.saveConfigs(_configs);
        
        // Mark loading as complete
        _isLoadingServers = false;
        notifyListeners();
        
        // Server delay functionality removed as requested
      } else {
        // If no servers found online, try to load from local storage
        _configs = await _v2rayService.loadConfigs();
      }
    } catch (e) {
      _setError('Failed to fetch servers: $e');
      // Try to load from local storage as fallback
      _configs = await _v2rayService.loadConfigs();
      notifyListeners();
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  Future<void> loadSubscriptions() async {
    _setLoading(true);
    try {
      _subscriptions = await _v2rayService.loadSubscriptions();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load subscriptions: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addConfig(V2RayConfig config) async {
    // Add config and display it immediately
    _configs.add(config);
    
    // Save the configuration immediately to display it
    await _v2rayService.saveConfigs(_configs);
    notifyListeners();
  }

  Future<void> removeConfig(V2RayConfig config) async {
    _configs.removeWhere((c) => c.id == config.id);
    
    // Also remove from subscriptions
    for (int i = 0; i < _subscriptions.length; i++) {
      final subscription = _subscriptions[i];
      if (subscription.configIds.contains(config.id)) {
        final updatedConfigIds = List<String>.from(subscription.configIds)
          ..remove(config.id);
        _subscriptions[i] = subscription.copyWith(configIds: updatedConfigIds);
      }
    }
    
    await _v2rayService.saveConfigs(_configs);
    await _v2rayService.saveSubscriptions(_subscriptions);
    notifyListeners();
  }

  Future<void> addSubscription(String name, String url) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      final configs = await _v2rayService.parseSubscriptionUrl(url);
      if (configs.isEmpty) {
        _setError('No valid configurations found in subscription');
        return;
      }
      
      // Add configs and display them immediately
      _configs.addAll(configs);
      
      // Save configs and update UI immediately to show servers
      await _v2rayService.saveConfigs(_configs);
      _setLoading(false);
      notifyListeners();
      
      final newConfigIds = configs.map((c) => c.id).toList();
      
      // Server delay functionality removed as requested
      
      // Save configs
      await _v2rayService.saveConfigs(_configs);
      
      // Create subscription
      final subscription = Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: url,
        lastUpdated: DateTime.now(),
        configIds: newConfigIds,
      );
      
      _subscriptions.add(subscription);
      await _v2rayService.saveSubscriptions(_subscriptions);
    } catch (e) {
      _setError('Failed to add subscription: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateSubscription(Subscription subscription) async {
    _setLoading(true);
    _isLoadingServers = true;
    _errorMessage = '';
    notifyListeners();
    
    try {
      final configs = await _v2rayService.parseSubscriptionUrl(subscription.url);
      if (configs.isEmpty) {
        _setError('No valid configurations found in subscription');
        _isLoadingServers = false;
        notifyListeners();
        return;
      }
      
      // Remove old configs
      _configs.removeWhere((c) => subscription.configIds.contains(c.id));
      
      // Add new configs and display them immediately
      _configs.addAll(configs);
      
      // Save configs and update UI immediately to show servers
      await _v2rayService.saveConfigs(_configs);
      
      // Mark loading as complete
      _isLoadingServers = false;
      _setLoading(false);
      notifyListeners();
      
      final newConfigIds = configs.map((c) => c.id).toList();
      
      // Update subscription
      final index = _subscriptions.indexWhere((s) => s.id == subscription.id);
      if (index != -1) {
        _subscriptions[index] = subscription.copyWith(
          lastUpdated: DateTime.now(),
          configIds: newConfigIds,
        );
        await _v2rayService.saveSubscriptions(_subscriptions);
      }
    } catch (e) {
      _setError('Failed to update subscription: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removeSubscription(Subscription subscription) async {
    // Remove configs associated with this subscription
    _configs.removeWhere((c) => subscription.configIds.contains(c.id));
    
    // Remove subscription
    _subscriptions.removeWhere((s) => s.id == subscription.id);
    
    await _v2rayService.saveConfigs(_configs);
    await _v2rayService.saveSubscriptions(_subscriptions);
    notifyListeners();
  }

  Future<void> connectToServer(V2RayConfig config) async {
    _isConnecting = true;
    _errorMessage = '';
    notifyListeners();
    
    try {
      // Disconnect from current server if connected
      if (_v2rayService.activeConfig != null) {
        await _v2rayService.disconnect();
      }
      
      // Connect to new server
      final success = await _v2rayService.connect(config);
      if (success) {
        // Wait for 3 seconds as requested
        await Future.delayed(const Duration(seconds: 3));
        
        // Update config status
        for (int i = 0; i < _configs.length; i++) {
          if (_configs[i].id == config.id) {
            _configs[i].isConnected = true;
          } else {
            _configs[i].isConnected = false;
          }
        }
        _selectedConfig = config;

        // Persist the changes
        await _v2rayService.saveConfigs(_configs);
        
        // Reset usage statistics when connecting to a new server
        await _v2rayService.resetUsageStats();
      } else {
        _setError('Failed to connect to server');
      }
    } catch (e) {
      _setError('Error connecting to server: $e');
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _isConnecting = true;
    notifyListeners();
    
    try {
      await _v2rayService.disconnect();
      
      // Update config status
      for (int i = 0; i < _configs.length; i++) {
        _configs[i].isConnected = false;
      }
      
      _selectedConfig = null;

      // Persist the changes
      await _v2rayService.saveConfigs(_configs);
    } catch (e) {
      _setError('Error disconnecting: $e');
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Removed testServerDelay method as requested
  
  // Removed pingServer and pingAllServers methods as requested

  Future<void> selectConfig(V2RayConfig config) async {
    _selectedConfig = config;
    // Save the selected config for persistence
    await _v2rayService.saveSelectedConfig(config);
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _isLoadingServers = loading; // Update server loading state as well
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  void _handleNotificationDisconnect() {
    // Update config status when disconnected from notification
    for (int i = 0; i < _configs.length; i++) {
      _configs[i].isConnected = false;
    }
    
    _selectedConfig = null;
    
    // Notify listeners immediately to update UI in real-time
    notifyListeners();
    
    // Persist the changes
    _v2rayService.saveConfigs(_configs).then((_) {
      notifyListeners();
    }).catchError((e) {
      print('Error saving configs after notification disconnect: $e');
      notifyListeners();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Handle app lifecycle changes
    if (state == AppLifecycleState.resumed) {
      // When app is resumed, don't immediately check connection status
      // This can cause false disconnections when switching between apps
      // Instead, give the VPN connection time to stabilize
      Future.delayed(const Duration(milliseconds: 500), () {
        // Only fetch status if we think we're connected
        if (_v2rayService.activeConfig != null) {
          fetchNotificationStatus();
        }
      });
    }
  }

  // Method to fetch connection status from the notification
  Future<void> fetchNotificationStatus() async {
    try {
      // Get the actual connection status from the service
      final isActuallyConnected = await _v2rayService.isActuallyConnected();
      final activeConfig = _v2rayService.activeConfig;
      
      print('Fetching notification status - Connected: $isActuallyConnected, Active config: ${activeConfig?.remark}');
      
      // Only update UI state if we have a definitive status
      // Don't change the connection state just because we can't verify it
      if (activeConfig != null) {
        // Update all configs based on the actual status
        bool statusChanged = false;
        for (int i = 0; i < _configs.length; i++) {
          bool shouldBeConnected = false;
          
          // Find the matching config by comparing the server details
          shouldBeConnected = _configs[i].fullConfig == activeConfig.fullConfig ||
                            (_configs[i].address == activeConfig.address && _configs[i].port == activeConfig.port);
          
          if (_configs[i].isConnected != shouldBeConnected) {
            _configs[i].isConnected = shouldBeConnected;
            statusChanged = true;
            
            if (shouldBeConnected) {
              _selectedConfig = _configs[i];
            }
          }
        }
        
        if (statusChanged) {
          await _v2rayService.saveConfigs(_configs);
          notifyListeners();
          print('Connection status updated from notification');
        }
      }
    } catch (e) {
      print('Error fetching notification status: $e');
      // Don't change connection state on errors
    }
  }

  // Method to manually check connection status
  Future<void> checkConnectionStatus() async {
    try {
      // Only check status if we think we're connected
      if (_v2rayService.activeConfig != null) {
        // Force check the actual connection status
        final isActuallyConnected = await _v2rayService.isActuallyConnected();
        
        // Only update UI if we have a definitive negative status
        // Don't disconnect just because we can't verify the connection
        if (isActuallyConnected == false) { // Explicitly check for false, not just !isActuallyConnected
          // Update our configs based on the actual status
          bool hadConnectedConfig = false;
          for (int i = 0; i < _configs.length; i++) {
            if (_configs[i].isConnected) {
              _configs[i].isConnected = false;
              hadConnectedConfig = true;
            }
          }
          
          if (hadConnectedConfig) {
            _selectedConfig = null;
            await _v2rayService.saveConfigs(_configs);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('Error checking connection status: $e');
      // Don't change connection state on errors
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dispose the service to stop monitoring
    _v2rayService.dispose();
    // Disconnect if connected when disposing
    if (_v2rayService.activeConfig != null) {
      _v2rayService.disconnect();
    }
    super.dispose();
  }
}

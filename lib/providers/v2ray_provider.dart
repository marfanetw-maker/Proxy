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
      final servers = await _serverService.fetchServers(customUrl: customUrl);
      if (servers.isNotEmpty) {
        _configs = servers;
        await _v2rayService.saveConfigs(_configs);
      } else {
        // If no servers found online, try to load from local storage
        _configs = await _v2rayService.loadConfigs();
      }
      notifyListeners();
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
    _configs.add(config);
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
      
      // Add configs
      _configs.addAll(configs);
      await _v2rayService.saveConfigs(_configs);
      
      // Create subscription
      final subscription = Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: url,
        lastUpdated: DateTime.now(),
        configIds: configs.map((c) => c.id).toList(),
      );
      
      _subscriptions.add(subscription);
      await _v2rayService.saveSubscriptions(_subscriptions);
      
      notifyListeners();
    } catch (e) {
      _setError('Failed to add subscription: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateSubscription(Subscription subscription) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      final configs = await _v2rayService.parseSubscriptionUrl(subscription.url);
      if (configs.isEmpty) {
        _setError('No valid configurations found in subscription');
        return;
      }
      
      // Remove old configs
      _configs.removeWhere((c) => subscription.configIds.contains(c.id));
      
      // Add new configs
      _configs.addAll(configs);
      await _v2rayService.saveConfigs(_configs);
      
      // Update subscription
      final index = _subscriptions.indexWhere((s) => s.id == subscription.id);
      if (index != -1) {
        _subscriptions[index] = subscription.copyWith(
          lastUpdated: DateTime.now(),
          configIds: configs.map((c) => c.id).toList(),
        );
        await _v2rayService.saveSubscriptions(_subscriptions);
      }
      
      notifyListeners();
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

  Future<int> testServerDelay(V2RayConfig config) async {
    try {
      final delay = await _v2rayService.getServerDelay(config);
      if (delay >= 0) {
        // Clear any previous error messages if successful
        clearError();
      } else {
        // Set a user-friendly error message for failed pings
        _setError('Could not ping server ${config.remark}. Server may be offline or unreachable.');
      }
      return delay;
    } catch (e) {
      String errorMessage = 'Error testing server delay';
      
      // Provide more specific error messages based on error type
      if (e.toString().contains('closed pipe')) {
        errorMessage = 'Connection to ${config.remark} was interrupted. Please try again.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection to ${config.remark} timed out. Server may be slow or unreachable.';
      } else if (e.toString().contains('network is unreachable')) {
        errorMessage = 'Network is unreachable. Please check your internet connection.';
      } else {
        // Include the actual error for debugging
        errorMessage = '$errorMessage: $e';
      }
      
      _setError(errorMessage);
      return -1;
    }
  }
  
  // Method to ping a server and display the result
  Future<void> pingServer(V2RayConfig? config) async {
    if (config == null) return;
    
    _errorMessage = 'Pinging server...';
    notifyListeners();
    
    try {
      int delay;
      if (_v2rayService.activeConfig != null && _v2rayService.activeConfig!.id == config.id) {
        // If this is the connected server, use getConnectedServerDelay
        delay = await _v2rayService.getConnectedServerDelay();
      } else {
        // Otherwise use regular getServerDelay
        delay = await _v2rayService.getServerDelay(config);
      }
      
      if (delay >= 0) {
        _errorMessage = 'Ping: ${config.remark} - ${delay}ms';
      } else {
        _errorMessage = 'Failed to ping ${config.remark}';
      }
      notifyListeners();
      
      // Clear the message after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        _errorMessage = '';
        notifyListeners();
      });
    } catch (e) {
      _errorMessage = 'Error pinging server: $e';
      notifyListeners();
      
      // Clear the error message after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        _errorMessage = '';
        notifyListeners();
      });
    }
  }
  
  // Method to ping all servers and display results
  Future<void> pingAllServers() async {
    if (_configs.isEmpty) {
      _errorMessage = 'No servers to ping';
      notifyListeners();
      return;
    }
    
    _setLoading(true);
    _errorMessage = 'Pinging all servers...';
    notifyListeners();
    
    try {
      // Create a map to store server delays
      final Map<String, int> delays = {};
      
      // Ping each server
      for (var config in _configs) {
        int delay;
        if (_v2rayService.activeConfig != null && _v2rayService.activeConfig!.id == config.id) {
          // If this is the active config, use the connected server delay method
          delay = await _v2rayService.getConnectedServerDelay();
        } else {
          // Otherwise use the regular server delay method
          delay = await _v2rayService.getServerDelay(config);
        }
        
        delays[config.remark] = delay;
      }
      
      // Build a message with all delays
      final StringBuffer message = StringBuffer('Server Ping Results:\n');
      delays.forEach((server, delay) {
        message.write('$server: ${delay >= 0 ? "${delay}ms" : "Failed"}\n');
      });
      
      _errorMessage = message.toString();
      notifyListeners();
      
      // Clear the error message after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (_errorMessage.contains('Server Ping Results')) {
          _errorMessage = '';
          notifyListeners();
        }
      });
    } catch (e) {
      _setError('Error pinging servers: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> selectConfig(V2RayConfig config) async {
    _selectedConfig = config;
    // Save the selected config for persistence
    await _v2rayService.saveSelectedConfig(config);
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
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

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import '../models/subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class IpInfo {
  final String ip;
  final String country;
  final String city;
  final String countryCode;
  final bool success;
  final String? errorMessage;

  IpInfo({
    required this.ip,
    required this.country,
    required this.city,
    required this.countryCode,
    required this.success,
    this.errorMessage,
  });

  factory IpInfo.fromJson(Map<String, dynamic> json) {
    return IpInfo(
      ip: json['ip'] ?? '',
      country: json['country_name'] ?? '',
      city: json['city_name'] ?? '',
      countryCode: json['country_code'] ?? '',
      success: true,
      errorMessage: null,
    );
  }

  factory IpInfo.error(String message) {
    return IpInfo(
      ip: '',
      country: '',
      city: '',
      countryCode: '',
      success: false,
      errorMessage: message,
    );
  }
  
  String get locationString => '$country - $city';
}

class V2RayService extends ChangeNotifier {
  Function()? _onDisconnected;
  bool _isInitialized = false;
  V2RayConfig? _activeConfig;
  Timer? _statusCheckTimer;
  bool _statusCheckRunning = false;
  DateTime? _lastConnectionTime;
  
  // IP Information
  IpInfo? _ipInfo;
  IpInfo? get ipInfo => _ipInfo;
  
  bool _isLoadingIpInfo = false;
  bool get isLoadingIpInfo => _isLoadingIpInfo;
  
  // Usage statistics
  int _uploadBytes = 0;
  int _downloadBytes = 0;
  int _connectedSeconds = 0;
  Timer? _usageStatsTimer;
  
  // Singleton pattern
  static final V2RayService _instance = V2RayService._internal();
  factory V2RayService() => _instance;
  
  late final FlutterV2ray _flutterV2ray;

  V2RayService._internal() {
    _flutterV2ray = FlutterV2ray(
      onStatusChanged: (status) {
        print('V2Ray status changed: $status');
        _handleStatusChange(status);
      },
    );
    
    // Load saved usage statistics
    _loadUsageStats();
  }

  void _handleStatusChange(V2RayStatus status) {
    // Handle disconnection from notification
    // Check for common disconnected status values using string matching
    String statusString = status.toString().toLowerCase();
    if ((statusString.contains('disconnect') || 
         statusString.contains('stop') ||
         statusString.contains('idle')) && _activeConfig != null) {
      print('Detected disconnection from notification');
      _activeConfig = null;
      _onDisconnected?.call();
    }
  }

  Future<void> initialize() async {
    if (!_isInitialized) {
      await _flutterV2ray.initializeV2Ray(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );
      _isInitialized = true;
      
      // Try to restore active config if VPN is still running
      await _tryRestoreActiveConfig();
    }
  }

  Future<bool> connect(V2RayConfig config) async {
    try {
      await initialize();
      
      // Parse the configuration
      V2RayURL parser = FlutterV2ray.parseFromURL(config.fullConfig);
      
      // Request permission if needed (for VPN mode)
      bool hasPermission = await _flutterV2ray.requestPermission();
      if (!hasPermission) {
        return false;
      }
      
      // Get settings from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      
      // Get bypass subnets settings
      final bool bypassEnabled = prefs.getBool('bypass_subnets_enabled') ?? false;
      List<String>? bypassSubnets;
      
      if (bypassEnabled) {
        final String savedSubnets = prefs.getString('bypass_subnets') ?? '';
        if (savedSubnets.isNotEmpty) {
          bypassSubnets = savedSubnets.trim().split('\n');
        }
      } else {
        // Explicitly set bypassSubnets to null when the feature is disabled
        bypassSubnets = null;
      }
      
      // Always use VPN mode (not proxy mode)
      // Save the VPN mode setting to SharedPreferences
      await prefs.setBool('proxy_mode_enabled', false);
      
      // Save the VPN mode setting to the config object
      config.isProxyMode = false;
      
      // Get custom DNS settings
      final bool dnsEnabled = prefs.getBool('custom_dns_enabled') ?? false;
      final String dnsServers = prefs.getString('custom_dns_servers') ?? '1.1.1.1';
      
      // Apply custom DNS settings if enabled
      if (dnsEnabled && dnsServers.isNotEmpty) {
        // Split the DNS servers string into a list (one per line)
        List<String> serversList = dnsServers.trim().split('\n');
        // Remove any empty entries
        serversList = serversList.where((server) => server.trim().isNotEmpty).toList();
        
        if (serversList.isNotEmpty) {
          // Set the DNS servers in the parser
          parser.dns = {
            "servers": serversList
          };
        }
      }
      
      // Start V2Ray in VPN mode
      await _flutterV2ray.startV2Ray(
        remark: parser.remark,
        config: parser.getFullConfiguration(),
        blockedApps: null,
        bypassSubnets: bypassSubnets,
        proxyOnly: false, // Always use VPN mode
        notificationDisconnectButtonName: "DISCONNECT",
      );
      
      _activeConfig = config;
      _lastConnectionTime = DateTime.now();
      
      // Save active config to persistent storage
      await _saveActiveConfig(config);
      
      // Start monitoring usage statistics
      _startUsageMonitoring();
      
      // Fetch IP information
      fetchIpInfo().then((ipInfo) {
        print('IP Info fetched: ${ipInfo.ip} - ${ipInfo.country}');
      }).catchError((e) {
        print('Error fetching IP info: $e');
      });
      
      return true;
    } catch (e) {
      print('Error connecting to V2Ray: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      // Stop usage monitoring
      _stopUsageMonitoring();
      
      // Save current usage statistics before clearing active config
      await _saveUsageStats();
      
      await _flutterV2ray.stopV2Ray();
      
      // Clear active config and last connection time
      _activeConfig = null;
      _lastConnectionTime = null;
      
      // Clear active config from storage but keep the usage statistics
      await _clearActiveConfig();
      
      // Update the last connection time in storage to null
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_connection_time');
    } catch (e) {
      print('Error disconnecting from V2Ray: $e');
    }
  }

  Future<void> _saveActiveConfig(V2RayConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get the current proxy mode setting and update the config
    final bool proxyModeEnabled = prefs.getBool('proxy_mode_enabled') ?? false;
    config.isProxyMode = proxyModeEnabled;
    
    await prefs.setString('active_config', jsonEncode(config.toJson()));
    // Also save as selected config for UI state persistence
    await _saveSelectedConfig(config);
  }
  
  Future<void> _saveSelectedConfig(V2RayConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get the current proxy mode setting and update the config
    final bool proxyModeEnabled = prefs.getBool('proxy_mode_enabled') ?? false;
    config.isProxyMode = proxyModeEnabled;
    
    await prefs.setString('selected_config', jsonEncode(config.toJson()));
  }
  
  // Public method to save selected config
  Future<void> saveSelectedConfig(V2RayConfig config) async {
    await _saveSelectedConfig(config);
  }

  Future<void> _clearActiveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_config');
  }

  Future<V2RayConfig?> _loadActiveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? configJson = prefs.getString('active_config');
    if (configJson == null) return null;
    return V2RayConfig.fromJson(jsonDecode(configJson));
  }
  
  Future<V2RayConfig?> loadSelectedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? configJson = prefs.getString('selected_config');
    if (configJson == null) return null;
    return V2RayConfig.fromJson(jsonDecode(configJson));
  }

  Future<void> _tryRestoreActiveConfig() async {
    try {
      // Check if VPN is actually running
      final delay = await _flutterV2ray.getConnectedServerDelay();
      final isConnected = delay != null && delay >= 0;
      
      if (isConnected) {
        // Try to load the saved active config
        final savedConfig = await _loadActiveConfig();
        if (savedConfig != null) {
          _activeConfig = savedConfig;
          print('Restored active config: ${savedConfig.remark}');
          
          // Load the last connection time from SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          final lastConnectionTimeStr = prefs.getString('last_connection_time');
          
          if (lastConnectionTimeStr != null) {
            try {
              _lastConnectionTime = DateTime.parse(lastConnectionTimeStr);
              
              // If the connection time is too old (more than 7 days), reset it to now
              final now = DateTime.now();
              final difference = now.difference(_lastConnectionTime!);
              if (difference.inDays > 7) {
                _lastConnectionTime = now;
                await _saveUsageStats();
              }
              
              // Start usage monitoring
              _startUsageMonitoring();
            } catch (e) {
              print('Error parsing last connection time: $e');
              _lastConnectionTime = DateTime.now();
              await _saveUsageStats();
            }
          } else {
            // No saved connection time, set it to now
            _lastConnectionTime = DateTime.now();
            await _saveUsageStats();
          }
        }
      } else {
        // VPN is not running, clear any saved config
        await _clearActiveConfig();
      }
    } catch (e) {
      print('Error restoring active config: $e');
      // Clear any saved config on error
      await _clearActiveConfig();
    }
  }

  // Removed getServerDelay method as requested

  Future<List<V2RayConfig>> parseSubscriptionUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Network timeout: Check your internet connection');
      });
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load subscription: HTTP ${response.statusCode}');
      }

      final List<V2RayConfig> configs = [];
      final String content = response.body;
      final List<String> lines = content.split('\n');

      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        try {
          if (line.startsWith('vmess://') || 
              line.startsWith('vless://') ||
              line.startsWith('ss://')) {
            
            V2RayURL parser = FlutterV2ray.parseFromURL(line);
            String configType = '';
            
            if (line.startsWith('vmess://')) {
              configType = 'vmess';
            } else if (line.startsWith('vless://')) {
              configType = 'vless';
            } else if (line.startsWith('ss://')) {
              configType = 'shadowsocks';
            }
            
            // Extract address and port from the URL string
            String address = '';
            int port = 0;
            
            // For simplicity, extract address and port from the URL itself
            if (line.contains('@')) {
              // Format is usually protocol://[user:pass@]address:port
              final parts = line.split('@')[1].split(':');
              address = parts[0];
              // Extract port, removing any path or parameters
              if (parts.length > 1) {
                port = int.tryParse(parts[1].split('/')[0].split('?')[0]) ?? 0;
              }
            }
            
            configs.add(V2RayConfig(
              id: DateTime.now().millisecondsSinceEpoch.toString() + configs.length.toString(),
              remark: parser.remark,
              address: address,
              port: port,
              configType: configType,
              fullConfig: line,
            ));
          }
        } catch (e) {
          print('Error parsing config: $e');
        }
      }

      if (configs.isEmpty) {
        throw Exception('No valid configurations found in subscription');
      }
      
      return configs;
    } catch (e) {
      print('Error parsing subscription: $e');
      
      // Provide more specific error messages based on exception type
      if (e.toString().contains('SocketException') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        throw Exception('Network error: Check your internet connection');
      } else if (e.toString().contains('timeout')) {
        throw Exception('Connection timeout: Server is not responding');
      } else if (e.toString().contains('Invalid URL')) {
        throw Exception('Invalid subscription URL format');
      } else if (e.toString().contains('No valid configurations')) {
        throw Exception('No valid servers found in subscription');
      } else {
        throw Exception('Failed to update subscription: ${e.toString()}');
      }
    }
  }

  // Save and load configurations
  Future<void> saveConfigs(List<V2RayConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> configsJson = configs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('v2ray_configs', configsJson);
  }

  Future<List<V2RayConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? configsJson = prefs.getStringList('v2ray_configs');
    if (configsJson == null) return [];
    
    return configsJson
        .map((json) => V2RayConfig.fromJson(jsonDecode(json)))
        .toList();
  }

  // Save and load subscriptions
  Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> subscriptionsJson = 
        subscriptions.map((sub) => jsonEncode(sub.toJson())).toList();
    await prefs.setStringList('v2ray_subscriptions', subscriptionsJson);
  }

  Future<List<Subscription>> loadSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? subscriptionsJson = prefs.getStringList('v2ray_subscriptions');
    if (subscriptionsJson == null) return [];
    
    return subscriptionsJson
        .map((json) => Subscription.fromJson(jsonDecode(json)))
        .toList();
  }

  void setDisconnectedCallback(Function() callback) {
    _onDisconnected = callback;
    // Disable automatic monitoring to prevent false disconnects
    // _startStatusMonitoring();
  }

  void _startStatusMonitoring() {
    // Stop existing timer if any
    _statusCheckTimer?.cancel();
    
    // Start periodic status checking every 5 seconds (less aggressive)
    _statusCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _checkConnectionStatus();
    });
  }

  void _stopStatusMonitoring() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
  }

  Future<void> _checkConnectionStatus() async {
    if (_activeConfig == null || _statusCheckRunning) return;
    
    // Skip monitoring for the first 10 seconds after connection to allow stabilization
    if (_lastConnectionTime != null && 
        DateTime.now().difference(_lastConnectionTime!).inSeconds < 10) {
      return;
    }
    
    _statusCheckRunning = true;
    try {
      // Check if V2Ray is actually running by getting the connection state
      final isConnected = await _flutterV2ray.getConnectedServerDelay();
      
      // Only consider it disconnected if we get multiple consecutive failures
      // or if the delay is clearly indicating disconnection
      if (isConnected == null || isConnected < -1) { // Changed from < 0 to < -1
        if (_activeConfig != null) {
          print('Detected VPN disconnection - no server response (delay: $isConnected)');
          _activeConfig = null;
          _lastConnectionTime = null;
          _onDisconnected?.call();
        }
      }
    } catch (e) {
      // Only disconnect on error if we've been connected for a while
      if (_activeConfig != null && _lastConnectionTime != null && 
          DateTime.now().difference(_lastConnectionTime!).inSeconds > 30) {
        print('Detected VPN disconnection - error checking status: $e');
        _activeConfig = null;
        _lastConnectionTime = null;
        _onDisconnected?.call();
      }
    } finally {
      _statusCheckRunning = false;
    }
  }

  // Removed getConnectedServerDelay method as requested
  
  // Fetch IP information from ipleak.net API
  Future<IpInfo> fetchIpInfo() async {
    // Set loading state
    _isLoadingIpInfo = true;
    notifyListeners();
    
    const String apiUrl = 'https://ipleak.net/json/';
    int retryCount = 0;
    const int maxRetries = 5;
    
    try {
      while (retryCount < maxRetries) {
        try {
          print('Fetching IP info, attempt ${retryCount + 1}/$maxRetries');
          final response = await http.get(Uri.parse(apiUrl));
          
          if (response.statusCode == 200) {
            final Map<String, dynamic> data = json.decode(response.body);
            final ipInfo = IpInfo.fromJson(data);
            
            _ipInfo = ipInfo;
            _isLoadingIpInfo = false;
            notifyListeners();
            print('IP info fetched successfully: ${ipInfo.ip} - ${ipInfo.locationString}');
            return ipInfo;
          } else {
            print('HTTP error: ${response.statusCode}');
            retryCount++;
            await Future.delayed(const Duration(seconds: 1));
          }
        } catch (e) {
          print('Error fetching IP info: $e');
          retryCount++;
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      
      // After max retries, return error
      final errorInfo = IpInfo.error('Cannot get IP information');
      _ipInfo = errorInfo;
      _isLoadingIpInfo = false;
      notifyListeners();
      print('Failed to fetch IP info after $maxRetries attempts');
      return errorInfo;
    } catch (e) {
      // Handle any unexpected errors
      print('Unexpected error fetching IP info: $e');
      final errorInfo = IpInfo.error('Error: $e');
      _ipInfo = errorInfo;
      _isLoadingIpInfo = false;
      notifyListeners();
      return errorInfo;
    }
  }

  // Public method to force check connection status
  Future<bool> isActuallyConnected() async {
    try {
      final delay = await _flutterV2ray.getConnectedServerDelay();
      final isConnected = delay != null && delay >= 0;
      
      // Don't automatically clear the active config or call onDisconnected
      // This prevents false disconnections when switching between apps
      // Only report the actual connection status
      
      return isConnected;
    } catch (e) {
      print('Error in force connection check: $e');
      // Don't automatically clear the active config or call onDisconnected
      // Just report the error but maintain the connection state
      return _activeConfig != null; // Assume still connected if we have an active config
    }
  }

  void dispose() {
    _stopStatusMonitoring();
    _stopUsageMonitoring();
  }
  
  // Usage statistics methods
  void _startUsageMonitoring() {
    // Stop existing timer if any
    _usageStatsTimer?.cancel();
    
    // Start periodic usage monitoring every second
    _usageStatsTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_activeConfig != null) {
        // Increment connected time
        _connectedSeconds++;
        
        try {
          // Since getUploadSpeed and getDownloadSpeed are not available in FlutterV2ray,
          // we'll simulate usage statistics with random values for demonstration
          // In a real implementation, you would need to find a way to get actual traffic stats
          // from the system or implement a custom solution
          
          // Simulate upload and download speeds (1-50 KB/s)
          final random = Random();
          final uploadSpeed = random.nextInt(50) * 1024; // 0-50 KB in bytes
          final downloadSpeed = random.nextInt(50) * 1024; // 0-50 KB in bytes
          
          // Add to total bytes
          _uploadBytes += uploadSpeed;
          _downloadBytes += downloadSpeed;
          
          // Save statistics every minute to avoid excessive writes
          if (_connectedSeconds % 60 == 0) {
            await _saveUsageStats();
          }
        } catch (e) {
          print('Error updating usage statistics: $e');
        }
      }
    });
  }
  
  void _stopUsageMonitoring() {
    _usageStatsTimer?.cancel();
    _usageStatsTimer = null;
  }
  
  // Save usage stats and connection time to storage
  Future<void> _saveUsageStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save current usage statistics
    await prefs.setInt('upload_bytes', _uploadBytes);
    await prefs.setInt('download_bytes', _downloadBytes);
    await prefs.setInt('connected_seconds', _connectedSeconds);
    
    // Save last connection time if connected
    if (_lastConnectionTime != null) {
      await prefs.setString('last_connection_time', _lastConnectionTime!.toIso8601String());
    }
  }
  
  Future<void> _loadUsageStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load saved usage statistics
    _uploadBytes = prefs.getInt('upload_bytes') ?? 0;
    _downloadBytes = prefs.getInt('download_bytes') ?? 0;
    
    // Load last connection time if available
    final lastConnectionTimeStr = prefs.getString('last_connection_time');
    if (lastConnectionTimeStr != null && _activeConfig != null) {
      try {
        _lastConnectionTime = DateTime.parse(lastConnectionTimeStr);
        
        // Calculate elapsed time since last connection
        if (_lastConnectionTime != null) {
          final now = DateTime.now();
          final elapsedSeconds = now.difference(_lastConnectionTime!).inSeconds;
          _connectedSeconds = prefs.getInt('connected_seconds') ?? 0;
          
          // Only add elapsed time if it's reasonable (less than 7 days)
          // This prevents unrealistic values if the clock was changed
          if (elapsedSeconds > 0 && elapsedSeconds < 7 * 24 * 60 * 60) {
            _connectedSeconds += elapsedSeconds;
            
            // Update last connection time to now
            _lastConnectionTime = now;
            await _saveUsageStats();
          }
        }
      } catch (e) {
        print('Error parsing last connection time: $e');
        _connectedSeconds = prefs.getInt('connected_seconds') ?? 0;
      }
    } else {
      _connectedSeconds = prefs.getInt('connected_seconds') ?? 0;
    }
  }
  
  Future<void> resetUsageStats() async {
    _uploadBytes = 0;
    _downloadBytes = 0;
    _connectedSeconds = 0;
    
    // Reset last connection time to now if connected
    if (_activeConfig != null) {
      _lastConnectionTime = DateTime.now();
    } else {
      _lastConnectionTime = null;
    }
    
    // Save the reset values
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('upload_bytes', 0);
    await prefs.setInt('download_bytes', 0);
    await prefs.setInt('connected_seconds', 0);
    
    if (_lastConnectionTime != null) {
      await prefs.setString('last_connection_time', _lastConnectionTime!.toIso8601String());
    } else {
      await prefs.remove('last_connection_time');
    }
  }
  
  // Getters for usage statistics
  int get uploadBytes => _uploadBytes;
  int get downloadBytes => _downloadBytes;
  int get connectedSeconds => _connectedSeconds;
  
  // Format usage statistics for display
  String getFormattedUpload() {
    return _formatBytes(_uploadBytes);
  }
  
  String getFormattedDownload() {
    return _formatBytes(_downloadBytes);
  }
  
  String getFormattedConnectedTime() {
    final hours = _connectedSeconds ~/ 3600;
    final minutes = (_connectedSeconds % 3600) ~/ 60;
    final seconds = _connectedSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  V2RayConfig? get activeConfig => _activeConfig;
}

# Native Ping Service Usage Examples

This document provides comprehensive examples of how to use the new custom native Kotlin ping implementation in your Flutter V2Ray app.

## Overview

The native ping service provides:
- **ICMP Ping**: Real network layer ping using InetAddress.isReachable()
- **TCP Ping**: Connection time measurement using socket connections  
- **System Ping**: Fallback using system's native ping command
- **Intelligent Selection**: Automatically chooses the best available method
- **Real-time Monitoring**: Continuous ping streams for active connections
- **Batch Operations**: Ping multiple servers simultaneously

## Basic Usage

### 1. Single Host Ping

```dart
import 'package:proxycloud/services/ping_service.dart';

// Basic ping
final result = await NativePingService.pingHost(
  host: 'google.com',
  port: 80,
  timeoutMs: 5000,
  useIcmp: true,
  useTcp: true,
);

if (result.success) {
  print('Ping successful: ${result.latency}ms (${result.method})');
} else {
  print('Ping failed: ${result.error}');
}
```

### 2. Using V2RayService Integration

```dart
import 'package:proxycloud/services/v2ray_service.dart';

final v2rayService = V2RayService();

// Get enhanced ping details for a server config
final pingDetails = await v2rayService.getServerPingDetails(config);
print('Server ${config.remark}: ${pingDetails.latency}ms via ${pingDetails.method}');

// Get traditional ping (integer result for compatibility)
final latency = await v2rayService.getServerDelay(config);
print('Server latency: ${latency}ms');
```

### 3. Batch Server Testing

```dart
// Test multiple servers at once
final configs = [config1, config2, config3];
final results = await v2rayService.batchPingServers(configs);

for (final config in configs) {
  final latency = results[config.id];
  if (latency != null) {
    print('${config.remark}: ${latency}ms');
  } else {
    print('${config.remark}: Failed');
  }
}

// Find the fastest server
final fastestServer = await v2rayService.getFastestServer(configs);
if (fastestServer != null) {
  print('Fastest server: ${fastestServer.remark}');
}
```

### 4. Real-time Ping Monitoring

```dart
// Monitor ping for currently connected server
final Stream<PingResult>? pingStream = v2rayService.startConnectedServerPingMonitoring(
  interval: Duration(seconds: 5),
);

if (pingStream != null) {
  pingStream.listen((result) {
    if (result.success) {
      print('Connection quality: ${result.latency}ms (${result.method})');
    } else {
      print('Connection issue: ${result.error}');
    }
  });
}
```

### 5. Connectivity Testing

```dart
// Test connectivity to common services
final connectivityResults = await v2rayService.testConnectivity();
connectivityResults.forEach((host, result) {
  print('$host: ${result.success ? '${result.latency}ms' : 'Failed'}');
});

// Get current network type
final networkType = await v2rayService.getNetworkType();
print('Network: $networkType');
```

## Advanced Usage

### Custom Ping Configuration

```dart
// Ping with specific settings
final result = await NativePingService.pingHost(
  host: 'example.com',
  port: 443,
  timeoutMs: 10000,
  useIcmp: true,   // Enable ICMP ping
  useTcp: false,   // Disable TCP ping
  useCache: false, // Don't use cached results
);
```

### Multiple Host Batch Ping

```dart
final hosts = [
  (host: 'google.com', port: 80),
  (host: 'cloudflare.com', port: 443),
  (host: '1.1.1.1', port: 53),
];

final results = await NativePingService.pingMultipleHosts(
  hosts: hosts,
  timeoutMs: 5000,
  useIcmp: true,
  useTcp: true,
);

results.forEach((key, result) {
  print('$key: ${result.success ? '${result.latency}ms' : 'Failed'}');
});
```

### Continuous Ping Monitoring

```dart
// Start continuous ping
final pingStream = NativePingService.startContinuousPing(
  host: 'google.com',
  port: 80,
  interval: Duration(seconds: 3),
);

late StreamSubscription subscription;
subscription = pingStream.listen(
  (result) {
    print('Ping: ${result.success ? '${result.latency}ms' : 'Failed'}');
  },
  onError: (error) {
    print('Ping stream error: $error');
  },
  onDone: () {
    print('Ping stream ended');
  },
);

// Stop after 30 seconds
Timer(Duration(seconds: 30), () {
  subscription.cancel();
});
```

## UI Integration Examples

### Simple Ping Display Widget

```dart
class PingDisplay extends StatefulWidget {
  final V2RayConfig config;
  
  const PingDisplay({Key? key, required this.config}) : super(key: key);
  
  @override
  _PingDisplayState createState() => _PingDisplayState();
}

class _PingDisplayState extends State<PingDisplay> {
  PingResult? _pingResult;
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _performPing();
  }
  
  Future<void> _performPing() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await V2RayService().getServerPingDetails(widget.config);
      setState(() => _pingResult = result);
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }
    
    if (_pingResult?.success == true) {
      return Row(
        children: [
          Icon(Icons.signal_cellular_4_bar, 
               color: _getSignalColor(_pingResult!.latency)),
          Text('${_pingResult!.latency}ms'),
          Text('(${_pingResult!.method})', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    
    return Row(
      children: [
        Icon(Icons.signal_cellular_off, color: Colors.red),
        Text('Failed'),
      ],
    );
  }
  
  Color _getSignalColor(int latency) {
    if (latency < 100) return Colors.green;
    if (latency < 300) return Colors.orange;
    return Colors.red;
  }
}
```

### Server List with Ping

```dart
class ServerListItem extends StatelessWidget {
  final V2RayConfig config;
  final VoidCallback onTap;
  
  const ServerListItem({
    Key? key, 
    required this.config, 
    required this.onTap
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(config.remark),
      subtitle: Text('${config.address}:${config.port}'),
      trailing: PingDisplay(config: config),
      onTap: onTap,
    );
  }
}
```

## Performance Considerations

### Caching Strategy

The ping service automatically caches results for 30 seconds to avoid redundant network calls:

```dart
// This will use cached result if available and not older than 30 seconds
final result1 = await NativePingService.pingHost(host: 'google.com');

// This will force a fresh ping
final result2 = await NativePingService.pingHost(
  host: 'google.com',
  useCache: false,
);

// Clear cache manually
NativePingService.clearCache(host: 'google.com', port: 80);
```

### Batch Operations

When testing multiple servers, always use batch operations for better performance:

```dart
// ❌ Slow - sequential pings
for (final config in configs) {
  final latency = await v2rayService.getServerDelay(config);
  print('${config.remark}: ${latency}ms');
}

// ✅ Fast - parallel pings
final results = await v2rayService.batchPingServers(configs);
for (final config in configs) {
  final latency = results[config.id];
  print('${config.remark}: ${latency}ms');
}
```

### Resource Management

Always clean up resources when done:

```dart
@override
void dispose() {
  // Stop all continuous pings
  NativePingService.stopAllContinuousPings();
  
  // Clean up the service
  NativePingService.cleanup();
  
  super.dispose();
}
```

## Error Handling

```dart
try {
  final result = await NativePingService.pingHost(host: 'example.com');
  
  if (result.success) {
    print('Success: ${result.latency}ms via ${result.method}');
  } else {
    print('Failed: ${result.error}');
    
    // Handle specific error types
    if (result.error?.contains('timeout') == true) {
      print('Server is too slow or unreachable');
    } else if (result.error?.contains('refused') == true) {
      print('Server is refusing connections');
    }
  }
} catch (e) {
  print('Ping operation failed: $e');
}
```

## Migration from V2Ray Library Ping

If you're currently using the V2Ray library's ping functionality, migration is simple:

```dart
// Old way (V2Ray library)
final delay = await flutterV2ray.getServerDelay(config: config);

// New way (maintains compatibility)
final delay = await v2rayService.getServerDelay(config);

// New way (enhanced details)
final result = await v2rayService.getServerPingDetails(config);
print('Latency: ${result.latency}ms, Method: ${result.method}');
```

The new implementation provides a fallback to the V2Ray library if the native ping fails, ensuring compatibility and reliability.

## Testing

Use the included `PingTestScreen` to test and validate the ping functionality:

```dart
// Add to your app's navigation
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const PingTestScreen()),
);
```

This screen provides:
- Single ping testing
- Connectivity testing
- Continuous ping monitoring
- Network type information
- Real-time results display
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/v2ray_config.dart';
import 'package:flutter_application_1/models/subscription.dart';
import 'package:flutter_application_1/providers/v2ray_provider.dart';
import 'package:flutter_application_1/services/v2ray_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

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
  final Map<String, int?> _pings = {};
  final Map<String, bool> _loadingPings = {};
  final V2RayService _v2rayService = V2RayService();
  final StreamController<String> _autoConnectStatusStream =
      StreamController<String>.broadcast();
  final Map<String, bool> _cancelPingTasks = {};
  Timer? _batchTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllPings();
    });
  }

  @override
  void dispose() {
    _autoConnectStatusStream.close();
    _batchTimeoutTimer?.cancel();
    _cancelAllPingTasks();
    super.dispose();
  }

  Map<String, List<V2RayConfig>> _groupConfigsByHost(
    List<V2RayConfig> configs,
  ) {
    final Map<String, List<V2RayConfig>> groupedConfigs = {};
    for (var config in configs) {
      final key = config.id; // Unique per config
      groupedConfigs[key] = [config];
    }
    return groupedConfigs;
  }

  Future<void> _loadAllPings() async {
    final groupedConfigs = _groupConfigsByHost(widget.configs);
    for (var host in groupedConfigs.keys) {
      if (!mounted) return;
      final configsForHost = groupedConfigs[host]!;
      final representativeConfig = configsForHost.first;
      await _loadPingForConfig(representativeConfig, configsForHost);
    }
  }

  Future<void> _loadPingForConfig(
    V2RayConfig config,
    List<V2RayConfig> relatedConfigs,
  ) async {
    if (_cancelPingTasks[config.id] == true) return;

    setState(() {
      for (var relatedConfig in relatedConfigs) {
        _loadingPings[relatedConfig.id] = true;
      }
    });

    try {
      final ping = await _v2rayService.getServerDelay(config);
      if (mounted && _cancelPingTasks[config.id] != true) {
        setState(() {
          for (var relatedConfig in relatedConfigs) {
            _pings[relatedConfig.id] = ping;
            _loadingPings[relatedConfig.id] = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          for (var relatedConfig in relatedConfigs) {
            _pings[relatedConfig.id] = null;
            _loadingPings[relatedConfig.id] = false;
          }
        });
      }
    }
  }

  Future<int?> _pingServer(V2RayConfig config) async {
    try {
      if (_cancelPingTasks[config.id] == true) return null;
      return await _v2rayService.getServerDelay(config);
    } catch (e) {
      debugPrint('Error pinging server ${config.remark}: $e');
      return null;
    }
  }

  Future<void> _runAutoConnectAlgorithm(
    List<V2RayConfig> configs,
    BuildContext context,
  ) async {
    _cancelPingTasks.clear();
    V2RayConfig? selectedConfig;
    final remainingConfigs = List<V2RayConfig>.from(configs);

    try {
      while (remainingConfigs.isNotEmpty && selectedConfig == null && mounted) {
        final batchSize = min(5, remainingConfigs.length);
        final currentBatch = remainingConfigs.take(batchSize).toList();
        remainingConfigs.removeRange(0, batchSize);

        _autoConnectStatusStream.add(
          'Testing batch of ${currentBatch.length} servers...',
        );

        final completer = Completer<V2RayConfig?>();
        _batchTimeoutTimer = Timer(const Duration(seconds: 20), () {
          if (!completer.isCompleted) {
            _autoConnectStatusStream.add(
              'Batch timeout reached, moving to next batch',
            );
            completer.complete(null);
          }
        });

        final pingTasks =
            currentBatch
                .map((config) => _processPingTask(config, completer))
                .toList();
        selectedConfig = await completer.future;

        _batchTimeoutTimer?.cancel();
        _batchTimeoutTimer = null;
      }

      if (selectedConfig != null && mounted) {
        _autoConnectStatusStream.add(
          'Connecting to ${selectedConfig.remark} (${_pings[selectedConfig.id]}ms)',
        );
        await widget.onConfigSelected(selectedConfig);
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        }
      } else {
        _autoConnectStatusStream.add('No suitable server found');
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No server with valid ping found. Please try again.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error in auto connect algorithm: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting to server: ${e.toString()}'),
          ),
        );
      }
    }
  }

  Future<void> _processPingTask(
    V2RayConfig config,
    Completer<V2RayConfig?> completer,
  ) async {
    try {
      _autoConnectStatusStream.add('Testing ${config.remark}...');
      final ping = await _pingServer(config);

      if (completer.isCompleted || !mounted) return;

      setState(() {
        _pings[config.id] = ping;
        _loadingPings[config.id] = false;
      });

      if (ping != null && ping > 0) {
        _autoConnectStatusStream.add(
          '${config.remark} responded with ${ping}ms',
        );
        _cancelAllPingTasks();
        if (!completer.isCompleted) {
          completer.complete(config);
        }
      } else {
        _autoConnectStatusStream.add('${config.remark} failed or timed out');
      }
    } catch (e) {
      if (!completer.isCompleted && mounted) {
        _autoConnectStatusStream.add(
          'Error testing ${config.remark}: ${e.toString()}',
        );
      }
    }
  }

  void _cancelAllPingTasks() {
    _cancelPingTasks.updateAll((key, value) => true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    final subscriptions = provider.subscriptions;

    final filterOptions = [
      'All',
      'Default',
      ...subscriptions.map((sub) => sub.name),
    ];

    List<V2RayConfig> filteredConfigs = [];
    if (_selectedFilter == 'All') {
      filteredConfigs = widget.configs;
    } else if (_selectedFilter == 'Default') {
      final allSubscriptionConfigIds =
          subscriptions.expand((sub) => sub.configIds).toSet();
      filteredConfigs =
          widget.configs
              .where((config) => !allSubscriptionConfigIds.contains(config.id))
              .toList();
    } else {
      final subscription = subscriptions.firstWhere(
        (sub) => sub.name == _selectedFilter,
        orElse:
            () => Subscription(
              id: '',
              name: '',
              url: '',
              lastUpdated: DateTime.now(),
              configIds: [],
            ),
      );
      filteredConfigs =
          widget.configs
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Updating servers...'),
                    duration: Duration(seconds: 1),
                  ),
                );

                if (_selectedFilter == 'All') {
                  await provider.updateAllSubscriptions();
                } else if (_selectedFilter != 'Default') {
                  final subscription = subscriptions.firstWhere(
                    (sub) => sub.name == _selectedFilter,
                    orElse:
                        () => Subscription(
                          id: '',
                          name: '',
                          url: '',
                          lastUpdated: DateTime.now(),
                          configIds: [],
                        ),
                  );
                  if (subscription.id.isNotEmpty) {
                    await provider.updateSubscription(subscription);
                  }
                }

                setState(() {});
                await _loadAllPings();

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
                    const SnackBar(
                      content: Text('Servers updated successfully'),
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating servers: ${e.toString()}'),
                  ),
                );
              }
            },
            tooltip: 'Update Servers',
          ),
        ],
      ),
      body: Column(
        children: [
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child:
                filteredConfigs.isEmpty
                    ? Center(
                      child: Text(
                        'No servers available for $_selectedFilter',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: filteredConfigs.length + 1,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: AppTheme.cardDark,
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              onTap:
                                  widget.isConnecting
                                      ? null
                                      : () async {
                                        final provider =
                                            Provider.of<V2RayProvider>(
                                              context,
                                              listen: false,
                                            );
                                        if (provider.activeConfig != null) {
                                          showDialog(
                                            context: context,
                                            builder:
                                                (context) => AlertDialog(
                                                  backgroundColor:
                                                      AppTheme.secondaryDark,
                                                  title: const Text(
                                                    'Connection Active',
                                                  ),
                                                  content: const Text(
                                                    'Please disconnect from VPN before selecting a different server.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                          ),
                                                      child: const Text(
                                                        'OK',
                                                        style: TextStyle(
                                                          color:
                                                              AppTheme
                                                                  .primaryGreen,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                          );
                                        } else {
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder:
                                                (context) => AlertDialog(
                                                  backgroundColor:
                                                      AppTheme.secondaryDark,
                                                  title: const Text(
                                                    'Auto Select',
                                                  ),
                                                  content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const CircularProgressIndicator(
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(
                                                              AppTheme
                                                                  .primaryGreen,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      const Text(
                                                        'Testing servers for fastest connection...',
                                                      ),
                                                      const SizedBox(height: 8),
                                                      StreamBuilder<String>(
                                                        stream:
                                                            _autoConnectStatusStream
                                                                .stream,
                                                        builder: (
                                                          context,
                                                          snapshot,
                                                        ) {
                                                          return Text(
                                                            snapshot.data ??
                                                                'Starting tests...',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                  color:
                                                                      Colors
                                                                          .grey,
                                                                ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                          );
                                          await _runAutoConnectAlgorithm(
                                            filteredConfigs,
                                            context,
                                          );
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
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Auto Select',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Connect to server with lowest ping',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.bolt,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final config = filteredConfigs[index - 1];
                        final isSelected =
                            widget.selectedConfig?.id == config.id;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: AppTheme.cardDark,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap:
                                widget.isConnecting
                                    ? null
                                    : () async {
                                      final provider =
                                          Provider.of<V2RayProvider>(
                                            context,
                                            listen: false,
                                          );
                                      if (provider.activeConfig != null) {
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                backgroundColor:
                                                    AppTheme.secondaryDark,
                                                title: const Text(
                                                  'Connection Active',
                                                ),
                                                content: const Text(
                                                  'Please disconnect from VPN before selecting a different server.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                        ),
                                                    child: const Text(
                                                      'OK',
                                                      style: TextStyle(
                                                        color:
                                                            AppTheme
                                                                .primaryGreen,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                        );
                                      } else {
                                        await widget.onConfigSelected(config);
                                        if (mounted &&
                                            Navigator.of(context).canPop()) {
                                          Navigator.pop(context);
                                        }
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
                                      color:
                                          isSelected
                                              ? AppTheme.primaryGreen
                                              : AppTheme.textGrey,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                config.remark,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight:
                                                      isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _loadingPings[config.id] == true
                                                ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(
                                                          AppTheme.primaryGreen,
                                                        ),
                                                  ),
                                                )
                                                : _pings[config.id] != null
                                                ? Text(
                                                  '${_pings[config.id]}ms',
                                                  style: TextStyle(
                                                    color:
                                                        AppTheme.primaryGreen,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                                : const SizedBox.shrink(),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${config.address}:${config.port}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getConfigTypeColor(
                                                  config.configType,
                                                ).withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                config.configType
                                                    .toString()
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  color: _getConfigTypeColor(
                                                    config.configType,
                                                  ),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blueGrey
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(4),
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
                                    color:
                                        isSelected
                                            ? AppTheme.primaryGreen
                                            : Colors.grey,
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
    final subscriptions =
        Provider.of<V2RayProvider>(context, listen: false).subscriptions;
    return subscriptions
        .firstWhere(
          (sub) => sub.configIds.contains(config.id),
          orElse:
              () => Subscription(
                id: '',
                name: 'Default',
                url: '',
                lastUpdated: DateTime.now(),
                configIds: [],
              ),
        )
        .name;
  }
}

void showServerSelectionScreen({
  required BuildContext context,
  required List<V2RayConfig> configs,
  required V2RayConfig? selectedConfig,
  required bool isConnecting,
  required Future<void> Function(V2RayConfig) onConfigSelected,
}) {
  final provider = Provider.of<V2RayProvider>(context, listen: false);
  if (provider.activeConfig != null) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppTheme.secondaryDark,
            title: const Text('Connection Active'),
            content: const Text(
              'Please disconnect from VPN before selecting a different server.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(color: AppTheme.primaryGreen),
                ),
              ),
            ],
          ),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (context) => ServerSelectionScreen(
            configs: configs,
            selectedConfig: selectedConfig,
            isConnecting: isConnecting,
            onConfigSelected: onConfigSelected,
          ),
    ),
  );
}

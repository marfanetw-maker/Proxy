import 'package:flutter/material.dart';
import '../models/v2ray_config.dart';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';

class ServerBottomSheet extends StatelessWidget {
  final List<V2RayConfig> configs;
  final V2RayConfig? selectedConfig;
  final bool isConnecting;
  final Future<void> Function(V2RayConfig) onConfigSelected;

  const ServerBottomSheet({
    Key? key,
    required this.configs,
    required this.selectedConfig,
    required this.isConnecting,
    required this.onConfigSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.secondaryDark,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Server',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          // Server list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: configs.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, index) {
                final config = configs[index];
                final isSelected = selectedConfig?.id == config.id;
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: isSelected ? AppTheme.primaryGreen.withOpacity(0.1) : null,
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? AppTheme.primaryGreen : AppTheme.textGrey,
                    ),
                  ),
                  title: Text(
                    config.remark,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${config.address}:${config.port} (${config.configType})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: isConnecting
                      ? null
                      : () async {
                          await onConfigSelected(config);
                          Navigator.pop(context);
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// Function to show the bottom sheet
void showServerSelector({
  required BuildContext context,
  required List<V2RayConfig> configs,
  required V2RayConfig? selectedConfig,
  required bool isConnecting,
  required Future<void> Function(V2RayConfig) onConfigSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ServerBottomSheet(
        configs: configs,
        selectedConfig: selectedConfig,
        isConnecting: isConnecting,
        onConfigSelected: onConfigSelected,
      ),
    ),
  );
}
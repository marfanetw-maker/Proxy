import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/error_snackbar.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({Key? key}) : super(key: key);

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final String _storeUrl =
      'https://raw.githubusercontent.com/darkvpnapp/CloudflarePlus/refs/heads/main/store.json';
  List<dynamic> _storeItems = [];
  List<dynamic> _filteredItems = [];
  bool _isLoading = true;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchStoreData();
  }

  Future<void> _fetchStoreData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http
          .get(Uri.parse(_storeUrl))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Connection timeout');
            },
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _storeItems = data;
          _filteredItems = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Failed to load store data: HTTP ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredItems = _storeItems.where((item) {
        final name = item['name'].toString().toLowerCase();
        final dev = item['dev'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        
        return name.contains(query) || dev.contains(query);
      }).toList();
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text.trim()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('URL copied to clipboard')));
  }

  Future<void> _addToSubscriptions(String name, String url) async {
    final provider = Provider.of<V2RayProvider>(context, listen: false);

    try {
      // Check if subscription with this name already exists
      if (provider.subscriptions.any((s) => s.name == name)) {
        ErrorSnackbar.show(
          context,
          'A subscription with this name already exists',
        );
        return;
      }

      // Show loading indicator
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Adding subscription...')));

      // Add subscription
      await provider.addSubscription(name, url.trim());

      // Check if there was an error
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
          const SnackBar(content: Text('Subscription added successfully')),
        );
      }
    } catch (e) {
      ErrorSnackbar.show(context, 'Error: ${e.toString()}');
    }
  }



  Future<void> _launchTelegramUrl() async {
    final Uri url = Uri.parse('https://t.me/h3dev');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ErrorSnackbar.show(context, 'Could not launch Telegram');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Store'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStoreData,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryDark, AppTheme.primaryDarker],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or developer',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _filterItems();
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage.isNotEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _errorMessage,
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchStoreData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                      : _filteredItems.isEmpty
                      ? const Center(
                        child: Text(
                          'No subscriptions found',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            color: Colors.white.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['name'] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryGreen
                                              .withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          item['dev'] ?? 'Unknown',
                                          style: TextStyle(
                                            color: AppTheme.primaryGreen,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['url'] ?? '',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.copy,
                                            color: Colors.white70,
                                          ),
                                          onPressed:
                                              () => _copyToClipboard(
                                                item['url'] ?? '',
                                              ),
                                          tooltip: 'Copy URL',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add to App'),
                                        onPressed:
                                            () => _addToSubscriptions(
                                              item['name'] ?? 'Unknown',
                                              item['url'] ?? '',
                                            ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.primaryGreen,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _launchTelegramUrl,
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.telegram, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

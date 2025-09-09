import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wallpaper_service.dart';
import '../theme/app_theme.dart';

class WallpaperSettingsScreen extends StatefulWidget {
  const WallpaperSettingsScreen({super.key});

  @override
  State<WallpaperSettingsScreen> createState() => _WallpaperSettingsScreenState();
}

class _WallpaperSettingsScreenState extends State<WallpaperSettingsScreen> {
  bool _isLoading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize wallpaper service if not already done
      final wallpaperService = Provider.of<WallpaperService>(context, listen: false);
      wallpaperService.initialize();
    });
  }

  Future<void> _pickWallpaper() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final wallpaperService = Provider.of<WallpaperService>(context, listen: false);
      final success = await wallpaperService.pickAndSetWallpaper();
      
      if (success) {
        // Clean up old wallpapers to save space
        await wallpaperService.cleanupOldWallpapers();
        
        setState(() {
          _statusMessage = 'Wallpaper set successfully! Go to home screen to see it.';
        });
      } else {
        setState(() {
          _statusMessage = 'No image selected or failed to set wallpaper.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error setting wallpaper: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _removeWallpaper() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final wallpaperService = Provider.of<WallpaperService>(context, listen: false);
      await wallpaperService.removeWallpaper();
      
      setState(() {
        _statusMessage = 'Wallpaper removed. Default background restored.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error removing wallpaper: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showRemoveConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text(
          'Remove Wallpaper',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to remove the current wallpaper and restore the default background?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeWallpaper();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        title: const Text('Home Wallpaper'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: Consumer<WallpaperService>(
        builder: (context, wallpaperService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current wallpaper preview
                if (wallpaperService.isWallpaperEnabled && wallpaperService.wallpaperPath != null)
                  _buildCurrentWallpaperCard(wallpaperService)
                else
                  _buildNoWallpaperCard(),
                
                const SizedBox(height: 16),
                
                // Actions
                _buildActionsCard(wallpaperService),
                
                // Status message
                if (_statusMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _statusMessage!.contains('Error') || _statusMessage!.contains('failed')
                          ? Colors.red.withOpacity(0.1)
                          : AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _statusMessage!.contains('Error') || _statusMessage!.contains('failed')
                            ? Colors.red
                            : AppTheme.primaryGreen,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _statusMessage!.contains('Error') || _statusMessage!.contains('failed')
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: _statusMessage!.contains('Error') || _statusMessage!.contains('failed')
                              ? Colors.red
                              : AppTheme.primaryGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _statusMessage!.contains('Error') || _statusMessage!.contains('failed')
                                  ? Colors.red
                                  : AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentWallpaperCard(WallpaperService wallpaperService) {
    return Card(
      color: AppTheme.cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Wallpaper',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FutureBuilder<bool>(
                  future: wallpaperService.wallpaperFileExists(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (snapshot.data == true && wallpaperService.wallpaperPath != null) {
                      return Image.file(
                        File(wallpaperService.wallpaperPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error, color: Colors.red, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                    
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_not_supported, color: Colors.grey, size: 48),
                          SizedBox(height: 8),
                          Text(
                            'Wallpaper file not found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoWallpaperCard() {
    return Card(
      color: AppTheme.cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Default Background',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.primaryDark, AppTheme.secondaryDark],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gradient, color: Colors.white54, size: 48),
                    SizedBox(height: 8),
                    Text(
                      'Default Gradient Background',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(WallpaperService wallpaperService) {
    return Card(
      color: AppTheme.cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wallpaper Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            // Select new wallpaper button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickWallpaper,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.photo_library),
                label: const Text('Select from Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Remove wallpaper button (only show if wallpaper is set)
            if (wallpaperService.isWallpaperEnabled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _showRemoveConfirmation,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove Wallpaper'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              
            const SizedBox(height: 16),
            
            // Info text
            Text(
              '• Images will be optimized and saved locally\n'
              '• Supports JPG, PNG formats\n'
              '• Wallpaper applies to home screen only',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
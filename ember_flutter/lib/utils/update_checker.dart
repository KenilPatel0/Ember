import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ember_flutter/services/update_service.dart';

class UpdateChecker {
  static const String _repoUrl = 'https://api.github.com/repos/AIwolfie/Ember/contents/Android_APK';

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode == 200) {
        final List<dynamic> files = jsonDecode(response.body);

        String latestVersion = '0.0.0';
        String downloadUrl = 'https://github.com/AIwolfie/Ember/raw/main/Android_APK/Ember_Latest.apk';

        for (var file in files) {
          final String name = file['name'] as String;
          if (name.startsWith('Ember_v') && name.endsWith('.apk')) {
            final version = name.replaceFirst('Ember_v', '').replaceAll('.apk', '');
            if (_isNewerVersion(latestVersion, version)) {
              latestVersion = version;
            }
          }
        }

        // Simple version comparison against currently running version
        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _UpdateDialog(newVersion: latestVersion, downloadUrl: downloadUrl),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final curr = i < currentParts.length ? currentParts[i] : 0;
        final lat = i < latestParts.length ? latestParts[i] : 0;

        if (lat > curr) return true;
        if (lat < curr) return false;
      }
    } catch (e) {
      return false;
    }
    return false;
  }
}

class _UpdateDialog extends StatefulWidget {
  final String newVersion;
  final String downloadUrl;

  const _UpdateDialog({required this.newVersion, required this.downloadUrl});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _status = '';

  void _startDownload() async {
    setState(() {
      _downloading = true;
      _status = 'Starting download...';
    });

    await UpdateService.instance.downloadApk(
      widget.downloadUrl,
      (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _status = 'Downloading... ${(progress * 100).toStringAsFixed(0)}%';
          });
        }
      },
      (msg, success) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _status = msg;
          });
          if (success) {
            Navigator.of(context).pop();
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Update Available 🚀', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A new version of Ember (v${widget.newVersion}) is available! Please update to get the latest features and bug fixes.',
            style: const TextStyle(color: Colors.white70),
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress, backgroundColor: Colors.white12, color: Colors.orangeAccent),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ] else if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ]
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.grey)),
          ),
        if (!_downloading)
          ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child: const Text('Download Update', style: TextStyle(color: Colors.black)),
          ),
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadCacheEntry {
  final String fileHash;
  final String url;
  final DateTime uploadedAt;

  const UploadCacheEntry({
    required this.fileHash,
    required this.url,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'fileHash': fileHash,
      'url': url,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }

  factory UploadCacheEntry.fromJson(Map<String, dynamic> json) {
    return UploadCacheEntry(
      fileHash: json['fileHash'] as String,
      url: json['url'] as String,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    );
  }
}

class UploadCacheService {
  static const String _key = 'upload_cache';

  Future<String> hashFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<String?> getCachedUrl({
    required String fileHash,
    required Duration rememberFor,
  }) async {
    final entries = await _getEntries();
    final now = DateTime.now();

    for (final entry in entries) {
      if (entry.fileHash != fileHash) continue;

      if (now.difference(entry.uploadedAt) <= rememberFor) {
        return entry.url;
      }
    }

    return null;
  }

  Future<void> save({
    required String fileHash,
    required String url,
  }) async {
    final entries = await _getEntries();
    entries.removeWhere((e) => e.fileHash == fileHash);
    entries.add(
      UploadCacheEntry(
        fileHash: fileHash,
        url: url,
        uploadedAt: DateTime.now(),
      ),
    );

    await _saveEntries(entries);
  }

  Future<List<UploadCacheEntry>> _getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_key);

    if (text == null || text.isEmpty) return [];

    final decoded = jsonDecode(text) as List;

    return decoded
        .map((e) => UploadCacheEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveEntries(List<UploadCacheEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

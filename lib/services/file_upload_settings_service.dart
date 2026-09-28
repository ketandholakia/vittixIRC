import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:vittix_irc/models/file_upload_settings.dart';

class FileUploadSettingsService {
  static const String _key = 'file_upload_settings';

  Future<FileUploadSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_key);

    if (text == null || text.isEmpty) {
      return const FileUploadSettings();
    }

    return FileUploadSettings.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<void> saveSettings(FileUploadSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(settings.toJson()),
    );
  }
}

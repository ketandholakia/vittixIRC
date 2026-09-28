import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vittix_irc/models/app_settings.dart';

class AppSettingsService {
  static const String _key = 'irc_app_settings';

  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);

    if (jsonString == null || jsonString.isEmpty) {
      return const AppSettings();
    }

    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return AppSettings.fromJson(decoded);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(settings.toJson()),
    );
  }
}

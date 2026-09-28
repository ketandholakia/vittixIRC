import 'package:shared_preferences/shared_preferences.dart';

import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/sqlite_message_storage_service.dart';
import 'package:vittix_irc/utils/history_retention_helper.dart';

class HistoryCleanupService {
  static const String _lastCleanupKey = 'last_history_cleanup_at';

  final _settingsService = AppSettingsService();
  final _messageStorage = SqliteMessageStorageService();

  Future<int> cleanupIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final lastCleanupText = prefs.getString(_lastCleanupKey);
    final lastCleanup = lastCleanupText == null
        ? null
        : DateTime.tryParse(lastCleanupText);

    final now = DateTime.now();

    if (lastCleanup != null &&
        now.difference(lastCleanup) < const Duration(hours: 24)) {
      return 0;
    }

    final settings = await _settingsService.getSettings();
    final duration = settings.historyRetention.duration;

    await prefs.setString(_lastCleanupKey, now.toIso8601String());

    if (duration == null) {
      return 0;
    }

    final cutoff = now.subtract(duration);

    return _messageStorage.deleteMessagesOlderThan(cutoff: cutoff);
  }

  Future<int> cleanupNow() async {
    final settings = await _settingsService.getSettings();
    final duration = settings.historyRetention.duration;

    if (duration == null) return 0;

    final cutoff = DateTime.now().subtract(duration);

    return _messageStorage.deleteMessagesOlderThan(cutoff: cutoff);
  }
}

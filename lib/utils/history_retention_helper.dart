import 'package:vittix_irc/models/app_settings.dart';

extension MessageHistoryRetentionHelper on MessageHistoryRetention {
  String get label {
    switch (this) {
      case MessageHistoryRetention.sevenDays:
        return '7 days';
      case MessageHistoryRetention.thirtyDays:
        return '30 days';
      case MessageHistoryRetention.ninetyDays:
        return '90 days';
      case MessageHistoryRetention.forever:
        return 'Forever';
    }
  }

  Duration? get duration {
    switch (this) {
      case MessageHistoryRetention.sevenDays:
        return const Duration(days: 7);
      case MessageHistoryRetention.thirtyDays:
        return const Duration(days: 30);
      case MessageHistoryRetention.ninetyDays:
        return const Duration(days: 90);
      case MessageHistoryRetention.forever:
        return null;
    }
  }
}

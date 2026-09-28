enum MessageHistoryRetention {
  sevenDays,
  thirtyDays,
  ninetyDays,
  forever,
}

class AppSettings {
  static const double minChatFontSize = 12;
  static const double maxChatFontSize = 26;
  static const double defaultChatFontSize = 16;

  final bool darkMode;
  final bool showTimestamps;
  final bool showMediaPreviews;
  final bool showJoinPartMessages;
  final bool showPrivateSystemMessages;
  final bool mentionNotifications;
  final bool privateMessageNotifications;
  final bool volumeKeysAdjustChatFont;
  final bool hotBuffersMoveToTop;
  final List<String> blockedNicks;
  final List<String> friendNicks;
  final double chatFontSize;
  final MessageHistoryRetention historyRetention;

  const AppSettings({
    this.darkMode = false,
    this.showTimestamps = true,
    this.showMediaPreviews = true,
    this.showJoinPartMessages = true,
    this.showPrivateSystemMessages = true,
    this.mentionNotifications = true,
    this.privateMessageNotifications = true,
    this.volumeKeysAdjustChatFont = true,
    this.hotBuffersMoveToTop = true,
    this.blockedNicks = const [],
    this.friendNicks = const [],
    this.chatFontSize = defaultChatFontSize,
    this.historyRetention = MessageHistoryRetention.thirtyDays,
  });

  AppSettings copyWith({
    bool? darkMode,
    bool? showTimestamps,
    bool? showMediaPreviews,
    bool? showJoinPartMessages,
    bool? showPrivateSystemMessages,
    bool? mentionNotifications,
    bool? privateMessageNotifications,
    bool? volumeKeysAdjustChatFont,
    bool? hotBuffersMoveToTop,
    List<String>? blockedNicks,
    List<String>? friendNicks,
    double? chatFontSize,
    MessageHistoryRetention? historyRetention,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      showTimestamps: showTimestamps ?? this.showTimestamps,
      showMediaPreviews: showMediaPreviews ?? this.showMediaPreviews,
      showJoinPartMessages: showJoinPartMessages ?? this.showJoinPartMessages,
      showPrivateSystemMessages:
          showPrivateSystemMessages ?? this.showPrivateSystemMessages,
      mentionNotifications: mentionNotifications ?? this.mentionNotifications,
      privateMessageNotifications:
          privateMessageNotifications ?? this.privateMessageNotifications,
      volumeKeysAdjustChatFont:
          volumeKeysAdjustChatFont ?? this.volumeKeysAdjustChatFont,
      hotBuffersMoveToTop: hotBuffersMoveToTop ?? this.hotBuffersMoveToTop,
      blockedNicks: blockedNicks ?? this.blockedNicks,
      friendNicks: friendNicks ?? this.friendNicks,
      chatFontSize: chatFontSize ?? this.chatFontSize,
      historyRetention: historyRetention ?? this.historyRetention,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'darkMode': darkMode,
      'showTimestamps': showTimestamps,
      'showMediaPreviews': showMediaPreviews,
      'showJoinPartMessages': showJoinPartMessages,
      'showPrivateSystemMessages': showPrivateSystemMessages,
      'mentionNotifications': mentionNotifications,
      'privateMessageNotifications': privateMessageNotifications,
      'volumeKeysAdjustChatFont': volumeKeysAdjustChatFont,
      'hotBuffersMoveToTop': hotBuffersMoveToTop,
      'blockedNicks': blockedNicks,
      'friendNicks': friendNicks,
      'chatFontSize': chatFontSize,
      'historyRetention': historyRetention.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      darkMode: json['darkMode'] as bool? ?? false,
      showTimestamps: json['showTimestamps'] as bool? ?? true,
      showMediaPreviews: json['showMediaPreviews'] as bool? ?? true,
      showJoinPartMessages: json['showJoinPartMessages'] as bool? ?? true,
      showPrivateSystemMessages:
          json['showPrivateSystemMessages'] as bool? ?? true,
      mentionNotifications: json['mentionNotifications'] as bool? ?? true,
      privateMessageNotifications:
          json['privateMessageNotifications'] as bool? ?? true,
      volumeKeysAdjustChatFont:
          json['volumeKeysAdjustChatFont'] as bool? ?? true,
      hotBuffersMoveToTop: json['hotBuffersMoveToTop'] as bool? ?? true,
      blockedNicks: (json['blockedNicks'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((nick) => nick.trim().isNotEmpty)
          .toList(),
      friendNicks: (json['friendNicks'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((nick) => nick.trim().isNotEmpty)
          .toList(),
      chatFontSize:
          (json['chatFontSize'] as num?)?.toDouble() ?? defaultChatFontSize,
      historyRetention: MessageHistoryRetention.values.firstWhere(
        (e) => e.name == json['historyRetention'],
        orElse: () => MessageHistoryRetention.thirtyDays,
      ),
    );
  }
}

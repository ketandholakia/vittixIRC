class WhoisInfo {
  final String nick;
  final String? userHost;
  final String? realName;
  final String? server;
  final String? serverInfo;
  final String? account;
  final List<String> channels;
  final String? idle;
  final DateTime updatedAt;
  final List<String> rawLines;

  const WhoisInfo({
    required this.nick,
    this.userHost,
    this.realName,
    this.server,
    this.serverInfo,
    this.account,
    this.channels = const [],
    this.idle,
    required this.updatedAt,
    this.rawLines = const [],
  });

  WhoisInfo copyWith({
    String? nick,
    String? userHost,
    String? realName,
    String? server,
    String? serverInfo,
    String? account,
    List<String>? channels,
    String? idle,
    DateTime? updatedAt,
    List<String>? rawLines,
  }) {
    return WhoisInfo(
      nick: nick ?? this.nick,
      userHost: userHost ?? this.userHost,
      realName: realName ?? this.realName,
      server: server ?? this.server,
      serverInfo: serverInfo ?? this.serverInfo,
      account: account ?? this.account,
      channels: channels ?? this.channels,
      idle: idle ?? this.idle,
      updatedAt: updatedAt ?? this.updatedAt,
      rawLines: rawLines ?? this.rawLines,
    );
  }
}

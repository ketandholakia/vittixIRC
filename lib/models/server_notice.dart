enum ServerNoticeType {
  info,
  warning,
  error,
  raw,
}

class ServerNotice {
  final String text;
  final DateTime time;
  final ServerNoticeType type;
  final String rawLine;
  final String? channel;

  const ServerNotice({
    required this.text,
    required this.time,
    required this.type,
    required this.rawLine,
    this.channel,
  });
}

class IrcUser {
  final String nick;
  final String prefix;

  const IrcUser({
    required this.nick,
    this.prefix = '',
  });

  String get displayName => '$prefix$nick';
}
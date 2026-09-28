class IrcChannelInfo {
  final String name;
  final int users;
  final String topic;

  const IrcChannelInfo({
    required this.name,
    required this.users,
    required this.topic,
  });
}

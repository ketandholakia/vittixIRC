enum IrcConnectionProfileType {
  normal,
  bouncer,
}

enum IrcBouncerType {
  znc,
  soju,
  other,
}

class ServerConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final bool useTls;
  final String nickname;
  final String username;
  final String realName;
  final IrcConnectionProfileType profileType;
  final IrcBouncerType? bouncerType;
  final String? bouncerNetwork;
  final bool useSasl;
  final String? password;
  final String defaultChannel;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.useTls,
    required this.nickname,
    required this.username,
    required this.realName,
    this.profileType = IrcConnectionProfileType.normal,
    this.bouncerType,
    this.bouncerNetwork,
    this.useSasl = false,
    this.password,
    required this.defaultChannel,
  });

  ServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    bool? useTls,
    String? nickname,
    String? username,
    String? realName,
    IrcConnectionProfileType? profileType,
    IrcBouncerType? bouncerType,
    String? bouncerNetwork,
    bool? useSasl,
    String? password,
    String? defaultChannel,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      useTls: useTls ?? this.useTls,
      nickname: nickname ?? this.nickname,
      username: username ?? this.username,
      realName: realName ?? this.realName,
      profileType: profileType ?? this.profileType,
      bouncerType: bouncerType ?? this.bouncerType,
      bouncerNetwork: bouncerNetwork ?? this.bouncerNetwork,
      useSasl: useSasl ?? this.useSasl,
      password: password ?? this.password,
      defaultChannel: defaultChannel ?? this.defaultChannel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'useTls': useTls,
      'nickname': nickname,
      'username': username,
      'realName': realName,
      'profileType': profileType.name,
      'bouncerType': bouncerType?.name,
      'bouncerNetwork': bouncerNetwork,
      'useSasl': useSasl,
      'defaultChannel': defaultChannel,
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      useTls: json['useTls'] as bool,
      nickname: json['nickname'] as String,
      username: json['username'] as String,
      realName: json['realName'] as String,
      profileType: IrcConnectionProfileType.values.firstWhere(
        (e) => e.name == json['profileType'],
        orElse: () => IrcConnectionProfileType.normal,
      ),
      bouncerType: json['bouncerType'] == null
          ? null
          : IrcBouncerType.values.firstWhere(
              (e) => e.name == json['bouncerType'],
              orElse: () => IrcBouncerType.other,
            ),
      bouncerNetwork: json['bouncerNetwork'] as String?,
      useSasl: json['useSasl'] as bool? ?? false,
      password: json['password'] as String?,
      defaultChannel: json['defaultChannel'] as String,
    );
  }

  String get loginUsername {
    if (profileType != IrcConnectionProfileType.bouncer) return username;

    final network = bouncerNetwork?.trim();
    if (network == null || network.isEmpty) return username;

    switch (bouncerType) {
      case IrcBouncerType.znc: return '$username/$network';
      case IrcBouncerType.soju: return '$username/$network';
      case IrcBouncerType.other:
      case null: return username;
    }
  }
}
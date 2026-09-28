import 'app_settings.dart';
import 'server_config.dart';

class AppBackup {
  final int version;
  final DateTime createdAt;
  final AppSettings settings;
  final List<ServerConfig> servers;

  const AppBackup({
    this.version = 1,
    required this.createdAt,
    required this.settings,
    required this.servers,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'settings': settings.toJson(),
      'servers': servers.map((server) => server.toJson()).toList(),
    };
  }

  factory AppBackup.fromJson(Map<String, dynamic> json) {
    return AppBackup(
      version: json['version'] as int? ?? 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      settings: AppSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      servers: (json['servers'] as List<dynamic>? ?? const [])
          .map((item) => ServerConfig.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A Strict-Transport-Security policy learned from a server's `sts` capability.
class StsPolicy {
  final String host;
  final int securePort;
  final int durationSeconds;
  final DateTime createdAt;

  const StsPolicy({
    required this.host,
    required this.securePort,
    required this.durationSeconds,
    required this.createdAt,
  });

  bool get isExpired =>
      durationSeconds <= 0 ||
      DateTime.now().isAfter(createdAt.add(Duration(seconds: durationSeconds)));

  Map<String, dynamic> toJson() => {
        'securePort': securePort,
        'durationSeconds': durationSeconds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StsPolicy.fromJson(String host, Map<String, dynamic> json) {
    return StsPolicy(
      host: host,
      securePort: json['securePort'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Stores IRCv3 STS policies per host. Policies are observed only (the client
/// never requests the sts capability) and apply to every server profile that
/// points at the same host.
class StsPolicyStore {
  static const String _key = 'irc_sts_policies';

  Future<StsPolicy?> policyFor(String host) async {
    final map = await _readAll();
    return map[host.toLowerCase()];
  }

  Future<void> upsert(StsPolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll();

    map[policy.host.toLowerCase()] = policy;

    await prefs.setString(
      _key,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  Future<void> delete(String host) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll();

    if (!map.containsKey(host.toLowerCase())) return;

    map.remove(host.toLowerCase());
    await prefs.setString(
      _key,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  Future<Map<String, StsPolicy>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      return decoded.map((host, json) {
        final policy = StsPolicy.fromJson(
          host,
          (json as Map).cast<String, dynamic>(),
        );
        return MapEntry(host, policy);
      });
    } catch (_) {
      return {};
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Trust-on-first-use storage for TLS certificate fingerprints, keyed by
/// server profile id. Fingerprints are not secrets, so plain
/// SharedPreferences is appropriate.
class TlsPinStore {
  static const String _key = 'irc_tls_pins';

  Future<String?> pinFor(String serverId) async {
    final map = await _readAll();
    return map[serverId] as String?;
  }

  Future<void> setPin(String serverId, String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll();

    map[serverId] = fingerprint;

    await prefs.setString(_key, jsonEncode(map));
  }

  Future<void> clearPin(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll();

    if (!map.containsKey(serverId)) return;

    map.remove(serverId);
    await prefs.setString(_key, jsonEncode(map));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return {};

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

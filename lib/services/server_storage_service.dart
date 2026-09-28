import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerStorageService {
  static const String _key = 'irc_servers';

  final _secureStorage = const FlutterSecureStorage();

  String _passwordKey(String serverId) => 'irc_server_password_$serverId';

  Future<List<ServerConfig>> getServers() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    final List decoded = jsonDecode(jsonString) as List;

    final servers = decoded
        .map((item) => ServerConfig.fromJson(item as Map<String, dynamic>))
        .toList();

    final result = <ServerConfig>[];

    for (final server in servers) {
      final password = await _secureStorage.read(
        key: _passwordKey(server.id),
      );

      result.add(
        server.copyWith(password: password),
      );
    }

    return result;
  }

  Future<void> saveServers(List<ServerConfig> servers) async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = jsonEncode(
      servers.map((server) => server.toJson()).toList(),
    );

    await prefs.setString(_key, jsonString);
  }

  Future<void> addServer(ServerConfig server) async {
    final servers = await getServers();

    servers.add(
      server.copyWith(password: null),
    );

    await saveServers(servers);

    if (server.password != null && server.password!.isNotEmpty) {
      await _secureStorage.write(
        key: _passwordKey(server.id),
        value: server.password,
      );
    }
  }

  Future<void> updateServer(ServerConfig updatedServer) async {
    final servers = await getServers();

    final index = servers.indexWhere((s) => s.id == updatedServer.id);

    final cleanServer = updatedServer.copyWith(password: null);

    if (index == -1) {
      servers.add(cleanServer);
    } else {
      servers[index] = cleanServer;
    }

    await saveServers(servers);

    if (updatedServer.password != null &&
        updatedServer.password!.isNotEmpty) {
      await _secureStorage.write(
        key: _passwordKey(updatedServer.id),
        value: updatedServer.password,
      );
    } else {
      await _secureStorage.delete(
        key: _passwordKey(updatedServer.id),
      );
    }
  }

  Future<void> deleteServer(String id) async {
    final servers = await getServers();
    servers.removeWhere((server) => server.id == id);
    await saveServers(servers);

    await _secureStorage.delete(
      key: _passwordKey(id),
    );
  }
}

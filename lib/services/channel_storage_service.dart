import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vittix_irc/models/channel.dart';

class ChannelStorageService {
  String _key(String serverId) => 'irc_channels_$serverId';

  Future<List<Channel>> getChannels(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key(serverId));

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    final List decoded = jsonDecode(jsonString) as List;

    return decoded.map((item) {
      final json = item as Map<String, dynamic>;

      return Channel(
        name: json['name'] as String,
        unreadCount: json['unreadCount'] as int? ?? 0,
        isPrivate: json['isPrivate'] as bool? ?? false,
        pinned: json['pinned'] as bool? ?? false,
        modes: json['modes'] as String? ?? '',
      );
    }).toList();
  }

  Future<void> saveChannels({
    required String serverId,
    required List<Channel> channels,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final cleanChannels = channels
        .where((c) => !c.isPrivate)
        .map((c) {
          return {
            'name': c.name,
            'unreadCount': 0,
            'isPrivate': false,
            'pinned': c.pinned,
            'modes': c.modes,
          };
        })
        .toList();

    await prefs.setString(
      _key(serverId),
      jsonEncode(cleanChannels),
    );
  }
}

import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/message_search_result.dart';

import 'app_database.dart';

class SqliteMessageStorageService {
  static const int maxMessagesPerChat = 200;

  Future<void> addMessage({
    required String serverId,
    required String target,
    required ChatMessage message,
  }) async {
    final db = await AppDatabase.instance.database;

    await db.insert('messages', {
      'server_id': serverId,
      'target': target.toLowerCase(),
      'sender': message.sender,
      'text': message.text,
      'time': message.time.toIso8601String(),
      'is_me': message.isMe ? 1 : 0,
      'is_system': message.isSystem ? 1 : 0,
      'type': message.type.name,
    });
  }

  Future<List<ChatMessage>> getMessages({
    required String serverId,
    required String target,
  }) async {
    final db = await AppDatabase.instance.database;

    final rows = await db.query(
      'messages',
      where: 'server_id = ? AND target = ?',
      whereArgs: [serverId, target.toLowerCase()],
      orderBy: 'time ASC',
    );

    return rows.map(_fromRow).toList();
  }

  Future<List<ChatMessage>> getMessagesPage({
    required String serverId,
    required String target,
    required int offsetFromEnd,
    int limit = 50,
  }) async {
    final db = await AppDatabase.instance.database;

    final rows = await db.query(
      'messages',
      where: 'server_id = ? AND target = ?',
      whereArgs: [serverId, target.toLowerCase()],
      orderBy: 'time DESC',
      limit: limit,
      offset: offsetFromEnd,
    );

    return rows.reversed.map(_fromRow).toList();
  }

  /// Newest non-system message time for a target, used as the CHATHISTORY
  /// backfill cursor. Returns null when nothing is stored locally.
  Future<DateTime?> getLastMessageTime({
    required String serverId,
    required String target,
  }) async {
    final db = await AppDatabase.instance.database;

    final rows = await db.query(
      'messages',
      columns: ['time'],
      where: 'server_id = ? AND target = ? AND is_system = 0',
      whereArgs: [serverId, target.toLowerCase()],
      orderBy: 'time DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['time'] as String? ?? '');
  }

  Future<void> clearMessages({
    required String serverId,
    required String target,
  }) async {
    final db = await AppDatabase.instance.database;

    await db.delete(
      'messages',
      where: 'server_id = ? AND target = ?',
      whereArgs: [serverId, target.toLowerCase()],
    );
  }

  Future<int> clearAllMessages() async {
    final db = await AppDatabase.instance.database;
    return db.delete('messages');
  }

  Future<int> deleteMessagesOlderThan({
    required DateTime cutoff,
  }) async {
    final db = await AppDatabase.instance.database;

    return db.delete(
      'messages',
      where: 'time < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }

  Future<List<MessageSearchResult>> searchMessages({
    required String serverId,
    required List<String> targets,
    required String query,
    int limit = 100,
  }) async {
    final q = query.trim();

    if (q.isEmpty || targets.isEmpty) return [];

    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(targets.length, '?').join(',');

    final rows = await db.query(
      'messages',
      where:
          'server_id = ? AND target IN ($placeholders) AND '
          '(LOWER(text) LIKE ? OR LOWER(sender) LIKE ?)',
      whereArgs: [
        serverId,
        ...targets.map((t) => t.toLowerCase()),
        '%${q.toLowerCase()}%',
        '%${q.toLowerCase()}%',
      ],
      orderBy: 'time DESC',
      limit: limit,
    );

    return rows.map((row) {
      return MessageSearchResult(
        target: row['target'] as String,
        message: _fromRow(row),
      );
    }).toList();
  }

  ChatMessage _fromRow(Map<String, Object?> row) {
    final typeName = row['type'] as String? ?? 'normal';

    return ChatMessage(
      sender: row['sender'] as String,
      target: row['target'] as String,
      text: row['text'] as String,
      time: DateTime.parse(row['time'] as String),
      isMe: (row['is_me'] as int? ?? 0) == 1,
      isSystem: (row['is_system'] as int? ?? 0) == 1,
      type: ChatMessageType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => ChatMessageType.normal,
      ),
    );
  }
}

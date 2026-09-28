import 'package:flutter/material.dart';
import 'package:vittix_irc/services/app_database.dart';

class MentionsHubScreen extends StatelessWidget {
  const MentionsHubScreen({super.key});

  Future<List<Map<String, dynamic>>> _fetchMentions() async {
    // Queries the SQLite database we built in Phase 1
    // Note: You would adjust this query based on how you flag mentions in your parser
    final db = await AppDatabase.instance.database;
    return await db.query(
      'messages',
      where: 'type = ? OR is_system = ?', 
      whereArgs: ['mention', 0], // Assuming you set message type to 'mention'
      orderBy: 'time DESC',
      limit: 50,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mentions & Highlights')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchMentions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No mentions yet!'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final msg = snapshot.data![index];
              return ListTile(
                leading: const Icon(Icons.alternate_email, color: Colors.blue),
                title: Text('${msg['sender']} in ${msg['target']}'),
                subtitle: Text(msg['text']),
                trailing: Text(msg['time'].toString().substring(11, 16)), // Simple time extract
              );
            },
          );
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:vittix_irc/models/server_notice.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';

class ServerNoticesScreen extends StatelessWidget {
  final IrcSessionController controller;

  const ServerNoticesScreen({
    super.key,
    required this.controller,
  });

  IconData _icon(ServerNoticeType type) {
    switch (type) {
      case ServerNoticeType.info:
        return Icons.info_outline;
      case ServerNoticeType.warning:
        return Icons.warning_amber;
      case ServerNoticeType.error:
        return Icons.error_outline;
      case ServerNoticeType.raw:
        return Icons.code;
    }
  }

  String _time(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final notices = controller.state.notices.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Notices'),
      ),
      body: notices.isEmpty
          ? const Center(
              child: Text('No server notices yet'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final notice = notices[index];

                return ListTile(
                  leading: Icon(_icon(notice.type)),
                  title: Text(notice.text),
                  subtitle: SelectableText(
                    '${_time(notice.time)}\n${notice.rawLine}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}

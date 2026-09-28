import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/widgets/app_badge.dart';

class ServerTile extends StatelessWidget {
  final ServerConfig server;
  final IrcConnectionStatus? status;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onDisconnect;

  const ServerTile({
    super.key,
    required this.server,
    required this.status,
    required this.unreadCount,
    required this.onTap,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
    this.onDisconnect,
  });

  bool get isConnected => status == IrcConnectionStatus.connected;

  String get statusText {
    switch (status) {
      case IrcConnectionStatus.connecting:
        return 'Connecting';
      case IrcConnectionStatus.connected:
        return 'Connected';
      case IrcConnectionStatus.error:
        return 'Connection error';
      case IrcConnectionStatus.disconnected:
      case null:
        return 'Disconnected';
    }
  }

  IconData get statusIcon {
    switch (status) {
      case IrcConnectionStatus.connected:
        return Icons.cloud_done;
      case IrcConnectionStatus.connecting:
        return Icons.sync;
      case IrcConnectionStatus.error:
        return Icons.error_outline;
      case IrcConnectionStatus.disconnected:
      case null:
        return Icons.cloud_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileText = server.profileType == IrcConnectionProfileType.bouncer
        ? 'Bouncer: ${server.bouncerType?.name ?? 'other'}'
        : 'Normal IRC';

    final card = Slidable(
      key: ValueKey(server.id),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.72,
        children: [
          SlidableAction(
            onPressed: (_) => onConnect(),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            icon: isConnected ? Icons.open_in_new : Icons.cloud_done,
            label: isConnected ? 'Open' : 'Connect',
          ),
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
            foregroundColor: Theme.of(context).colorScheme.onTertiary,
            icon: Icons.edit,
            label: 'Edit',
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: Card(
        child: ListTile(
        leading: Icon(statusIcon),
        title: Text(server.name),
        subtitle: Text(
          '${server.host}:${server.port}\n'
          '$statusText • $profileText • Nick: ${server.nickname}',
        ),
        isThreeLine: true,
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unreadCount > 0)
              AppBadge(label: unreadCount.toString()),
            SizedBox(
              width: 40,
              height: 40,
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'connect':
                      onConnect();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'disconnect':
                      onDisconnect?.call();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'connect',
                    child: Text(isConnected ? 'Open' : 'Connect'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  if (isConnected)
                    const PopupMenuItem(
                      value: 'disconnect',
                      child: Text('Disconnect'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );

    return card.animate().fadeIn(duration: 220.ms).slideX(
          begin: 0.03,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOut,
        );
  }
}

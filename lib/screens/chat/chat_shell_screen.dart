import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/server_notice.dart';
import 'package:vittix_irc/screens/chat/global_message_search_screen.dart';
import 'package:vittix_irc/screens/chat/chat_screen.dart';
import 'package:vittix_irc/screens/server/channel_list_screen.dart'
    as server_channel_list;
import 'package:vittix_irc/screens/server/whois_screen.dart';
import 'package:vittix_irc/screens/settings_screen.dart';
import 'package:vittix_irc/state/active_session_registry.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';
import 'package:vittix_irc/state/session_manager.dart';
import 'package:vittix_irc/utils/nick_color_helper.dart';
import 'package:vittix_irc/widgets/app_badge.dart';
import 'package:vittix_irc/widgets/channel_tile.dart';

class ChatShellScreen extends StatefulWidget {
  final IrcSessionController controller;
  final String? initialTarget;
  final String? initialSharedText;

  const ChatShellScreen({
    super.key,
    required this.controller,
    this.initialTarget,
    this.initialSharedText,
  });

  @override
  State<ChatShellScreen> createState() => _ChatShellScreenState();
}

class _ChatShellScreenState extends State<ChatShellScreen> {
  late final IrcSessionController _controller;
  final Set<String> _pendingKeyDialogs = {};
  final TextEditingController _drawerSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
    _controller.onServerNotice = _handleServerNotice;
    _controller.onInviteReceived = _handleInviteReceived;

    ActiveSessionRegistry.setActive(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = widget.initialTarget;
      if (target != null) {
        _controller.openTarget(
          target,
          isPrivate: !target.startsWith('#'),
        );
      }
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildConnectionBanner() {
    final status = _controller.state.status;
    final socket = _controller.irc;

    if (status == IrcConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    final isReconnecting = status == IrcConnectionStatus.disconnected &&
        socket.lastReconnectDelaySeconds != null;
    final bgColor = isReconnecting
        ? Theme.of(context).colorScheme.tertiary
        : status == IrcConnectionStatus.connecting
            ? Colors.orange.shade700
            : Theme.of(context).colorScheme.error;
    final text = isReconnecting
        ? 'Reconnecting in ${socket.lastReconnectDelaySeconds}s...'
        : status == IrcConnectionStatus.connecting
            ? 'Connecting to ${_controller.server.host}...'
            : 'Connection lost';

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(
          begin: -0.08,
          end: 0,
          duration: 180.ms,
          curve: Curves.easeOut,
        );
  }

  String get _statusText {
    switch (_controller.state.status) {
      case IrcConnectionStatus.connecting:
        return 'Connecting';
      case IrcConnectionStatus.connected:
        return 'Connected';
      case IrcConnectionStatus.disconnected:
        return 'Disconnected';
      case IrcConnectionStatus.error:
        return 'Connection error';
    }
  }

  String? _matchBadgeForChannel({
    required String query,
    required dynamic channel,
  }) {
    if (query.isEmpty) return null;

    final name = channel.name.toLowerCase();
    final modes = channel.modes.toLowerCase();
    final topic = _controller.topicFor(channel.name)?.toLowerCase() ?? '';
    final serverName = _controller.server.name.toLowerCase();
    final serverHost = _controller.server.host.toLowerCase();

    if (name.contains(query)) {
      return channel.isPrivate ? 'nick' : 'name';
    }
    if (topic.contains(query)) {
      return 'topic';
    }
    if (modes.contains(query)) {
      return 'modes';
    }
    if (serverName.contains(query) || serverHost.contains(query)) {
      return 'server';
    }
    if ((channel.isPrivate ? 'private' : 'channel').contains(query)) {
      return channel.isPrivate ? 'private' : 'channel';
    }

    return null;
  }

  Widget _buildUsersDrawer() {
    final target = _controller.state.activeTarget;
    if (target != null && !target.startsWith('#')) {
      return _buildPrivateUserDrawer(target);
    }

    final users =
        target == null ? const <String>[] : _controller.usersFor(target);

    String query = '';
    bool opsOnly = false;
    bool sortByRole = false;

    return SafeArea(
      child: SizedBox(
        width: 344,
        child: StatefulBuilder(
          builder: (context, setState) {
            List<String> filteredUsers() {
              final result = users.where((user) {
                final clean = _cleanNick(user).toLowerCase();
                if (opsOnly && !_isOperator(user)) return false;
                if (query.isNotEmpty && !clean.contains(query)) return false;
                return true;
              }).toList();

              result.sort((a, b) {
                if (sortByRole) {
                  final roleA = _roleWeight(a);
                  final roleB = _roleWeight(b);
                  if (roleA != roleB) return roleA.compareTo(roleB);
                }
                return _cleanNick(a)
                    .toLowerCase()
                    .compareTo(_cleanNick(b).toLowerCase());
              });
              return result;
            }

            final filtered = filteredUsers();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 10, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Users (${users.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              target ?? 'No channel selected',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search users',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      isDense: true,
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (value) {
                      query = value.trim().toLowerCase();
                      setState(() {});
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: [
                      FilterChip(
                        label: const Text('Ops only'),
                        selected: opsOnly,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        onSelected: (value) {
                          opsOnly = value;
                          setState(() {});
                        },
                      ),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Name'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Role'),
                          ),
                        ],
                        selected: {sortByRole},
                        onSelectionChanged: (selection) {
                          sortByRole = selection.first;
                          setState(() {});
                        },
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              target == null
                                  ? 'Open a channel to see users.'
                                  : 'No users match your filters.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 10),
                          itemBuilder: (_, index) {
                            final user = filtered[index];
                            final clean = _cleanNick(user);
                            final role = _userRole(user);
                            final isFriend = _controller.friendNicks.any(
                              (nick) =>
                                  nick.toLowerCase() == clean.toLowerCase(),
                            );
                            final isOnline = _controller.isFriendOnline(user);
                            final accent = NickColorHelper.forNick(
                              context,
                              clean,
                            );

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                if (clean.isEmpty) return;
                                Navigator.pop(context);
                                await _controller.openTarget(
                                  clean,
                                  isPrivate: true,
                                );
                              },
                              onLongPress: () => _showUserActions(clean),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: accent.withValues(
                                        alpha: 0.16,
                                      ),
                                      child: Text(
                                        clean.isEmpty
                                            ? '?'
                                            : clean[0].toUpperCase(),
                                        style: TextStyle(
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        clean,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: role.color,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AppBadge(
                                      label: isFriend
                                          ? (isOnline ? 'online' : 'offline')
                                          : role.label,
                                      backgroundColor: isFriend
                                          ? (isOnline
                                              ? Colors.green
                                              : Colors.grey)
                                          : role.color,
                                      fontSize: 10.5,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'User info',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      icon: const Icon(Icons.info_outline),
                                      onPressed: () => _openWhois(clean),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPrivateUserDrawer(String nick) {
    final info = _controller.whoisFor(nick);
    final accent = NickColorHelper.forNick(context, nick);

    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text('User', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(nick),
            trailing: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: accent.withValues(alpha: 0.16),
                      child: Text(
                        nick.isEmpty ? '?' : nick[0].toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nick,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            info?.account?.isNotEmpty == true
                                ? 'Account: ${info!.account}'
                                : 'Private conversation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('View WHOIS'),
                  subtitle: const Text('Open user details'),
                  onTap: () => _openWhois(nick),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh WHOIS'),
                  subtitle: const Text('Request latest user info'),
                  onTap: () => _controller.requestWhois(nick),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy nick'),
                  subtitle: Text(nick),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: nick));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied $nick')),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alternate_email),
                  title: const Text('Copy mention'),
                  subtitle: Text('$nick:'),
                  onTap: () {
                    final mention = '$nick: ';
                    Clipboard.setData(ClipboardData(text: mention));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Mention copied: $mention')),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('Add to friends'),
                  subtitle: const Text('Track online status'),
                  onTap: () async {
                    await _controller.addFriendNick(nick);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added $nick to friends')),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_sweep_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Clear chat history'),
                  subtitle: const Text('Delete local messages for this chat'),
                  onTap: () => _confirmClearChatHistory(nick),
                ),
                const Divider(height: 24),
                _privateUserInfoRow('Host', info?.userHost ?? 'Unknown'),
                _privateUserInfoRow('Real name', info?.realName ?? 'Unknown'),
                _privateUserInfoRow('Server', info?.server ?? 'Unknown'),
                _privateUserInfoRow('Idle', info?.idle ?? 'Unknown'),
                _privateUserInfoRow(
                  'Shared rooms',
                  info?.channels.isNotEmpty == true
                      ? info!.channels.join(', ')
                      : 'Unknown',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearChatHistory(String target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear chat history?'),
          content: Text(
            'This will delete local message history for $target. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _controller.clearMessages(target);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleared chat history for $target')),
    );
  }

  Widget _privateUserInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  String _cleanNick(String nick) {
    return nick.replaceAll('@', '').replaceAll('+', '').trim();
  }

  bool _isOperator(String nick) => nick.startsWith('@');

  ({String label, Color color}) _userRole(String nick) {
    if (nick.startsWith('@')) {
      return (label: 'Op', color: Colors.redAccent);
    }
    if (nick.startsWith('+')) {
      return (label: 'Voice', color: Colors.green);
    }
    return (label: 'Member', color: Theme.of(context).colorScheme.primary);
  }

  int _roleWeight(String nick) {
    if (nick.startsWith('@')) return 0;
    if (nick.startsWith('+')) return 1;
    return 2;
  }

  Future<void> _openWhois(String nick) async {
    if (nick.isEmpty) return;
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhoisScreen(
          controller: _controller,
          nick: nick,
        ),
      ),
    );
  }

  void _showUserActions(String nick) {
    if (nick.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    nick,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('User actions'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Open PM'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pop(context);
                    _controller.openTarget(
                      nick,
                      isPrivate: true,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('View WHOIS'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openWhois(nick);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy nick'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: nick));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied $nick')),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.alternate_email,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Copy mention'),
                  onTap: () {
                    final mention = '$nick: ';
                    Clipboard.setData(ClipboardData(text: mention));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Mention copied: $mention')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('Add to friends'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _controller.addFriendNick(nick);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added $nick to friends')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    ActiveSessionRegistry.clear(_controller);
    if (_controller.onServerNotice == _handleServerNotice) {
      _controller.onServerNotice = null;
    }
    if (_controller.onInviteReceived == _handleInviteReceived) {
      _controller.onInviteReceived = null;
    }
    _controller.removeListener(_onControllerChanged);
    _drawerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinChannelDialog() async {
    final channelCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    final result = await showDialog<({String channel, String? key})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: channelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Channel',
                hintText: '#channel',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Key / Password',
                hintText: 'Optional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              var channel = channelCtrl.text.trim();
              final key = keyCtrl.text.trim();

              if (channel.isEmpty) return;
              if (!channel.startsWith('#')) channel = '#$channel';

              Navigator.pop(
                dialogContext,
                (
                  channel: channel,
                  key: key.isEmpty ? null : key,
                ),
              );
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );

    channelCtrl.dispose();
    keyCtrl.dispose();

    if (result == null) return;

    await _controller.joinChannel(
      result.channel,
      key: result.key,
    );
  }

  Future<String?> _askChannelKey(String channel) async {
    final controller = TextEditingController();

    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Channel key required'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Key for $channel',
            hintText: 'Enter channel password',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );

    controller.dispose();
    return key;
  }

  Future<void> _handleServerNotice(ServerNotice notice) async {
    if (notice.type != ServerNoticeType.error) return;
    if (IrcParser.numericFromLine(notice.rawLine) != '475') return;

    final channel = notice.channel;
    if (channel == null || channel.isEmpty) return;

    final keyId = channel.toLowerCase();
    if (_pendingKeyDialogs.contains(keyId)) return;
    _pendingKeyDialogs.add(keyId);

    final key = await _askChannelKey(channel);

    if (!mounted) return;

    _pendingKeyDialogs.remove(keyId);

    if (key == null || key.isEmpty) return;

    await _controller.joinChannel(
      channel,
      key: key,
    );
  }

  Future<void> _handleInviteReceived(String inviter, String channel) async {
    if (!mounted) return;

    final join = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Channel Invite'),
        content: Text('$inviter invited you to join $channel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ignore'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (join == true) {
      if (!mounted) return;
      await _controller.joinChannel(channel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final channels = [...state.channels]..sort((a, b) {
        if (a.pinned != b.pinned) {
          return a.pinned ? -1 : 1;
        }
        if (a.unreadCount != b.unreadCount) {
          return b.unreadCount.compareTo(a.unreadCount);
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final query = _drawerSearchCtrl.text.trim().toLowerCase();
    final serverMatches = query.isNotEmpty &&
        (_controller.server.name.toLowerCase().contains(query) ||
            _controller.server.host.toLowerCase().contains(query));
    final filteredChannels = query.isEmpty
        ? channels
        : channels.where((channel) {
            final topic =
                _controller.topicFor(channel.name)?.toLowerCase() ?? '';
            return channel.name.toLowerCase().contains(query) ||
                channel.modes.toLowerCase().contains(query) ||
                topic.contains(query) ||
                (channel.isPrivate ? 'private' : 'channel').contains(query) ||
                serverMatches;
          }).toList();
    final selectedChannel = state.activeTarget;
    final isPrivateTarget =
        selectedChannel != null && !selectedChannel.startsWith('#');

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  _controller.server.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(_controller.server.host),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Room browser',
                      icon: const Icon(Icons.dashboard_outlined),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                server_channel_list.ChannelListScreen(
                              controller: _controller,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Search messages',
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GlobalMessageSearchScreen(
                              controller: _controller,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Join channel',
                      icon: const Icon(Icons.add),
                      onPressed: _joinChannelDialog,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  controller: _drawerSearchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _drawerSearchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _drawerSearchCtrl.clear();
                              setState(() {});
                            },
                          ),
                    hintText: 'Search rooms',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Column(
                  children: [
                    if (query.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            serverMatches
                                ? 'Server match: ${_controller.server.name}'
                                : 'Searching rooms, topics, and server details',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    Expanded(
                      child: filteredChannels.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No rooms match your search.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: KeyedSubtree(
                                key: ValueKey(
                                    '$query-${filteredChannels.length}'),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: filteredChannels.length,
                                  itemBuilder: (_, index) {
                                    final channel = filteredChannels[index];
                                    final selected =
                                        channel.name.toLowerCase() ==
                                            selectedChannel?.toLowerCase();

                                    return ChannelTile(
                                      channel: channel,
                                      selected: selected,
                                      searchQuery: query,
                                      matchBadge: _matchBadgeForChannel(
                                        query: query,
                                        channel: channel,
                                      ),
                                      onTap: () {
                                        _controller.selectTarget(channel.name);
                                        Navigator.pop(context);
                                      },
                                      onSearch: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                GlobalMessageSearchScreen(
                                              controller: _controller,
                                              target: channel.name,
                                            ),
                                          ),
                                        );
                                      },
                                      onPin: channel.isPrivate
                                          ? null
                                          : () => _controller
                                              .togglePinned(channel.name),
                                      onMoveUp: channel.isPrivate
                                          ? null
                                          : () => _controller.moveChannel(
                                              channel.name, -1),
                                      onMoveDown: channel.isPrivate
                                          ? null
                                          : () => _controller.moveChannel(
                                              channel.name, 1),
                                      onClose: () {
                                        if (channel.isPrivate) {
                                          _controller
                                              .closePrivateTarget(channel.name);
                                          return;
                                        }

                                        _controller.irc
                                            .sendRaw('PART ${channel.name}');
                                      },
                                    ).animate(
                                      delay: Duration(
                                        milliseconds:
                                            (index * 14).clamp(0, 180),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Disconnect'),
                onTap: () async {
                  await SessionManager.instance
                      .disconnect(_controller.server.id);

                  if (!context.mounted) return;

                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('App settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      endDrawer: Drawer(
        child: _buildUsersDrawer(),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedChannel ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            Text(
              state.topicsByTarget[selectedChannel?.toLowerCase() ?? ''] ??
                  '${_controller.server.name} • $_statusText • Nick: ${_controller.currentNick}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search messages',
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GlobalMessageSearchScreen(
                    controller: _controller,
                  ),
                ),
              );
            },
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: isPrivateTarget ? 'User actions' : 'Users',
              icon: Icon(isPrivateTarget ? Icons.person_outline : Icons.people),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
          IconButton(
            tooltip: 'Join channel',
            icon: const Icon(Icons.add),
            onPressed: _joinChannelDialog,
          ),
        ],
      ),
      body: selectedChannel == null
          ? const Center(child: Text('No channel selected'))
          : Column(
              children: [
                _buildConnectionBanner(),
                Expanded(
                  child: ChatScreen(
                    key: ValueKey(selectedChannel),
                    controller: _controller,
                    channelName: selectedChannel,
                    initialSharedText: widget.initialSharedText,
                  ),
                ),
              ],
            ),
    );
  }
}

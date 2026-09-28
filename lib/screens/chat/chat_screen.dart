import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:vittix_irc/core/irc_command_help.dart';
import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/share_intent_service.dart';
import 'package:vittix_irc/services/shared_file_queue_service.dart';
import 'package:vittix_irc/services/volume_key_service.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';
import 'package:vittix_irc/state/upload_controller.dart';
import 'package:vittix_irc/screens/chat/upload_queue_screen.dart';
import 'package:vittix_irc/screens/server/whois_screen.dart';
import 'package:vittix_irc/utils/nick_color_helper.dart';
import 'package:vittix_irc/utils/url_helper.dart';
import 'package:vittix_irc/widgets/chat_bubble.dart';
import 'package:vittix_irc/widgets/app_badge.dart';
import 'package:vittix_irc/widgets/empty_state.dart';
import 'package:vittix_irc/widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  final IrcSessionController controller;
  final String channelName;
  final String? initialSharedText;

  const ChatScreen({
    super.key,
    required this.controller,
    required this.channelName,
    this.initialSharedText,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  final _messageInputKey = GlobalKey<MessageInputState>();
  final Set<String> _selectedMessages = {};
  final TextEditingController _userSearchCtrl = TextEditingController();
  final _uploadController = UploadController();
  final _settingsService = AppSettingsService();
  AppSettings _settings = const AppSettings();
  bool _loadingOlder = false;
  double _oldMaxScrollExtent = 0;
  double _lastViewInsetBottom = 0;
  String _userSortMode = 'name';
  bool _showOpsOnly = false;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  StreamSubscription<String>? _volumeKeySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    widget.controller.addListener(_onControllerChanged);
    widget.controller.loadMessages(widget.channelName);
    _scrollCtrl.addListener(_onScroll);
    _consumePendingSharedFiles();
    _consumePendingSharedText();
    _shareSub = ShareIntentService.instance.sharedFiles.listen((_) {
      _consumePendingSharedFiles();
      _consumePendingSharedText();
    });

    _loadSettings();

    if (_isPrivateMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.requestWhois(_displayTarget);
      });
    }

    if (widget.initialSharedText != null &&
        widget.initialSharedText!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messageInputKey.currentState
            ?.insertSharedText(widget.initialSharedText!);
      });
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final messages = widget.controller.messagesFor(_displayTarget);
    if (widget.controller.state.highlightedMessageTime != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlightedMessage(messages);
      });
      return;
    }

    _scrollToBottom();
  }

  Widget _buildPrivateTargetTabs() {
    final privateTargets = _privateTargets;
    if (privateTargets.length < 2) return const SizedBox.shrink();
    final activeTarget = _displayTarget.toLowerCase();
    final sortedTargets = [
      ...privateTargets.where((target) => target.toLowerCase() == activeTarget),
      ...privateTargets.where((target) => target.toLowerCase() != activeTarget),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: sortedTargets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) {
                  final target = sortedTargets[index];
                  final selected = target.toLowerCase() == activeTarget;
                  final color = NickColorHelper.forNick(context, target);
                  final unread = widget.controller.state.channels
                      .where((channel) =>
                          channel.name.toLowerCase() == target.toLowerCase())
                      .map((channel) => channel.unreadCount)
                      .fold<int>(0, (value, element) => element);

                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async => widget.controller.selectTarget(target),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.only(left: 10, right: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            bottom: BorderSide(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                target.isEmpty ? '?' : target[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                target,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              AppBadge(
                                label: unread.toString(),
                                backgroundColor: selected
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ],
                            const SizedBox(width: 2),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await widget.controller
                                    .closePrivateTarget(target);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 15,
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 160.ms).slideY(
                        begin: 0.08,
                        end: 0,
                        duration: 160.ms,
                        curve: Curves.easeOut,
                      );
                },
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Private chats',
              icon: const Icon(Icons.more_horiz),
              onSelected: (target) async {
                if (target == '__close_active__') {
                  await widget.controller.closePrivateTarget(_displayTarget);
                  return;
                }

                await widget.controller.selectTarget(target);
              },
              itemBuilder: (_) => [
                for (final target in sortedTargets)
                  PopupMenuItem<String>(
                    value: target,
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: NickColorHelper.forNick(context, target),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            target,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.controller.state.channels
                                .where((channel) =>
                                    channel.name.toLowerCase() ==
                                    target.toLowerCase())
                                .map((channel) => channel.unreadCount)
                                .fold<int>(0, (value, element) => element) >
                            0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              widget.controller.state.channels
                                  .where((channel) =>
                                      channel.name.toLowerCase() ==
                                      target.toLowerCase())
                                  .map((channel) => channel.unreadCount)
                                  .fold<int>(0, (value, element) => element)
                                  .toString(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: '__close_active__',
                  child: Row(
                    children: [
                      Icon(
                        Icons.close,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Close active PM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sortedTargets.isEmpty)
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Text('No private chats'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onScroll() async {
    if (!_scrollCtrl.hasClients) return;

    if (mounted) {
      setState(() {});
    }

    if (_loadingOlder) return;

    if (_scrollCtrl.position.pixels <= 80) {
      _loadingOlder = true;
      _oldMaxScrollExtent = _scrollCtrl.position.maxScrollExtent;

      await widget.controller.loadOlderMessages(_displayTarget);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;

        final newMax = _scrollCtrl.position.maxScrollExtent;
        final diff = newMax - _oldMaxScrollExtent;

        _scrollCtrl.jumpTo(_scrollCtrl.position.pixels + diff);
        _loadingOlder = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.getSettings();

    if (!mounted) return;

    setState(() {
      _settings = settings;
    });

    await _configureVolumeKeys();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;

      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _goToBottom() {
    if (!_scrollCtrl.hasClients) return;

    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    final position = _scrollCtrl.position;
    return (position.maxScrollExtent - position.pixels) <= 80;
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final view = View.of(context);
    final newBottomInset = view.viewInsets.bottom / view.devicePixelRatio;
    final keyboardOpened =
        newBottomInset > _lastViewInsetBottom && newBottomInset > 0;

    _lastViewInsetBottom = newBottomInset;

    if (keyboardOpened && _isNearBottom) {
      _scrollToBottom();
    }
  }

  Future<void> _configureVolumeKeys() async {
    await VolumeKeyService.instance.setEnabled(true);

    await _volumeKeySub?.cancel();
    _volumeKeySub = null;

    _volumeKeySub = VolumeKeyService.instance.events.listen((event) {
      if (!mounted) return;

      if (event == 'volume_up') {
        if (_settings.volumeKeysAdjustChatFont) {
          _changeChatFontSize(1);
        } else {
          _messageInputKey.currentState?.previousHistory();
        }
      } else if (event == 'volume_down') {
        if (_settings.volumeKeysAdjustChatFont) {
          _changeChatFontSize(-1);
        } else {
          _messageInputKey.currentState?.nextHistory();
        }
      }
    });
  }

  double _clampChatFontSize(double size) {
    return size
        .clamp(
          AppSettings.minChatFontSize,
          AppSettings.maxChatFontSize,
        )
        .toDouble();
  }

  Future<void> _changeChatFontSize(double delta) async {
    final nextSize = _clampChatFontSize(_settings.chatFontSize + delta);
    if (nextSize == _settings.chatFontSize) return;

    final updated = _settings.copyWith(chatFontSize: nextSize);

    setState(() {
      _settings = updated;
    });

    await _settingsService.saveSettings(updated);

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Chat text size ${nextSize.toStringAsFixed(0)} pt'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _consumePendingSharedFiles() {
    final files = SharedFileQueueService.instance.consumePendingFiles();

    if (files.isEmpty) return;

    _uploadController.addFiles(files);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${files.length} file(s) added to upload queue'),
      ),
    );
  }

  void _consumePendingSharedText() {
    final texts = SharedFileQueueService.instance.consumePendingText();

    if (texts.isEmpty) return;

    final input = _messageInputKey.currentState;
    if (input == null) return;

    for (final text in texts) {
      input.insertSharedText(text);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${texts.length} shared text item(s) added to composer'),
      ),
    );
  }

  void _openUploadQueue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UploadQueueScreen(
          controller: _uploadController,
        ),
      ),
    );
  }

  String _selectionKey(ChatMessage message) {
    return '${message.sender}_${message.target}_${message.time.toIso8601String()}_${message.text.hashCode}';
  }

  void _toggleMessageSelection(ChatMessage message) {
    final key = _selectionKey(message);
    setState(() {
      if (!_selectedMessages.add(key)) {
        _selectedMessages.remove(key);
      }
    });
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    VolumeKeyService.instance.setEnabled(false);
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _scrollCtrl.removeListener(_onScroll);
    _shareSub?.cancel();
    _volumeKeySub?.cancel();
    _scrollCtrl.dispose();
    _messageKeys.clear();
    _uploadController.dispose();
    super.dispose();
  }

  String _messageKey(ChatMessage message) {
    return '${message.sender}_${message.target}_${message.time.toIso8601String()}_${message.text.hashCode}';
  }

  void _scrollToHighlightedMessage(List<ChatMessage> messages) {
    final highlightTime = widget.controller.state.highlightedMessageTime;
    if (highlightTime == null) return;

    final match = messages.where((m) {
      return m.time.isAtSameMomentAs(highlightTime);
    }).toList();

    if (match.isEmpty) return;

    final key = _messageKeys[_messageKey(match.first)];
    final context = key?.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.35,
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        widget.controller.clearHighlightedMessage();
      }
    });
  }

  IrcConnectionStatus get status => widget.controller.state.status;
  String get _displayTarget =>
      widget.controller.state.activeTarget ?? widget.channelName;

  List<ChatMessage> get messages {
    final targets = <String>{
      widget.channelName.trim().toLowerCase(),
      _displayTarget.trim().toLowerCase(),
    };

    final merged = <ChatMessage>[];
    final seen = <String>{};

    for (final target in targets) {
      for (final message in widget.controller.messagesFor(target)) {
        final key =
            '${message.sender}|${message.target.trim().toLowerCase()}|${message.time.toIso8601String()}|${message.text}|${message.type.name}|${message.isMe}|${message.isSystem}';
        if (seen.add(key)) {
          merged.add(message);
        }
      }
    }

    merged.sort((a, b) => a.time.compareTo(b.time));
    return merged;
  }

  Future<void> _reconnect() async {
    await widget.controller.addSystemMessage(
      _displayTarget,
      'Reconnecting...',
    );

    try {
      await widget.controller.irc.connect(widget.controller.server);

      await widget.controller.addSystemMessage(
        _displayTarget,
        'Reconnected',
      );
    } catch (e) {
      await widget.controller.addSystemMessage(
        _displayTarget,
        'Reconnect failed: $e',
      );
    }
  }

  void _sendMessage(String text) {
    widget.controller.sendMessage(_displayTarget, text);
  }

  bool get _isPrivateMessage => !_displayTarget.startsWith('#');

  List<String> get _privateTargets {
    return widget.controller.state.channels
        .where((channel) => channel.isPrivate)
        .map((channel) => channel.name)
        .toList();
  }

  Future<void> _switchPrivateTarget(int direction) async {
    if (!_isPrivateMessage) return;

    final privateTargets = _privateTargets;
    if (privateTargets.length < 2) return;

    final currentIndex = privateTargets.indexWhere(
      (target) => target.toLowerCase() == _displayTarget.toLowerCase(),
    );
    if (currentIndex == -1) return;

    final nextIndex = currentIndex + direction;
    if (nextIndex < 0 || nextIndex >= privateTargets.length) return;

    await widget.controller.selectTarget(privateTargets[nextIndex]);
  }

  Future<void> _handleHorizontalSwipe(DragEndDetails details) async {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < 250) return;

    if (velocity < 0) {
      await _switchPrivateTarget(1);
      return;
    }

    await _switchPrivateTarget(-1);
  }

  Widget _buildUsersDrawer() {
    if (_isPrivateMessage) {
      final nick = _displayTarget;
      final info = widget.controller.whoisFor(nick);
      final history = widget.controller
          .messagesFor(nick)
          .where((msg) => !msg.isSystem)
          .toList();
      final recentHistory =
          history.length <= 5 ? history : history.sublist(history.length - 5);

      return SafeArea(
        child: SizedBox(
          width: 320,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Contact',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(nick),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NickColorHelper.forNick(context, nick)
                                .withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            nick.isEmpty ? '?' : nick[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: NickColorHelper.forNick(context, nick),
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
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                info?.account != null &&
                                        info!.account!.isNotEmpty
                                    ? 'Account: ${info.account}'
                                    : 'Private conversation',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip(
                          label:
                              info?.account != null && info!.account!.isNotEmpty
                                  ? 'Identified'
                                  : 'Unidentified',
                          active: info?.account != null &&
                              info!.account!.isNotEmpty,
                        ),
                        _statusChip(
                          label: info?.idle != null ? 'Idle' : 'Active',
                          active: info?.idle != null,
                        ),
                        _statusChip(
                          label: info?.channels.isNotEmpty == true
                              ? '${info!.channels.length} shared rooms'
                              : 'No shared rooms',
                          active: info?.channels.isNotEmpty == true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Activity',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            _infoRow(
                              'Last seen',
                              _formatLastSeen(info?.updatedAt),
                            ),
                            _infoRow(
                              'WHOIS updated',
                              info != null
                                  ? _formatFullDateTime(info.updatedAt)
                                  : 'Unknown',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent messages',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            if (recentHistory.isEmpty)
                              Text(
                                'No recent private messages yet.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              for (final msg in recentHistory)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              msg.isMe ? 'You' : msg.sender,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: msg.isMe
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : NickColorHelper
                                                            .forNick(
                                                            context,
                                                            msg.sender,
                                                          ),
                                                  ),
                                            ),
                                          ),
                                          Text(
                                            _formatShortDateTime(msg.time),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        msg.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('WHOIS'),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WhoisScreen(
                                  controller: widget.controller,
                                  nick: nick,
                                ),
                              ),
                            );
                          },
                        ),
                        ActionChip(
                          label: const Text('Refresh'),
                          onPressed: () {
                            widget.controller.requestWhois(nick);
                          },
                        ),
                        ActionChip(
                          label: const Text('Copy Nick'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: nick));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied $nick')),
                            );
                          },
                        ),
                        if (info?.account != null && info!.account!.isNotEmpty)
                          ActionChip(
                            label: const Text('Copy Account'),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: info.account!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied ${info.account}'),
                                ),
                              );
                            },
                          ),
                        ActionChip(
                          label: const Text('Copy Mention'),
                          onPressed: () {
                            final mention = '$nick: ';
                            Clipboard.setData(ClipboardData(text: mention));
                            widget.controller.addSystemMessage(
                              _displayTarget,
                              'Mention copied: $mention',
                            );
                          },
                        ),
                        ActionChip(
                          label: const Text('Copy Hostmask'),
                          onPressed: () {
                            final value = info?.userHost ?? nick;
                            Clipboard.setData(ClipboardData(text: value));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied $value')),
                            );
                          },
                        ),
                        if (info?.channels.isNotEmpty == true)
                          ActionChip(
                            label: const Text('Copy Shared Rooms'),
                            onPressed: () {
                              final value = info!.channels.join(', ');
                              Clipboard.setData(ClipboardData(text: value));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Copied shared rooms')),
                              );
                            },
                          ),
                        ActionChip(
                          avatar: Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          label: const Text('Clear History'),
                          onPressed: () => _confirmClearChatHistory(nick),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow('Nick', info?.nick ?? nick),
                            _infoRow('User/Host', info?.userHost ?? 'Unknown'),
                            _infoRow('Real name', info?.realName ?? 'Unknown'),
                            _infoRow('Account', info?.account ?? 'Unknown'),
                            _infoRow('Server', info?.server ?? 'Unknown'),
                            _infoRow('Idle', info?.idle ?? 'Unknown'),
                            _infoRow(
                              'Channels',
                              info?.channels.isNotEmpty == true
                                  ? info!.channels.join(', ')
                                  : 'Unknown',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((info?.rawLines ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Raw WHOIS lines'),
                        subtitle: const Text('Useful for troubleshooting'),
                        children: [
                          for (final line in info!.rawLines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SelectableText(
                                line,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allUsers = [...widget.controller.usersFor(_displayTarget)];
    final query = _userSearchCtrl.text.trim().toLowerCase();

    final users = allUsers.where((user) {
      if (_showOpsOnly && !_isPrivileged(user)) return false;
      if (query.isEmpty) return true;

      final nick = _cleanNick(user).toLowerCase();
      final role = _nickDecoration(user).label.toLowerCase();
      final host = widget.controller
              .whoisFor(_cleanNick(user))
              ?.userHost
              ?.toLowerCase() ??
          '';

      return nick.contains(query) ||
          role.contains(query) ||
          host.contains(query);
    }).toList()
      ..sort((a, b) {
        switch (_userSortMode) {
          case 'role':
            final rankA = _roleRank(a);
            final rankB = _roleRank(b);
            if (rankA != rankB) return rankA.compareTo(rankB);
            return _cleanNick(a)
                .toLowerCase()
                .compareTo(_cleanNick(b).toLowerCase());
          case 'nick':
            return _cleanNick(a)
                .toLowerCase()
                .compareTo(_cleanNick(b).toLowerCase());
          default:
            return _cleanNick(a)
                .toLowerCase()
                .compareTo(_cleanNick(b).toLowerCase());
        }
      });

    return SafeArea(
      child: SizedBox(
        width: 320,
        child: Column(
          children: [
            ListTile(
              title: Text(
                'Users (${users.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(_displayTarget),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _userSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search users',
                      suffixIcon: _userSearchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _userSearchCtrl.clear();
                                setState(() {});
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Ops only'),
                        selected: _showOpsOnly,
                        onSelected: (selected) {
                          setState(() => _showOpsOnly = selected);
                        },
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'name', label: Text('Name')),
                          ButtonSegment(value: 'role', label: Text('Role')),
                        ],
                        selected: {_userSortMode},
                        onSelectionChanged: (selection) {
                          setState(() => _userSortMode = selection.first);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? const Center(
                      child: Text('No users match the current filters'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 1),
                      itemBuilder: (_, index) {
                        final user = users[index];
                        final decoration = _nickDecoration(user);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              _showUserActions(user);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: decoration.color
                                          .withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      decoration.badge.isEmpty
                                          ? '•'
                                          : decoration.badge,
                                      style: TextStyle(
                                        fontSize:
                                            decoration.badge.isEmpty ? 14 : 12,
                                        fontWeight: FontWeight.w800,
                                        color: decoration.color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: _cleanNick(user),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: NickColorHelper.forNick(
                                          context,
                                          _cleanNick(user),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  AppBadge(
                                    label: _nickDecoration(user).label,
                                    backgroundColor:
                                        _nickDecoration(user).color,
                                    textColor:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required bool active,
  }) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      labelStyle: TextStyle(
        color: active
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _formatLastSeen(DateTime? time) {
    if (time == null) return 'Unknown';

    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatFullDateTime(DateTime time) {
    final date = time.toLocal();
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $hh:$mm';
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

    await widget.controller.clearMessages(target);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleared chat history for $target')),
    );
  }

  String _formatShortDateTime(DateTime time) {
    final date = time.toLocal();
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _cleanNick(String user) {
    return user
        .replaceAll('@', '')
        .replaceAll('+', '')
        .replaceAll('%', '')
        .replaceAll('&', '')
        .replaceAll('~', '')
        .trim();
  }

  bool _isPrivileged(String user) {
    return user.isNotEmpty && '@+%&~'.contains(user[0]);
  }

  int _roleRank(String user) {
    if (user.isEmpty) return 99;
    switch (user[0]) {
      case '~':
        return 0;
      case '&':
        return 1;
      case '@':
        return 2;
      case '%':
        return 3;
      case '+':
        return 4;
      default:
        return 5;
    }
  }

  ({String badge, String label, Color color}) _nickDecoration(String rawUser) {
    final prefix = rawUser.isNotEmpty ? rawUser[0] : '';
    switch (prefix) {
      case '@':
        return (
          badge: '@',
          label: 'Op',
          color: Theme.of(context).colorScheme.error,
        );
      case '+':
        return (
          badge: '+',
          label: 'Voice',
          color: Theme.of(context).colorScheme.primary,
        );
      case '%':
        return (
          badge: '%',
          label: 'Half-Op',
          color: Theme.of(context).colorScheme.tertiary,
        );
      case '&':
        return (
          badge: '&',
          label: 'Admin',
          color: Theme.of(context).colorScheme.secondary,
        );
      case '~':
        return (
          badge: '~',
          label: 'Owner',
          color: Theme.of(context).colorScheme.primaryContainer,
        );
      default:
        return (
          badge: '',
          label: 'Member',
          color: NickColorHelper.forNick(context, _cleanNick(rawUser)),
        );
    }
  }

  void _showUserActions(String rawUser) {
    final nick = _cleanNick(rawUser);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('WHOIS'),
                subtitle: Text(nick),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WhoisScreen(
                        controller: widget.controller,
                        nick: nick,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Private Message'),
                subtitle: Text('Open chat with $nick'),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.controller.openTarget(
                    nick,
                    isPrivate: true,
                  );
                },
              ),
              if (_displayTarget.startsWith('#'))
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: const Text('Invite to Channel'),
                  subtitle: Text('Invite $nick to $_displayTarget'),
                  onTap: () async {
                    Navigator.pop(context);

                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/invite $nick $_displayTarget',
                    );
                  },
                ),
              if (_displayTarget.startsWith('#')) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Kick'),
                  subtitle: Text('Kick $nick from $_displayTarget'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/kick $nick Kicked',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Ban'),
                  subtitle: Text('Ban $nick from $_displayTarget'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/ban $nick',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Op'),
                  subtitle: Text('Give operator to $nick'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/op $nick',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_moderator),
                  title: const Text('Deop'),
                  subtitle: Text('Remove operator from $nick'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/deop $nick',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over),
                  title: const Text('Voice'),
                  subtitle: Text('Give voice to $nick'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/voice $nick',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.voice_over_off),
                  title: const Text('Devoice'),
                  subtitle: Text('Remove voice from $nick'),
                  onTap: () async {
                    Navigator.pop(context);
                    await widget.controller.handleCommand(
                      _displayTarget,
                      '/devoice $nick',
                    );
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Mention'),
                subtitle: Text('$nick:'),
                onTap: () {
                  Navigator.pop(context);
                  widget.controller.addSystemMessage(
                    _displayTarget,
                    'Mention copied: $nick:',
                  );
                  Clipboard.setData(
                    ClipboardData(text: '$nick: '),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Nick'),
                subtitle: Text(nick),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                    ClipboardData(text: nick),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied $nick'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  widget.controller.isBlockedNick(nick)
                      ? Icons.volume_up
                      : Icons.block,
                ),
                title: Text(
                  widget.controller.isBlockedNick(nick) ? 'Unblock' : 'Block',
                ),
                subtitle: Text(
                  widget.controller.isBlockedNick(nick)
                      ? 'Allow messages from $nick again'
                      : 'Ignore messages from $nick\nExamples: $nick, $nick!*@*, ${nick.split('!').first}*',
                ),
                onTap: () async {
                  final wasBlocked = widget.controller.isBlockedNick(nick);
                  Navigator.pop(context);
                  if (wasBlocked) {
                    await widget.controller.unblockNick(nick);
                  } else {
                    await widget.controller.blockNick(nick);
                  }

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          wasBlocked ? 'Unblocked $nick' : 'Blocked $nick'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMessageActions(String text) {
    final urls = UrlHelper.extractUrls(text);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Message'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: text));

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied')),
                  );
                },
              ),
              for (final url in urls)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Copy link'),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: url));

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final users = widget.controller.usersFor(_displayTarget);
    final allMessages = widget.controller.messagesFor(_displayTarget);
    final messages = allMessages;
    final loadingHistory = widget.controller.isLoadingHistory(_displayTarget);
    final hasMoreHistory = widget.controller.hasMoreHistory(_displayTarget);

    return Scaffold(
      endDrawer: Drawer(
        child: _buildUsersDrawer(),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _isPrivateMessage ? _handleHorizontalSwipe : null,
        child: Stack(
          children: [
            Column(
              children: [
                if (_isPrivateMessage) _buildPrivateTargetTabs(),
                if (loadingHistory || !hasMoreHistory)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: loadingHistory
                          ? const CircularProgressIndicator()
                          : Text(
                              'Start of history',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                Expanded(
                  child: messages.isEmpty
                      ? const EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'No messages yet',
                          message:
                              'Start the conversation or wait for new messages.',
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: EdgeInsets.fromLTRB(
                            8,
                            8,
                            8,
                            8 + keyboardInset,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            if (_isPrivateMessage &&
                                msg.isSystem &&
                                !_settings.showPrivateSystemMessages) {
                              return const SizedBox.shrink();
                            }
                            final keyId = _messageKey(msg);
                            final key = _messageKeys.putIfAbsent(
                              keyId,
                              () => GlobalKey(),
                            );
                            final highlightedTime =
                                widget.controller.state.highlightedMessageTime;
                            final highlighted = highlightedTime != null &&
                                msg.time.isAtSameMomentAs(highlightedTime);

                            return KeyedSubtree(
                              key: key,
                              child: GestureDetector(
                                onLongPress: () {
                                  _toggleMessageSelection(msg);
                                  _showMessageActions(msg.text);
                                },
                                child: ChatBubble(
                                  message: msg,
                                  highlighted: highlighted ||
                                      _selectedMessages.contains(
                                        _messageKey(msg),
                                      ),
                                  showTimestamp: _settings.showTimestamps,
                                  showMediaPreviews: _settings.showMediaPreviews,
                                  onSenderTap: _showUserActions,
                                ),
                              ),
                            ).animate(
                              delay: Duration(
                                milliseconds: (index * 10).clamp(0, 150),
                              ),
                            ).fadeIn(
                              duration: const Duration(milliseconds: 250),
                            ).slideY(
                              begin: 0.05,
                              end: 0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutQuad,
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                status == IrcConnectionStatus.connected
                    ? MessageInput(
                        key: _messageInputKey,
                        hintText: 'Message $_displayTarget',
                        commandSuggestions:
                            ircCommandHelpList.map((e) => e.command).toList(),
                        nickSuggestions: users
                            .map((u) =>
                                u.replaceAll('@', '').replaceAll('+', ''))
                            .toList(),
                        uploadController: _uploadController,
                        onOpenUploadQueue: _openUploadQueue,
                        onSend: _sendMessage,
                      )
                    : SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: FilledButton.icon(
                            onPressed: _reconnect,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reconnect'),
                          ),
                        ),
                      ),
              ],
            ),
            if (_scrollCtrl.hasClients && !_isNearBottom && messages.isNotEmpty)
              Positioned(
                right: 16,
                bottom: status == IrcConnectionStatus.connected
                    ? 88 + MediaQuery.of(context).padding.bottom
                    : 24 + MediaQuery.of(context).padding.bottom,
                child: AnimatedScale(
                  scale: 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: FloatingActionButton.small(
                    heroTag: 'go_to_bottom_$_displayTarget',
                    onPressed: _goToBottom,
                    tooltip: 'Go to bottom',
                    child: const Icon(Icons.arrow_downward),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

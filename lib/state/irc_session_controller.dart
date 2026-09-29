import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/models/channel.dart';
import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/message_search_result.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/models/server_notice.dart';
import 'package:vittix_irc/models/whois_info.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/channel_storage_service.dart';
import 'package:vittix_irc/services/notification_service.dart';
import 'package:vittix_irc/services/sqlite_message_storage_service.dart';
import 'package:vittix_irc/state/irc_session_state.dart';

class IrcSessionController extends ChangeNotifier {
  final ServerConfig server;
  final IrcSocketService irc;
  ValueChanged<ServerNotice>? onServerNotice;
  void Function(String inviter, String channel)? onInviteReceived;

  final _channelStorage = ChannelStorageService();
  final _messageStorage = SqliteMessageStorageService();

  final _settingsService = AppSettingsService();
  AppSettings _settings = const AppSettings();

  StreamSubscription<String>? _lineSub;
  StreamSubscription<IrcConnectionStatus>? _statusSub;

  // Root batch id of an in-flight CHATHISTORY response, so backfilled
  // messages neither increment unread counters nor trigger notifications.
  String? _activeHistoryBatch;

  late IrcSessionState state;

  bool isFetchingChannels = false;
  List<IrcChannelInfo> networkChannels = [];
  Timer? _listUpdateTimer;
  Timer? _friendPresenceTimer;

  int get totalUnreadCount {
    return state.channels.fold<int>(
      0,
      (total, channel) => total + channel.unreadCount,
    );
  }

  bool get hasUnread => totalUnreadCount > 0;

  String get currentNick => irc.currentNick ?? server.nickname;

  String _normalizeTarget(String target) => target.trim();

  bool isBlockedNick(String nick) {
    final clean = nick.trim().toLowerCase();
    if (clean.isEmpty) return false;
    return _settings.blockedNicks.any((blocked) => _matchesBlockRule(
          rule: blocked,
          nick: clean,
        ));
  }

  List<String> get blockedNicks => List.unmodifiable(_settings.blockedNicks);

  Future<void> blockNick(String nick) async {
    final clean = nick.trim();
    if (clean.isEmpty || isBlockedNick(clean)) return;

    _settings = _settings.copyWith(
      blockedNicks: [..._settings.blockedNicks, clean],
    );
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> unblockNick(String nick) async {
    final clean = nick.trim().toLowerCase();
    if (clean.isEmpty) return;

    _settings = _settings.copyWith(
      blockedNicks: _settings.blockedNicks
          .where((blocked) => blocked.toLowerCase() != clean)
          .toList(),
    );
    await _settingsService.saveSettings(_settings);
    notifyListeners();
  }

  bool _matchesBlockRule({
    required String rule,
    required String nick,
    String? hostmask,
  }) {
    final pattern = rule.trim().toLowerCase();
    if (pattern.isEmpty) return false;

    final inputs = <String>[
      nick,
      if (hostmask != null && hostmask.trim().isNotEmpty)
        hostmask.trim().toLowerCase(),
    ];

    for (final input in inputs) {
      if (_wildcardMatch(pattern, input)) return true;
    }

    return false;
  }

  bool _wildcardMatch(String pattern, String value) {
    if (pattern == '*') return true;
    if (!pattern.contains('*') && !pattern.contains('?')) {
      return pattern == value;
    }

    var regex = RegExp.escape(pattern);
    regex = regex.replaceAll(r'\*', '.*').replaceAll(r'\?', '.');
    return RegExp('^$regex\$').hasMatch(value);
  }

  String? _hostmaskFromLine(String line) {
    final prefix = IrcParser.splitLine(line)?.$1;
    if (prefix == null || prefix.isEmpty) return null;
    return prefix.contains('!') ? prefix : null;
  }

  String get statusText {
    switch (state.status) {
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

  IrcSessionController({
    required this.server,
    required this.irc,
  }) {
    state = IrcSessionState(
      server: server,
      status: IrcConnectionStatus.connected,
      channels: const [],
      activeTarget: null,
      messagesByTarget: const {},
      topicsByTarget: const {},
      usersByChannel: const {},
      friendOnlineStatus: const {},
      notices: const [],
      whoisByNick: const {},
      highlightedMessageTime: null,
      hasMoreHistoryByTarget: const {},
      loadingHistoryByTarget: const {},
      historyOffsetByTarget: const {},
    );

    _init();
  }

  Future<void> _init() async {
    _settings = await _settingsService.getSettings();
    await _loadChannels();
    _refreshFriendPresence();
    _friendPresenceTimer?.cancel();
    _friendPresenceTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshFriendPresence(),
    );

    _lineSub = irc.lines.listen((line) {
      _onLine(line);
    });
    _statusSub = irc.status.listen((status) {
      state = state.copyWith(status: status);
      notifyListeners();
    });
  }

  Future<void> reloadSettings() async {
    _settings = await _settingsService.getSettings();
    _refreshFriendPresence();
    notifyListeners();
  }

  Future<void> _loadChannels() async {
    final saved = await _channelStorage.getChannels(server.id);

    final channels =
        saved.isEmpty ? [Channel(name: server.defaultChannel)] : saved;

    state = state.copyWith(
      channels: channels,
      activeTarget: channels.isEmpty ? null : channels.first.name,
    );

    irc.setAutoJoinChannels(
      channels.where((c) => !c.isPrivate).map((c) => c.name).toList(),
    );

    notifyListeners();
  }

  List<String> get friendNicks => List.unmodifiable(_settings.friendNicks);

  bool isFriendOnline(String nick) {
    return state.friendOnlineStatus[nick.toLowerCase()] ?? false;
  }

  Future<void> addFriendNick(String nick) async {
    final clean = nick.trim();
    if (clean.isEmpty) return;
    if (_settings.friendNicks
        .any((item) => item.toLowerCase() == clean.toLowerCase())) {
      return;
    }

    _settings = _settings.copyWith(
      friendNicks: [..._settings.friendNicks, clean],
    );
    await _settingsService.saveSettings(_settings);
    _refreshFriendPresence();
    notifyListeners();
  }

  Future<void> removeFriendNick(String nick) async {
    final clean = nick.trim().toLowerCase();
    if (clean.isEmpty) return;

    _settings = _settings.copyWith(
      friendNicks: _settings.friendNicks
          .where((item) => item.toLowerCase() != clean)
          .toList(),
    );
    await _settingsService.saveSettings(_settings);
    _refreshFriendPresence();
    notifyListeners();
  }

  void _refreshFriendPresence() {
    final friends = _settings.friendNicks
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();

    final map = <String, bool>{};
    for (final friend in friends) {
      map[friend.toLowerCase()] = false;
    }

    state = state.copyWith(friendOnlineStatus: map);
    notifyListeners();

    if (friends.isNotEmpty && irc.isConnected) {
      irc.sendRaw('ISON ${friends.join(' ')}');
    }
  }

  Future<void> saveChannels() async {
    await _channelStorage.saveChannels(
      serverId: server.id,
      channels: state.channels,
    );
  }

  Future<void> selectTarget(String target) async {
    final normalizedTarget = _normalizeTarget(target);
    final channels = state.channels.map((c) {
      if (c.name.toLowerCase() == normalizedTarget.toLowerCase()) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();

    state = state.copyWith(
      activeTarget: normalizedTarget,
      channels: channels,
    );

    await loadMessages(normalizedTarget);
    requestChannelInfo(normalizedTarget);
    requestChannelModes(normalizedTarget);
    notifyListeners();
  }

  Future<void> openTarget(String target, {bool isPrivate = false}) async {
    final normalizedTarget = _normalizeTarget(target);
    _ensureChannel(normalizedTarget, isPrivate: isPrivate);
    await selectTarget(normalizedTarget);

    if (isPrivate) {
      requestHistoryBackfill(normalizedTarget);
    }
  }

  /// Asks a CHATHISTORY-capable server (bouncer or modern ircd) for messages
  /// missed since the newest locally stored one. No-op on servers without
  /// the capability (they reply 421, which is ignored).
  Future<void> requestHistoryBackfill(String target) async {
    final normalizedTarget = _normalizeTarget(target);
    if (normalizedTarget.isEmpty) return;

    final last = await _messageStorage.getLastMessageTime(
      serverId: server.id,
      target: normalizedTarget,
    );

    final from =
        last ?? DateTime.now().subtract(const Duration(hours: 24));
    final fromParam = IrcParser.formatChathistoryTimestamp(from);

    irc.sendRaw('CHATHISTORY AFTER $normalizedTarget $fromParam * 100');
  }

  Future<void> loadMessages(String target) async {
    final normalizedTarget = _normalizeTarget(target);
    final key = normalizedTarget.toLowerCase();
    final messages = await _messageStorage.getMessagesPage(
      serverId: server.id,
      target: normalizedTarget,
      offsetFromEnd: 0,
      limit: 50,
    );

    final messagesMap = Map<String, List<ChatMessage>>.from(
      state.messagesByTarget,
    );
    final hasMoreMap = Map<String, bool>.from(
      state.hasMoreHistoryByTarget,
    );
    final offsetMap = Map<String, int>.from(
      state.historyOffsetByTarget,
    );
    final existing = List<ChatMessage>.from(messagesMap[key] ?? const []);

    final merged = <ChatMessage>[];
    final seen = <String>{};

    void addUnique(ChatMessage message) {
      final dedupeKey =
          '${message.sender}|${message.target.trim().toLowerCase()}|${message.time.toIso8601String()}|${message.text}|${message.type.name}|${message.isMe}|${message.isSystem}';
      if (seen.add(dedupeKey)) {
        merged.add(message);
      }
    }

    for (final message in messages) {
      addUnique(message);
    }
    for (final message in existing) {
      addUnique(message);
    }

    merged.sort((a, b) => a.time.compareTo(b.time));

    messagesMap[key] = merged;
    hasMoreMap[key] = messages.length == 50;
    offsetMap[key] = merged.length;

    state = state.copyWith(
      messagesByTarget: messagesMap,
      hasMoreHistoryByTarget: hasMoreMap,
      historyOffsetByTarget: offsetMap,
    );
    notifyListeners();
  }

  Future<void> loadOlderMessages(String target) async {
    final key = target.toLowerCase();

    final isLoading = state.loadingHistoryByTarget[key] ?? false;
    final hasMore = state.hasMoreHistoryByTarget[key] ?? true;

    if (isLoading || !hasMore) return;

    final loadingMap = Map<String, bool>.from(state.loadingHistoryByTarget);
    loadingMap[key] = true;

    state = state.copyWith(loadingHistoryByTarget: loadingMap);
    notifyListeners();

    final offset = state.historyOffsetByTarget[key] ?? 0;

    final olderMessages = await _messageStorage.getMessagesPage(
      serverId: server.id,
      target: target,
      offsetFromEnd: offset,
      limit: 50,
    );

    final messagesMap = Map<String, List<ChatMessage>>.from(
      state.messagesByTarget,
    );
    final existing = List<ChatMessage>.from(messagesMap[key] ?? const []);
    messagesMap[key] = [
      ...olderMessages,
      ...existing,
    ];

    final hasMoreMap = Map<String, bool>.from(state.hasMoreHistoryByTarget);
    final offsetMap = Map<String, int>.from(state.historyOffsetByTarget);

    final newOffset = offset + olderMessages.length;
    hasMoreMap[key] = olderMessages.length == 50;
    offsetMap[key] = newOffset;
    loadingMap[key] = false;

    state = state.copyWith(
      messagesByTarget: messagesMap,
      hasMoreHistoryByTarget: hasMoreMap,
      loadingHistoryByTarget: loadingMap,
      historyOffsetByTarget: offsetMap,
    );
    notifyListeners();
  }

  Future<void> clearMessages(String target) async {
    final normalizedTarget = _normalizeTarget(target);
    final key = normalizedTarget.toLowerCase();

    await _messageStorage.clearMessages(
      serverId: server.id,
      target: normalizedTarget,
    );

    final messagesMap = Map<String, List<ChatMessage>>.from(
      state.messagesByTarget,
    );
    final hasMoreMap = Map<String, bool>.from(
      state.hasMoreHistoryByTarget,
    );
    final offsetMap = Map<String, int>.from(
      state.historyOffsetByTarget,
    );
    final loadingMap = Map<String, bool>.from(
      state.loadingHistoryByTarget,
    );

    messagesMap[key] = const [];
    hasMoreMap[key] = false;
    offsetMap[key] = 0;
    loadingMap[key] = false;

    state = state.copyWith(
      messagesByTarget: messagesMap,
      hasMoreHistoryByTarget: hasMoreMap,
      historyOffsetByTarget: offsetMap,
      loadingHistoryByTarget: loadingMap,
    );

    notifyListeners();
  }

  bool isLoadingHistory(String target) {
    return state.loadingHistoryByTarget[target.toLowerCase()] ?? false;
  }

  bool hasMoreHistory(String target) {
    return state.hasMoreHistoryByTarget[target.toLowerCase()] ?? false;
  }

  String? topicFor(String target) {
    return state.topicsByTarget[target.toLowerCase()];
  }

  List<String> usersFor(String channel) {
    return state.usersByChannel[channel.toLowerCase()] ?? const [];
  }

  String modesFor(String target) {
    final channel = state.channels.firstWhere(
      (c) => c.name.toLowerCase() == target.toLowerCase(),
      orElse: () => Channel(name: target),
    );
    return channel.modes;
  }

  void requestChannelInfo(String channel) {
    if (!channel.startsWith('#')) return;

    final key = channel.toLowerCase();
    final usersMap = Map<String, List<String>>.from(state.usersByChannel);
    usersMap[key] = const [];
    state = state.copyWith(usersByChannel: usersMap);
    notifyListeners();

    irc.sendRaw('NAMES $channel');
    irc.sendRaw('TOPIC $channel');
    irc.sendRaw('MODE $channel');
  }

  void requestChannelModes(String channel) {
    if (!channel.startsWith('#')) return;

    irc.sendRaw('MODE $channel');
  }

  void requestChannelList() {
    isFetchingChannels = true;
    networkChannels.clear();
    notifyListeners();
    irc.sendRaw('LIST');
  }

  List<ChatMessage> messagesFor(String target) {
    return state.messagesByTarget[_normalizeTarget(target).toLowerCase()] ??
        const [];
  }

  WhoisInfo? whoisFor(String nick) {
    return state.whoisByNick[nick.toLowerCase()];
  }

  Future<void> requestWhois(String nick) async {
    final cleanNick = nick.trim();
    if (cleanNick.isEmpty) return;

    irc.sendRaw('WHOIS $cleanNick');

    final active = state.activeTarget;
    if (active != null) {
      await addSystemMessage(active, 'Requested WHOIS for $cleanNick');
    }
  }

  Future<List<MessageSearchResult>> searchAllMessages(String query) async {
    final targets = state.channels.map((c) => c.name).toList();

    return _messageStorage.searchMessages(
      serverId: server.id,
      targets: targets,
      query: query,
    );
  }

  Future<List<MessageSearchResult>> searchMessagesInTarget({
    required String target,
    required String query,
    bool useRegex = false,
    bool caseSensitive = false,
  }) async {
    final messages = messagesFor(target);
    if (query.trim().isEmpty) return const [];

    final results = <MessageSearchResult>[];
    RegExp? regex;

    if (useRegex) {
      regex = RegExp(
        query,
        caseSensitive: caseSensitive,
        multiLine: true,
      );
    }

    for (final msg in messages) {
      final text = caseSensitive ? msg.text : msg.text.toLowerCase();
      final needle = caseSensitive ? query : query.toLowerCase();
      final matched =
          useRegex ? regex!.hasMatch(msg.text) : text.contains(needle);
      if (matched) {
        results.add(MessageSearchResult(target: target, message: msg));
      }
    }

    return results.reversed.toList();
  }

  Future<void> openSearchResult(MessageSearchResult result) async {
    await openTarget(
      result.target,
      isPrivate: !result.target.startsWith('#'),
    );

    state = state.copyWith(
      highlightedMessageTime: result.message.time,
    );

    notifyListeners();
  }

  void clearHighlightedMessage() {
    state = state.copyWith(clearHighlight: true);
    notifyListeners();
  }

  void _addNotice(ServerNotice notice) {
    final notices = [
      ...state.notices,
      notice,
    ];

    final limited =
        notices.length > 200 ? notices.sublist(notices.length - 200) : notices;

    state = state.copyWith(notices: limited);
    onServerNotice?.call(notice);
    notifyListeners();
  }

  Future<void> _handleInviteLine(String line) async {
    final invite = IrcParser.parseInvite(
      line: line,
      myNick: currentNick,
    );

    if (invite == null) return;

    final active = state.activeTarget;
    if (active != null) {
      await addSystemMessage(
        active,
        '${invite.inviter} invited you to ${invite.channel}',
      );
    }

    onInviteReceived?.call(
      invite.inviter,
      invite.channel,
    );
  }

  void _handleWhoisLine(String line) {
    final nick = IrcParser.whoisNickFromLine(line);
    if (nick == null || nick.isEmpty) return;

    final key = nick.toLowerCase();
    final existing = state.whoisByNick[key] ??
        WhoisInfo(
          nick: nick,
          updatedAt: DateTime.now(),
        );

    var updated = existing.copyWith(
      updatedAt: DateTime.now(),
      rawLines: [...existing.rawLines, line],
    );

    // Params after the command, so indexes survive IRCv3 message-tags.
    final params = IrcParser.splitLine(line)?.$3 ?? const <String>[];

    if (IrcParser.numericFromLine(line) == '311') {
      if (params.length >= 4) {
        final user = params[2];
        final host = params[3];
        final realNameIndex = line.indexOf(' :');
        final realName =
            realNameIndex == -1 ? null : line.substring(realNameIndex + 2);

        updated = updated.copyWith(
          userHost: '$user@$host',
          realName: realName,
        );
      }
    } else if (IrcParser.numericFromLine(line) == '312') {
      if (params.length >= 3) {
        final server = params[2];
        final infoIndex = line.indexOf(' :');
        final info = infoIndex == -1 ? null : line.substring(infoIndex + 2);

        updated = updated.copyWith(
          server: server,
          serverInfo: info,
        );
      }
    } else if (IrcParser.numericFromLine(line) == '319') {
      final channelIndex = line.indexOf(' :');
      if (channelIndex != -1) {
        final channels = line
            .substring(channelIndex + 2)
            .split(' ')
            .where((c) => c.trim().isNotEmpty)
            .toList();

        updated = updated.copyWith(channels: channels);
      }
    } else if (IrcParser.numericFromLine(line) == '317') {
      if (params.length >= 3) {
        final idleSeconds = int.tryParse(params[2]);
        if (idleSeconds != null) {
          updated = updated.copyWith(
            idle: '${idleSeconds ~/ 60} minutes idle',
          );
        }
      }
    } else if (IrcParser.numericFromLine(line) == '330') {
      if (params.length >= 3) {
        updated = updated.copyWith(account: params[2]);
      }
    }

    final map = Map<String, WhoisInfo>.from(state.whoisByNick);
    map[key] = updated;
    state = state.copyWith(whoisByNick: map);
    notifyListeners();
  }

  Future<void> sendMessage(String target, String text) async {
    final normalizedTarget = _normalizeTarget(target);
    if (text.trim().isEmpty) return;

    if (text.startsWith('/')) {
      await handleCommand(target, text);
      return;
    }

    irc.sendRaw('PRIVMSG $normalizedTarget :$text');

    final msg = ChatMessage(
      sender: currentNick,
      target: normalizedTarget,
      text: text,
      time: DateTime.now(),
      isMe: true,
    );

    await _addMessage(normalizedTarget, msg);
  }

  Future<void> handleCommand(String currentTarget, String input) async {
    final parts = input.trim().split(' ');
    final command = parts.first.toLowerCase();

    switch (command) {
      case '/join':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /join #channel [key]');
          return;
        }

        final channel = parts[1].startsWith('#') ? parts[1] : '#${parts[1]}';
        final key = parts.length >= 3 ? parts[2] : null;

        if (key == null || key.isEmpty) {
          irc.sendRaw('JOIN $channel');
        } else {
          irc.sendRaw('JOIN $channel $key');
        }

        await addSystemMessage(
          currentTarget,
          key == null ? 'Joining $channel...' : 'Joining $channel with key...',
        );
        break;

      case '/part':
        final target = parts.length >= 2 ? parts[1] : currentTarget;
        irc.sendRaw('PART $target');
        await addSystemMessage(currentTarget, 'Leaving $target...');
        break;

      case '/msg':
        if (parts.length < 3) {
          await addSystemMessage(currentTarget, 'Usage: /msg nickname message');
          return;
        }

        final nick = parts[1];
        final message = parts.sublist(2).join(' ');
        irc.sendRaw('PRIVMSG $nick :$message');

        _ensureChannel(nick, isPrivate: true);

        final msg = ChatMessage(
          sender: currentNick,
          target: nick,
          text: message,
          time: DateTime.now(),
          isMe: true,
        );

        await _addMessage(nick, msg);
        await selectTarget(nick);
        break;

      case '/query':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /query nickname');
          return;
        }

        await openTarget(
          parts[1],
          isPrivate: true,
        );
        break;

      case '/invite':
        if (parts.length < 2) {
          await addSystemMessage(
            currentTarget,
            'Usage: /invite nickname [#channel]',
          );
          return;
        }

        if (!currentTarget.startsWith('#') && parts.length < 3) {
          await addSystemMessage(
            currentTarget,
            'Invite needs a channel when used from private chat',
          );
          return;
        }

        {
          final nick = parts[1];
          final channel = parts.length >= 3 ? parts[2] : currentTarget;

          irc.sendRaw('INVITE $nick $channel');

          await addSystemMessage(
            currentTarget,
            'Invite sent to $nick for $channel',
          );
        }
        break;

      case '/nick':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /nick newNickname');
          return;
        }

        irc.sendRaw('NICK ${parts[1]}');
        await addSystemMessage(
            currentTarget, 'Changing nickname to ${parts[1]}...');
        break;

      case '/me':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /me action');
          return;
        }

        final action = parts.sublist(1).join(' ');
        irc.sendRaw('PRIVMSG $currentTarget :\u0001ACTION $action\u0001');

        final msg = ChatMessage(
          sender: currentNick,
          target: currentTarget,
          text: action,
          time: DateTime.now(),
          isMe: true,
          type: ChatMessageType.action,
        );

        await _addMessage(currentTarget, msg);
        break;

      case '/topic':
        if (parts.length < 2) {
          irc.sendRaw('TOPIC $currentTarget');
          await addSystemMessage(currentTarget, 'Requested topic');
          return;
        }

        final topic = parts.sublist(1).join(' ');
        irc.sendRaw('TOPIC $currentTarget :$topic');
        await addSystemMessage(currentTarget, 'Changing topic...');
        break;

      case '/key':
        if (!currentTarget.startsWith('#')) {
          await addSystemMessage(
              currentTarget, 'Channel key works only in channels');
          return;
        }

        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /key secret');
          return;
        }

        irc.sendRaw('MODE $currentTarget +k ${parts[1]}');
        await addSystemMessage(
          currentTarget,
          'Changing channel key...',
        );
        break;

      case '/removekey':
        if (!currentTarget.startsWith('#')) {
          await addSystemMessage(
              currentTarget, 'Channel key works only in channels');
          return;
        }

        irc.sendRaw('MODE $currentTarget -k');
        await addSystemMessage(
          currentTarget,
          'Removing channel key...',
        );
        break;

      case '/list':
        requestChannelList();
        await addSystemMessage(
            currentTarget, 'Requested channel list from server...');
        break;

      case '/identify':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /identify password');
          return;
        }

        irc.sendRaw('PRIVMSG NickServ :IDENTIFY ${parts[1]}');
        await addSystemMessage(currentTarget, 'Identifying with NickServ...');
        break;

      case '/clear':
        await _messageStorage.clearMessages(
          serverId: server.id,
          target: currentTarget,
        );

        final map = Map<String, List<ChatMessage>>.from(state.messagesByTarget);
        map[currentTarget.toLowerCase()] = [];

        state = state.copyWith(messagesByTarget: map);
        notifyListeners();
        break;

      case '/whois':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /whois nickname');
          return;
        }

        await requestWhois(parts[1]);
        break;

      case '/kick':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /kick nickname reason');
          return;
        }

        if (!currentTarget.startsWith('#')) {
          await addSystemMessage(currentTarget, 'Kick works only in channels');
          return;
        }

        {
          final nick = parts[1];
          final reason =
              parts.length >= 3 ? parts.sublist(2).join(' ') : 'Kicked';
          irc.sendRaw('KICK $currentTarget $nick :$reason');
          await addSystemMessage(currentTarget, 'Kick requested for $nick');
        }
        break;

      case '/ban':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /ban nickname-or-mask');
          return;
        }

        if (!currentTarget.startsWith('#')) {
          await addSystemMessage(currentTarget, 'Ban works only in channels');
          return;
        }

        {
          final mask = parts[1];
          irc.sendRaw('MODE $currentTarget +b $mask');
          await addSystemMessage(currentTarget, 'Ban requested: $mask');
        }
        break;

      case '/unban':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /unban mask');
          return;
        }

        if (!currentTarget.startsWith('#')) {
          await addSystemMessage(currentTarget, 'Unban works only in channels');
          return;
        }

        {
          final mask = parts[1];
          irc.sendRaw('MODE $currentTarget -b $mask');
          await addSystemMessage(currentTarget, 'Unban requested: $mask');
        }
        break;

      case '/op':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /op nickname');
          return;
        }

        irc.sendRaw('MODE $currentTarget +o ${parts[1]}');
        await addSystemMessage(currentTarget, 'Giving op to ${parts[1]}...');
        break;

      case '/deop':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /deop nickname');
          return;
        }

        irc.sendRaw('MODE $currentTarget -o ${parts[1]}');
        await addSystemMessage(
            currentTarget, 'Removing op from ${parts[1]}...');
        break;

      case '/voice':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /voice nickname');
          return;
        }

        irc.sendRaw('MODE $currentTarget +v ${parts[1]}');
        await addSystemMessage(currentTarget, 'Giving voice to ${parts[1]}...');
        break;

      case '/devoice':
        if (parts.length < 2) {
          await addSystemMessage(currentTarget, 'Usage: /devoice nickname');
          return;
        }

        irc.sendRaw('MODE $currentTarget -v ${parts[1]}');
        await addSystemMessage(
            currentTarget, 'Removing voice from ${parts[1]}...');
        break;

      case '/mode':
        if (parts.length < 2) {
          await addSystemMessage(
              currentTarget, 'Usage: /mode #channel +/-mode');
          return;
        }

        final rawMode = parts.sublist(1).join(' ');
        irc.sendRaw('MODE $rawMode');
        await addSystemMessage(
          currentTarget,
          'Mode command sent: MODE $rawMode',
        );
        break;

      default:
        await addSystemMessage(currentTarget, 'Unknown command: $command');
    }
  }

  Future<void> addSystemMessage(String target, String text) async {
    final normalizedTarget = _normalizeTarget(target);
    final msg = ChatMessage(
      sender: 'system',
      target: normalizedTarget,
      text: text,
      time: DateTime.now(),
      isSystem: true,
      type: ChatMessageType.system,
    );

    await _addMessage(normalizedTarget, msg);
  }

  Future<void> _addMessage(String target, ChatMessage msg) async {
    final normalizedTarget = _normalizeTarget(target);
    final key = normalizedTarget.toLowerCase();

    final map = Map<String, List<ChatMessage>>.from(state.messagesByTarget);
    final existing = List<ChatMessage>.from(map[key] ?? const []);

    if (_isDuplicateRecent(existing, msg)) return;

    if (msg.isSystem) {
      final merged = _mergeBurstSystemMessage(existing, msg);
      if (merged != null) {
        existing
          ..removeLast()
          ..add(merged);
        map[key] = existing;

        state = state.copyWith(messagesByTarget: map);
        notifyListeners();
        return;
      }
    }

    existing.add(msg);
    map[key] = existing;

    state = state.copyWith(messagesByTarget: map);
    notifyListeners();

    await _messageStorage.addMessage(
      serverId: server.id,
      target: normalizedTarget,
      message: msg,
    );
  }

  ChatMessage? _mergeBurstSystemMessage(
      List<ChatMessage> existing, ChatMessage next) {
    if (existing.isEmpty) return null;

    final last = existing.last;
    if (!last.isSystem ||
        last.target.toLowerCase() != next.target.toLowerCase()) {
      return null;
    }

    final delta = next.time.difference(last.time).inSeconds.abs();
    if (delta > 6) return null;

    final lastBurst = _systemBurst(last.text);
    final nextBurst = _systemBurst(next.text);
    if (lastBurst == null || nextBurst == null) return null;
    if (lastBurst.action != nextBurst.action) return null;

    final names = [...lastBurst.names, ...nextBurst.names];
    final uniqNames = <String>[];
    for (final name in names) {
      if (!uniqNames.contains(name)) uniqNames.add(name);
    }

    final text = _formatBurstSummary(
      names: uniqNames,
      action: lastBurst.action,
      target: next.target,
    );

    return ChatMessage(
      sender: 'system',
      target: next.target,
      text: text,
      time: next.time,
      isSystem: true,
      type: ChatMessageType.system,
    );
  }

  ({List<String> names, String action})? _systemBurst(String text) {
    final patterns = <(RegExp, String, int)>[
      (RegExp(r'^(.*) joined (.*)$'), 'joined', 1),
      (RegExp(r'^(.*) left (.*)$'), 'left', 1),
      (RegExp(r'^(.*) quit$'), 'quit', 1),
      (RegExp(r'^(.*) is now known as (.*)$'), 'nick', 2),
    ];

    for (final pattern in patterns) {
      final match = pattern.$1.firstMatch(text);
      if (match == null) continue;
      final names = [
        match.group(1)!.trim(),
        if (pattern.$3 == 2) match.group(2)!.trim(),
      ].where((n) => n.isNotEmpty).toList();
      return (names: names, action: pattern.$2);
    }
    return null;
  }

  String _formatBurstSummary({
    required List<String> names,
    required String action,
    required String target,
  }) {
    final uniqueNames = names.take(3).toList();
    final remaining = names.length - uniqueNames.length;
    final nameText = uniqueNames.join(', ');
    final tail = remaining > 0 ? ', and $remaining others' : '';

    switch (action) {
      case 'joined':
        return '$nameText$tail joined $target';
      case 'left':
        return '$nameText$tail left $target';
      case 'quit':
        return '$nameText$tail quit';
      case 'nick':
        return '$nameText$tail changed nick';
      default:
        return '$nameText$tail';
    }
  }

  bool _isDuplicateRecent(List<ChatMessage> messages, ChatMessage msg) {
    if (messages.isEmpty) return false;

    final last = messages.last;

    final sameSender = last.sender == msg.sender;
    final sameTarget = last.target == msg.target;
    final sameText = last.text == msg.text;
    final timeDiff = msg.time.difference(last.time).inSeconds.abs();

    return sameSender && sameTarget && sameText && timeDiff <= 3;
  }

  Future<void> _maybeNotify({
    required String target,
    required ChatMessage msg,
    required bool isPrivate,
  }) async {
    if (msg.isMe) return;
    if (isBlockedNick(msg.sender)) return;

    final activeTarget = state.activeTarget?.toLowerCase();
    final currentTarget = target.toLowerCase();

    if (activeTarget == currentTarget) return;

    final myNick = currentNick.toLowerCase();
    final isMention = msg.text.toLowerCase().contains(myNick);
    final shouldNotifyPrivate =
        isPrivate && _settings.privateMessageNotifications;
    final shouldNotifyMention = isMention && _settings.mentionNotifications;

    if (!shouldNotifyPrivate && !shouldNotifyMention) return;

    final title =
        isPrivate ? 'Private message from ${msg.sender}' : 'Mention in $target';
    final body = isPrivate ? msg.text : '${msg.sender}: ${msg.text}';

    await NotificationService.instance.showMessageNotification(
      title: title,
      body: body,
      payload: '${server.id}|$target',
    );
  }

  Future<void> _onLine(String line) async {
    await _handleInviteLine(line);

    if (IrcParser.numericFromLine(line) == '303') {
      final idx = line.indexOf(' :');
      if (idx != -1) {
        final onlineNicks = line
            .substring(idx + 2)
            .split(' ')
            .map((n) => n.trim().toLowerCase())
            .where((n) => n.isNotEmpty)
            .toSet();

        final map = <String, bool>{};
        for (final friend in _settings.friendNicks) {
          map[friend.toLowerCase()] =
              onlineNicks.contains(friend.toLowerCase());
        }

        state = state.copyWith(friendOnlineStatus: map);
        notifyListeners();
      }
      return;
    }

    // Handle LIST command numeric replies (321: Start, 322: Item, 323: End)
    final listNumeric = IrcParser.numericFromLine(line);
    if (listNumeric == '321') {
      isFetchingChannels = true;
      networkChannels.clear();
      notifyListeners();
    } else if (listNumeric == '322') {
      final split = IrcParser.splitLine(line);
      if (split != null && split.$3.length >= 3) {
        final channel = split.$3[1];
        final users = int.tryParse(split.$3[2]) ?? 0;
        final topicIndex = line.indexOf(' :');
        final topic =
            topicIndex != -1 ? line.substring(topicIndex + 2) : '';

        networkChannels.add(IrcChannelInfo(
          name: channel,
          users: users,
          topic: topic,
        ));

        // Debounce UI rebuilds when receiving thousands of items
        if (!(_listUpdateTimer?.isActive ?? false)) {
          _listUpdateTimer = Timer(const Duration(milliseconds: 500), () {
            notifyListeners();
          });
        }
      }
      return; // Skip standard processing for 322 lines to prevent log flooding
    } else if (listNumeric == '323') {
      isFetchingChannels = false;
      _listUpdateTimer?.cancel();
      notifyListeners();
    }

    final kickedChannel = IrcParser.parseKickedChannelForMe(
      line: line,
      myNick: currentNick,
    );

    if (kickedChannel != null) {
      final channels = state.channels
          .where((c) => c.name.toLowerCase() != kickedChannel.toLowerCase())
          .toList();

      final newActive =
          state.activeTarget?.toLowerCase() == kickedChannel.toLowerCase()
              ? channels.isEmpty
                  ? null
                  : channels.first.name
              : state.activeTarget;

      state = state.copyWith(
        channels: channels,
        activeTarget: newActive,
      );

      await addSystemMessage(
        newActive ?? kickedChannel,
        'You were kicked from $kickedChannel',
      );

      await saveChannels();
      notifyListeners();
      return;
    }

    // Keep channel user lists in sync for events from other users; must run
    // before the early returns below so events for non-active channels are
    // still reflected.
    _maintainChannelUserLists(line);
    _trackHistoryBatch(line);

    final typing = IrcParser.parseTyping(line);
    if (typing != null) {
      _handleTypingEvent(typing);
      return;
    }

    if (IrcParser.isWhoisLine(line)) {
      _handleWhoisLine(line);
    }

    final notice = IrcParser.parseServerNotice(line);
    if (notice != null) {
      _addNotice(notice);

      if (notice.type == ServerNoticeType.error) {
        final active = state.activeTarget;
        if (active != null) {
          addSystemMessage(active, notice.text);
        }
      }
    }

    final joined = IrcParser.parseJoinedChannel(
      line: line,
      myNick: currentNick,
    );

    if (joined != null) {
      _ensureChannel(joined);
      await openTarget(
        joined,
        isPrivate: false,
      );
      saveChannels();
      requestHistoryBackfill(joined);
      return;
    }

    final parted = IrcParser.parsePartedChannel(
      line: line,
      myNick: currentNick,
    );

    if (parted != null) {
      final channels = state.channels
          .where((c) => c.name.toLowerCase() != parted.toLowerCase())
          .toList();

      final newActive =
          state.activeTarget?.toLowerCase() == parted.toLowerCase()
              ? channels.isEmpty
                  ? null
                  : channels.first.name
              : state.activeTarget;

      state = state.copyWith(
        channels: channels,
        activeTarget: newActive,
      );

      saveChannels();
      notifyListeners();
      return;
    }

    final msg = IrcParser.parsePrivMsg(
      line: line,
      myNick: currentNick,
    );

    if (msg != null) {
      final hostmask = _hostmaskFromLine(line);
      if (_settings.blockedNicks.any((rule) => _matchesBlockRule(
            rule: rule,
            nick: msg.sender.toLowerCase(),
            hostmask: hostmask,
          ))) {
        return;
      }

      final myNick = currentNick.toLowerCase();

      final target =
          msg.target.toLowerCase() == myNick ? msg.sender : msg.target;

      final isPrivate = msg.target.toLowerCase() == myNick;
      final isActive =
          state.activeTarget?.toLowerCase() == target.toLowerCase();

      // History backfill replays past messages: store them, but do not
      // count unread or raise notifications for them.
      final isBackfill = _isHistoryBackfill(line);

      _ensureChannel(target, isPrivate: isPrivate);

      if (!isBackfill && !isActive && !msg.isMe) {
        _incrementUnread(target);
      }

      if (!isBackfill) {
        _maybeNotify(
          target: target,
          msg: msg,
          isPrivate: isPrivate,
        );
      }

      _clearTyping(msg.sender, target);
      _addMessage(target, msg);
      return;
    }

    final active = state.activeTarget;
    if (active == null) return;

    final names = IrcParser.parseNamesReply(
      line: line,
      channelName: active,
    );

    if (names != null) {
      final map = Map<String, List<String>>.from(state.usersByChannel);
      final key = active.toLowerCase();
      final existing = map[key] ?? const [];
      final merged = <String>{
        ...existing,
        ...names,
      }.toList();
      map[key] = merged;

      state = state.copyWith(usersByChannel: map);
      notifyListeners();
      return;
    }

    final topicReply = IrcParser.parseTopicReply(
      line: line,
      channelName: active,
    );

    final topicChanged = IrcParser.parseTopicChanged(
      line: line,
      channelName: active,
    );

    final newTopic = topicReply ?? topicChanged;

    if (newTopic != null) {
      final map = Map<String, String>.from(state.topicsByTarget);
      map[active.toLowerCase()] = newTopic;

      state = state.copyWith(topicsByTarget: map);
      notifyListeners();
      return;
    }

    final systemMsg = IrcParser.parseSystemEvent(
      line: line,
      myNick: currentNick,
      currentTarget: active,
    );

    if (systemMsg != null) {
      _addMessage(active, systemMsg);
      return;
    }

    final modeMsg = IrcParser.parseModeEvent(
      line: line,
      currentTarget: active,
    );

    if (modeMsg != null) {
      _addMessage(active, modeMsg);
      return;
    }

    final kickMsg = IrcParser.parseKickEvent(
      line: line,
      currentTarget: active,
    );

    if (kickMsg != null) {
      _addMessage(active, kickMsg);
    }
  }

  void _ensureChannel(String name, {bool isPrivate = false}) {
    final exists = state.channels.any(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
    );

    if (exists) return;

    final channels = [
      ...state.channels,
      Channel(name: name, isPrivate: isPrivate),
    ];

    state = state.copyWith(
      channels: channels,
      activeTarget: state.activeTarget ?? name,
    );

    notifyListeners();
  }

  void _incrementUnread(String target) {
    final channels = state.channels.map((c) {
      if (c.name.toLowerCase() == target.toLowerCase()) {
        return c.copyWith(unreadCount: c.unreadCount + 1);
      }
      return c;
    }).toList();

    state = state.copyWith(channels: channels);
    notifyListeners();
  }

  void _maintainChannelUserLists(String line) {
    final join = IrcParser.parseUserJoined(line);
    if (join != null) {
      _addChannelUser(join.channel, join.nick);
      return;
    }

    final part = IrcParser.parseUserPart(line);
    if (part != null) {
      _removeChannelUser(part.channel, part.nick);
      return;
    }

    final quitNick = IrcParser.parseQuitNick(line);
    if (quitNick != null) {
      _removeUserFromAllChannels(quitNick);
      return;
    }

    final nickChange = IrcParser.parseAnyNickChange(line);
    if (nickChange != null) {
      _renameUserInAllChannels(nickChange.oldNick, nickChange.newNick);
      return;
    }

    final kick = IrcParser.parseKickTarget(line);
    if (kick != null) {
      _removeChannelUser(kick.channel, kick.nick);
    }
  }

  void _updateChannelUsers(String key, List<String> users) {
    final usersMap = Map<String, List<String>>.from(state.usersByChannel);
    usersMap[key] = users;

    state = state.copyWith(usersByChannel: usersMap);
    notifyListeners();
  }

  void _addChannelUser(String channel, String nick) {
    final key = channel.toLowerCase();
    final existing = state.usersByChannel[key];
    if (existing == null) return;

    final cleanNick = IrcParser.stripModePrefix(nick).toLowerCase();
    final alreadyPresent = existing.any(
      (u) => IrcParser.stripModePrefix(u).toLowerCase() == cleanNick,
    );
    if (alreadyPresent) return;

    _updateChannelUsers(key, [...existing, nick]);
  }

  void _removeChannelUser(String channel, String nick) {
    final key = channel.toLowerCase();
    final existing = state.usersByChannel[key];
    if (existing == null) return;

    final cleanNick = IrcParser.stripModePrefix(nick).toLowerCase();
    final updated = existing
        .where((u) => IrcParser.stripModePrefix(u).toLowerCase() != cleanNick)
        .toList();

    if (updated.length == existing.length) return;

    _updateChannelUsers(key, updated);
  }

  void _removeUserFromAllChannels(String nick) {
    final cleanNick = nick.toLowerCase();
    final usersMap = Map<String, List<String>>.from(state.usersByChannel);
    var changed = false;

    for (final entry in usersMap.entries) {
      final updated = entry.value
          .where((u) => IrcParser.stripModePrefix(u).toLowerCase() != cleanNick)
          .toList();

      if (updated.length != entry.value.length) {
        usersMap[entry.key] = updated;
        changed = true;
      }
    }

    if (changed) {
      state = state.copyWith(usersByChannel: usersMap);
      notifyListeners();
    }
  }

  void _renameUserInAllChannels(String oldNick, String newNick) {
    final old = oldNick.toLowerCase();
    final usersMap = Map<String, List<String>>.from(state.usersByChannel);
    var changed = false;

    for (final entry in usersMap.entries) {
      var updated = entry.value;
      var entryChanged = false;

      for (var i = 0; i < updated.length; i++) {
        final token = updated[i];
        final bareToken = IrcParser.stripModePrefix(token);

        if (bareToken.toLowerCase() == old) {
          final prefix = token.substring(0, token.length - bareToken.length);

          if (!entryChanged) updated = [...updated];
          updated[i] = '$prefix$newNick';
          entryChanged = true;
        }
      }

      if (entryChanged) {
        usersMap[entry.key] = updated;
        changed = true;
      }
    }

    if (changed) {
      state = state.copyWith(usersByChannel: usersMap);
      notifyListeners();
    }
  }

  bool _isHistoryBackfill(String line) {
    final batch = IrcParser.tagValueFromLine(line, 'batch');
    if (batch == null || _activeHistoryBatch == null) return false;
    return batch.split(';').first == _activeHistoryBatch;
  }

  void _trackHistoryBatch(String line) {
    final split = IrcParser.splitLine(line);
    if (split == null || split.$2 != 'BATCH') return;

    final params = split.$3;
    if (params.isEmpty) return;

    final ref = params[0];
    final isStart = ref.startsWith('+');
    final id = ref.substring(1);

    if (!isStart) {
      if (_activeHistoryBatch == id) _activeHistoryBatch = null;
      return;
    }

    final type = params.length >= 2 ? params[1].toLowerCase() : '';
    if (type == 'draft/history' || type == 'chathistory') {
      // Only the outermost history batch matters; nested batches are ignored.
      _activeHistoryBatch ??= id;
    }
  }

  List<String> typingUsersFor(String target) {
    final users =
        state.typingByTarget[_normalizeTarget(target).toLowerCase()];
    if (users == null || users.isEmpty) return const [];

    final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
    final active = users.entries
        .where((e) => e.value.isAfter(cutoff))
        .map((e) => e.key)
        .toList()
      ..sort();
    return active;
  }

  void _handleTypingEvent(({String nick, String target, String mode}) event) {
    if (event.nick.toLowerCase() == currentNick.toLowerCase()) return;

    final key = event.target.toLowerCase();
    final targetMap = Map<String, Map<String, DateTime>>.from(
      state.typingByTarget,
    );
    final users = Map<String, DateTime>.from(targetMap[key] ?? const {});

    if (event.mode == 'done') {
      if (!users.containsKey(event.nick.toLowerCase())) return;
      users.remove(event.nick.toLowerCase());
    } else {
      users[event.nick.toLowerCase()] = DateTime.now();
    }

    if (users.isEmpty) {
      targetMap.remove(key);
    } else {
      targetMap[key] = users;
    }

    state = state.copyWith(typingByTarget: targetMap);
    notifyListeners();
  }

  void _clearTyping(String nick, String target) {
    final key = _normalizeTarget(target).toLowerCase();
    final users = state.typingByTarget[key];
    if (users == null || !users.containsKey(nick.toLowerCase())) return;

    final updatedUsers = Map<String, DateTime>.from(users)
      ..remove(nick.toLowerCase());

    final targetMap = Map<String, Map<String, DateTime>>.from(
      state.typingByTarget,
    );
    if (updatedUsers.isEmpty) {
      targetMap.remove(key);
    } else {
      targetMap[key] = updatedUsers;
    }

    state = state.copyWith(typingByTarget: targetMap);
    notifyListeners();
  }

  Future<void> joinChannel(
    String channel, {
    String? key,
  }) async {
    final clean = channel.startsWith('#') ? channel : '#$channel';

    if (key == null || key.trim().isEmpty) {
      irc.sendRaw('JOIN $clean');
    } else {
      irc.sendRaw('JOIN $clean ${key.trim()}');
    }
  }

  Future<void> closePrivateTarget(String target) async {
    final normalized = target.toLowerCase();
    final channels = state.channels
        .where((channel) => channel.name.toLowerCase() != normalized)
        .toList();

    final nextActive = state.activeTarget?.toLowerCase() == normalized
        ? (channels.isEmpty ? null : channels.first.name)
        : state.activeTarget;

    state = state.copyWith(
      channels: channels,
      activeTarget: nextActive,
    );

    notifyListeners();
    await saveChannels();
  }

  Future<void> togglePinned(String target) async {
    final channels = state.channels.map((channel) {
      if (channel.name.toLowerCase() == target.toLowerCase()) {
        return channel.copyWith(pinned: !channel.pinned);
      }
      return channel;
    }).toList();

    state = state.copyWith(channels: channels);
    notifyListeners();
    await saveChannels();
  }

  Future<void> moveChannel(String target, int delta) async {
    final index = state.channels.indexWhere(
      (c) => c.name.toLowerCase() == target.toLowerCase(),
    );
    if (index == -1) return;

    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= state.channels.length) return;

    final channels = [...state.channels];
    final channel = channels.removeAt(index);
    channels.insert(nextIndex, channel);

    state = state.copyWith(channels: channels);
    notifyListeners();
    await saveChannels();
  }

  Future<void> disconnect() async {
    await irc.disconnect();
  }

  @override
  void dispose() {
    _lineSub?.cancel();
    _statusSub?.cancel();
    _listUpdateTimer?.cancel();
    _friendPresenceTimer?.cancel();
    super.dispose();
  }
}

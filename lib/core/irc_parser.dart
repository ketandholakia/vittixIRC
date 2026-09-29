import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';
import 'package:vittix_irc/models/server_notice.dart';

class IrcParser {
  /// Splits a raw IRC line into (prefix, command, params) per RFC 2812,
  /// skipping IRCv3 message-tags when present. Returns null for lines that
  /// carry no command token.
  ///
  /// Matching commands positionally (instead of substring checks) prevents
  /// message text like "see RFC 433" from being mistaken for a server reply.
  static (String? prefix, String command, List<String> params)? splitLine(
    String line,
  ) {
    var rest = line;

    if (rest.startsWith('@')) {
      final space = rest.indexOf(' ');
      if (space == -1) return null;
      rest = rest.substring(space + 1);
    }

    String? prefix;
    if (rest.startsWith(':')) {
      final space = rest.indexOf(' ');
      if (space == -1) return null;
      prefix = rest.substring(1, space);
      rest = rest.substring(space + 1);
    }

    if (rest.isEmpty) return null;

    final parts = rest.split(' ');
    final command = parts.removeAt(0);

    return (prefix, command, parts);
  }

  /// The command token of the line ('PRIVMSG', 'NOTICE', '433', ...) or null.
  static String? commandFromLine(String line) {
    return splitLine(line)?.$2;
  }

  /// The numeric reply code of the line (e.g. '433'), or null.
  static String? numericFromLine(String line) {
    final command = commandFromLine(line);
    if (command == null || command.length != 3) return null;
    return int.tryParse(command) == null ? null : command;
  }

  /// Joins the trailing param (everything after the first " :" or the first
  /// ':'-prefixed token) back into a single string, or null if none exists.
  static String? _trailingFromParams(List<String> params) {
    for (var i = 0; i < params.length; i++) {
      if (params[i].startsWith(':')) {
        final rest = params.sublist(i + 1).join(' ');
        return rest.isEmpty ? params[i].substring(1) : '${params[i].substring(1)} $rest';
      }
    }
    return null;
  }

  static String? _senderNickFromPrefix(String? prefix) {
    if (prefix == null || prefix.isEmpty) return null;
    return prefix.split('!').first;
  }

  /// Strips channel-membership prefixes (~ & @ % +) from a NAMES token.
  static String stripModePrefix(String token) {
    var t = token;
    while (t.isNotEmpty && '~&@%+'.contains(t[0])) {
      t = t.substring(1);
    }
    return t;
  }

  /// Extracts a message-tag value from the line's `@tags` prefix (minimal
  /// unescaping), or null when absent.
  static String? tagValueFromLine(String line, String name) {
    if (!line.startsWith('@')) return null;

    final space = line.indexOf(' ');
    if (space == -1) return null;

    for (final tag in line.substring(1, space).split(';')) {
      final eq = tag.indexOf('=');
      if (eq == -1 || tag.substring(0, eq) != name) continue;

      return tag
          .substring(eq + 1)
          .replaceAll(r'\:', ';')
          .replaceAll(r'\s', ' ')
          .replaceAll(r'\\', r'\');
    }

    return null;
  }

  /// Extracts the IRCv3 `time` message-tag value (server-time) as a local
  /// DateTime, or null when the line has no usable time tag.
  static DateTime? timeFromTags(String line) {
    final raw = tagValueFromLine(line, 'time');
    if (raw == null) return null;

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.toLocal();
  }

  /// Parses a TYPING event (`@typing=active :bob TYPING #chan`).
  static ({String nick, String target, String mode})? parseTyping(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'TYPING') return null;

    final nick = _senderNickFromPrefix(split.$1);
    if (nick == null || split.$3.isEmpty) return null;

    final mode = tagValueFromLine(line, 'typing') ?? 'done';

    return (nick: nick, target: split.$3[0], mode: mode);
  }

  /// Formats a timestamp for CHATHISTORY parameters
  /// (`timestamp=YYYY-MM-DDThh:mm:ss.sssZ`, always UTC).
  static String formatChathistoryTimestamp(DateTime time) {
    final utc = time.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');

    return 'timestamp='
        '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}'
        '.${utc.millisecond.toString().padLeft(3, '0')}Z';
  }

  /// Parses a CAP client line (`CAP * LS :...`, `CAP me ACK :sasl`, ...)
  /// into its subcommand and capability list, or null. Handles the client
  /// nick being present or replaced by `*`, and `*` multiline continuation
  /// markers.
  static ({String subcommand, List<String> caps})? parseCapLine(String line) {
    final split = splitLine(line);
    if (split == null || split.$2.toUpperCase() != 'CAP') return null;

    const subcommands = {'LS', 'LIST', 'REQ', 'ACK', 'NAK', 'END', 'NEW', 'DEL'};

    for (var i = 0; i < split.$3.length; i++) {
      final param = split.$3[i];

      // Subcommands are middle params; a ':'-prefixed token is the trailing.
      if (param.startsWith(':')) continue;
      if (!subcommands.contains(param.toUpperCase())) continue;

      final caps = split.$3
          .sublist(i + 1)
          .where((t) => t != '*')
          .map((t) => t.startsWith(':') ? t.substring(1) : t)
          .where((t) => t.isNotEmpty)
          .toList();

      return (subcommand: param.toUpperCase(), caps: caps);
    }

    return null;
  }

  /// Parses the IRCv3 STS capability value `sts=<port>,<duration>[,...]`.
  /// Over TLS the port is omitted (`sts=<duration>`), so [currentPort] fills
  /// in. Returns null when nothing usable can be parsed; durationSeconds of 0
  /// means the policy is withdrawn.
  static ({int securePort, int durationSeconds})? parseStsCapValue(
    String value, {
    required bool isTlsConnection,
    required int currentPort,
  }) {
    final parts = value.split(',');
    if (parts.isEmpty) return null;

    final int securePort;
    final int durationSeconds;

    if (isTlsConnection) {
      securePort = currentPort;
      durationSeconds = int.tryParse(parts.first.trim()) ?? 0;
    } else {
      securePort = int.tryParse(parts.first.trim()) ?? 0;
      durationSeconds =
          parts.length >= 2 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    }

    if (securePort <= 0 && durationSeconds <= 0) return null;

    return (securePort: securePort, durationSeconds: durationSeconds);
  }

  static bool _paramsContainTarget(List<String> params, String target) {
    final needle = target.toLowerCase();
    return params.any((p) => p.toLowerCase() == needle);
  }

  static ChatMessage? parsePrivMsg({
    required String line,
    required String myNick,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'PRIVMSG') return null;
    if (split.$1 == null) return null;

    final sender = _senderNickFromPrefix(split.$1)!;
    if (split.$3.isEmpty) return null;

    final target = split.$3[0];

    final trailing = _trailingFromParams(split.$3);
    if (trailing == null) return null;

    var messageType = ChatMessageType.normal;
    var messageText = trailing;

    if (trailing.startsWith('\u0001ACTION ') && trailing.endsWith('\u0001')) {
      messageType = ChatMessageType.action;
      messageText = trailing
          .replaceFirst('\u0001ACTION ', '')
          .replaceFirst('\u0001', '');
    }

    return ChatMessage(
      sender: sender,
      target: target,
      text: messageText,
      time: timeFromTags(line) ?? DateTime.now(),
      isMe: sender.toLowerCase() == myNick.toLowerCase(),
      type: messageType,
    );
  }

  static bool isWelcome(String line) {
    return numericFromLine(line) == '001';
  }

  static String? parsePingToken(String line) {
    if (!line.startsWith('PING')) return null;
    if (line.length > 4 && line[4] != ' ') return null;
    return line.length > 5 ? line.substring(5).trim() : '';
  }

  static ({String inviter, String channel})? parseInvite({
    required String line,
    required String myNick,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'INVITE') return null;

    final inviter = _senderNickFromPrefix(split.$1);
    if (inviter == null) return null;

    if (split.$3.length < 2) return null;

    final targetNick = split.$3[0];
    if (targetNick.toLowerCase() != myNick.toLowerCase()) return null;

    var channel = split.$3[1].trim();
    if (channel.startsWith(':')) {
      channel = channel.substring(1);
    }

    if (channel.isEmpty) return null;

    return (inviter: inviter, channel: channel);
  }

  static bool isWhoisLine(String line) {
    final numeric = numericFromLine(line);
    return numeric == '311' ||
        numeric == '312' ||
        numeric == '317' ||
        numeric == '318' ||
        numeric == '319' ||
        numeric == '330';
  }

  static String? whoisNickFromLine(String line) {
    // :server 311 <me> <nick> <user> <host> * :<realname>
    final params = splitLine(line)?.$3;
    if (params == null || params.length < 2) return null;
    return params[1];
  }

  static bool isNicknameInUse(String line) {
    return numericFromLine(line) == '433';
  }

  static String? parseJoinedChannel({
    required String line,
    required String myNick,
  }) {
    // Example:
    // :ketan!user@host JOIN :#flutter
    // :ketan!user@host JOIN #flutter

    final split = splitLine(line);
    if (split == null || split.$2 != 'JOIN') return null;

    final sender = _senderNickFromPrefix(split.$1);
    if (sender == null) return null;

    if (sender.toLowerCase() != myNick.toLowerCase()) return null;

    if (split.$3.isEmpty) return null;

    var channel = split.$3.first.trim();
    if (channel.startsWith(':')) {
      channel = channel.substring(1);
    }

    if (channel.isEmpty) return null;

    return channel;
  }

  static String? parsePartedChannel({
    required String line,
    required String myNick,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'PART') return null;

    final sender = _senderNickFromPrefix(split.$1);
    if (sender == null) return null;

    if (sender.toLowerCase() != myNick.toLowerCase()) return null;

    if (split.$3.isEmpty) return null;

    var channel = split.$3.first;
    if (channel.startsWith(':')) {
      channel = channel.substring(1);
    }

    return channel.isEmpty ? null : channel;
  }

  /// Another user joined a channel: `:nick!user@host JOIN :#chan`.
  static ({String nick, String channel})? parseUserJoined(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'JOIN') return null;

    final nick = _senderNickFromPrefix(split.$1);
    if (nick == null || split.$3.isEmpty) return null;

    var channel = split.$3.first;
    if (channel.startsWith(':')) channel = channel.substring(1);

    if (channel.isEmpty) return null;

    return (nick: nick, channel: channel);
  }

  /// Another user left a channel: `:nick!user@host PART #chan :reason`.
  static ({String nick, String channel})? parseUserPart(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'PART') return null;

    final nick = _senderNickFromPrefix(split.$1);
    if (nick == null || split.$3.isEmpty) return null;

    var channel = split.$3.first;
    if (channel.startsWith(':')) channel = channel.substring(1);

    if (channel.isEmpty) return null;

    return (nick: nick, channel: channel);
  }

  /// A user quit the network: `:nick!user@host QUIT :reason`.
  static String? parseQuitNick(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'QUIT') return null;

    final nick = _senderNickFromPrefix(split.$1);
    return nick;
  }

  /// Any user changed nick: `:old!user@host NICK :new`.
  static ({String oldNick, String newNick})? parseAnyNickChange(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'NICK') return null;

    final oldNick = _senderNickFromPrefix(split.$1);
    if (oldNick == null || split.$3.isEmpty) return null;

    var newNick = split.$3.first;
    if (newNick.startsWith(':')) newNick = newNick.substring(1);

    if (newNick.isEmpty) return null;

    return (oldNick: oldNick, newNick: newNick);
  }

  /// A user was kicked: `:op!user@host KICK #chan victim :reason`.
  static ({String channel, String nick})? parseKickTarget(String line) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'KICK') return null;

    if (split.$3.length < 2) return null;

    var channel = split.$3[0];
    if (channel.startsWith(':')) channel = channel.substring(1);

    if (channel.isEmpty) return null;

    return (channel: channel, nick: split.$3[1]);
  }

  static List<String>? parseNamesReply({
    required String line,
    required String channelName,
  }) {
    // Example:
    // :server 353 myNick = #test :@admin +voice normalUser

    if (numericFromLine(line) != '353') return null;

    final split = splitLine(line);
    if (split == null) return null;

    if (!_paramsContainTarget(split.$3, channelName)) return null;

    final namesText = _trailingFromParams(split.$3);
    if (namesText == null) return null;

    return namesText
        .split(' ')
        .where((name) => name.trim().isNotEmpty)
        .toList();
  }

  static String? parseTopicReply({
    required String line,
    required String channelName,
  }) {
    // Example:
    // :server 332 myNick #test :Welcome to test channel

    if (numericFromLine(line) != '332') return null;

    final split = splitLine(line);
    if (split == null) return null;

    if (!_paramsContainTarget(split.$3, channelName)) return null;

    return _trailingFromParams(split.$3);
  }

  static String? parseTopicChanged({
    required String line,
    required String channelName,
  }) {
    // Example:
    // :nick!user@host TOPIC #test :New topic

    final split = splitLine(line);
    if (split == null || split.$2 != 'TOPIC') return null;

    if (split.$3.isEmpty) return null;

    if (split.$3.first.toLowerCase() != channelName.toLowerCase()) {
      return null;
    }

    return _trailingFromParams(split.$3);
  }

  static String? parseChannelModesReply({
    required String line,
    required String channelName,
  }) {
    if (numericFromLine(line) != '324') return null;

    final split = splitLine(line);
    if (split == null || split.$3.length < 3) return null;

    final channel = split.$3[1];
    final modes = split.$3[2];

    if (channel.toLowerCase() != channelName.toLowerCase()) {
      return null;
    }

    return modes;
  }

  static String? parseChannelModeChanged({
    required String line,
    required String channelName,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'MODE') return null;

    if (split.$3.length < 2) return null;

    final target = split.$3[0];
    final modeChange = split.$3[1];

    if (target.toLowerCase() != channelName.toLowerCase()) {
      return null;
    }

    return modeChange;
  }

  static String? parseOwnNickChange({
    required String line,
    required String currentNick,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'NICK') return null;

    final oldNick = _senderNickFromPrefix(split.$1);
    if (oldNick == null) return null;

    if (oldNick.toLowerCase() != currentNick.toLowerCase()) {
      return null;
    }

    if (split.$3.isEmpty) return null;

    var newNick = split.$3.first.trim();

    if (newNick.startsWith(':')) {
      newNick = newNick.substring(1);
    }

    return newNick.isEmpty ? null : newNick;
  }

  static ChatMessage? parseModeEvent({
    required String line,
    required String currentTarget,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'MODE') return null;

    final sender = _senderNickFromPrefix(split.$1);
    if (sender == null) return null;

    if (split.$3.isEmpty) return null;

    final target = split.$3[0];

    if (target.toLowerCase() != currentTarget.toLowerCase()) {
      return null;
    }

    final modeText = split.$3.sublist(1).join(' ');

    return ChatMessage(
      sender: 'system',
      target: currentTarget,
      text: '$sender set mode $modeText',
      time: timeFromTags(line) ?? DateTime.now(),
      isSystem: true,
      type: ChatMessageType.system,
    );
  }

  static ChatMessage? parseKickEvent({
    required String line,
    required String currentTarget,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'KICK') return null;

    final sender = _senderNickFromPrefix(split.$1);
    if (sender == null) return null;

    if (split.$3.length < 2) return null;

    final channel = split.$3[0];
    final kickedNick = split.$3[1];

    if (channel.toLowerCase() != currentTarget.toLowerCase()) {
      return null;
    }

    final reasonIndex = line.indexOf(' :');
    final reason = reasonIndex == -1 ? '' : line.substring(reasonIndex + 2);

    final text = reason.isEmpty
        ? '$sender kicked $kickedNick from $channel'
        : '$sender kicked $kickedNick from $channel: $reason';

    return ChatMessage(
      sender: 'system',
      target: currentTarget,
      text: text,
      time: timeFromTags(line) ?? DateTime.now(),
      isSystem: true,
      type: ChatMessageType.system,
    );
  }

  static String? parseKickedChannelForMe({
    required String line,
    required String myNick,
  }) {
    final split = splitLine(line);
    if (split == null || split.$2 != 'KICK') return null;

    if (split.$3.length < 2) return null;

    final channel = split.$3[0];
    final kickedNick = split.$3[1];

    if (kickedNick.toLowerCase() != myNick.toLowerCase()) {
      return null;
    }

    return channel;
  }

  static ChatMessage? parseSystemEvent({
    required String line,
    required String myNick,
    required String currentTarget,
  }) {
    final split = splitLine(line);
    if (split == null || split.$1 == null) return null;

    final sender = _senderNickFromPrefix(split.$1)!;
    final params = split.$3;

    switch (split.$2) {
      case 'JOIN':
        if (params.isEmpty) return null;

        var channel = params.first;
        if (channel.startsWith(':')) channel = channel.substring(1);

        if (channel.toLowerCase() != currentTarget.toLowerCase()) return null;

        return ChatMessage(
          sender: 'system',
          target: channel,
          text: '$sender joined $channel',
          time: timeFromTags(line) ?? DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'PART':
        if (params.isEmpty) return null;

        final channel = params.first.startsWith(':')
            ? params.first.substring(1)
            : params.first;

        if (channel.toLowerCase() != currentTarget.toLowerCase()) return null;

        return ChatMessage(
          sender: 'system',
          target: channel,
          text: '$sender left $channel',
          time: timeFromTags(line) ?? DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'QUIT':
        return ChatMessage(
          sender: 'system',
          target: currentTarget,
          text: '$sender quit',
          time: timeFromTags(line) ?? DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'NICK':
        if (params.isEmpty) return null;

        var newNick = params.first;
        if (newNick.startsWith(':')) newNick = newNick.substring(1);

        return ChatMessage(
          sender: 'system',
          target: currentTarget,
          text: '$sender is now known as $newNick',
          time: timeFromTags(line) ?? DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      default:
        return null;
    }
  }

  static IrcChannelInfo? parseListReply(String line) {
    // Example:
    // :server 322 myNick #flutter 120 :Flutter discussion

    if (numericFromLine(line) != '322') return null;

    final split = splitLine(line);
    if (split == null || split.$3.length < 3) return null;

    final topicIndex = line.indexOf(' :');
    if (topicIndex == -1) return null;

    return IrcChannelInfo(
      name: split.$3[1],
      users: int.tryParse(split.$3[2]) ?? 0,
      topic: line.substring(topicIndex + 2),
    );
  }

  static bool isListEnd(String line) {
    // 323 = End of LIST
    return numericFromLine(line) == '323';
  }

  static ServerNotice? parseServerNotice(String line) {
    ServerNoticeType type = ServerNoticeType.raw;
    String? text;

    final numeric = numericFromLine(line);
    final command = commandFromLine(line);

    if (numeric == '433') {
      type = ServerNoticeType.error;
      text = 'Nickname is already in use.';
    } else if (numeric == '464') {
      type = ServerNoticeType.error;
      text = 'Password incorrect.';
    } else if (numeric == '471') {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: channel is full.';
    } else if (numeric == '473') {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: invite only.';
    } else if (numeric == '474') {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: banned.';
    } else if (numeric == '475') {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: bad channel key.';
    } else if (numeric == '904' ||
        numeric == '905' ||
        numeric == '906' ||
        numeric == '907') {
      type = ServerNoticeType.error;
      text = 'SASL authentication failed.';
    } else if (command == 'NOTICE') {
      type = ServerNoticeType.info;
      final idx = line.indexOf(' :');
      text = idx == -1 ? line : line.substring(idx + 2);
    }

    if (text == null) return null;

    return ServerNotice(
      text: text,
      time: timeFromTags(line) ?? DateTime.now(),
      type: type,
      rawLine: line,
      channel: _channelFromNumericLine(line),
    );
  }

  static String? _channelFromNumericLine(String line) {
    // Error numerics like 473 carry the channel right after the client nick:
    // :server 473 <me> #chan :Cannot join channel (+i)
    final params = splitLine(line)?.$3;
    if (params == null || params.length < 2) return null;

    final token = params[1];
    return token.startsWith('#') ? token : null;
  }
}

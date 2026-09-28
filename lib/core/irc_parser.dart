import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';
import 'package:vittix_irc/models/server_notice.dart';

class IrcParser {
  static ChatMessage? parsePrivMsg({
    required String line,
    required String myNick,
  }) {
    if (!line.contains(' PRIVMSG ')) return null;
    if (!line.startsWith(':')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final prefix = line.substring(1, prefixEnd);
    final sender = prefix.split('!').first;

    final privmsgIndex = line.indexOf(' PRIVMSG ');
    final afterCommand = line.substring(privmsgIndex + 9);

    final targetEnd = afterCommand.indexOf(' ');
    if (targetEnd == -1) return null;

    final target = afterCommand.substring(0, targetEnd);

    final textIndex = afterCommand.indexOf(' :');
    if (textIndex == -1) return null;

    final text = afterCommand.substring(textIndex + 2);

    var messageType = ChatMessageType.normal;
    var messageText = text;

    if (text.startsWith('\u0001ACTION ') && text.endsWith('\u0001')) {
      messageType = ChatMessageType.action;
      messageText = text
          .replaceFirst('\u0001ACTION ', '')
          .replaceFirst('\u0001', '');
    }

    return ChatMessage(
      sender: sender,
      target: target,
      text: messageText,
      time: DateTime.now(),
      isMe: sender.toLowerCase() == myNick.toLowerCase(),
      type: messageType,
    );
  }

  static bool isWelcome(String line) {
    return line.contains(' 001 ');
  }

  static String? parsePingToken(String line) {
    if (!line.startsWith('PING')) return null;
    return line.substring(5).trim();
  }

  static ({String inviter, String channel})? parseInvite({
    required String line,
    required String myNick,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' INVITE ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final inviter = line.substring(1, prefixEnd).split('!').first;

    final rest = line.substring(prefixEnd + 1);
    final parts = rest.split(' ');

    if (parts.length < 3) return null;

    final targetNick = parts[1];
    if (targetNick.toLowerCase() != myNick.toLowerCase()) return null;

    var channel = parts[2].trim();
    if (channel.startsWith(':')) {
      channel = channel.substring(1);
    }

    if (channel.isEmpty) return null;

    return (inviter: inviter, channel: channel);
  }

  static bool isWhoisLine(String line) {
    return line.contains(' 311 ') ||
        line.contains(' 312 ') ||
        line.contains(' 317 ') ||
        line.contains(' 318 ') ||
        line.contains(' 319 ') ||
        line.contains(' 330 ');
  }

  static String? whoisNickFromLine(String line) {
    final parts = line.split(' ');
    if (parts.length >= 4) {
      return parts[3];
    }
    return null;
  }

  static bool isNicknameInUse(String line) {
    return line.contains(' 433 ');
  }

  static String? parseJoinedChannel({
    required String line,
    required String myNick,
  }) {
    // Example:
    // :ketan!user@host JOIN :#flutter
    // :ketan!user@host JOIN #flutter

    if (!line.startsWith(':')) return null;
    if (!line.contains(' JOIN ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final prefix = line.substring(1, prefixEnd);
    final sender = prefix.split('!').first;

    if (sender.toLowerCase() != myNick.toLowerCase()) return null;

    final joinIndex = line.indexOf(' JOIN ');
    var channel = line.substring(joinIndex + 6).trim();

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
    if (!line.startsWith(':')) return null;
    if (!line.contains(' PART ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final prefix = line.substring(1, prefixEnd);
    final sender = prefix.split('!').first;

    if (sender.toLowerCase() != myNick.toLowerCase()) return null;

    final partIndex = line.indexOf(' PART ');
    final afterPart = line.substring(partIndex + 6).trim();

    if (afterPart.isEmpty) return null;

    return afterPart.split(' ').first;
  }

  static List<String>? parseNamesReply({
    required String line,
    required String channelName,
  }) {
    // Example:
    // :server 353 myNick = #test :@admin +voice normalUser

    if (!line.contains(' 353 ')) return null;
    if (!line.contains(' $channelName ')) return null;

    final namesIndex = line.indexOf(' :');
    if (namesIndex == -1) return null;

    final namesText = line.substring(namesIndex + 2);

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

    if (!line.contains(' 332 ')) return null;
    if (!line.contains(' $channelName ')) return null;

    final topicIndex = line.indexOf(' :');
    if (topicIndex == -1) return null;

    return line.substring(topicIndex + 2);
  }

  static String? parseTopicChanged({
    required String line,
    required String channelName,
  }) {
    // Example:
    // :nick!user@host TOPIC #test :New topic

    if (!line.startsWith(':')) return null;
    if (!line.contains(' TOPIC $channelName ')) return null;

    final topicIndex = line.indexOf(' :');
    if (topicIndex == -1) return null;

    return line.substring(topicIndex + 2);
  }

  static String? parseChannelModesReply({
    required String line,
    required String channelName,
  }) {
    if (!line.contains(' 324 ')) return null;

    final parts = line.split(' ');
    if (parts.length < 5) return null;

    final channel = parts[3];
    final modes = parts[4];

    if (channel.toLowerCase() != channelName.toLowerCase()) {
      return null;
    }

    return modes;
  }

  static String? parseChannelModeChanged({
    required String line,
    required String channelName,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' MODE ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final rest = line.substring(prefixEnd + 1);
    final parts = rest.split(' ');

    if (parts.length < 3) return null;

    final target = parts[1];
    final modeChange = parts[2];

    if (target.toLowerCase() != channelName.toLowerCase()) {
      return null;
    }

    return modeChange;
  }

  static String? parseOwnNickChange({
    required String line,
    required String currentNick,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' NICK ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final prefix = line.substring(1, prefixEnd);
    final oldNick = prefix.split('!').first;

    if (oldNick.toLowerCase() != currentNick.toLowerCase()) {
      return null;
    }

    var newNick = line.substring(line.indexOf(' NICK ') + 6).trim();

    if (newNick.startsWith(':')) {
      newNick = newNick.substring(1);
    }

    return newNick.isEmpty ? null : newNick;
  }

  static ChatMessage? parseModeEvent({
    required String line,
    required String currentTarget,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' MODE ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final sender = line.substring(1, prefixEnd).split('!').first;
    final rest = line.substring(prefixEnd + 1);
    final parts = rest.split(' ');

    if (parts.length < 3) return null;

    final target = parts[1];

    if (target.toLowerCase() != currentTarget.toLowerCase()) {
      return null;
    }

    final modeText = parts.sublist(2).join(' ');

    return ChatMessage(
      sender: 'system',
      target: currentTarget,
      text: '$sender set mode $modeText',
      time: DateTime.now(),
      isSystem: true,
      type: ChatMessageType.system,
    );
  }

  static ChatMessage? parseKickEvent({
    required String line,
    required String currentTarget,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' KICK ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final sender = line.substring(1, prefixEnd).split('!').first;
    final rest = line.substring(prefixEnd + 1);
    final parts = rest.split(' ');

    if (parts.length < 3) return null;

    final channel = parts[1];
    final kickedNick = parts[2];

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
      time: DateTime.now(),
      isSystem: true,
      type: ChatMessageType.system,
    );
  }

  static String? parseKickedChannelForMe({
    required String line,
    required String myNick,
  }) {
    if (!line.startsWith(':')) return null;
    if (!line.contains(' KICK ')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final rest = line.substring(prefixEnd + 1);
    final parts = rest.split(' ');

    if (parts.length < 3) return null;

    final channel = parts[1];
    final kickedNick = parts[2];

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
    if (!line.startsWith(':')) return null;

    final prefixEnd = line.indexOf(' ');
    if (prefixEnd == -1) return null;

    final prefix = line.substring(1, prefixEnd);
    final sender = prefix.split('!').first;
    final rest = line.substring(prefixEnd + 1);

    final parts = rest.split(' ');
    if (parts.isEmpty) return null;

    final command = parts[0];

    switch (command) {
      case 'JOIN':
        var channel = rest.substring(5).trim();
        if (channel.startsWith(':')) channel = channel.substring(1);

        if (channel.toLowerCase() != currentTarget.toLowerCase()) return null;

        return ChatMessage(
          sender: 'system',
          target: channel,
          text: '$sender joined $channel',
          time: DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'PART':
        if (parts.length < 2) return null;

        final channel = parts[1];
        if (channel.toLowerCase() != currentTarget.toLowerCase()) return null;

        return ChatMessage(
          sender: 'system',
          target: channel,
          text: '$sender left $channel',
          time: DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'QUIT':
        return ChatMessage(
          sender: 'system',
          target: currentTarget,
          text: '$sender quit',
          time: DateTime.now(),
          isSystem: true,
          type: ChatMessageType.system,
        );

      case 'NICK':
        if (parts.length < 2) return null;

        var newNick = parts[1];
        if (newNick.startsWith(':')) newNick = newNick.substring(1);

        return ChatMessage(
          sender: 'system',
          target: currentTarget,
          text: '$sender is now known as $newNick',
          time: DateTime.now(),
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

    if (!line.contains(' 322 ')) return null;

    final topicIndex = line.indexOf(' :');
    if (topicIndex == -1) return null;

    final beforeTopic = line.substring(0, topicIndex);
    final topic = line.substring(topicIndex + 2);

    final parts = beforeTopic.split(' ');

    if (parts.length < 5) return null;

    final channel = parts[3];
    final users = int.tryParse(parts[4]) ?? 0;

    return IrcChannelInfo(
      name: channel,
      users: users,
      topic: topic,
    );
  }

  static bool isListEnd(String line) {
    // 323 = End of LIST
    return line.contains(' 323 ');
  }

  static ServerNotice? parseServerNotice(String line) {
    ServerNoticeType type = ServerNoticeType.raw;
    String? text;

    if (line.contains(' 433 ')) {
      type = ServerNoticeType.error;
      text = 'Nickname is already in use.';
    } else if (line.contains(' 464 ')) {
      type = ServerNoticeType.error;
      text = 'Password incorrect.';
    } else if (line.contains(' 471 ')) {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: channel is full.';
    } else if (line.contains(' 473 ')) {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: invite only.';
    } else if (line.contains(' 474 ')) {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: banned.';
    } else if (line.contains(' 475 ')) {
      type = ServerNoticeType.error;
      text = 'Cannot join channel: bad channel key.';
    } else if (line.contains(' 904 ') ||
        line.contains(' 905 ') ||
        line.contains(' 906 ') ||
        line.contains(' 907 ')) {
      type = ServerNoticeType.error;
      text = 'SASL authentication failed.';
    } else if (line.contains(' NOTICE ')) {
      type = ServerNoticeType.info;
      final idx = line.indexOf(' :');
      text = idx == -1 ? line : line.substring(idx + 2);
    }

    if (text == null) return null;

    return ServerNotice(
      text: text,
      time: DateTime.now(),
      type: type,
      rawLine: line,
      channel: _channelFromNumericLine(line),
    );
  }

  static String? _channelFromNumericLine(String line) {
    final parts = line.split(' ');

    if (parts.length >= 4 && parts[3].startsWith('#')) {
      return parts[3];
    }

    return null;
  }
}

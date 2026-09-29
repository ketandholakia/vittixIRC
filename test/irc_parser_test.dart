import 'package:flutter_test/flutter_test.dart';

import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/server_notice.dart';

void main() {
  group('command/numeric extraction', () {
    test('extracts the command token positionally', () {
      expect(
        IrcParser.commandFromLine(':alice!u@h PRIVMSG #chan :hello'),
        'PRIVMSG',
      );
      expect(IrcParser.commandFromLine('PING :token'), 'PING');
      expect(IrcParser.commandFromLine(':server 433 me bob :in use'), '433');
    });

    test('skips IRCv3 message-tags', () {
      expect(
        IrcParser.numericFromLine(
          '@time=2024-01-01T00:00:00Z :server 433 me bob :in use',
        ),
        '433',
      );
    });

    test('numericFromLine rejects named commands and junk', () {
      expect(IrcParser.numericFromLine(':server PRIVMSG x'), isNull);
      expect(IrcParser.numericFromLine('CAP LS 302'), isNull);
      expect(IrcParser.numericFromLine(''), isNull);
    });
  });

  group('numeric false-positive regression', () {
    // A user message whose *text* mentions numerics or commands must never be
    // mistaken for a server reply.
    const tricky = ':alice!u@h PRIVMSG #chan :see RFC 433 / 001 / 353 codes '
        'and 322 TOPIC #chan 324 MODE 303';

    test('PRIVMSG text is not a welcome', () {
      expect(IrcParser.isWelcome(tricky), isFalse);
      expect(IrcParser.isWelcome(':server 001 me :Welcome to the network'),
          isTrue);
    });

    test('PRIVMSG text is not a nick collision', () {
      expect(IrcParser.isNicknameInUse(tricky), isFalse);
      expect(IrcParser.isNicknameInUse(':server 433 * bob :Nickname is in use'),
          isTrue);
    });

    test('PRIVMSG text is not a whois reply', () {
      expect(IrcParser.isWhoisLine(tricky), isFalse);
      expect(IrcParser.isWhoisLine(':server 311 me bob user host * :Bob'),
          isTrue);
    });

    test('PRIVMSG text is not a server notice', () {
      expect(IrcParser.parseServerNotice(tricky), isNull);
    });

    test('PRIVMSG text is not a names reply', () {
      // Contains both " 353 " and " #chan " as substrings.
      expect(
        IrcParser.parseNamesReply(line: tricky, channelName: '#chan'),
        isNull,
      );
    });

    test('PRIVMSG text is not a topic change', () {
      expect(
        IrcParser.parseTopicChanged(
          line: ':alice!u@h PRIVMSG #chan :TOPIC #chan is great',
          channelName: '#chan',
        ),
        isNull,
      );
    });

    test('PRIVMSG text is not an invite', () {
      expect(
        IrcParser.parseInvite(
          line: ':alice!u@h PRIVMSG #chan :INVITE bob #secret',
          myNick: 'bob',
        ),
        isNull,
      );
    });

    test('PRIVMSG text does not fake a channel mode change', () {
      expect(
        IrcParser.parseChannelModeChanged(
          line: ':alice!u@h PRIVMSG #chan :MODE #chan +m now',
          channelName: '#chan',
        ),
        isNull,
      );
    });
  });

  group('parsePrivMsg', () {
    test('parses a channel message', () {
      final msg = IrcParser.parsePrivMsg(
        line: ':alice!u@h PRIVMSG #chan :hello world',
        myNick: 'me',
      );

      expect(msg, isNotNull);
      expect(msg!.sender, 'alice');
      expect(msg.target, '#chan');
      expect(msg.text, 'hello world');
      expect(msg.isMe, isFalse);
      expect(msg.type, ChatMessageType.normal);
    });

    test('parses a private message and flags own messages', () {
      final incoming = IrcParser.parsePrivMsg(
        line: ':alice!u@h PRIVMSG me :hi there',
        myNick: 'me',
      );
      expect(incoming!.target, 'me');

      final own = IrcParser.parsePrivMsg(
        line: ':me!u@h PRIVMSG #chan :posted by me',
        myNick: 'me',
      );
      expect(own!.isMe, isTrue);
    });

    test('parses /me actions', () {
      final msg = IrcParser.parsePrivMsg(
        line: ':alice!u@h PRIVMSG #chan :\u0001ACTION waves\u0001',
        myNick: 'me',
      );

      expect(msg!.type, ChatMessageType.action);
      expect(msg.text, 'waves');
    });

    test('rejects non-PRIVMSG lines', () {
      expect(
        IrcParser.parsePrivMsg(line: ':server 001 me :Welcome', myNick: 'me'),
        isNull,
      );
    });
  });

  group('parseServerNotice', () {
    test('maps real error numerics', () {
      final banned = IrcParser.parseServerNotice(
        ':server 474 me #chan :Cannot join channel (+b)',
      );

      expect(banned!.type, ServerNoticeType.error);
      expect(banned.channel, '#chan');
    });

    test('parses NOTICE as info', () {
      final notice = IrcParser.parseServerNotice(
        ':NickServ NOTICE me :You are now identified.',
      );

      expect(notice!.type, ServerNoticeType.info);
      expect(notice.text, 'You are now identified.');
    });

    test('ignores ordinary channel chatter', () {
      expect(
        IrcParser.parseServerNotice(
          ':alice!u@h PRIVMSG #chan :password incorrect btw',
        ),
        isNull,
      );
    });
  });

  group('parsePingToken', () {
    test('parses PING with token', () {
      expect(IrcParser.parsePingToken('PING :abc123'), ':abc123');
      expect(IrcParser.parsePingToken('PING server1'), 'server1');
    });

    test('handles bare PING without crashing', () {
      expect(IrcParser.parsePingToken('PING'), '');
    });

    test('rejects lookalike commands', () {
      expect(IrcParser.parsePingToken('PINGPONG :x'), isNull);
    });
  });

  group('parseNamesReply', () {
    test('parses names including mode prefixes', () {
      final names = IrcParser.parseNamesReply(
        line: ':server 353 me = #test :@admin +voice normalUser',
        channelName: '#test',
      );

      expect(names, ['@admin', '+voice', 'normalUser']);
      expect(IrcParser.stripModePrefix('@admin'), 'admin');
      expect(IrcParser.stripModePrefix('+voice'), 'voice');
      expect(IrcParser.stripModePrefix('normalUser'), 'normalUser');
    });

    test('ignores other channels and non-353 lines', () {
      expect(
        IrcParser.parseNamesReply(
          line: ':server 353 me = #other :bob',
          channelName: '#test',
        ),
        isNull,
      );
      expect(
        IrcParser.parseNamesReply(
          line: ':server 366 me #test :End of /NAMES',
          channelName: '#test',
        ),
        isNull,
      );
    });
  });

  group('topic parsing', () {
    test('parses topic reply 332', () {
      final topic = IrcParser.parseTopicReply(
        line: ':server 332 me #test :Welcome to test channel',
        channelName: '#test',
      );

      expect(topic, 'Welcome to test channel');
    });

    test('parses TOPIC changes', () {
      final topic = IrcParser.parseTopicChanged(
        line: ':alice!u@h TOPIC #test :New topic here',
        channelName: '#test',
      );

      expect(topic, 'New topic here');
    });
  });

  group('channel modes', () {
    test('parses 324 mode reply', () {
      final modes = IrcParser.parseChannelModesReply(
        line: ':server 324 me #test +nt',
        channelName: '#test',
      );

      expect(modes, '+nt');
    });

    test('parses MODE changes', () {
      final mode = IrcParser.parseChannelModeChanged(
        line: ':alice!u@h MODE #test +m',
        channelName: '#test',
      );

      expect(mode, '+m');
    });
  });

  group('user event helpers', () {
    test('parseUserJoined handles quoted and bare channels', () {
      expect(
        IrcParser.parseUserJoined(':bob!u@h JOIN :#flutter'),
        (nick: 'bob', channel: '#flutter'),
      );
      expect(
        IrcParser.parseUserJoined(':bob!u@h JOIN #flutter key'),
        (nick: 'bob', channel: '#flutter'),
      );
    });

    test('parseUserPart extracts channel ignoring reason', () {
      expect(
        IrcParser.parseUserPart(':bob!u@h PART #flutter :bye all'),
        (nick: 'bob', channel: '#flutter'),
      );
    });

    test('parseQuitNick extracts the nick', () {
      expect(IrcParser.parseQuitNick(':bob!u@h QUIT :Ping timeout'), 'bob');
      expect(IrcParser.parseQuitNick(':bob!u@h PRIVMSG #c :QUIT now'), isNull);
    });

    test('parseAnyNickChange extracts old and new nick', () {
      expect(
        IrcParser.parseAnyNickChange(':bob!u@h NICK :bobby'),
        (oldNick: 'bob', newNick: 'bobby'),
      );
    });

    test('parseKickTarget extracts channel and victim', () {
      expect(
        IrcParser.parseKickTarget(':op!u@h KICK #chan bob :flooding'),
        (channel: '#chan', nick: 'bob'),
      );
    });
  });

  group('self events', () {
    test('parseJoinedChannel only matches my own JOIN', () {
      expect(
        IrcParser.parseJoinedChannel(line: ':me!u@h JOIN :#chan', myNick: 'me'),
        '#chan',
      );
      expect(
        IrcParser.parseJoinedChannel(
          line: ':other!u@h JOIN :#chan',
          myNick: 'me',
        ),
        isNull,
      );
    });

    test('parsePartedChannel only matches my own PART', () {
      expect(
        IrcParser.parsePartedChannel(
          line: ':me!u@h PART #chan :bye',
          myNick: 'me',
        ),
        '#chan',
      );
      expect(
        IrcParser.parsePartedChannel(
          line: ':other!u@h PART #chan :bye',
          myNick: 'me',
        ),
        isNull,
      );
    });

    test('parseOwnNickChange matches case-insensitively', () {
      expect(
        IrcParser.parseOwnNickChange(
          line: ':ME!u@h NICK :NewNick',
          currentNick: 'me',
        ),
        'NewNick',
      );
    });

    test('parseKickedChannelForMe only matches my own kick', () {
      expect(
        IrcParser.parseKickedChannelForMe(
          line: ':op!u@h KICK #chan me :bye',
          myNick: 'me',
        ),
        '#chan',
      );
      expect(
        IrcParser.parseKickedChannelForMe(
          line: ':op!u@h KICK #chan other :bye',
          myNick: 'me',
        ),
        isNull,
      );
    });
  });

  group('list replies', () {
    test('parseListReply extracts channel, users and topic', () {
      final info = IrcParser.parseListReply(
        ':server 322 me #flutter 120 :Flutter discussion',
      );

      expect(info!.name, '#flutter');
      expect(info.users, 120);
      expect(info.topic, 'Flutter discussion');
    });

    test('isListEnd matches 323 only', () {
      expect(IrcParser.isListEnd(':server 323 me :End of LIST'), isTrue);
      expect(IrcParser.isListEnd(':server 322 me #a 1 :x'), isFalse);
    });
  });

  group('parseInvite', () {
    test('parses a real invite addressed to me', () {
      final invite = IrcParser.parseInvite(
        line: ':alice!u@h INVITE me #secret',
        myNick: 'me',
      );

      expect(invite!.inviter, 'alice');
      expect(invite.channel, '#secret');
    });

    test('ignores invites addressed to others', () {
      expect(
        IrcParser.parseInvite(
          line: ':alice!u@h INVITE other #secret',
          myNick: 'me',
        ),
        isNull,
      );
    });
  });

  group('parseSystemEvent', () {
    test('builds join/part/quit/nick system messages', () {
      final join = IrcParser.parseSystemEvent(
        line: ':bob!u@h JOIN :#chan',
        myNick: 'me',
        currentTarget: '#chan',
      );
      expect(join!.text, 'bob joined #chan');

      final quit = IrcParser.parseSystemEvent(
        line: ':bob!u@h QUIT :gone',
        myNick: 'me',
        currentTarget: '#chan',
      );
      expect(quit!.text, 'bob quit');
    });

    test('ignores events for other channels', () {
      expect(
        IrcParser.parseSystemEvent(
          line: ':bob!u@h JOIN :#other',
          myNick: 'me',
          currentTarget: '#chan',
        ),
        isNull,
      );
    });
  });

  group('message tags (server-time)', () {
    test('timeFromTags parses a time tag', () {
      final time = IrcParser.timeFromTags(
        '@time=2024-06-01T12:00:00.000Z :nick!u@h PRIVMSG #c :hi',
      );

      expect(time, isNotNull);
      expect(time!.toUtc().toIso8601String(), '2024-06-01T12:00:00.000Z');
    });

    test('timeFromTags returns null without tags or with junk', () {
      expect(IrcParser.timeFromTags(':nick!u@h PRIVMSG #c :hi'), isNull);
      expect(IrcParser.timeFromTags('@other=1 :nick!u@h PRIVMSG #c :hi'), isNull);
      expect(IrcParser.timeFromTags('@time=not-a-date :nick!u@h PRIVMSG #c :hi'),
          isNull);
    });

    test('parsePrivMsg uses the server timestamp when present', () {
      final msg = IrcParser.parsePrivMsg(
        line:
            '@time=2024-06-01T12:00:00.000Z :alice!u@h PRIVMSG #chan :hello',
        myNick: 'me',
      );

      expect(msg!.time.toUtc().toIso8601String(), '2024-06-01T12:00:00.000Z');
    });

    test('parseSystemEvent uses the server timestamp when present', () {
      final msg = IrcParser.parseSystemEvent(
        line: '@time=2024-06-01T12:00:00.000Z :bob!u@h JOIN :#chan',
        myNick: 'me',
        currentTarget: '#chan',
      );

      expect(msg!.time.toUtc().toIso8601String(), '2024-06-01T12:00:00.000Z');
    });
  });

  group('CAP lines', () {
    test('parses ACK with trailing caps', () {
      final cap = IrcParser.parseCapLine(':server CAP me ACK :sasl server-time');

      expect(cap!.subcommand, 'ACK');
      expect(cap.caps, ['sasl', 'server-time']);
    });

    test('parses ACK with middle-param caps', () {
      final cap = IrcParser.parseCapLine(':server CAP me ACK sasl');

      expect(cap!.subcommand, 'ACK');
      expect(cap.caps, ['sasl']);
    });

    test('parses LS with multiline continuation markers', () {
      final cap = IrcParser.parseCapLine(
        ':server CAP * LS * :multi-prefix server-time',
      );

      expect(cap!.subcommand, 'LS');
      expect(cap.caps, ['multi-prefix', 'server-time']);
    });

    test('parses LS with cap values', () {
      final cap = IrcParser.parseCapLine(
        ':server CAP * LS :sts=6697,180000 message-tags',
      );

      expect(cap!.caps, ['sts=6697,180000', 'message-tags']);
    });

    test('parses NAK', () {
      expect(
        IrcParser.parseCapLine(':server CAP me NAK :sasl')!.subcommand,
        'NAK',
      );
    });

    test('ignores non-CAP lines', () {
      expect(IrcParser.parseCapLine(':server 001 me :Welcome'), isNull);
      expect(IrcParser.parseCapLine('PING :x'), isNull);
    });
  });

  group('STS cap value', () {
    test('parses port and duration over plaintext', () {
      final sts = IrcParser.parseStsCapValue(
        '6697,180000',
        isTlsConnection: false,
        currentPort: 6667,
      );

      expect(sts!.securePort, 6697);
      expect(sts.durationSeconds, 180000);
    });

    test('parses duration-only over TLS, using current port', () {
      final sts = IrcParser.parseStsCapValue(
        '180000',
        isTlsConnection: true,
        currentPort: 6697,
      );

      expect(sts!.securePort, 6697);
      expect(sts.durationSeconds, 180000);
    });

    test('duration 0 means policy withdrawn', () {
      final sts = IrcParser.parseStsCapValue(
        '6697,0',
        isTlsConnection: false,
        currentPort: 6667,
      );

      expect(sts!.durationSeconds, 0);
    });

    test('rejects garbage', () {
      expect(
        IrcParser.parseStsCapValue(
          'abc,def',
          isTlsConnection: false,
          currentPort: 6667,
        ),
        isNull,
      );
    });
  });

  group('typing events', () {
    test('parses an active TYPING event', () {
      final typing = IrcParser.parseTyping(
        '@typing=active :bob!u@h TYPING #chan',
      );

      expect(typing!.nick, 'bob');
      expect(typing.target, '#chan');
      expect(typing.mode, 'active');
    });

    test('defaults to done without a tag', () {
      final typing = IrcParser.parseTyping(':bob!u@h TYPING #chan');

      expect(typing!.mode, 'done');
    });

    test('ignores non-TYPING commands', () {
      expect(
        IrcParser.parseTyping(':bob!u@h PRIVMSG #chan :TYPING stuff'),
        isNull,
      );
    });
  });

  group('chathistory timestamps', () {
    test('formats as timestamp=... in UTC with milliseconds', () {
      final formatted = IrcParser.formatChathistoryTimestamp(
        DateTime.utc(2024, 6, 1, 12, 30, 5, 7),
      );

      expect(formatted, 'timestamp=2024-06-01T12:30:05.007Z');
    });

    test('pads single-digit fields', () {
      final formatted = IrcParser.formatChathistoryTimestamp(
        DateTime.utc(2024, 1, 2, 3, 4, 5, 60),
      );

      expect(formatted, 'timestamp=2024-01-02T03:04:05.060Z');
    });
  });

  group('tag values', () {
    test('extracts a tag value', () {
      expect(
        IrcParser.tagValueFromLine('@msgid=abc;batch=root1 :n!u@h PRIVMSG #c :x',
            'batch'),
        'root1',
      );
    });

    test('returns null when absent', () {
      expect(
        IrcParser.tagValueFromLine(':n!u@h PRIVMSG #c :@msgid=hi', 'msgid'),
        isNull,
      );
    });
  });
}

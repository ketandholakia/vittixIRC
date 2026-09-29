import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/channel.dart';
import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/models/server_notice.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/models/whois_info.dart';

class IrcSessionState {
  final ServerConfig server;
  final IrcConnectionStatus status;
  final List<Channel> channels;
  final String? activeTarget;
  final Map<String, List<ChatMessage>> messagesByTarget;
  final Map<String, String> topicsByTarget;
  final Map<String, List<String>> usersByChannel;
  final Map<String, bool> friendOnlineStatus;
  final List<ServerNotice> notices;
  final Map<String, WhoisInfo> whoisByNick;
  final DateTime? highlightedMessageTime;
  final Map<String, bool> hasMoreHistoryByTarget;
  final Map<String, bool> loadingHistoryByTarget;
  final Map<String, int> historyOffsetByTarget;
  final Map<String, Map<String, DateTime>> typingByTarget;

  const IrcSessionState({
    required this.server,
    required this.status,
    required this.channels,
    required this.activeTarget,
    required this.messagesByTarget,
    required this.topicsByTarget,
    required this.usersByChannel,
    required this.friendOnlineStatus,
    required this.notices,
    required this.whoisByNick,
    required this.highlightedMessageTime,
    required this.hasMoreHistoryByTarget,
    required this.loadingHistoryByTarget,
    required this.historyOffsetByTarget,
    this.typingByTarget = const {},
  });

  IrcSessionState copyWith({
    ServerConfig? server,
    IrcConnectionStatus? status,
    List<Channel>? channels,
    String? activeTarget,
    Map<String, List<ChatMessage>>? messagesByTarget,
    Map<String, String>? topicsByTarget,
    Map<String, List<String>>? usersByChannel,
    Map<String, bool>? friendOnlineStatus,
    List<ServerNotice>? notices,
    Map<String, WhoisInfo>? whoisByNick,
    DateTime? highlightedMessageTime,
    bool clearHighlight = false,
    Map<String, bool>? hasMoreHistoryByTarget,
    Map<String, bool>? loadingHistoryByTarget,
    Map<String, int>? historyOffsetByTarget,
    Map<String, Map<String, DateTime>>? typingByTarget,
  }) {
    return IrcSessionState(
      server: server ?? this.server,
      status: status ?? this.status,
      channels: channels ?? this.channels,
      activeTarget: activeTarget ?? this.activeTarget,
      messagesByTarget: messagesByTarget ?? this.messagesByTarget,
      topicsByTarget: topicsByTarget ?? this.topicsByTarget,
      usersByChannel: usersByChannel ?? this.usersByChannel,
      friendOnlineStatus: friendOnlineStatus ?? this.friendOnlineStatus,
      notices: notices ?? this.notices,
      whoisByNick: whoisByNick ?? this.whoisByNick,
      highlightedMessageTime: clearHighlight
          ? null
          : highlightedMessageTime ?? this.highlightedMessageTime,
      hasMoreHistoryByTarget:
          hasMoreHistoryByTarget ?? this.hasMoreHistoryByTarget,
      loadingHistoryByTarget:
          loadingHistoryByTarget ?? this.loadingHistoryByTarget,
      historyOffsetByTarget:
          historyOffsetByTarget ?? this.historyOffsetByTarget,
      typingByTarget: typingByTarget ?? this.typingByTarget,
    );
  }
}

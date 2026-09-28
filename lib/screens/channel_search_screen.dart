import 'dart:async';
import 'package:flutter/material.dart';

import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/widgets/channel_browser.dart';

class ChannelSearchScreen extends StatefulWidget {
  final ServerConfig server;
  final IrcSocketService irc;

  const ChannelSearchScreen({
    super.key,
    required this.server,
    required this.irc,
  });

  @override
  State<ChannelSearchScreen> createState() => _ChannelSearchScreenState();
}

class _ChannelSearchScreenState extends State<ChannelSearchScreen> {
  final List<IrcChannelInfo> _channels = [];
  StreamSubscription<String>? _lineSub;
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _lineSub = widget.irc.lines.listen(_onLine);
    _requestList();
  }

  void _requestList() {
    setState(() {
      _loading = true;
      _channels.clear();
    });

    widget.irc.sendRaw('LIST');
  }

  void _onLine(String line) {
    final item = IrcParser.parseListReply(line);

    if (item != null) {
      setState(() {
        _channels.add(item);
      });
      return;
    }

    if (IrcParser.isListEnd(line)) {
      setState(() {
        _loading = false;
        _channels.sort((a, b) => b.users.compareTo(a.users));
      });
    }
  }

  void _joinChannel(IrcChannelInfo channel) {
    widget.irc.sendRaw('JOIN ${channel.name}');
    Navigator.pop(context, channel.name);
  }

  @override
  void dispose() {
    _lineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChannelBrowser(
      title: 'Find Channels',
      channels: _channels,
      loading: _loading,
      onRefresh: () async => _requestList(),
      onJoin: _joinChannel,
      emptyMessage: 'No channels found',
      searchingEmptyMessage: 'No channels match the current search and filters',
      loadingMessage: 'Loading channel list...',
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/channel.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/screens/channel_search_screen.dart';
import 'package:vittix_irc/services/channel_storage_service.dart';

class ChannelListScreen extends StatefulWidget {
  final ServerConfig server;
  final IrcSocketService irc;

  const ChannelListScreen({
    super.key,
    required this.server,
    required this.irc,
  });

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final _storage = ChannelStorageService();
  late final List<Channel> _channels;
  StreamSubscription<String>? _lineSub;
  String? _activeChannel;

  @override
  void initState() {
    super.initState();
    _channels = [
      Channel(name: widget.server.defaultChannel),
    ];
    _lineSub = widget.irc.lines.listen(_onLine);
  }

  void _onLine(String line) {
    final joinedChannel = IrcParser.parseJoinedChannel(
      line: line,
      myNick: widget.server.nickname,
    );

    if (joinedChannel != null) {
      setState(() {
        if (!_channels.any(
          (c) => c.name.toLowerCase() == joinedChannel.toLowerCase(),
        )) {
          _channels.add(Channel(name: joinedChannel));
        }
      });
      _saveChannels();
    }

    final partedChannel = IrcParser.parsePartedChannel(
      line: line,
      myNick: widget.server.nickname,
    );

    if (partedChannel != null) {
      setState(() {
        _channels.removeWhere(
          (c) => c.name.toLowerCase() == partedChannel.toLowerCase(),
        );
      });

      _saveChannels();
      return;
    }

    final msg = IrcParser.parsePrivMsg(
      line: line,
      myNick: widget.server.nickname,
    );

    if (msg == null) return;

    final myNick = widget.server.nickname.toLowerCase();
    final channelName = msg.target.toLowerCase() == myNick
        ? msg.sender
        : msg.target;
    final target = channelName.toLowerCase();

    setState(() {
      final index = _channels.indexWhere(
        (c) => c.name.toLowerCase() == target,
      );

      if (index == -1) {
        _channels.add(
          Channel(
            name: channelName,
            unreadCount: 1,
            isPrivate: msg.target.toLowerCase() == myNick,
          ),
        );
        return;
      }

      final channel = _channels[index];

      if (_activeChannel?.toLowerCase() == channel.name.toLowerCase()) {
        return;
      }

      _channels[index] = channel.copyWith(
        unreadCount: channel.unreadCount + 1,
      );
    });
  }

  Future<void> _openChannel(Channel channel) async {
    setState(() {
      _activeChannel = channel.name;

      final index = _channels.indexWhere((c) => c.name == channel.name);
      if (index != -1) {
        _channels[index] = _channels[index].copyWith(unreadCount: 0);
      }
    });
  }

  Future<void> _joinChannelDialog() async {
    final controller = TextEditingController();
    final channel = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Join Channel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '#channel',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              var text = controller.text.trim();
              if (text.isEmpty) return;
              if (!text.startsWith('#')) text = '#$text';
              Navigator.pop(context, text);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
    
    controller.dispose();
    
    if (channel == null) return;
    
    widget.irc.sendRaw('JOIN $channel');
    
    setState(() {
      if (!_channels.any((c) => c.name == channel)) {
        _channels.add(Channel(name: channel));
      }
    });
    _saveChannels();
  }

  Future<void> _saveChannels() async {
    await _storage.saveChannels(
      serverId: widget.server.id,
      channels: _channels,
    );
  }

  @override
  void dispose() {
    _lineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.server.name),
            Text(
              widget.server.host,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Find channels',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final joinedChannel = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => ChannelSearchScreen(
                    server: widget.server,
                    irc: widget.irc,
                  ),
                ),
              );

              if (joinedChannel != null) {
                setState(() {
                  if (!_channels.any(
                    (c) => c.name.toLowerCase() == joinedChannel.toLowerCase(),
                  )) {
                    _channels.add(Channel(name: joinedChannel));
                  }
                });
                _saveChannels();
              }
            },
          ),
          IconButton(
            tooltip: 'Join channel',
            icon: const Icon(Icons.add),
            onPressed: _joinChannelDialog,
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.irc.disconnect();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          final channel = _channels[index];
          return Card(
            child: ListTile(
              leading: Icon(
                channel.isPrivate ? Icons.person : Icons.tag,
              ),
              title: Text(channel.name),
              subtitle: channel.unreadCount > 0
                  ? Text('${channel.unreadCount} unread')
                  : const Text('Tap to open chat'),
              trailing: channel.unreadCount > 0
                  ? CircleAvatar(
                      radius: 13,
                      child: Text(
                        channel.unreadCount.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        widget.irc.sendRaw('PART ${channel.name}');
                      },
                    ),
              onTap: () => _openChannel(channel),
            ),
          );
        },
      ),
    );
  }
}

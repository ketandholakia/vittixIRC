import 'package:flutter/material.dart';
import 'package:vittix_irc/models/irc_channel_info.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';
import 'package:vittix_irc/widgets/channel_browser.dart';

class ChannelListScreen extends StatefulWidget {
  final IrcSessionController? controller;

  const ChannelListScreen({
    super.key,
    this.controller,
  });

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  String? _pendingJoinTarget;

  IrcSessionController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller?.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      if (controller != null &&
          controller.networkChannels.isEmpty &&
          !controller.isFetchingChannels) {
        controller.requestChannelList();
      }
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = _controller;
    final pending = _pendingJoinTarget;
    if (!mounted || controller == null || pending == null) return;

    if (controller.state.activeTarget?.toLowerCase() == pending.toLowerCase()) {
      _pendingJoinTarget = null;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final channels = controller?.networkChannels ?? const <IrcChannelInfo>[];
    final isFetching = controller?.isFetchingChannels ?? false;
    if (controller == null) {
      return const Scaffold(
        body: Center(
          child: Text('Channel list controller is not attached.'),
        ),
      );
    }

    return ChannelBrowser(
      title: 'Network Channels',
      channels: channels,
      loading: isFetching,
      onRefresh: () async {
        controller.requestChannelList();
        while (controller.isFetchingChannels) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;
        }
      },
      onJoin: (channel) {
        _pendingJoinTarget = channel.name;
        controller.joinChannel(channel.name);
      },
      emptyMessage: 'No channels reported by the server yet.',
      searchingEmptyMessage: 'No matching channels for the current search and filters.',
      loadingMessage: 'Loading network channel list...',
    );
  }
}

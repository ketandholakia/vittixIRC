import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/models/notification_route_payload.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/screens/chat/chat_shell_screen.dart';
import 'package:vittix_irc/screens/server/add_server_screen.dart';
import 'package:vittix_irc/screens/settings_screen.dart';
import 'package:vittix_irc/services/notification_service.dart';
import 'package:vittix_irc/services/server_storage_service.dart';
import 'package:vittix_irc/services/shared_file_queue_service.dart';
import 'package:vittix_irc/state/session_manager.dart';
import 'package:vittix_irc/state/active_session_registry.dart';
import 'package:vittix_irc/widgets/empty_state.dart';
import 'package:vittix_irc/widgets/server_tile.dart';

class ServerListScreen extends StatefulWidget {
  final ValueChanged<AppSettings>? onSettingsChanged;

  const ServerListScreen({
    super.key,
    this.onSettingsChanged,
  });

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  final _storage = ServerStorageService();
  final _settingsService = AppSettingsService();
  final _settingsShowcaseKey = GlobalKey();
  final _addServerShowcaseKey = GlobalKey();
  bool _tutorialScheduled = false;

  List<ServerConfig> _servers = [];
  bool _loading = true;
  AppSettings _settings = const AppSettings();

  NotificationRoutePayload? _pendingNotificationRoute;
  StreamSubscription<String>? _notificationTapSub;
  StreamSubscription<void>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _checkNotificationLaunch();
    _loadSettings();
    _loadServers();

    _notificationTapSub = NotificationService.instance.notificationTaps.listen(
      _handleNotificationPayload,
    );

    _sessionSub = SessionManager.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _checkNotificationLaunch() {
    final payload = NotificationService.instance.consumeLaunchPayload();

    final route = NotificationRoutePayload.parse(payload);

    if (route == null) return;

    _pendingNotificationRoute = route;
  }

  Future<void> _handleNotificationPayload(String payload) async {
    final route = NotificationRoutePayload.parse(payload);

    if (route == null) return;

    final existingController =
        SessionManager.instance.controllerFor(route.serverId);

    if (existingController != null) {
      await existingController.openTarget(
        route.target,
        isPrivate: !route.target.startsWith('#'),
      );
      return;
    }

    final server = _findServerById(route.serverId);

    if (server == null) {
      _pendingNotificationRoute = route;
      await _loadServers();
      return;
    }

    await _connect(
      server,
      initialTarget: route.target,
    );
  }

  ServerConfig? _findServerById(String id) {
    for (final server in _servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  Future<void> _loadServers() async {
    final servers = await _storage.getServers();

    setState(() {
      _servers = servers;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartTutorial();
    });

    final route = _pendingNotificationRoute;
    if (route != null) {
      _pendingNotificationRoute = null;

      final server = _findServerById(route.serverId);

      if (server != null) {
        await _connect(
          server,
          initialTarget: route.target,
        );
      }
    }
  }

  Future<void> _addServer() async {
    final server = await Navigator.push<ServerConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddServerScreen(),
      ),
    );

    if (server != null) {
      await _storage.addServer(server);
      _loadServers();
    }
  }

  Future<void> _deleteServer(ServerConfig server) async {
    await _storage.deleteServer(server.id);
    _loadServers();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.getSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _maybeStartTutorial() async {
    if (_tutorialScheduled) return;
    _tutorialScheduled = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('showcase_tutorial_seen') == true) return;
    if (!mounted) return;

    final keys = <GlobalKey<State<StatefulWidget>>>[
      _settingsShowcaseKey,
      _addServerShowcaseKey,
    ];

    ShowCaseWidget.of(context).startShowCase(keys);
  }

  List<ServerConfig> _sortedServers() {
    final servers = [..._servers];

    if (!_settings.hotBuffersMoveToTop) {
      return servers;
    }

    servers.sort((a, b) {
      final aUnread = SessionManager.instance.unreadFor(a.id);
      final bUnread = SessionManager.instance.unreadFor(b.id);
      if (aUnread != bUnread) return bUnread.compareTo(aUnread);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return servers;
  }

  Future<void> _openActiveChatForSharedFiles() async {
    final controller = ActiveSessionRegistry.activeController;
    if (controller == null) return;

    final target = controller.state.activeTarget;
    if (target == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatShellScreen(
          controller: controller,
          initialTarget: target,
        ),
      ),
    );
  }

  Future<String?> _pickSharedFileTarget() async {
    final controller = ActiveSessionRegistry.activeController;
    if (controller == null) return null;

    final channels = controller.state.channels;
    if (channels.isEmpty) return controller.state.activeTarget;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: channels.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final channel = channels[index];
              return ListTile(
                leading: Icon(channel.isPrivate ? Icons.person : Icons.tag),
                title: Text(channel.name),
                subtitle: Text(channel.isPrivate ? 'Private chat' : 'Channel'),
                onTap: () => Navigator.pop(context, channel.name),
              );
            },
          ),
        );
      },
    );
  }

  Future<String?> _pickSharedTextTarget(String preview) async {
    final controller = ActiveSessionRegistry.activeController;
    if (controller == null) return null;

    final channels = controller.state.channels;
    if (channels.isEmpty) return controller.state.activeTarget;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: channels.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final channel = channels[index];
                      return ListTile(
                        leading:
                            Icon(channel.isPrivate ? Icons.person : Icons.tag),
                        title: Text(channel.name),
                        subtitle: Text(
                          channel.isPrivate ? 'Private chat' : 'Channel',
                        ),
                        onTap: () => Navigator.pop(context, channel.name),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSharedFilesChooser() async {
    final controller = ActiveSessionRegistry.activeController;
    if (controller == null) return;

    final target = await _pickSharedFileTarget();
    if (target == null || target.isEmpty) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatShellScreen(
          controller: controller,
          initialTarget: target,
        ),
      ),
    );
  }

  Future<void> _openSharedTextChooser() async {
    final controller = ActiveSessionRegistry.activeController;
    if (controller == null) return;

    final texts = SharedFileQueueService.instance.peekPendingText();
    if (texts.isEmpty) return;

    final preview = texts.first;
    final target = await _pickSharedTextTarget(
      preview.length > 120 ? '${preview.substring(0, 120)}...' : preview,
    );
    if (target == null || target.isEmpty) return;
    if (!mounted) return;

    final text = texts.join('\n');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatShellScreen(
          controller: controller,
          initialTarget: target,
          initialSharedText: text,
        ),
      ),
    );
  }

  Future<void> _connect(
    ServerConfig server, {
    String? initialTarget,
  }) async {
    try {
      final controller = await SessionManager.instance.connect(server);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatShellScreen(
            controller: controller,
            initialTarget: initialTarget,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IRC Servers'),
        actions: [
          Showcase(
            key: _settingsShowcaseKey,
            title: 'Settings',
            description: 'Open app settings, backups, and message preferences.',
            child: IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      onSettingsChanged: widget.onSettingsChanged,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _servers.isEmpty
          ? null
          : Showcase(
              key: _addServerShowcaseKey,
              title: 'Add more servers',
              description: 'Use this button to add another IRC server.',
              child: FloatingActionButton.extended(
                onPressed: _addServer,
                icon: const Icon(Icons.add),
                label: const Text('Add Server'),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (SharedFileQueueService.instance.hasPendingFiles ||
                    SharedFileQueueService.instance.hasPendingText)
                  MaterialBanner(
                    content: Text(
                      '${[
                        if (SharedFileQueueService.instance.hasPendingFiles)
                          '${SharedFileQueueService.instance.pendingCount} shared file(s)',
                        if (SharedFileQueueService.instance.hasPendingText)
                          '${SharedFileQueueService.instance.pendingTextCount} shared text item(s)',
                      ].join(' and ')} waiting.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _openActiveChatForSharedFiles,
                        child: const Text('Current chat'),
                      ),
                      TextButton(
                        onPressed: _openSharedFilesChooser,
                        child: const Text('Choose target'),
                      ),
                      if (SharedFileQueueService.instance.hasPendingText)
                        TextButton(
                          onPressed: _openSharedTextChooser,
                          child: const Text('Send text'),
                        ),
                      TextButton(
                        onPressed: () => setState(() {}),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                Expanded(
                  child: _servers.isEmpty
                      ? EmptyState(
                          icon: Icons.dns,
                          title: 'No IRC servers yet',
                          message:
                              'Add your first IRC server to start chatting.',
                          buttonText: 'Add Server',
                          buttonKey: _addServerShowcaseKey,
                          onPressed: _addServer,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _sortedServers().length,
                          itemBuilder: (context, index) {
                            final server = _sortedServers()[index];

                            final status =
                                SessionManager.instance.statusFor(server.id);
                            final unread =
                                SessionManager.instance.unreadFor(server.id);

                            return ServerTile(
                              server: server,
                              status: status,
                              unreadCount: unread,
                              onTap: () => _connect(server),
                              onConnect: () => _connect(server),
                              onEdit: () async {
                                final updated =
                                    await Navigator.push<ServerConfig>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AddServerScreen(existingServer: server),
                                  ),
                                );

                                if (updated == null) return;

                                await _storage.updateServer(updated);
                                await _loadServers();
                              },
                              onDelete: () => _deleteServer(server),
                              onDisconnect: () =>
                                  SessionManager.instance.disconnect(server.id),
                            ).animate(
                              delay: Duration(
                                milliseconds: (index * 18).clamp(0, 220),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

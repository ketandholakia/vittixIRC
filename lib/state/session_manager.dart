import 'dart:async';

import 'package:vittix_irc/core/irc_socket_service.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/services/app_lifecycle_service.dart';
import 'package:vittix_irc/services/keep_alive_service.dart';
import 'package:vittix_irc/state/irc_session_controller.dart';

class SessionManager {
  static final SessionManager instance = SessionManager._();

  SessionManager._();

  final Map<String, IrcSocketService> _sockets = {};
  final Map<String, IrcSessionController> _controllers = {};

  final _changeController = StreamController<void>.broadcast();

  AppLifecycleService? _lifecycleService;

  Stream<void> get changes => _changeController.stream;

  void _notifyChanged() {
    _changeController.add(null);
  }

  IrcSessionController? controllerFor(String serverId) {
    return _controllers[serverId];
  }

  bool isConnected(String serverId) {
    final controller = _controllers[serverId];
    if (controller == null) return false;

    return controller.irc.isConnected;
  }

  IrcConnectionStatus? statusFor(String serverId) {
    return _controllers[serverId]?.state.status;
  }

  int unreadFor(String serverId) {
    return _controllers[serverId]?.totalUnreadCount ?? 0;
  }

  Future<IrcSessionController> connect(ServerConfig server) async {
    final existing = _controllers[server.id];

    if (existing != null && existing.irc.isConnected) {
      return existing;
    }

    final socket = _sockets[server.id] ?? IrcSocketService();
    _sockets[server.id] = socket;

    await socket.connect(server);

    final controller = _controllers[server.id] ??
        IrcSessionController(
          server: server,
          irc: socket,
        );

    _controllers[server.id] = controller;

    controller.addListener(_notifyChanged);
    _notifyChanged();

    unawaited(KeepAliveService.start());

    return controller;
  }

  Future<void> disconnect(String serverId) async {
    final controller = _controllers[serverId];
    final socket = _sockets[serverId];

    await controller?.disconnect();
    await socket?.disconnect();

    controller?.removeListener(_notifyChanged);
    controller?.dispose();

    _controllers.remove(serverId);
    _sockets.remove(serverId);

    if (_controllers.isEmpty) {
      unawaited(KeepAliveService.stop());
    }

    _notifyChanged();
  }

  Future<void> disconnectAll() async {
    final ids = _controllers.keys.toList();

    for (final id in ids) {
      await disconnect(id);
    }
  }

  void startLifecycleHandling() {
    _lifecycleService ??= AppLifecycleService(
      onForeground: () {
        for (final socket in _sockets.values) {
          socket.setAppInBackground(false);
        }
        reconnectDisconnectedSessions();
      },
      onBackground: () {
        for (final socket in _sockets.values) {
          socket.setAppInBackground(true);
        }
      },
    );

    _lifecycleService!.start();
  }

  Future<void> reconnectDisconnectedSessions() async {
    final controllers = _controllers.values.toList();

    for (final controller in controllers) {
      if (!controller.irc.isConnected) {
        try {
          await controller.irc.connect(controller.server);
        } catch (_) {
          // Auto reconnect in IrcSocketService will continue trying
        }
      }
    }
  }

  Future<void> reloadSettingsForAll() async {
    final controllers = _controllers.values.toList();

    for (final controller in controllers) {
      await controller.reloadSettings();
    }

    _notifyChanged();
  }

  Future<void> dispose() async {
    _lifecycleService?.stop();
    _lifecycleService = null;

    await disconnectAll();

    await _changeController.close();
  }
}

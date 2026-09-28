import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/models/server_config.dart';

enum IrcConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class IrcSocketService {
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  ServerConfig? _currentConfig;
  String? _currentNick;
  int _nickRetryCount = 0;
  static const int _maxNickRetries = 5;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  ServerConfig? _lastConfig;

  List<String> _autoJoinChannels = [];
  bool _manualDisconnect = false;
  bool _autoReconnect = true;
  bool _isAppInBackground = false;

  int _reconnectAttempts = 0;
  int? _lastReconnectDelaySeconds;
  DateTime? _lastLineReceivedAt;

  static const Duration _heartbeatInterval = Duration(seconds: 45);
  static const Duration _staleConnectionTimeout = Duration(minutes: 3);

  final _lineController = StreamController<String>.broadcast();
  final _statusController = StreamController<IrcConnectionStatus>.broadcast();

  Stream<String> get lines => _lineController.stream;
  Stream<IrcConnectionStatus> get status => _statusController.stream;

  bool get isConnected => _socket != null;
  String? get currentNick => _currentNick;
  int get reconnectAttempts => _reconnectAttempts;
  int? get lastReconnectDelaySeconds => _lastReconnectDelaySeconds;

  Future<void> connect(ServerConfig config) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Direct IRC TCP connections are not supported on Flutter web. '
        'Run this app on Android, iOS, desktop, or use a server-side IRC proxy.',
      );
    }

    _lastConfig = config;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    await disconnect(sendQuit: false, manual: false);

    _currentConfig = config;
    _currentNick = config.nickname;
    _nickRetryCount = 0;
    _statusController.add(IrcConnectionStatus.connecting);

    try {
      if (config.useTls) {
        _socket = await SecureSocket.connect(
          config.host,
          config.port,
          timeout: const Duration(seconds: 15),
        );
      } else {
        _socket = await Socket.connect(
          config.host,
          config.port,
          timeout: const Duration(seconds: 15),
        );
      }

      _lastLineReceivedAt = DateTime.now();
      _reconnectAttempts = 0;
      _statusController.add(IrcConnectionStatus.connected);

      _login(config);
      _startHeartbeat();

      _subscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _handleIncomingLine(line);
        },
        onError: (error) {
          _cleanupClosedSocket();
          _statusController.add(IrcConnectionStatus.error);
          _scheduleReconnect();
        },
        onDone: () {
          _cleanupClosedSocket();
          _statusController.add(IrcConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _statusController.add(IrcConnectionStatus.error);
      rethrow;
    }
  }

  void _handleIncomingLine(String line) {
    _lastLineReceivedAt = DateTime.now();
    debugPrint('IRC < $line');

    final pingToken = IrcParser.parsePingToken(line);
    if (pingToken != null) {
      sendRaw('PONG $pingToken');
      return;
    }

    final config = _currentConfig;

    if (config != null && config.useSasl) {
      if (line.contains(' CAP ') &&
          line.contains(' ACK ') &&
          line.contains('sasl')) {
        sendRaw('AUTHENTICATE PLAIN');
        return;
      }

      if (line.startsWith('AUTHENTICATE +')) {
        final authString = base64Encode(
          utf8.encode(
            '${config.loginUsername}\u0000${config.loginUsername}\u0000${config.password}',
          ),
        );

        sendRaw('AUTHENTICATE $authString');
        return;
      }

      if (line.contains(' 903 ')) {
        sendRaw('CAP END');
        return;
      }

      if (line.contains(' 904 ') ||
          line.contains(' 905 ') ||
          line.contains(' 906 ') ||
          line.contains(' 907 ')) {
        sendRaw('CAP END');
        _lineController.add('SASL authentication failed');
        return;
      }
    }

    if (IrcParser.isNicknameInUse(line)) {
      _handleNicknameInUse();
      return;
    }

    final nickChange = IrcParser.parseOwnNickChange(
      line: line,
      currentNick: _currentNick ?? _currentConfig?.nickname ?? '',
    );

    if (nickChange != null) {
      _currentNick = nickChange;
    }

    if (IrcParser.isWelcome(line)) {
      _onLoginSuccess();
    }

    _lineController.add(line);
  }

  void _login(ServerConfig config) {
    if (config.useSasl &&
        config.password != null &&
        config.password!.isNotEmpty) {
      sendRaw('CAP REQ :sasl');
    }

    sendRaw('NICK ${_currentNick ?? config.nickname}');
    sendRaw('USER ${config.loginUsername} 0 * :${config.realName}');
  }

  void _handleNicknameInUse() {
    final config = _currentConfig;
    if (config == null) return;

    if (_nickRetryCount >= _maxNickRetries) {
      _lineController.add(
        'Nickname conflict: maximum alternate nickname attempts reached',
      );
      return;
    }

    _nickRetryCount++;

    final baseNick = config.nickname;
    final newNick = _nickRetryCount < _maxNickRetries
        ? '$baseNick${'_' * _nickRetryCount}'
        : '${baseNick}123';

    _currentNick = newNick;

    sendRaw('NICK $newNick');

    _lineController.add(
      'Nickname already in use. Trying $newNick...',
    );
  }

  void setAutoJoinChannels(List<String> channels) {
    _autoJoinChannels = channels;
  }

  void _onLoginSuccess() {
    final config = _currentConfig;
    if (config == null) return;

    final channels =
        _autoJoinChannels.isEmpty ? [config.defaultChannel] : _autoJoinChannels;

    for (final channel in channels) {
      if (channel.isNotEmpty) {
        sendRaw('JOIN $channel');
      }
    }
  }

  void identifyNickServ() {
    final config = _currentConfig;
    if (config == null) return;

    final password = config.password;
    if (password == null || password.isEmpty) return;

    sendRaw('PRIVMSG NickServ :IDENTIFY $password');
  }

  void sendRaw(String line) {
    final socket = _socket;
    if (socket == null) return;

    debugPrint('IRC > $line');
    socket.write('$line\r\n');
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final socket = _socket;
      if (socket == null) return;

      if (!_isAppInBackground) {
        final lastSeen = _lastLineReceivedAt;
        if (lastSeen != null &&
            DateTime.now().difference(lastSeen) > _staleConnectionTimeout) {
          _lineController.add('Connection timed out. Reconnecting...');
          _handleUnexpectedDisconnect();
          return;
        }
      }

      sendRaw('PING :vittix-${DateTime.now().millisecondsSinceEpoch}');
    });
  }

  void setAppInBackground(bool value) {
    _isAppInBackground = value;

    if (!value && _socket != null) {
      _lastLineReceivedAt = DateTime.now();
    }
  }

  void _handleUnexpectedDisconnect() {
    _cleanupClosedSocket();
    _statusController.add(IrcConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _cleanupClosedSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _subscription?.cancel();
    _subscription = null;

    try {
      _socket?.destroy();
    } catch (_) {}

    _socket = null;
  }

  Future<void> disconnect({
    bool sendQuit = true,
    bool manual = true,
  }) async {
    if (manual) {
      _manualDisconnect = true;
      _reconnectTimer?.cancel();
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    try {
      if (sendQuit) {
        sendRaw('QUIT :Leaving');
      }

      await _socket?.flush();
      await _socket?.close();
    } catch (_) {}

    _socket = null;
    _lastLineReceivedAt = null;
    _lastReconnectDelaySeconds = null;
    _statusController.add(IrcConnectionStatus.disconnected);
  }

  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    if (_manualDisconnect) return;

    final config = _lastConfig;
    if (config == null) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    final delaySeconds = switch (_reconnectAttempts) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      5 => 30,
      _ => 60,
    };
    _lastReconnectDelaySeconds = delaySeconds;

    _lineController.add(
      'Reconnecting to ${config.host} in ${delaySeconds}s (attempt $_reconnectAttempts)...',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      try {
        await connect(config);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<void> dispose() async {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();

    await disconnect();
    await _lineController.close();
    await _statusController.close();
  }
}

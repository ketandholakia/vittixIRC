import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:vittix_irc/core/irc_parser.dart';
import 'package:vittix_irc/core/scram_sha256.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/services/sts_policy_store.dart';
import 'package:vittix_irc/services/tls_pin_store.dart';

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
  bool _registrationComplete = false;

  // CAP negotiation state.
  bool _capEndSent = false;
  bool _awaitingSaslResult = false;
  final List<String> _pendingCapReqs = [];
  final Set<String> _acknowledgedCaps = {};
  final Set<String> _advertisedSaslMechs = {};
  ScramSha256Client? _scram;

  // Reconnect intelligence.
  bool _authFailed = false;
  final List<DateTime> _recentDrops = [];

  // TLS pinning / STS state for the active connection attempt.
  String? _expectedTlsPin;
  bool _certRejected = false;
  String _activeHost = '';
  int _activePort = 0;
  bool _activeTls = false;

  static const Duration _heartbeatInterval = Duration(seconds: 45);
  static const Duration _staleConnectionTimeout = Duration(minutes: 3);
  static const int _flapDropThreshold = 3;
  static const Duration _flapDetectionWindow = Duration(minutes: 15);
  static const int _flapCooldownSeconds = 300;

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
    _certRejected = false;
    _capEndSent = false;
    _awaitingSaslResult = false;
    _registrationComplete = false;
    _authFailed = false;
    _scram = null;
    _acknowledgedCaps.clear();
    _advertisedSaslMechs.clear();
    _pendingCapReqs.clear();
    _reconnectTimer?.cancel();

    await disconnect(sendQuit: false, manual: false);

    _currentConfig = config;
    _currentNick = config.nickname;
    _nickRetryCount = 0;
    _statusController.add(IrcConnectionStatus.connecting);

    // Enforce a learned STS policy: a host that advertised STS must not be
    // contacted over plaintext, so upgrade to its advertised secure port.
    var host = config.host;
    var port = config.port;
    var useTls = config.useTls;

    final stsPolicy = await StsPolicyStore().policyFor(host);
    if (stsPolicy != null &&
        !stsPolicy.isExpired &&
        !useTls &&
        stsPolicy.securePort > 0) {
      _lineController.add(
        'STS: ${config.host} requires TLS; connecting to port ${stsPolicy.securePort}',
      );
      port = stsPolicy.securePort;
      useTls = true;
    }

    _activeHost = host;
    _activePort = port;
    _activeTls = useTls;

    // TOFU pin preloaded so the certificate callback can stay synchronous.
    _expectedTlsPin = useTls ? await TlsPinStore().pinFor(config.id) : null;

    try {
      if (useTls) {
        _socket = await SecureSocket.connect(
          host,
          port,
          timeout: const Duration(seconds: 15),
          onBadCertificate: (certificate) =>
              _shouldAcceptCertificate(config, certificate),
        );
      } else {
        _socket = await Socket.connect(
          host,
          port,
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

  /// TOFU (trust-on-first-use) check for certificates that fail normal CA
  /// validation (self-signed certs, typical for bouncers). CA-valid chains
  /// never reach this callback, so routine CA renewal cannot trip the pin.
  bool _shouldAcceptCertificate(ServerConfig config, X509Certificate certificate) {
    final fingerprint = sha256.convert(certificate.der).toString();

    if (_expectedTlsPin == null) {
      _expectedTlsPin = fingerprint;
      unawaited(TlsPinStore().setPin(config.id, fingerprint));
      _lineController.add(
        'TLS: pinned self-signed certificate for ${config.host} '
        '(sha256/${fingerprint.substring(0, 12)})',
      );
      return true;
    }

    if (_expectedTlsPin == fingerprint) return true;

    _certRejected = true;
    _lineController.add(
      'TLS certificate for ${config.host} changed since first connection '
      '(was sha256/${_expectedTlsPin!.substring(0, 12)}, '
      'now sha256/${fingerprint.substring(0, 12)}). Connection refused. '
      'Delete and re-add the server to accept the new certificate.',
    );
    return false;
  }

  void _handleIncomingLine(String line) {
    _lastLineReceivedAt = DateTime.now();
    _logLine('<', line);

    final pingToken = IrcParser.parsePingToken(line);
    if (pingToken != null) {
      sendRaw('PONG $pingToken');
      return;
    }

    if (!_registrationComplete) {
      final cap = IrcParser.parseCapLine(line);
      if (cap != null) {
        _handleCapLine(cap);
        return;
      }
    }

    final config = _currentConfig;

    // A rejected server password is not transient: retrying with the same
    // credentials would hammer the server (and risk a k-line), so stop.
    if (!_registrationComplete && IrcParser.numericFromLine(line) == '464') {
      _authFailed = true;
      _lineController.add(
        'Server password incorrect; auto-reconnect stopped.',
      );
    }

    // SASL payload exchange once sasl has been ACKed during registration.
    if (config != null &&
        config.useSasl &&
        !_registrationComplete &&
        _awaitingSaslResult) {
      final numeric = IrcParser.numericFromLine(line);

      if (numeric == '903') {
        _awaitingSaslResult = false;
        _scram = null;
        _sendCapEnd();
        return;
      }

      if (numeric == '904' ||
          numeric == '905' ||
          numeric == '906' ||
          numeric == '907') {
        _authFailed = true;
        _scram = null;
        _awaitingSaslResult = false;
        _sendCapEnd();
        _lineController.add(
          'SASL authentication failed; auto-reconnect stopped. '
          'Check your credentials and reconnect.',
        );
        return;
      }

      if (line.startsWith('AUTHENTICATE ')) {
        _handleSaslPayload(config, line);
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
      _registrationComplete = true;
      _recentDrops.clear();
      // Safety net: never leave a server waiting in CAP negotiation, even if
      // it never sent an explicit ACK/NAK (or predates CAP entirely).
      _sendCapEnd();
      _onLoginSuccess();
    }

    _lineController.add(line);
  }

  /// Handles an AUTHENTICATE payload from the server, for either the PLAIN
  /// credential push or the SCRAM challenge/response steps.
  void _handleSaslPayload(ServerConfig config, String line) {
    final payload = line.substring('AUTHENTICATE '.length);
    final scram = _scram;

    if (scram != null) {
      if (payload.isEmpty || payload == '+') {
        _abortSasl('SCRAM: unexpected empty payload from server');
        return;
      }

      final String decoded;
      try {
        decoded = utf8.decode(base64Decode(payload));
      } on FormatException {
        _abortSasl('SCRAM: malformed payload from server');
        return;
      }

      if (decoded.startsWith('v=')) {
        if (!scram.verifyServerFinal(decoded)) {
          _authFailed = true;
          _scram = null;
          _awaitingSaslResult = false;
          _sendCapEnd();
          _lineController.add(
            'SCRAM: server signature mismatch; connection not trusted. '
            'Auto-reconnect stopped.',
          );
          return;
        }
        // Server proven; registration finishes with the 903 numeric.
        return;
      }

      final clientFinal = scram.handleServerFirst(
        decoded,
        config.password ?? '',
      );

      if (clientFinal == null) {
        _abortSasl('SCRAM: server sent an invalid challenge');
        return;
      }

      sendRaw('AUTHENTICATE ${base64Encode(utf8.encode(clientFinal))}');
      return;
    }

    // PLAIN: the server asks for credentials with an empty payload ("+").
    if (payload == '+') {
      final authString = base64Encode(
        utf8.encode(
          '${config.loginUsername}\u0000${config.loginUsername}\u0000${config.password}',
        ),
      );

      sendRaw('AUTHENTICATE $authString');
    }
  }

  void _abortSasl(String reason) {
    sendRaw('AUTHENTICATE *');
    _scram = null;
    _awaitingSaslResult = false;
    _sendCapEnd();
    _lineController.add(reason);
  }

  void _handleCapLine(({String subcommand, List<String> caps}) cap) {
    switch (cap.subcommand) {
      case 'ACK':
        _acknowledgedCaps.addAll(cap.caps);

        if (cap.caps.contains('sasl')) {
          _startSasl();
        }

        _advanceCapNegotiation();
        break;

      case 'NAK':
        _advanceCapNegotiation();
        break;

      case 'LS':
        _observeServerCapabilities(cap.caps);
        break;
    }
  }

  void _startSasl() {
    final config = _currentConfig;
    if (config == null) return;

    _awaitingSaslResult = true;

    // Prefer SCRAM when the server advertises it: the password never leaves
    // the device. Fall back to PLAIN otherwise.
    if (_advertisedSaslMechs.contains('SCRAM-SHA-256')) {
      _scram = ScramSha256Client(username: config.loginUsername);
      sendRaw('AUTHENTICATE SCRAM-SHA-256');
    } else {
      sendRaw('AUTHENTICATE PLAIN');
    }
  }

  /// Sends the next queued CAP REQ; once the queue is drained and SASL is
  /// not in flight, finishes negotiation.
  void _advanceCapNegotiation() {
    if (_pendingCapReqs.isNotEmpty) {
      sendRaw('CAP REQ :${_pendingCapReqs.removeAt(0)}');
      return;
    }

    if (!_awaitingSaslResult) {
      _sendCapEnd();
    }
  }

  /// Records capabilities advertised via CAP LS: STS policies (observed only)
  /// and the SASL mechanisms the server supports.
  void _observeServerCapabilities(List<String> caps) {
    for (final cap in caps) {
      if (cap.startsWith('sts=')) {
        _observeStsPolicy(cap.substring(4));
        continue;
      }

      if (cap == 'sasl') {
        // No mechanism list advertised (pre-3.2 servers); PLAIN stays the
        // default choice.
        continue;
      }

      if (cap.startsWith('sasl=')) {
        _advertisedSaslMechs.addAll(
          cap
              .substring(5)
              .split(',')
              .map((m) => m.trim().toUpperCase())
              .where((m) => m.isNotEmpty),
        );
      }
    }
  }

  /// Records an STS policy advertised via CAP LS. The capability is observed
  /// only — it is never requested.
  void _observeStsPolicy(String value) {
    final parsed = IrcParser.parseStsCapValue(
      value,
      isTlsConnection: _activeTls,
      currentPort: _activePort,
    );

    if (parsed == null) return;

    if (parsed.durationSeconds <= 0) {
      unawaited(StsPolicyStore().delete(_activeHost));
    } else {
      unawaited(StsPolicyStore().upsert(StsPolicy(
        host: _activeHost,
        securePort: parsed.securePort,
        durationSeconds: parsed.durationSeconds,
        createdAt: DateTime.now(),
      )));
    }
  }

  void _sendCapEnd() {
    if (_capEndSent) return;
    _capEndSent = true;
    sendRaw('CAP END');
  }

  void _login(ServerConfig config) {
    final useSasl =
        config.useSasl && config.password != null && config.password!.isNotEmpty;

    // Each capability is requested on its own line: a REQ containing any
    // unknown capability is NAKed as a whole, so combining them would lose
    // the ones the server does know. sasl goes last so its ACK — which
    // starts authentication — arrives after everything else settled.
    _pendingCapReqs.addAll([
      'server-time',
      'batch',
      'typing',
      'chathistory',
      'draft/chathistory',
      if (useSasl) 'sasl',
    ]);

    // Observe-only LS: lets us learn STS policies and the SASL mechanism
    // list without requesting caps we do not implement. Servers without CAP
    // support reply 421, which is harmless, and the 001 handler below still
    // sends CAP END as a fallback.
    sendRaw('CAP LS 302');

    if (_pendingCapReqs.isNotEmpty) {
      sendRaw('CAP REQ :${_pendingCapReqs.removeAt(0)}');
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

  /// Sends a typing status for [target] (the `typing` client capability).
  /// Silently ignored when the server did not acknowledge the capability.
  void sendTyping(String target, bool active) {
    if (!_acknowledgedCaps.contains('typing')) return;

    sendRaw('@+typing=${active ? 'active' : 'done'} TYPING $target');
  }

  void sendRaw(String line) {
    final socket = _socket;
    if (socket == null) return;

    // A raw CR/LF inside the payload would terminate the IRC line early and
    // let pasted text inject protocol commands.
    final safeLine = line.replaceAll(RegExp(r'[\r\n]'), ' ');

    _logLine('>', safeLine);
    socket.write('$safeLine\r\n');
  }

  /// Logs raw traffic only in debug builds, with credentials redacted:
  /// SASL payloads, NickServ IDENTIFY, channel join keys and +k modes.
  void _logLine(String direction, String line) {
    if (!kDebugMode) return;
    debugPrint('IRC $direction ${_redactSecrets(line)}');
  }

  String _redactSecrets(String line) {
    var redacted = line;

    redacted = redacted.replaceFirst(
      RegExp(r'^(AUTHENTICATE)\s+\S+$', caseSensitive: false),
      r'$1 ***',
    );

    redacted = redacted.replaceFirst(
      RegExp(r'(IDENTIFY)\s+\S+\s*$', caseSensitive: false),
      r'$1 ***',
    );

    redacted = redacted.replaceFirst(
      RegExp(r'^(JOIN\s+#\S+)\s+\S+\s*$', caseSensitive: false),
      r'$1 ***',
    );

    redacted = redacted.replaceFirst(
      RegExp(r'^(MODE\s+#\S+\s+\+k)\s+\S+\s*$', caseSensitive: false),
      r'$1 ***',
    );

    return redacted;
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
    // Failed authentication and a changed TLS fingerprint are not transient;
    // retrying would fail identically and hammer the server.
    if (_authFailed) return;
    if (_certRejected) return;

    final config = _lastConfig;
    if (config == null) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    // Flap detection: repeated drops inside the window mean the connection
    // is unstable — back off hard instead of cycling every minute.
    final now = DateTime.now();
    _recentDrops.add(now);
    _recentDrops.removeWhere(
      (t) => now.difference(t) > _flapDetectionWindow,
    );

    final isFlapping = _recentDrops.length >= _flapDropThreshold;
    if (isFlapping) {
      _recentDrops.clear();
      _lineController.add(
        'Connection unstable ($_flapDropThreshold drops in '
        '${_flapDetectionWindow.inMinutes} minutes); pausing auto-reconnect '
        'for $_flapCooldownSeconds s.',
      );
    }

    final delaySeconds = isFlapping
        ? _flapCooldownSeconds
        : switch (_reconnectAttempts) {
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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starts and stops the Android foreground service that keeps IRC sockets
/// alive while the app is backgrounded. No-ops on other platforms and when
/// the native side is unavailable (e.g. tests).
class KeepAliveService {
  KeepAliveService._();

  static const MethodChannel _channel = MethodChannel('vittix_irc/keep_alive');

  static bool _running = false;

  static Future<void> start({String title = 'VIRC'}) async {
    if (_running) return;

    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('start', {'title': title});
      _running = true;
    } on PlatformException {
      // Starting a foreground service can fail (e.g. background start
      // restrictions); the app keeps working, just without keep-alive.
    } on MissingPluginException {
      // Native handler not registered (tests, unsupported builds).
    }
  }

  static Future<void> stop() async {
    if (!_running) return;
    _running = false;

    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing to recover: the service is going away either way.
    } on MissingPluginException {
      // Same as above.
    }
  }
}

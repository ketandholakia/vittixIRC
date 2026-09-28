import 'dart:async';

import 'package:flutter/services.dart';

class VolumeKeyService {
  static const MethodChannel _methodChannel = MethodChannel(
    'vittix_irc/volume_keys',
  );
  static const EventChannel _eventChannel = EventChannel(
    'vittix_irc/volume_keys/events',
  );

  static final VolumeKeyService instance = VolumeKeyService._();

  VolumeKeyService._();

  Stream<String>? _events;

  Stream<String> get events {
    return _events ??= _eventChannel.receiveBroadcastStream().map((event) {
      return event as String;
    });
  }

  Future<void> setEnabled(bool enabled) async {
    await _methodChannel.invokeMethod(
      'setEnabled',
      <String, dynamic>{'enabled': enabled},
    );
  }
}

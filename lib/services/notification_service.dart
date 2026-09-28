import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  // Stream to broadcast notification responses (taps and inline replies)
  final _notificationResponseController = StreamController<String>.broadcast();
  Stream<String> get notificationTaps =>
      _notificationResponseController.stream;
  String? _launchPayload;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    final details = await _flutterLocalNotificationsPlugin
        .getNotificationAppLaunchDetails();
    _launchPayload = details?.notificationResponse?.payload;

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null) {
          _notificationResponseController.add(payload);
        }
      },
    );
  }

  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // 1. Define the Remote Input for Inline Replies
    const AndroidNotificationAction action = AndroidNotificationAction(
      'reply_action',
      'Reply',
      inputs: [AndroidNotificationActionInput(label: 'Type a message...')],
    );

    // 2. Define standard notification details
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'vittix_mentions',
      'Mentions & DMs',
      channelDescription: 'Notifications for mentions and private messages',
      importance: Importance.max,
      priority: Priority.high,
      actions: [action],
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  void dispose() {
    _notificationResponseController.close();
  }
}

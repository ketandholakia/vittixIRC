import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  static final ShareIntentService instance = ShareIntentService._internal();
  ShareIntentService._internal();

  // Expose the stream from the plugin directly. This will be listened to by the UI.
  Stream<List<SharedMediaFile>> get sharedFiles =>
      ReceiveSharingIntent.instance.getMediaStream();

  void init() {
    // The init method is called from main.dart.
    // The UI code in chat_screen.dart handles initial media separately,
    // so we don't need to do anything with getInitialMedia() here.
    // The stream is accessed via the `sharedFiles` getter.
  }

  void dispose() {
    // The stream from the `receive_sharing_intent` plugin is managed by the plugin itself.
    // There's no local StreamController to close in this service.
  }
}
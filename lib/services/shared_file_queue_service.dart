import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class SharedFileQueueService {
  static final SharedFileQueueService instance = SharedFileQueueService._();

  SharedFileQueueService._();

  final List<File> _pendingFiles = [];
  final List<String> _pendingTexts = [];

  int get pendingCount => _pendingFiles.length;

  bool get hasPendingFiles => _pendingFiles.isNotEmpty;

  int get pendingTextCount => _pendingTexts.length;

  bool get hasPendingText => _pendingTexts.isNotEmpty;

  List<File> consumePendingFiles() {
    final files = List<File>.from(_pendingFiles);
    _pendingFiles.clear();
    return files;
  }

  List<String> consumePendingText() {
    final texts = List<String>.from(_pendingTexts);
    _pendingTexts.clear();
    return texts;
  }

  List<String> peekPendingText() {
    return List<String>.from(_pendingTexts);
  }

  void addSharedMedia(List<SharedMediaFile> mediaFiles) {
    for (final media in mediaFiles) {
      if (media.type == SharedMediaType.text) {
        final text = media.path.trim();
        if (text.isNotEmpty) {
          _pendingTexts.add(text);
        }
        continue;
      }

      final file = File(media.path);
      if (file.existsSync()) {
        _pendingFiles.add(file);
      }
    }
  }
}

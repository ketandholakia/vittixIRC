import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';

class ClipboardAttachmentService {
  Future<File?> getImageFromClipboard() async {
    final Uint8List? bytes = await Pasteboard.image;

    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final dir = await getTemporaryDirectory();

    final file = File(
      '${dir.path}/clipboard_image_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    await file.writeAsBytes(bytes);

    return file;
  }

  Future<String?> getTextFromClipboard() async {
    final text = await Pasteboard.text;

    if (text == null || text.trim().isEmpty) {
      return null;
    }

    return text.trim();
  }
}

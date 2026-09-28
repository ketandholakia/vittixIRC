import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'package:vittix_irc/models/file_upload_settings.dart';
import 'package:vittix_irc/models/upload_cancel_token.dart';
import 'package:vittix_irc/models/upload_progress.dart';
import 'package:vittix_irc/utils/upload_response_parser.dart';

class FileUploadService {
  Future<String> uploadFile({
    required File file,
    required FileUploadSettings settings,
    required UploadCancelToken cancelToken,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    if (!settings.isConfigured) {
      throw StateError('Upload server is not configured');
    }

    final uri = Uri.parse(settings.uploadUrl);
    final client = HttpClient();

    try {
      final request = await client.postUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'vittix_irc/1.0 Dart/${Platform.version.split(' ').first}',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');

      final headers = _parseHeaders(settings.additionalHeaders);

      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }

      if (settings.authType == UploadAuthType.basic) {
        final user = settings.username ?? '';
        final pass = settings.password ?? '';
        final token = base64Encode(utf8.encode('$user:$pass'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
      }

      final boundary = '----irc-mobile-${DateTime.now().microsecondsSinceEpoch}';
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final fields = _parseFields(settings.additionalFields);
      final fileField =
          settings.fileField.trim().isEmpty ? 'file' : settings.fileField.trim();

      final fileName = p.basename(file.path);
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      final fileLength = await file.length();

      final beforeFile = BytesBuilder();

      for (final entry in fields.entries) {
        beforeFile.add(utf8.encode('--$boundary\r\n'));
        beforeFile.add(
          utf8.encode(
            'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n',
          ),
        );
        beforeFile.add(utf8.encode('${entry.value}\r\n'));
      }

      beforeFile.add(utf8.encode('--$boundary\r\n'));
      beforeFile.add(
        utf8.encode(
          'Content-Disposition: form-data; name="$fileField"; filename="$fileName"\r\n',
        ),
      );
      beforeFile.add(utf8.encode('Content-Type: $mimeType\r\n\r\n'));

      final afterFile = utf8.encode('\r\n--$boundary--\r\n');
      final beforeBytes = beforeFile.toBytes();
      final totalBytes = beforeBytes.length + fileLength + afterFile.length;

      request.contentLength = totalBytes;

      var sentBytes = 0;
      void addProgress(int count) {
        sentBytes += count;
        onProgress?.call(
          UploadProgress(
            sentBytes: sentBytes,
            totalBytes: totalBytes,
          ),
        );
      }

      if (cancelToken.isCancelled) {
        throw const UploadCancelledException();
      }

      request.add(beforeBytes);
      addProgress(beforeBytes.length);

      await for (final chunk in file.openRead()) {
        if (cancelToken.isCancelled) {
          throw const UploadCancelledException();
        }

        request.add(chunk);
        addProgress(chunk.length);
      }

      if (cancelToken.isCancelled) {
        throw const UploadCancelledException();
      }

      request.add(afterFile);
      addProgress(afterFile.length);

      final response = await request.close();
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Upload failed: HTTP ${response.statusCode}: $body',
        );
      }

      final url = UploadResponseParser.parseUrl(
        responseBody: body,
        regex: settings.responseRegex,
      );

      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        throw FormatException('Upload response is not a valid URL: $url');
      }

      return url;
    } finally {
      client.close(force: cancelToken.isCancelled);
    }
  }

  Map<String, String> _parseHeaders(String text) {
    final result = <String, String>{};

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final index = trimmed.indexOf(':');
      if (index == -1) continue;

      final key = trimmed.substring(0, index).trim();
      final value = trimmed.substring(index + 1).trim();

      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  Map<String, String> _parseFields(String text) {
    final result = <String, String>{};

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final index = trimmed.indexOf('=');
      if (index == -1) continue;

      final key = trimmed.substring(0, index).trim();
      final value = trimmed.substring(index + 1).trim();

      if (key.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }
}

class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

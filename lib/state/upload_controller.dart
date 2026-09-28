import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'package:vittix_irc/models/file_upload_settings.dart';
import 'package:vittix_irc/models/pending_upload.dart';
import 'package:vittix_irc/models/upload_cancel_token.dart';
import 'package:vittix_irc/models/upload_progress.dart';
import 'package:vittix_irc/services/file_upload_service.dart';
import 'package:vittix_irc/services/file_upload_settings_service.dart';
import 'package:vittix_irc/services/upload_cache_service.dart';

class UploadController extends ChangeNotifier {
  final _uploadService = FileUploadService();
  final _settingsService = FileUploadSettingsService();
  final _cacheService = UploadCacheService();
  final Map<String, UploadCancelToken> _cancelTokens = {};

  final List<PendingUpload> _uploads = [];

  List<PendingUpload> get uploads => List.unmodifiable(_uploads);

  bool get hasUploads => _uploads.isNotEmpty;

  bool get hasPendingUploads {
    return _uploads.any(
      (u) => u.status == UploadStatus.pending || u.status == UploadStatus.failed,
    );
  }

  bool get isUploading {
    return _uploads.any((u) => u.status == UploadStatus.uploading);
  }

  bool get allUploaded {
    return _uploads.isNotEmpty &&
        _uploads.every((u) => u.status == UploadStatus.uploaded);
  }

  void addFiles(List<File> files) {
    for (final file in files) {
      final id = '${file.path}_${DateTime.now().microsecondsSinceEpoch}';

      _uploads.add(
        PendingUpload(
          id: id,
          file: file,
          fileName: p.basename(file.path),
          mimeType: lookupMimeType(file.path),
        ),
      );
    }

    notifyListeners();
  }

  void removeUpload(String id) {
    _uploads.removeWhere((u) => u.id == id);
    notifyListeners();
  }

  void removeFailed() {
    _uploads.removeWhere((u) => u.status == UploadStatus.failed);
    notifyListeners();
  }

  void removeCompleted() {
    _uploads.removeWhere((u) => u.status == UploadStatus.uploaded);
    notifyListeners();
  }

  void cancelPending(String id) {
    final token = _cancelTokens[id];
    if (token != null) {
      token.cancel();
    }

    final index = _uploads.indexWhere((u) => u.id == id);
    if (index == -1) return;

    final upload = _uploads[index];

    if (upload.status == UploadStatus.uploading) {
      _uploads[index] = upload.copyWith(
        status: UploadStatus.cancelled,
        error: 'Cancelling upload...',
      );
    } else {
      _uploads.removeAt(index);
    }

    notifyListeners();
  }

  void clearUploaded() {
    _uploads.removeWhere((u) => u.status == UploadStatus.uploaded);
    notifyListeners();
  }

  Future<String> retryUpload(String id) async {
    final index = _uploads.indexWhere((u) => u.id == id);
    if (index == -1) {
      throw StateError('Upload not found');
    }

    final upload = _uploads[index].copyWith(
      status: UploadStatus.pending,
      progress: 0,
      error: null,
    );

    _uploads[index] = upload;
    notifyListeners();

    final settings = await _settingsService.getSettings();
    return _uploadOne(upload, settings);
  }

  Future<List<String>> uploadAll() async {
    final settings = await _settingsService.getSettings();

    if (!settings.isConfigured) {
      throw StateError('File upload settings are not configured');
    }

    final urls = await Future.wait(
      _uploads
          .where((u) =>
              u.status != UploadStatus.uploaded &&
              u.status != UploadStatus.cancelled &&
              u.status != UploadStatus.uploading)
          .map((upload) => _uploadOne(upload, settings)),
    );

    return <String>{
      ..._uploads.where((u) => u.uploadedUrl != null).map((u) => u.uploadedUrl!),
      ...urls,
    }.toList();
  }

  Future<String> _uploadOne(
    PendingUpload upload,
    FileUploadSettings settings,
  ) async {
    final totalBytes = await upload.file.length();
    final cancelToken = UploadCancelToken();
    _cancelTokens[upload.id] = cancelToken;

    _updateUpload(
      upload.id,
      upload.copyWith(
        status: UploadStatus.uploading,
        progress: 0,
        uploadedBytes: 0,
        totalBytes: totalBytes,
        error: null,
      ),
    );

    try {
      final fileSize = await upload.file.length();
      final maxBytes = settings.maxFileSizeMb * 1024 * 1024;

      if (fileSize > maxBytes) {
        throw StateError(
          '${upload.fileName} is larger than ${settings.maxFileSizeMb} MB',
        );
      }

      final fileHash = await _cacheService.hashFile(upload.file);
      final rememberFor = Duration(hours: settings.rememberUploadsHours);

      final cachedUrl = await _cacheService.getCachedUrl(
        fileHash: fileHash,
        rememberFor: rememberFor,
      );

      if (cachedUrl != null) {
        _updateUpload(
          upload.id,
          upload.copyWith(
            status: UploadStatus.uploaded,
            progress: 1,
            uploadedBytes: totalBytes,
            totalBytes: totalBytes,
            uploadedUrl: cachedUrl,
          ),
        );

        return cachedUrl;
      }

      final url = await _uploadService.uploadFile(
        file: upload.file,
        settings: settings,
        cancelToken: cancelToken,
        onProgress: (UploadProgress progress) {
          final latestIndex = _uploads.indexWhere((u) => u.id == upload.id);
          if (latestIndex == -1) return;

          final latest = _uploads[latestIndex];
          _updateUpload(
            upload.id,
            latest.copyWith(
              progress: progress.progress,
              uploadedBytes: progress.sentBytes,
              totalBytes: progress.totalBytes,
            ),
          );
        },
      );

      await _cacheService.save(
        fileHash: fileHash,
        url: url,
      );

      _updateUpload(
        upload.id,
        upload.copyWith(
          status: UploadStatus.uploaded,
          progress: 1,
          uploadedBytes: totalBytes,
          totalBytes: totalBytes,
          uploadedUrl: url,
        ),
      );

      return url;
    } catch (e) {
      final wasCancelled = cancelToken.isCancelled;
      _updateUpload(
        upload.id,
        upload.copyWith(
          status: wasCancelled ? UploadStatus.cancelled : UploadStatus.failed,
          error: e.toString(),
        ),
      );

      rethrow;
    } finally {
      _cancelTokens.remove(upload.id);
    }
  }

  void _updateUpload(String id, PendingUpload updated) {
    final index = _uploads.indexWhere((u) => u.id == id);
    if (index == -1) return;

    _uploads[index] = updated;
    notifyListeners();
  }
}

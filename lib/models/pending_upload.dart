import 'dart:io';

enum UploadStatus {
  pending,
  uploading,
  uploaded,
  failed,
  cancelled,
}

class PendingUpload {
  final String id;
  final File file;
  final String fileName;
  final String? mimeType;
  final UploadStatus status;
  final double progress;
  final int totalBytes;
  final int uploadedBytes;
  final String? uploadedUrl;
  final String? error;

  const PendingUpload({
    required this.id,
    required this.file,
    required this.fileName,
    this.mimeType,
    this.status = UploadStatus.pending,
    this.progress = 0,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.uploadedUrl,
    this.error,
  });

  PendingUpload copyWith({
    UploadStatus? status,
    double? progress,
    int? totalBytes,
    int? uploadedBytes,
    String? uploadedUrl,
    String? error,
  }) {
    return PendingUpload(
      id: id,
      file: file,
      fileName: fileName,
      mimeType: mimeType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
      error: error,
    );
  }

  double get computedProgress {
    if (totalBytes <= 0) return progress;
    return uploadedBytes / totalBytes;
  }
}

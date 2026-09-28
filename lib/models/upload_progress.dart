class UploadProgress {
  final int sentBytes;
  final int totalBytes;

  const UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    return sentBytes / totalBytes;
  }
}

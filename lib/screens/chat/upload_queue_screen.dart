import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:vittix_irc/models/pending_upload.dart';
import 'package:vittix_irc/state/upload_controller.dart';

class UploadQueueScreen extends StatefulWidget {
  final UploadController controller;

  const UploadQueueScreen({
    super.key,
    required this.controller,
  });

  @override
  State<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends State<UploadQueueScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  String _statusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return 'Pending';
      case UploadStatus.uploading:
        return 'Uploading';
      case UploadStatus.uploaded:
        return 'Uploaded';
      case UploadStatus.failed:
        return 'Failed';
      case UploadStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData _statusIcon(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return Icons.schedule;
      case UploadStatus.uploading:
        return Icons.cloud_upload;
      case UploadStatus.uploaded:
        return Icons.check_circle_outline;
      case UploadStatus.failed:
        return Icons.error_outline;
      case UploadStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Future<void> _retry(PendingUpload upload) async {
    try {
      await widget.controller.retryUpload(upload.id);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry failed: $e')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final uploads = widget.controller.uploads;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove_completed') {
                widget.controller.removeCompleted();
              } else if (value == 'remove_failed') {
                widget.controller.removeFailed();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'remove_completed',
                child: Text('Remove completed'),
              ),
              PopupMenuItem(
                value: 'remove_failed',
                child: Text('Remove failed'),
              ),
            ],
          ),
        ],
      ),
      body: uploads.isEmpty
          ? const Center(
              child: Text('No uploads in queue'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: uploads.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final upload = uploads[index];

                return Slidable(
                  key: ValueKey(upload.id),
                  endActionPane: ActionPane(
                    motion: const BehindMotion(),
                    extentRatio: upload.status == UploadStatus.failed ||
                            upload.status == UploadStatus.cancelled
                        ? 0.45
                        : 0.30,
                    children: [
                      if (upload.status == UploadStatus.failed ||
                          upload.status == UploadStatus.cancelled)
                        SlidableAction(
                          onPressed: (_) => _retry(upload),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          icon: Icons.refresh,
                          label: 'Retry',
                        ),
                      SlidableAction(
                        onPressed: (_) {
                          widget.controller.cancelPending(upload.id);
                        },
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                        icon: upload.status == UploadStatus.uploading
                            ? Icons.cancel_outlined
                            : Icons.close,
                        label: upload.status == UploadStatus.uploading
                            ? 'Cancel'
                            : 'Remove',
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Icon(_statusIcon(upload.status)),
                    title: Text(
                      upload.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          upload.error == null
                              ? _statusText(upload.status)
                              : '${_statusText(upload.status)}: ${upload.error}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (upload.status == UploadStatus.uploading) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: upload.computedProgress <= 0
                                ? null
                                : upload.computedProgress,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatBytes(upload.uploadedBytes)} / ${_formatBytes(upload.totalBytes)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (upload.status == UploadStatus.uploading)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (upload.status == UploadStatus.failed ||
                            upload.status == UploadStatus.cancelled)
                          IconButton(
                            tooltip: 'Retry',
                            icon: const Icon(Icons.refresh),
                            onPressed: () => _retry(upload),
                          ),
                        IconButton(
                          tooltip: upload.status == UploadStatus.uploading
                              ? 'Cancel'
                              : 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            widget.controller.cancelPending(upload.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

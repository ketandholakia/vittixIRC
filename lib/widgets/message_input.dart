import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vittix_irc/models/pending_upload.dart';
import 'package:vittix_irc/services/clipboard_attachment_service.dart';
import 'package:vittix_irc/state/upload_controller.dart';

class MessageInput extends StatefulWidget {
  final String hintText;
  final List<String> commandSuggestions;
  final List<String> nickSuggestions;
  final ValueChanged<String> onSend;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onOpenUploadQueue;
  final VoidCallback? onHistoryPrevious;
  final VoidCallback? onHistoryNext;
  final UploadController uploadController;

  const MessageInput({
    super.key,
    required this.hintText,
    required this.commandSuggestions,
    required this.nickSuggestions,
    required this.onSend,
    this.onTextChanged,
    this.onOpenUploadQueue,
    this.onHistoryPrevious,
    this.onHistoryNext,
    required this.uploadController,
  });

  @override
  State<MessageInput> createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();
  final _clipboardAttachmentService = ClipboardAttachmentService();
  final List<String> _history = [];
  int _historyIndex = -1;
  List<String> _completions = const [];
  int _completionIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.uploadController.addListener(_onUploadChanged);
    _controller.addListener(_updateCompletions);
    _controller.addListener(_notifyTextChanged);
  }

  void _notifyTextChanged() {
    widget.onTextChanged?.call(_controller.text);
  }

  void _onUploadChanged() {
    if (mounted) setState(() {});
  }

  void _updateCompletions() {
    final completions = _buildCompletions(_controller.text, _controller.selection);
    if (_completions.length == completions.length &&
        _completions.asMap().entries.every((entry) => entry.value == completions[entry.key])) {
      return;
    }
    setState(() {
      _completions = completions;
      _completionIndex = 0;
    });
  }

  @override
  void dispose() {
    widget.uploadController.removeListener(_onUploadChanged);
    _controller.removeListener(_updateCompletions);
    _controller.removeListener(_notifyTextChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> _buildCompletions(String text, TextSelection selection) {
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    if (cursor < 0 || cursor > text.length) return const [];

    final prefix = text.substring(0, cursor);
    final start = prefix.lastIndexOf(' ');
    final tokenStart = start == -1 ? 0 : start + 1;
    final token = prefix.substring(tokenStart);
    if (token.isEmpty) return const [];

    final suggestions = token.startsWith('/')
        ? widget.commandSuggestions
        : widget.nickSuggestions;

    final lower = token.toLowerCase();
    return suggestions
        .where((s) => s.toLowerCase().startsWith(lower))
        .take(8)
        .toList();
  }

  void _applyCompletion([int step = 0]) {
    if (_completions.isEmpty) return;

    final text = _controller.text;
    final selection = _controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final prefix = text.substring(0, cursor);
    final suffix = text.substring(cursor);
    final start = prefix.lastIndexOf(' ');
    final tokenStart = start == -1 ? 0 : start + 1;

    final nextIndex = (_completionIndex + step) % _completions.length;
    _completionIndex = nextIndex < 0 ? _completions.length - 1 : nextIndex;
    final completion = _completions[_completionIndex];

    final tokenPrefix = prefix.substring(0, tokenStart);
    final nextText = '$tokenPrefix$completion $suffix';

      _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: '$tokenPrefix$completion '.length,
      ),
    );
  }

  void _send() {
    if (widget.uploadController.hasPendingUploads ||
        widget.uploadController.isUploading) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload or remove attachments before sending'),
        ),
      );
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _pushHistory(text);
    widget.onSend(text);
    _controller.clear();
    widget.uploadController.clearUploaded();
  }

  void _pushHistory(String text) {
    if (text.isEmpty) return;
    if (_history.isNotEmpty && _history.last == text) return;
    _history.add(text);
    if (_history.length > 100) {
      _history.removeAt(0);
    }
    _historyIndex = _history.length;
  }

  void previousHistory() {
    if (_history.isEmpty) return;
    if (_historyIndex > 0) {
      _historyIndex--;
    }
    _controller.text = _history[_historyIndex];
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  void nextHistory() {
    if (_history.isEmpty) return;
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _controller.text = _history[_historyIndex];
    } else {
      _historyIndex = _history.length;
      _controller.clear();
      return;
    }
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  void insertSharedText(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    final existing = _controller.text.trim();
    _controller.text = existing.isEmpty ? cleaned : '$existing\n$cleaned';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null) return;

    final files = result.paths
        .whereType<String>()
        .map((path) => File(path))
        .toList();

    widget.uploadController.addFiles(files);
  }

  Future<void> _takePhoto() async {
    final photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (photo == null) return;

    widget.uploadController.addFiles([File(photo.path)]);
  }

  Future<void> _pasteFromClipboard() async {
    final image = await _clipboardAttachmentService.getImageFromClipboard();

    if (image != null) {
      widget.uploadController.addFiles([image]);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard image added')),
      );

      return;
    }

    final text = await _clipboardAttachmentService.getTextFromClipboard();

    if (text != null && text.isNotEmpty) {
      final existing = _controller.text;
      _controller.text = existing.isEmpty ? text : '$existing $text';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clipboard is empty')),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _uploadAttachments() async {
    try {
      final urls = await widget.uploadController.uploadAll();
      if (!mounted) return;

      final existing = _controller.text.trim();
      final urlText = urls.join(' ');

      _controller.text = existing.isEmpty ? urlText : '$existing $urlText';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _send();
      widget.uploadController.clearUploaded();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploads = widget.uploadController.uploads;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (uploads.isNotEmpty)
              SizedBox(
                height: 112,
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: uploads.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final upload = uploads[index];
                    final isImage = upload.mimeType?.startsWith('image/') == true;

                    return Stack(
                      children: [
                        Container(
                          width: 92,
                          height: 104,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: isImage
                              ? Image.file(upload.file, fit: BoxFit.cover)
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.insert_drive_file),
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        upload.fileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: FutureBuilder<int>(
                            future: upload.file.length(),
                            builder: (_, snapshot) {
                              final size = snapshot.data;
                              if (size == null) return const SizedBox.shrink();
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _formatFileSize(size),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (upload.status == UploadStatus.uploading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black45,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        if (upload.status == UploadStatus.uploading)
                          Positioned(
                            left: 4,
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(upload.computedProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        if (upload.status == UploadStatus.uploaded)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () {
                              widget.uploadController.removeUpload(upload.id);
                            },
                            child: const CircleAvatar(
                              radius: 12,
                              child: Icon(Icons.close, size: 16),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Row(
              children: [
                if (widget.uploadController.uploads.isNotEmpty)
                  IconButton(
                    tooltip: 'Upload queue',
                    icon: const Icon(Icons.cloud_queue),
                    onPressed: widget.onOpenUploadQueue,
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Insert',
                  icon: const Icon(Icons.add_circle_outline),
                  onSelected: (value) {
                    switch (value) {
                      case 'file':
                        _pickFiles();
                        break;
                      case 'camera':
                        _takePhoto();
                        break;
                      case 'clipboard':
                        _pasteFromClipboard();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'file',
                      child: Text('Attach file'),
                    ),
                    PopupMenuItem(
                      value: 'camera',
                      child: Text('Take photo'),
                    ),
                    PopupMenuItem(
                      value: 'clipboard',
                      child: Text('Paste from clipboard'),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_completions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < _completions.length; i++)
                                ChoiceChip(
                                  label: Text(_completions[i]),
                                  selected: i == _completionIndex,
                                  onSelected: (_) {
                                    setState(() {
                                      _completionIndex = i;
                                    });
                                    _applyCompletion();
                                  },
                                ),
                            ],
                          ),
                        ),
                      Focus(
                        focusNode: _focusNode,
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) return KeyEventResult.ignored;
                          if (event.logicalKey == LogicalKeyboardKey.tab) {
                            if (_completions.isEmpty) return KeyEventResult.ignored;
                            _applyCompletion();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
                            widget.onHistoryPrevious?.call();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
                            widget.onHistoryNext?.call();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                              _completions.isNotEmpty) {
                            setState(() {
                              _completionIndex =
                                  (_completionIndex + 1) % _completions.length;
                            });
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                              _completions.isNotEmpty) {
                            setState(() {
                              _completionIndex =
                                  (_completionIndex - 1) % _completions.length;
                              if (_completionIndex < 0) {
                                _completionIndex = _completions.length - 1;
                              }
                            });
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                widget.uploadController.hasPendingUploads
                    ? FilledButton(
                        onPressed: widget.uploadController.isUploading
                            ? null
                            : _uploadAttachments,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(14),
                        ),
                        child: widget.uploadController.isUploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload),
                      )
                    : FilledButton(
                        onPressed: _send,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(14),
                        ),
                        child: const Icon(Icons.send),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

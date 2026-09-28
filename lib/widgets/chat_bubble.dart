import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vittix_irc/models/chat_message.dart';
import 'package:vittix_irc/services/url_preview_service.dart';
import 'package:vittix_irc/utils/nick_color_helper.dart';
import 'package:vittix_irc/utils/url_helper.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final bool highlighted;
  final bool showTimestamp;
  final bool showMediaPreviews;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onSenderTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.highlighted = false,
    this.showTimestamp = true,
    this.showMediaPreviews = true,
    this.onLongPress,
    this.onSenderTap,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TapGestureRecognizer _tapRecognizer(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  void _resetRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(UrlHelper.normalizeUrl(url));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _isImageUrl(String url) async {
    final normalized = UrlHelper.normalizeUrl(url);
    final preview = await UrlPreviewService.fetchPreview(normalized);
    final contentType = preview?.contentType ??
        await UrlPreviewService.fetchContentType(normalized);
    return contentType?.toLowerCase().startsWith('image/') ?? false;
  }

  List<InlineSpan> _buildLinkifiedSpans({
    required String text,
    required TextStyle baseStyle,
    required TextStyle linkStyle,
  }) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in UrlHelper.urlRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: baseStyle,
        ));
      }

      final rawUrl = match.group(0) ?? '';
      spans.add(
        TextSpan(
          text: rawUrl,
          style: linkStyle,
          recognizer: _tapRecognizer(() => _openUrl(rawUrl)),
        ),
      );

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return spans;
  }

  Widget _buildImagePreview(BuildContext context, String url) {
    if (!widget.showMediaPreviews) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<bool>(
      future: _isImageUrl(url),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () => _openUrl(url),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      UrlHelper.normalizeUrl(url),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                    child: const Text(
                      'Tap to open',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _resetRecognizers();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isSystem = widget.message.type == ChatMessageType.system ||
        widget.message.isSystem;
    final isAction = widget.message.type == ChatMessageType.action;
    final isMe = widget.message.isMe;
    final sender = isMe ? 'You' : widget.message.sender;
    final accent = isMe
        ? const Color(0xFF3B82F6)
        : NickColorHelper.forNick(context, widget.message.sender);

    if (isSystem) {
      final systemBackground = isDark
          ? colorScheme.secondaryContainer.withValues(alpha: 0.34)
          : const Color(0xFFF4ECFF);
      final systemBorder = isDark
          ? colorScheme.secondary.withValues(alpha: 0.42)
          : const Color(0xFFD7BFFF);
      final systemText =
          isDark ? colorScheme.onSecondaryContainer : const Color(0xFF3D2B61);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: systemBackground,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: systemBorder),
            ),
            child: Text.rich(
              TextSpan(
                children: _buildLinkifiedSpans(
                  text: widget.message.text,
                  baseStyle: TextStyle(
                    color: systemText,
                    fontSize: 12.5,
                    height: 1.18,
                    fontWeight: FontWeight.w500,
                  ),
                  linkStyle: TextStyle(
                    color: systemText,
                    fontSize: 12.5,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: systemText,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final bubbleColor = widget.highlighted
        ? colorScheme.tertiaryContainer.withValues(alpha: isDark ? 0.42 : 1)
        : isMe
            ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.46 : 1)
            : isDark
                ? colorScheme.surfaceContainerHighest
                : const Color(0xFFEAF7EE);
    final borderColor = widget.highlighted
        ? colorScheme.tertiary.withValues(alpha: isDark ? 0.72 : 0.78)
        : isMe
            ? colorScheme.primary.withValues(alpha: isDark ? 0.58 : 0.42)
            : isDark
                ? colorScheme.outlineVariant.withValues(alpha: 0.55)
                : const Color(0xFFB3D6BD);
    final senderColor = isMe ? colorScheme.primary : accent;
    final messageColor = colorScheme.onSurface.withValues(alpha: 0.92);
    final timestampColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final text = isAction
        ? '* ${widget.message.sender} ${widget.message.text}'
        : widget.message.text;
    final urls = UrlHelper.extractUrls(widget.message.text);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: borderColor,
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: borderColor.withValues(alpha: isDark ? 0.10 : 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            sender.isEmpty ? '?' : sender[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: GestureDetector(
                            onTap: () =>
                                widget.onSenderTap?.call(widget.message.sender),
                            child: Text(
                              sender,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: senderColor,
                                letterSpacing: 0.05,
                              ),
                            ),
                          ),
                        ),
                        if (isMe)
                          Container(
                            margin: const EdgeInsets.only(left: 5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'YOU',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onPrimary,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: _buildLinkifiedSpans(
                          text: text,
                          baseStyle: TextStyle(
                            fontSize: 14.5,
                            height: 1.18,
                            color: messageColor,
                            fontStyle:
                                isAction ? FontStyle.italic : FontStyle.normal,
                            fontWeight:
                                isMe ? FontWeight.w500 : FontWeight.w400,
                          ),
                          linkStyle: TextStyle(
                            fontSize: 14.5,
                            height: 1.18,
                            color: colorScheme.primary,
                            fontStyle:
                                isAction ? FontStyle.italic : FontStyle.normal,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    for (final url in urls) _buildImagePreview(context, url),
                    if (widget.showTimestamp) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatTime(widget.message.time),
                          style: TextStyle(
                            fontSize: 8.5,
                            color: timestampColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

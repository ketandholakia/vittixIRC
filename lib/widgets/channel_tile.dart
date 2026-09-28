import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:vittix_irc/models/channel.dart';
import 'package:vittix_irc/widgets/app_badge.dart';

class ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool selected;
  final String? searchQuery;
  final String? matchBadge;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final VoidCallback? onPin;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onSearch;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.selected,
    this.searchQuery,
    this.matchBadge,
    required this.onTap,
    this.onClose,
    this.onPin,
    this.onMoveUp,
    this.onMoveDown,
    this.onSearch,
  });

  Color _unreadColor(BuildContext context) {
    return channel.unreadCount > 0
        ? (selected
            ? Theme.of(context).colorScheme.primary
            : (matchBadge != null
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.secondary))
        : Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  TextSpan _highlightedSpan({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    final query = searchQuery?.trim();
    if (query == null || query.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final queryIndex = lowerText.indexOf(lowerQuery);
    if (queryIndex == -1) {
      return TextSpan(text: text, style: style);
    }

    final highlightStyle = style.copyWith(
      fontWeight: FontWeight.w700,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    );

    return TextSpan(
      style: style,
      children: [
        if (queryIndex > 0) TextSpan(text: text.substring(0, queryIndex)),
        TextSpan(
          text: text.substring(queryIndex, queryIndex + query.length),
          style: highlightStyle,
        ),
        if (queryIndex + query.length < text.length)
          TextSpan(text: text.substring(queryIndex + query.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = Slidable(
      key: ValueKey(channel.name),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.82,
        children: [
          if (onSearch != null)
            SlidableAction(
              onPressed: (_) => onSearch?.call(),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              icon: Icons.search,
              label: 'Search',
            ),
          if (onPin != null)
            SlidableAction(
              onPressed: (_) => onPin?.call(),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              foregroundColor: Theme.of(context).colorScheme.onTertiary,
              icon: channel.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: channel.pinned ? 'Unpin' : 'Pin',
            ),
          if (onClose != null)
            SlidableAction(
              onPressed: (_) => onClose?.call(),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              icon: Icons.close,
              label: channel.isPrivate ? 'Close' : 'Leave',
            ),
        ],
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 10,
        minVerticalPadding: 0,
        selected: selected,
        leading: Icon(
          channel.isPrivate ? Icons.person : Icons.tag,
          size: 22,
        ),
        title: Text.rich(
          _highlightedSpan(
            context: context,
            text: channel.name,
            style:
                (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
                    .copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        subtitle: (channel.modes.isEmpty && matchBadge == null)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (channel.modes.isNotEmpty)
                    Text.rich(
                      _highlightedSpan(
                        context: context,
                        text: channel.modes,
                        style: (Theme.of(context).textTheme.bodySmall ??
                                const TextStyle())
                            .copyWith(
                          fontSize: 12,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  if (matchBadge != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: Text(matchBadge!),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (channel.unreadCount > 0)
              AppBadge(
                label: channel.unreadCount.toString(),
                backgroundColor: _unreadColor(context),
                textColor: Theme.of(context).colorScheme.onPrimary,
              ),
            if (onMoveUp != null)
              IconButton(
                tooltip: 'Move up',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.keyboard_arrow_up, size: 22),
                onPressed: onMoveUp,
              ),
            if (onMoveDown != null)
              IconButton(
                tooltip: 'Move down',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.keyboard_arrow_down, size: 22),
                onPressed: onMoveDown,
              ),
            if (onClose != null)
              IconButton(
                tooltip:
                    channel.isPrivate ? 'Close conversation' : 'Leave room',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );

    return tile.animate().fadeIn(duration: 180.ms).slideX(
          begin: 0.03,
          end: 0,
          duration: 180.ms,
          curve: Curves.easeOut,
        );
  }
}

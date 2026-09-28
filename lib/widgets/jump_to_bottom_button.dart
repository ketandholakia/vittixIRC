import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vittix_irc/widgets/app_badge.dart';

class JumpToBottomButton extends StatefulWidget {
  final ScrollController scrollController;
  final int unreadCount; // Optional: Pass unread count while scrolled up

  const JumpToBottomButton({
    super.key,
    required this.scrollController,
    this.unreadCount = 0,
  });

  @override
  State<JumpToBottomButton> createState() => _JumpToBottomButtonState();
}

class _JumpToBottomButtonState extends State<JumpToBottomButton> {
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    // Show button if scrolled more than 100 pixels away from the bottom 
    // (Assuming the ListView is reversed for chat, so offset 0 is the bottom)
    final show = widget.scrollController.offset > 100;
    if (show != _showButton) {
      setState(() {
        _showButton = show;
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrollListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = FloatingActionButton(
      mini: true,
      onPressed: _showButton
          ? () => widget.scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              )
          : null,
      child: widget.unreadCount > 0
          ? Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Icon(Icons.arrow_downward),
                Positioned(
                  right: -2,
                  top: -2,
                  child: AppBadge(
                    label: widget.unreadCount.toString(),
                    backgroundColor: Theme.of(context).colorScheme.error,
                    textColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    fontSize: 10,
                  ),
                ),
              ],
            )
          : const Icon(Icons.arrow_downward),
    );

    return AnimatedOpacity(
      opacity: _showButton ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: button.animate().scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1, 1),
            duration: 180.ms,
            curve: Curves.easeOut,
          ),
    );
  }
}

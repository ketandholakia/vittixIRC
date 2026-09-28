import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AppBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsets padding;
  final double fontSize;

  const AppBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final fg = textColor ?? Theme.of(context).colorScheme.onPrimary;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    ).animate().scale(
          begin: const Offset(0.94, 0.94),
          end: const Offset(1, 1),
          duration: 180.ms,
          curve: Curves.easeOut,
        );
  }
}

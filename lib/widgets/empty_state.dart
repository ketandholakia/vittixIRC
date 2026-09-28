import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:showcaseview/showcaseview.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onPressed;
  final GlobalKey? buttonKey;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (buttonText != null && onPressed != null) ...[
              const SizedBox(height: 20),
              buttonKey == null
                  ? FilledButton(
                      onPressed: onPressed,
                      child: Text(buttonText!),
                    )
                  : Showcase(
                      key: buttonKey!,
                      title: buttonText!,
                      description: 'Create your first IRC server here.',
                      child: FilledButton(
                        onPressed: onPressed,
                        child: Text(buttonText!),
                      ),
                    ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(
          begin: 0.06,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOut,
        );
  }
}

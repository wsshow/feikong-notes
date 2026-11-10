import 'package:flutter/material.dart';

import '../app.dart';
import 'app_icon.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AlignmentGeometry alignment;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: context.appColors.softGreen,
                borderRadius: BorderRadius.circular(18),
              ),
              child: AppIcon(icon, size: 27, color: context.appColors.moss),
            ),
            const SizedBox(height: 17),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 7),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.appColors.muted,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const AppIcon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

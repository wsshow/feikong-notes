import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/note_read_aloud_service.dart';
import 'app_icon.dart';

/// Compact read-aloud controls floating above the editor's formatting toolbar.
final class NoteReadAloudBar extends StatelessWidget {
  const NoteReadAloudBar({
    required this.status,
    required this.onStop,
    super.key,
  });

  final ReadAloudStatus status;
  final VoidCallback onStop;

  static double heightFor(BuildContext context) =>
      math.max(56, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 8);

  @override
  Widget build(BuildContext context) {
    final preparing = status == ReadAloudStatus.generating;
    final label = preparing
        ? context.l10n.preparingReadAloud
        : status == ReadAloudStatus.paused
        ? context.l10n.paused
        : context.l10n.readAloudPlaying;
    return Container(
      key: const Key('note-read-aloud-bar'),
      height: heightFor(context),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border.all(color: context.appColors.line),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        boxShadow: context.appColors.floatingShadows,
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: [
              if (preparing)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                AppIcon(
                  Icons.volume_up_outlined,
                  size: 20,
                  color: context.appColors.accent,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('note-read-aloud-stop'),
                tooltip: context.l10n.stopReadAloud,
                onPressed: onStop,
                style: IconButton.styleFrom(fixedSize: const Size.square(48)),
                icon: const AppIcon(Icons.stop_circle_outlined, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

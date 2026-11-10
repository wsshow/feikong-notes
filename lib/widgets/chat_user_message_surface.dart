import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'editorial_paper_surface.dart';

/// Shared surface for user-authored chat content.
///
/// Both persisted chat messages and agent-run prompts must use this component,
/// otherwise the same user message can change appearance after a run starts.
class ChatUserMessageSurface extends StatelessWidget {
  const ChatUserMessageSurface({
    required this.padding,
    required this.quietColor,
    required this.child,
    this.width = double.infinity,
    this.outlineQuietSurface = false,
    super.key,
  });

  final EdgeInsets padding;
  final Color quietColor;
  final Widget child;
  final double? width;
  final bool outlineQuietSurface;

  static bool usesEditorialStyle(BuildContext context) =>
      context.appComponents.usesPaperAssistantCards;

  static Color foregroundColor(BuildContext context) =>
      usesEditorialStyle(context)
      ? context.appColors.onAccent
      : context.appColors.ink;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    if (usesEditorialStyle(context)) {
      final surface = EditorialPaperSurface(
        color: EditorialJournalTokens.colorCobalt,
        radius: context.appRadii.large,
        depth: EditorialSurfaceDepth.lifted,
        textureOpacity: .06,
        child: content,
      );
      return width == null ? surface : SizedBox(width: width, child: surface);
    }
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: quietColor,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: outlineQuietSurface
            ? Border.all(color: context.appColors.line)
            : null,
        boxShadow: outlineQuietSurface
            ? context.appColors.paperEdgeShadows
            : null,
      ),
      child: content,
    );
  }
}

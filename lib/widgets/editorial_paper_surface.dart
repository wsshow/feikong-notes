import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

/// The four physical depths used by the paper-craft theme.
enum EditorialSurfaceDepth { flat, lifted, raised, floating }

/// A reusable paper surface with stable texture and warm shadows.
///
/// Keeping the material recipe here prevents search, cards, dialogs and docks
/// from each approximating paper with a different elevation or border.
class EditorialPaperSurface extends StatelessWidget {
  const EditorialPaperSurface({
    required this.child,
    this.color,
    this.gradient,
    this.radius,
    this.depth = EditorialSurfaceDepth.lifted,
    this.textureOpacity = .18,
    this.borderColor,
    this.borderWidth = 1,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;
  final Color? color;
  final Gradient? gradient;
  final double? radius;
  final EditorialSurfaceDepth depth;
  final double textureOpacity;
  final Color? borderColor;
  final double borderWidth;
  final Clip clipBehavior;

  static List<BoxShadow> shadowsFor(
    AppPalette colors,
    EditorialSurfaceDepth depth,
  ) => switch (depth) {
    EditorialSurfaceDepth.flat => const [],
    EditorialSurfaceDepth.lifted => [
      BoxShadow(
        color: colors.shadow.withValues(alpha: .075),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: .07),
        blurRadius: 16,
        spreadRadius: -4,
        offset: const Offset(0, 7),
      ),
    ],
    EditorialSurfaceDepth.raised => [
      BoxShadow(
        color: colors.shadow.withValues(alpha: .105),
        blurRadius: 5,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: .105),
        blurRadius: 25,
        spreadRadius: -5,
        offset: const Offset(0, 12),
      ),
    ],
    EditorialSurfaceDepth.floating => [
      BoxShadow(
        color: colors.shadow.withValues(alpha: .12),
        blurRadius: 6,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: .14),
        blurRadius: 34,
        spreadRadius: -7,
        offset: const Offset(0, 17),
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final surface = color ?? colors.surface;
    final resolvedRadius = radius ?? context.appRadii.large;
    final shape = BorderRadius.circular(resolvedRadius);
    final edge =
        borderColor ??
        Color.alphaBlend(Colors.white.withValues(alpha: .55), colors.line);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadowsFor(colors, depth),
      ),
      child: ClipRRect(
        borderRadius: shape,
        clipBehavior: clipBehavior,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            gradient:
                gradient ??
                LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: .16),
                      surface,
                    ),
                    surface,
                  ],
                  stops: const [0, .7],
                ),
            image: textureOpacity <= 0
                ? null
                : DecorationImage(
                    image: const AssetImage(
                      EditorialJournalTokens.paperTextureAsset,
                    ),
                    fit: BoxFit.cover,
                    opacity: textureOpacity,
                    filterQuality: FilterQuality.low,
                  ),
            border: Border.all(color: edge, width: borderWidth),
            borderRadius: shape,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The lifted center action shared by the home and calendar paper docks.
class EditorialDockPrimaryAction extends StatelessWidget {
  const EditorialDockPrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.actionKey,
    this.emblemKey,
    this.iconSize = 29,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Key actionKey;
  final Key? emblemKey;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      key: actionKey,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -16,
            child: Container(
              key: emblemKey,
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.appColors.decoration,
                    context.appColors.accent,
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .68),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.appColors.shadow.withValues(alpha: .14),
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: context.appColors.decoration.withValues(alpha: .22),
                    blurRadius: 18,
                    spreadRadius: -3,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: AppIcon(icon, size: iconSize, color: Colors.white),
            ),
          ),
          Positioned(
            top: 41,
            left: 2,
            right: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appColors.accent,
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

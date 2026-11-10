import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import 'app_icon.dart';

/// Shared structural pieces retained by feature surfaces during the workspace
/// redesign. Standard controls remain regular Material controls so interaction
/// and accessibility semantics stay predictable.
final class PaperShell extends StatelessWidget {
  const PaperShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appColors.canvas,
      gradient: context.appColors.canvasGradient,
    ),
    child: child,
  );
}

final class BrandSpine extends StatelessWidget {
  const BrandSpine({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isCjk = RegExp(r'[\u3400-\u9fff]').hasMatch(label);
    return Semantics(
      container: true,
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                key: const Key('brand-spine-paper-tab'),
                width: double.infinity,
                height: math.min(208.0, constraints.maxHeight),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      context.appColors.paperPrimary.withValues(alpha: .82),
                      context.appColors.paperSecondary.withValues(alpha: .97),
                    ],
                  ),
                  border: Border.all(
                    color: context.appColors.line.withValues(alpha: .82),
                    width: .75,
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppRadius.medium),
                    bottomRight: Radius.circular(AppRadius.medium),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.appColors.shadow.withValues(alpha: .05),
                      blurRadius: 10,
                      offset: Offset(3, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: _BrandSpineTexturePainter(colors: context.appColors),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 20,
                      right: 5,
                      bottom: 8,
                      left: 5,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 22,
                          child: CustomPaint(
                            painter: _SpineMonogramPainter(
                              colors: context.appColors,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        const _SpineLocator(),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 64,
                          child: Center(
                            child: isCjk
                                ? Text(
                                    label.split('').join('\n'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: context.appColors.ink,
                                      fontFamily: 'Songti SC',
                                      fontFamilyFallback: [
                                        'Noto Serif CJK SC',
                                        'serif',
                                      ],
                                      fontSize: 13,
                                      height: 1.23,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  )
                                : RotatedBox(
                                    quarterTurns: 1,
                                    child: Text(
                                      label.toUpperCase(),
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: context.appColors.ink,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        const _SpineTerminal(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class SearchPullHandle extends StatelessWidget {
  const SearchPullHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('search-pull-handle-surface'),
    height: 48,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          context.appColors.paperPrimary.withValues(alpha: .98),
          context.appColors.paperSecondary.withValues(alpha: .96),
        ],
      ),
      border: Border.all(
        color: context.appColors.line.withValues(alpha: .9),
        width: .8,
      ),
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.large),
      ),
      boxShadow: [
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: .04),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

final class SearchPullTab extends StatelessWidget {
  const SearchPullTab({
    required this.label,
    required this.onTap,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            key: const Key('search-pull-tab-surface'),
            width: 100,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.appColors.paperPrimary.withValues(alpha: .96),
                  context.appColors.paperSecondary.withValues(alpha: .94),
                ],
              ),
              border: Border.all(
                color: context.appColors.line.withValues(alpha: .9),
                width: .8,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
              boxShadow: [
                BoxShadow(
                  color: context.appColors.shadow.withValues(alpha: .03),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: context.appColors.mechanicalBlue,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class EdgeToolAction {
  const EdgeToolAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;
}

final class EdgeToolDock extends StatelessWidget {
  const EdgeToolDock({required this.actions, super.key});

  final List<EdgeToolAction> actions;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('edge-tool-dock'),
    width: 38,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          context.appColors.paperPrimary.withValues(alpha: .96),
          context.appColors.paperSecondary.withValues(alpha: .94),
        ],
      ),
      border: Border.all(
        color: context.appColors.line.withValues(alpha: .88),
        width: .75,
      ),
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(AppRadius.medium),
      ),
      boxShadow: [
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: .04),
          blurRadius: 8,
          offset: Offset(-2, 3),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 6,
                endIndent: 6,
                color: context.appColors.line,
              ),
            _EdgeToolButton(action: actions[index]),
          ],
        ],
      ),
    ),
  );
}

final class _EdgeToolButton extends StatelessWidget {
  const _EdgeToolButton({required this.action});

  final EdgeToolAction action;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: action.tooltip,
    child: InkWell(
      key: action.buttonKey,
      onTap: action.onPressed,
      child: SizedBox(
        width: 38,
        height: 42,
        child: AppIcon(
          action.icon,
          size: 19,
          color: action.onPressed == null
              ? context.appColors.subtle
              : context.appColors.mechanicalBlue,
        ),
      ),
    ),
  );
}

final class CreateArcButton extends StatelessWidget {
  const CreateArcButton({
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: context.appColors.mechanicalBlue,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 56,
            child: AppIcon(
              Icons.add_rounded,
              color: context.appColors.onAccent,
              size: 28,
            ),
          ),
        ),
      ),
    ),
  );
}

final class IndexTicks extends StatelessWidget {
  const IndexTicks({
    required this.index,
    required this.count,
    required this.onDrag,
    super.key,
  });

  final int index;
  final int count;
  final ValueChanged<double>? onDrag;

  @override
  Widget build(BuildContext context) {
    final current = count == 0 ? 0 : index + 1;
    final exactReading = '$current / $count';
    return Semantics(
      label: exactReading,
      value: exactReading,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: onDrag == null
              ? null
              : (details) => _update(details.localPosition.dy, constraints),
          onVerticalDragUpdate: onDrag == null
              ? null
              : (details) => _update(details.localPosition.dy, constraints),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(end: count == 0 ? 0 : index.toDouble()),
                  builder: (context, position, _) => CustomPaint(
                    key: const Key('index-ticks-dial'),
                    painter: _IndexTicksPainter(
                      colors: context.appColors,
                      position: position,
                      count: count,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  key: const Key('index-ticks-reading'),
                  width: 60,
                  height: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        context.appColors.paperPrimary.withValues(alpha: .96),
                        context.appColors.paperSecondary.withValues(alpha: .94),
                      ],
                    ),
                    border: Border.all(
                      color: context.appColors.line.withValues(alpha: .88),
                      width: .75,
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(AppRadius.medium),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.appColors.shadow.withValues(alpha: .04),
                        blurRadius: 8,
                        offset: Offset(-2, 3),
                      ),
                    ],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$current',
                          key: const Key('index-ticks-current'),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: context.appColors.ink,
                            fontSize: 10,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '/',
                          key: Key('index-ticks-reading-divider'),
                          style: TextStyle(
                            color: context.appColors.subtle,
                            fontSize: 8,
                            height: 1,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$count',
                          key: const Key('index-ticks-total'),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 8,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _update(double dy, BoxConstraints constraints) {
    final height = constraints.maxHeight;
    if (height <= 0 || !height.isFinite) return;
    onDrag?.call((dy / height).clamp(0, 1));
  }
}

final class PaperTag extends StatelessWidget {
  const PaperTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.transparent,
      border: Border.all(
        color: context.appColors.mechanicalBlue.withValues(alpha: .65),
      ),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: context.appColors.ink,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

final class PaperSection extends StatelessWidget {
  const PaperSection({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.appColors.paperPrimary,
      borderRadius: BorderRadius.all(Radius.circular(context.appRadii.large)),
      border: context.appComponents.outlinesSurfaces
          ? Border.all(
              color: context.appColors.line,
              width: context.appComponents.surfaceBorderWidth,
            )
          : null,
      boxShadow: context.appColors.lowShadows,
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: Padding(padding: padding, child: child),
    ),
  );
}

final class _SpineLocator extends StatelessWidget {
  const _SpineLocator();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 12,
    height: 28,
    child: CustomPaint(
      painter: _SpineLocatorPainter(colors: context.appColors),
    ),
  );
}

final class _SpineLocatorPainter extends CustomPainter {
  final AppPalette colors;
  const _SpineLocatorPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.mechanicalBlue
      ..strokeWidth = 1;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, 15), paint);
    canvas.drawCircle(Offset(x, 23), 2.2, paint);
  }

  @override
  bool shouldRepaint(covariant _SpineLocatorPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

final class _SpineTerminal extends StatelessWidget {
  const _SpineTerminal();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 12,
    height: 32,
    child: CustomPaint(
      painter: _SpineTerminalPainter(colors: context.appColors),
    ),
  );
}

final class _SpineTerminalPainter extends CustomPainter {
  final AppPalette colors;
  const _SpineTerminalPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.mechanicalBlue
      ..strokeWidth = 1;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, 15), paint);
    canvas.drawLine(Offset(x - 3, 21), Offset(x + 3, 21), paint);
    canvas.drawLine(Offset(x - 3, 25), Offset(x + 3, 25), paint);
    canvas.drawCircle(
      Offset(x, 30),
      1.6,
      Paint()
        ..color = colors.mechanicalBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SpineTerminalPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

final class _SpineMonogramPainter extends CustomPainter {
  final AppPalette colors;
  const _SpineMonogramPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 30;
    final scaleY = size.height / 28;
    final monogram = Path()
      // F, with lightly cut ends to keep the mark mechanical rather than
      // typographic.
      ..moveTo(0, 0)
      ..lineTo(14, 0)
      ..lineTo(12.5, 4.5)
      ..lineTo(4.5, 4.5)
      ..lineTo(4.5, 11)
      ..lineTo(12, 11)
      ..lineTo(10.5, 15.5)
      ..lineTo(4.5, 15.5)
      ..lineTo(4.5, 28)
      ..lineTo(0, 28)
      ..close()
      // K stem.
      ..addRect(const Rect.fromLTWH(15, 0, 4.5, 28))
      // K upper and lower arms.
      ..moveTo(19, 13)
      ..lineTo(26.5, 0)
      ..lineTo(30, 0)
      ..lineTo(22, 15)
      ..close()
      ..moveTo(19, 12)
      ..lineTo(22.2, 10)
      ..lineTo(30, 28)
      ..lineTo(25.5, 28)
      ..lineTo(19, 15.5)
      ..close();
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(
      monogram,
      Paint()
        ..color = colors.mechanicalBlue
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpineMonogramPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

final class _BrandSpineTexturePainter extends CustomPainter {
  final AppPalette colors;
  const _BrandSpineTexturePainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalFiber = Paint()
      ..color = colors.ink.withValues(alpha: .012)
      ..strokeWidth = .45;
    for (var y = 7.0; y < size.height; y += 17) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + (y % 3) * .12),
        horizontalFiber,
      );
    }

    final verticalFiber = Paint()
      ..color = colors.surface.withValues(alpha: .16)
      ..strokeWidth = .35;
    for (var x = 5.0; x < size.width; x += 13) {
      canvas.drawLine(Offset(x, 0), Offset(x + .5, size.height), verticalFiber);
    }

    final fleck = Paint()..color = colors.ink.withValues(alpha: .018);
    for (var index = 0; index < 26; index++) {
      final x = ((index * 37) % 101) / 101 * size.width;
      final y = ((index * 67) % 283) / 283 * size.height;
      canvas.drawCircle(Offset(x, y), .32, fleck);
    }
  }

  @override
  bool shouldRepaint(covariant _BrandSpineTexturePainter oldDelegate) =>
      oldDelegate.colors != colors;
}

final class _IndexTicksPainter extends CustomPainter {
  final AppPalette colors;
  const _IndexTicksPainter({
    required this.colors,
    required this.position,
    required this.count,
  });

  final double position;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 1) return;
    final paint = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    final centerY = size.height / 2;
    final gap = math.max(1.0, (centerY - 6) / (count - 1));
    final firstVisible = math.max(0, ((5 - centerY) / gap + position).ceil());
    final lastVisible = math.min(
      count - 1,
      ((size.height - 5 - centerY) / gap + position).floor(),
    );
    for (var ordinal = firstVisible; ordinal <= lastVisible; ordinal++) {
      final y = centerY + (ordinal - position) * gap;
      final length = ordinal % 4 == 0 ? 10.0 : 6.0;
      final right = size.width - 2;
      canvas.drawLine(Offset(right - length, y), Offset(right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IndexTicksPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.position != position ||
      oldDelegate.count != count;
}

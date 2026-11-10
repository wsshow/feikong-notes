import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../theme/app_theme.dart';
import 'editorial_paper_surface.dart';

/// App-owned SVG artwork, compiled to cached paths without an image dependency.
/// The illustration is decorative and never participates in hit testing.
class SunCloudDecoration extends StatelessWidget {
  const SunCloudDecoration({
    this.size = SunnyGrowthTokens.compMascotSize,
    super.key,
  });

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        width: size,
        height: size * 80 / 96,
        child: const CustomPaint(painter: _SunCloudPainter()),
      ),
    ),
  );
}

class _SunCloudPainter extends CustomPainter {
  const _SunCloudPainter();

  static final _paths = [
    for (final layer in SunnyGrowthTokens.sunCloudPaths) _parse(layer.path),
  ];

  static Path _parse(String data) {
    final proxy = _VectorPathProxy();
    writeSvgPathDataToPath(data, proxy);
    return proxy.path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 80);
    for (var i = 0; i < _paths.length; i++) {
      final layer = SunnyGrowthTokens.sunCloudPaths[i];
      if (layer.fill case final fill?) {
        canvas.drawPath(_paths[i], Paint()..color = fill);
      }
      if (layer.stroke case final stroke?) {
        canvas.drawPath(
          _paths[i],
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = layer.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SunCloudPainter oldDelegate) => false;
}

class _VectorPathProxy extends PathProxy {
  final path = Path();
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void close() => path.close();
}

/// Text keeps its full scale; narrow layouts omit the optional illustration.
class SunnyGrowthHeading extends StatelessWidget {
  const SunnyGrowthHeading({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!context.appComponents.usesSunCloudDecoration ||
          constraints.maxWidth < 200 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return child;
      }
      return Row(
        children: [
          Flexible(child: child),
          const SizedBox(width: AppSpacing.xs),
          const SunCloudDecoration(),
        ],
      );
    },
  );
}

class AppThemeCanvas extends StatelessWidget {
  const AppThemeCanvas({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usesPaper = context.appComponents.usesPaperCraftDecoration;
    return Material(
      color: colors.canvas,
      child: DecoratedBox(
        key: const Key('app-theme-static-decoration'),
        decoration: BoxDecoration(
          gradient: colors.canvasGradient,
          image: usesPaper
              ? const DecorationImage(
                  image: AssetImage(EditorialJournalTokens.paperTextureAsset),
                  fit: BoxFit.cover,
                  opacity: .72,
                  filterQuality: FilterQuality.low,
                )
              : null,
        ),
        // Keep descendant Ink decorations above the opaque paper background.
        // Without a local Material, Ink paints on the outer Material and is
        // then covered by this DecoratedBox (for example, the settings avatar).
        child: Material(
          key: const Key('app-theme-content-material'),
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }
}

/// A shared navigation shell. Floating themes overlay this shell on the body;
/// scrollables add [floatingScrollClearance] only at their trailing edge so
/// content can travel behind the dock without becoming unreachable.
class AppBottomDock extends StatelessWidget {
  const AppBottomDock({required this.child, super.key});
  final Widget child;

  static const floatingContentHeight = 64.0;
  static const _floatingTopInset = 18.0;
  static const _floatingBottomInset = 12.0;

  static double floatingScrollClearance(BuildContext context) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    return floatingContentHeight +
        _floatingTopInset +
        (systemBottom > _floatingBottomInset
            ? systemBottom
            : _floatingBottomInset);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dockRadius = context.appRadii.dock;
    if (context.appComponents.usesFloatingNavigationDock) {
      final horizontalInset = MediaQuery.sizeOf(context).width < 360
          ? 24.0
          : 30.0;
      return Material(
        key: const Key('app-floating-navigation-region'),
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.fromLTRB(
            horizontalInset,
            _floatingTopInset,
            horizontalInset,
            _floatingBottomInset,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SizedBox(
                height: floatingContentHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(dockRadius),
                          boxShadow: EditorialPaperSurface.shadowsFor(
                            colors,
                            EditorialSurfaceDepth.floating,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(dockRadius),
                          child: _buildFloatingSurface(colors, dockRadius),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      // Continue the page background through the bar and its bottom safe area.
      color: colors.canvasGradient?.colors.last ?? colors.canvas,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: child,
      ),
    );
  }

  Widget _buildFloatingSurface(AppPalette colors, double dockRadius) {
    final surface = Color.alphaBlend(
      colors.surface.withValues(alpha: .92),
      colors.canvas,
    );
    return Material(
      key: const Key('app-floating-navigation-dock'),
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dockRadius),
        side: BorderSide(
          color: Color.alphaBlend(
            Colors.white.withValues(alpha: .78),
            colors.line,
          ),
          width: 1.1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(Colors.white.withValues(alpha: .22), surface),
              surface,
            ],
            stops: const [0, .78],
          ),
          image: const DecorationImage(
            image: AssetImage(EditorialJournalTokens.paperTextureAsset),
            fit: BoxFit.cover,
            opacity: .1,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}

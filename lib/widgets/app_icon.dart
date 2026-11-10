import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import 'app_icon_catalog.dart';
import '../theme/app_theme.dart';

/// The single renderer for app-owned interface icons.
///
/// Material identifiers are retained as semantic tokens for compatibility with
/// existing controls. The actual artwork is a local, rounded outline vector.
/// Parsing is lazy and cached; rebuilding a list never reloads an icon asset.
class AppIcon extends Icon {
  const AppIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
  }) : _chatComposer = false;

  /// Reference artwork for the chat camera, voice and more-action controls.
  /// Other uses of the same semantic tokens keep the standard app artwork.
  const AppIcon.chatComposer(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
  }) : _chatComposer = true;

  final bool _chatComposer;

  static const strokeWidth = 1.8;

  static bool supports(IconData icon) => appIconNames.containsKey(icon);

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final baseSize = size ?? theme.size ?? 24;
    final iconSize = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(baseSize)
        : baseSize;
    final data = icon;
    if (data == null) return SizedBox.square(dimension: iconSize);
    final name = _chatComposer
        ? appChatComposerIconNames[data] ?? appIconNames[data]
        : appIconNames[data];
    // A third-party caller can still supply a font icon. App-owned tokens are
    // exhaustively checked by app_icon_test.dart, so omissions fail CI.
    if (name == null) return super.build(context);
    final foreground =
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final direction = textDirection ?? Directionality.maybeOf(context);
    return Semantics(
      label: semanticLabel,
      textDirection: direction,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: iconSize,
          child: Center(
            child: SizedBox.square(
              dimension: iconSize,
              child: CustomPaint(
                painter: AppIconPainter(
                  name: name,
                  color: foreground.withValues(
                    alpha: foreground.a * (theme.opacity ?? 1),
                  ),
                  mirrored:
                      data.matchTextDirection && direction == TextDirection.rtl,
                  strokeWidth: _chatComposer
                      ? 2
                      : context.appComponents.iconStrokeWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class AppIconPainter extends CustomPainter {
  const AppIconPainter({
    required this.name,
    required this.color,
    this.mirrored = false,
    this.strokeWidth = AppIcon.strokeWidth,
  });

  final String name;
  final Color color;
  final bool mirrored;
  final double strokeWidth;
  static final _paths = <String, Path>{};

  Rect get artworkBounds => _pathFor(name).getBounds();

  static Path _pathFor(String name) => _paths.putIfAbsent(name, () {
    final proxy = _IconPathProxy();
    writeSvgPathDataToPath(appIconPaths[name]!, proxy);
    if (name == 'fk-selected') proxy.path.fillType = PathFillType.evenOdd;
    return proxy.path;
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    if (mirrored) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(
      _pathFor(name),
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..style = name == 'fk-selected'
            ? PaintingStyle.fill
            : PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.mirrored != mirrored ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _IconPathProxy extends PathProxy {
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

final appActionIconTheme = ActionIconThemeData(
  backButtonIconBuilder: (_) => const AppIcon(Icons.arrow_back_rounded),
  closeButtonIconBuilder: (_) => const AppIcon(Icons.close_rounded),
  drawerButtonIconBuilder: (_) => const AppIcon(Icons.menu),
  endDrawerButtonIconBuilder: (_) => const AppIcon(Icons.menu_open),
);

var _licenseRegistered = false;

void registerAppIconLicense() {
  if (_licenseRegistered) return;
  _licenseRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Lucide / Feather icons',
    ], appIconLicense);
  });
}

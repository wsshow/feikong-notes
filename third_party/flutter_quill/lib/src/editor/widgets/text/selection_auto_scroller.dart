import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../editor.dart';

/// One frame clock drives edge scrolling and selection hit testing, including
/// when the finger stays still. Caret-reveal animations must not run alongside.
class SelectionAutoScroller {
  SelectionAutoScroller({
    required this.renderEditor,
    required this.scrollController,
    required this.onUpdate,
  }) {
    _ticker = Ticker(_tick);
  }

  final RenderEditor renderEditor;
  final ScrollController scrollController;
  final ValueChanged<Offset> onUpdate;
  late final Ticker _ticker;
  Offset? _position;
  Duration _lastElapsed = Duration.zero;

  Rect? get _viewport {
    if (!renderEditor.attached || !scrollController.hasClients) return null;
    final viewport = RenderAbstractViewport.maybeOf(renderEditor);
    if (viewport is! RenderBox) return null;
    final box = viewport as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  double _velocity(Rect viewport, Offset point) {
    final edge = math.min(40.0, viewport.height / 4);
    final top = ((viewport.top + edge - point.dy) / edge).clamp(0.0, 1.0);
    final bottom = ((point.dy - viewport.bottom + edge) / edge).clamp(0.0, 1.0);
    // Slow entry into the edge band, capped at six typical body lines / second.
    return 180 * (bottom * bottom - top * top);
  }

  Offset _clampToViewport(Offset point, Rect viewport) =>
      Offset(point.dx, point.dy.clamp(viewport.top + 1, viewport.bottom - 1));

  void update(Offset position) {
    _position = position;
    final viewport = _viewport;
    onUpdate(
      viewport == null ? position : _clampToViewport(position, viewport),
    );
    if (viewport != null && _canScroll(_velocity(viewport, position))) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else {
      stop();
    }
  }

  bool _canScroll(double velocity) {
    final position = scrollController.position;
    return velocity < 0 && position.pixels > position.minScrollExtent ||
        velocity > 0 && position.pixels < position.maxScrollExtent;
  }

  void _tick(Duration elapsed) {
    final viewport = _viewport;
    final point = _position;
    if (viewport == null || point == null) {
      stop();
      return;
    }
    final velocity = _velocity(viewport, point);
    if (!_canScroll(velocity)) {
      stop();
      return;
    }
    // A delayed frame must never turn into a large jump through the document.
    final seconds = ((elapsed - _lastElapsed).inMicroseconds / 1000000).clamp(
      0.0,
      1 / 30,
    );
    _lastElapsed = elapsed;
    final position = scrollController.position;
    final target = (position.pixels + velocity * seconds).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) {
      position.jumpTo(target);
      onUpdate(_clampToViewport(point, viewport));
    }
  }

  void stop() {
    _ticker.stop();
    _lastElapsed = Duration.zero;
  }

  void dispose() => _ticker.dispose();
}

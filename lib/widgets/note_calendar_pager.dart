import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps the existing calendar layouts while moving whole periods with the
/// finger. Only the current period is interactive or exposed to accessibility.
class NoteCalendarPager extends StatefulWidget {
  const NoteCalendarPager({
    required this.period,
    required this.child,
    required this.adjacentBuilder,
    required this.canPrevious,
    required this.canNext,
    required this.onChanged,
    super.key,
  });

  final Object period;
  final Widget child;
  final Widget Function(int offset) adjacentBuilder;
  final bool canPrevious;
  final bool canNext;
  final ValueChanged<int> onChanged;

  @override
  State<NoteCalendarPager> createState() => NoteCalendarPagerState();
}

class NoteCalendarPagerState extends State<NoteCalendarPager>
    with SingleTickerProviderStateMixin {
  late final _position = AnimationController.unbounded(vsync: this);
  var _showAdjacent = false;
  var _width = 1.0;
  var _generation = 0;

  @override
  void didUpdateWidget(NoteCalendarPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      // A date/scale change must not let an older settling animation commit.
      _generation++;
      _position.stop();
      _position.value = 0;
      _showAdjacent = false;
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  bool _canGo(int offset) => offset < 0 ? widget.canPrevious : widget.canNext;

  void cancelTransition() {
    _generation++;
    _position.stop();
    setState(() {
      _position.value = 0;
      _showAdjacent = false;
    });
  }

  /// Header arrows use the same transition as a completed swipe.
  void goToPeriod(int offset) {
    if (!_canGo(offset) || _position.isAnimating) return;
    setState(() => _showAdjacent = true);
    unawaited(_settle(offset));
  }

  void _startDrag(DragStartDetails details) {
    _generation++;
    _position.stop();
    setState(() => _showAdjacent = true);
  }

  void _updateDrag(DragUpdateDetails details) {
    _position.value = (_position.value + details.delta.dx / _width).clamp(
      widget.canNext ? -1.0 : 0.0,
      widget.canPrevious ? 1.0 : 0.0,
    );
  }

  void _endDrag(DragEndDetails details) {
    final displacement = _position.value;
    final velocity = details.primaryVelocity ?? 0;
    final fling = velocity.abs() >= 500 && displacement.abs() * _width >= 12;
    // Releasing with velocity toward the starting page cancels the turn.
    final commit = fling
        ? velocity.sign == displacement.sign
        : displacement.abs() >= .25;
    final offset = commit ? (displacement < 0 ? 1 : -1) : 0;
    unawaited(_settle(offset));
  }

  Future<void> _settle(int offset) async {
    final generation = ++_generation;
    final target = -offset.toDouble();
    if (!MediaQuery.disableAnimationsOf(context)) {
      final remaining = (target - _position.value).abs().clamp(0.0, 1.0);
      try {
        await _position
            .animateTo(
              target,
              duration: Duration(milliseconds: (160 + 100 * remaining).round()),
              curve: Curves.easeOutCubic,
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _position.value = 0;
      _showAdjacent = false;
    });
    if (offset != 0 && _canGo(offset)) widget.onChanged(offset);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
      return GestureDetector(
        key: const Key('calendar-swipe-area'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _startDrag,
        onHorizontalDragUpdate: _updateDrag,
        onHorizontalDragEnd: _endDrag,
        onHorizontalDragCancel: () => unawaited(_settle(0)),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_showAdjacent && widget.canPrevious)
                _page(-1, widget.adjacentBuilder(-1)),
              _page(0, widget.child),
              if (_showAdjacent && widget.canNext)
                _page(1, widget.adjacentBuilder(1)),
            ],
          ),
        ),
      );
    },
  );

  Widget _page(int slot, Widget child) => AnimatedBuilder(
    key: ValueKey('calendar-period-slot-$slot'),
    animation: _position,
    // Calendar grids, lunar conversion and note counts do not rebuild on each
    // animation tick; only their paint translation changes.
    child: ExcludeSemantics(
      excluding: slot != 0,
      child: IgnorePointer(
        ignoring: slot != 0 || _showAdjacent,
        child: RepaintBoundary(
          child: slot == 0 ? child : PrimaryScrollController.none(child: child),
        ),
      ),
    ),
    builder: (context, child) => FractionalTranslation(
      translation: Offset(slot + _position.value, 0),
      child: child,
    ),
  );
}

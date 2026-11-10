import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/nodes/block.dart';
import '../box.dart';

/// A viewport around the *native* editable block, not a separate text input.
///
/// Its outer render box still implements Quill's text geometry protocol. This
/// keeps document offsets, selection, IME and undo in the same editor while the
/// block's measured, unwrapped contents can scroll independently of prose.
class ScrollableCodeBlock extends StatefulWidget {
  const ScrollableCodeBlock({
    required this.block,
    required this.controller,
    required this.hasFocus,
    required this.decoration,
    required this.margin,
    required this.contentBuilder,
    this.onScroll,
    super.key,
  });

  final Block block;
  final QuillController controller;
  final bool hasFocus;
  final BoxDecoration decoration;
  final EdgeInsets margin;
  final Widget Function(GlobalKey key) contentBuilder;
  final VoidCallback? onScroll;

  @override
  State<ScrollableCodeBlock> createState() => _ScrollableCodeBlockState();
}

class _ScrollableCodeBlockState extends State<ScrollableCodeBlock> {
  final _contentKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _scrollController = ScrollController(keepScrollOffset: false);
  bool _revealScheduled = false;
  TextSelection? _previousSelection;
  TextPosition? _revealPosition;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_selectionChanged);
    _scrollController.addListener(_didScroll);
    _selectionChanged();
  }

  @override
  void didUpdateWidget(ScrollableCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_selectionChanged);
      widget.controller.addListener(_selectionChanged);
      _selectionChanged();
    }
    if (!oldWidget.hasFocus && widget.hasFocus) _selectionChanged();
  }

  void _selectionChanged() {
    final selection = widget.controller.selection;
    final previous = _previousSelection;
    // Follow whichever selection handle is moving, not always the extent.
    _revealPosition =
        previous != null &&
            previous.baseOffset != selection.baseOffset &&
            previous.extentOffset == selection.extentOffset
        ? selection.base
        : selection.extent;
    _previousSelection = selection;
    _scheduleReveal();
  }

  void _scheduleReveal() {
    if (_revealScheduled || !widget.hasFocus) return;
    if (!widget.block.containsOffset(_revealPosition!.offset)) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !widget.hasFocus || !_scrollController.hasClients) return;
      final targetPosition = _revealPosition!;
      if (!widget.block.containsOffset(targetPosition.offset)) return;
      final content = _contentKey.currentContext?.findRenderObject();
      if (content is! RenderEditableBox || !content.attached) return;
      final caret = content.getLocalRectForCaret(
        content.globalToLocalPosition(targetPosition),
      );
      final viewport = RenderAbstractViewport.of(content);
      final position = _scrollController.position;
      const margin = 16.0;
      final leading =
          viewport.getOffsetToReveal(content, 0, rect: caret).offset - margin;
      final trailing =
          viewport.getOffsetToReveal(content, 1, rect: caret).offset + margin;
      final target =
          (leading < position.pixels
                  ? leading
                  : trailing > position.pixels
                  ? trailing
                  : position.pixels)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() > 0.5) {
        position.jumpTo(target);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _didScroll() {
    // The inner scroll view is a repaint boundary. Repaint the outer editor
    // too, so its selection-handle leader layers follow the scrolled text.
    final viewport = _viewportKey.currentContext?.findRenderObject();
    viewport?.markNeedsPaint();
    widget.onScroll?.call();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_selectionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CodeBlockViewport(
      key: _viewportKey,
      block: widget.block,
      contentKey: _contentKey,
      child: Padding(
        padding: widget.margin,
        child: LayoutBuilder(
          builder: (context, constraints) => DecoratedBox(
            decoration: widget.decoration,
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.horizontal) {
                  _scheduleReveal();
                }
                return false;
              },
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                // This viewport is inside the document, not against the
                // screen edge. System safe-area padding would lift the thumb
                // over the last code line instead of into its bottom padding.
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                thumbColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .28),
                thickness: 3,
                radius: const Radius.circular(2),
                notificationPredicate: (notification) =>
                    notification.depth == 0 &&
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: const ValueKey('quill-code-block-scroll'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    // Measure actual styled glyphs (including tabs, CJK and text
                    // scaling); never estimate columns or cap the content width.
                    child: IntrinsicWidth(
                      child: widget.contentBuilder(_contentKey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBlockViewport extends SingleChildRenderObjectWidget {
  const _CodeBlockViewport({
    required this.block,
    required this.contentKey,
    required super.child,
    super.key,
  });

  final Block block;
  final GlobalKey contentKey;

  @override
  _RenderCodeBlockViewport createRenderObject(BuildContext context) =>
      _RenderCodeBlockViewport(block, contentKey);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCodeBlockViewport renderObject,
  ) {
    renderObject
      ..block = block
      ..contentKey = contentKey;
  }
}

/// The editor sees a normal, screen-width block. Every geometry query crosses
/// the viewport transform so caret, hit testing and selection handles agree
/// with the horizontally scrolled text, including cross-block selections.
class _RenderCodeBlockViewport extends RenderProxyBox
    implements RenderEditableBox {
  _RenderCodeBlockViewport(this.block, this.contentKey);

  Block block;
  GlobalKey contentKey;

  RenderEditableBox get _content =>
      contentKey.currentContext!.findRenderObject()! as RenderEditableBox;

  Offset _fromContent(Offset point) =>
      MatrixUtils.transformPoint(_content.getTransformTo(this), point);

  TextSelectionPoint _fromSelectionPoint(TextSelectionPoint point) =>
      TextSelectionPoint(_fromContent(point.point), point.direction);

  @override
  Block get container => block;

  @override
  double preferredLineHeight(TextPosition position) =>
      _content.preferredLineHeight(position);

  @override
  Offset getOffsetForCaret(TextPosition position) =>
      _fromContent(_content.getOffsetForCaret(position));

  @override
  TextPosition getPositionForOffset(Offset offset) => _content
      .getPositionForOffset(_content.globalToLocal(localToGlobal(offset)));

  @override
  TextPosition getWordPositionForOffset(Offset offset) => _content
      .getWordPositionForOffset(_content.globalToLocal(localToGlobal(offset)));

  @override
  TextPosition globalToLocalPosition(TextPosition position) =>
      _content.globalToLocalPosition(position);

  @override
  TextPosition? getPositionAbove(TextPosition position) =>
      _content.getPositionAbove(position);

  @override
  TextPosition? getPositionBelow(TextPosition position) =>
      _content.getPositionBelow(position);

  @override
  TextRange getWordBoundary(TextPosition position) =>
      _content.getWordBoundary(position);

  @override
  TextRange getLineBoundary(TextPosition position) =>
      _content.getLineBoundary(position);

  @override
  TextSelectionPoint getBaseEndpointForSelection(TextSelection selection) =>
      _fromSelectionPoint(_content.getBaseEndpointForSelection(selection));

  @override
  TextSelectionPoint getExtentEndpointForSelection(TextSelection selection) =>
      _fromSelectionPoint(_content.getExtentEndpointForSelection(selection));

  @override
  Rect getLocalRectForCaret(TextPosition position) => MatrixUtils.transformRect(
    _content.getTransformTo(this),
    _content.getLocalRectForCaret(position),
  );

  @override
  Rect getCaretPrototype(TextPosition position) =>
      _content.getCaretPrototype(position);
}

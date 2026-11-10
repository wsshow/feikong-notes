// Flutter Quill 11.5.1 exposes custom list-leading layout as experimental. The
// dependency is pinned and this integration is covered by editor widget tests.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../app.dart';
import '../editor/note_editor_controller.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../services/note_audio_playback_service.dart';
import 'app_popup_menu.dart';
import 'editor_context_menu.dart';
import 'note_attachment_title_sheet.dart';
import 'note_external_image_drop.dart';
import 'note_link_editor_sheet.dart';
import 'note_file_reference_card.dart';
import 'app_icon.dart';

typedef NoteAssetImageProvider = ImageProvider? Function(NoteAsset asset);
typedef NoteAssetPathResolver = String? Function(NoteAsset asset);
typedef NoteImageAssetAction = Future<void> Function(NoteAsset asset);

TextStyle _paperListLineStyle(quill.Node node, quill.DefaultStyles styles) {
  final heading = node.style.attributes[quill.Attribute.header.key]?.value;
  final style = switch (heading) {
    1 => styles.h1!.style,
    2 => styles.h2!.style,
    3 => styles.h3!.style,
    4 => styles.h4!.style,
    5 => styles.h5!.style,
    6 => styles.h6!.style,
    _ => styles.paragraph!.style,
  };
  final explicitHeight = {
    quill.LineHeightAttribute.lineHeightNormal:
        styles.lineHeightNormal!.style.height,
    quill.LineHeightAttribute.lineHeightTight:
        styles.lineHeightTight!.style.height,
    quill.LineHeightAttribute.lineHeightOneAndHalf:
        styles.lineHeightOneAndHalf!.style.height,
    quill.LineHeightAttribute.lineHeightDouble:
        styles.lineHeightDouble!.style.height,
  }[node.style.attributes[quill.Attribute.lineHeight.key]];
  final inlineSize = node is quill.Line && node.children.isNotEmpty
      ? node.children.first.style.attributes[quill.Attribute.size.key]?.value
      : null;
  final fontSize = switch (inlineSize) {
    'small' => styles.sizeSmall?.fontSize,
    'large' => styles.sizeLarge?.fontSize,
    'huge' => styles.sizeHuge?.fontSize,
    final num size => size.toDouble(),
    final String size => double.tryParse(size),
    _ => null,
  };
  return style.copyWith(
    height: explicitHeight,
    fontSize: math.max(style.fontSize!, fontSize ?? 0),
  );
}

quill.HorizontalSpacing _paperListIndentWidth(
  quill.Block block,
  BuildContext context,
  int count,
  quill.LeadingBlockNumberPointWidth numberPointWidthBuilder,
) {
  final spacing = quill.TextBlockUtils.defaultIndentWidthBuilder(
    block,
    context,
    count,
    numberPointWidthBuilder,
  );
  final list = block.style.attributes[quill.Attribute.list.key];
  if (list != quill.Attribute.ol &&
      list != quill.Attribute.ul &&
      list != quill.Attribute.checked &&
      list != quill.Attribute.unchecked) {
    return spacing;
  }

  final styles = quill.QuillStyles.getStyles(context, false)!;
  var style = _paperListLineStyle(block, styles);
  // Headers and inline sizes live on each line, not on the shared list block.
  // Quill evaluates this block-level gutter once, keeping long lists linear.
  for (final line in block.children) {
    final candidate = _paperListLineStyle(line, styles);
    if (candidate.fontSize! > style.fontSize!) style = candidate;
  }
  final scaler = MediaQuery.textScalerOf(context);
  final painter = TextPainter(
    text: TextSpan(
      text: list == quill.Attribute.ol ? '$count.' : '•',
      style: style,
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
  )..layout();
  final fontSize = styles.paragraph!.style.fontSize!;
  final defaultWidth = list == quill.Attribute.ol
      ? numberPointWidthBuilder(fontSize, count)
      : fontSize * 2;
  final markerWidth = math.max(
    scaler.scale(style.fontSize!) * 2,
    painter.width + fontSize / 2,
  );
  painter.dispose();
  final level =
      block.style.attributes[quill.Attribute.indent.key]?.value as int? ?? 0;
  // Tasks and ordinary lists share a text column at each depth. Keep a clear
  // 24dp step between levels while the marker gutter follows system text size.
  return quill.HorizontalSpacing(
    math.max(defaultWidth, markerWidth) + level * AppSpacing.xl,
    spacing.right,
  );
}

Widget? _paperLeadingBlockBuilder(quill.Node node, quill.LeadingConfig config) {
  final isTask =
      config.attribute == quill.Attribute.checked ||
      config.attribute == quill.Attribute.unchecked;
  final isOrdered = config.attribute == quill.Attribute.ol;
  final isBullet = config.attribute == quill.Attribute.ul;
  if (!isTask && !isOrdered && !isBullet) return null;

  // Resolve numbering once: rebuilding a marker must not advance the counter.
  final index = isOrdered ? config.getIndexNumberByIndent! : null;
  final size = config.lineSize ?? 16;
  final enabled = config.enabled ?? false;
  final checked = config.value;
  return Builder(
    builder: (context) {
      final styles = quill.QuillStyles.getStyles(context, false)!;
      final lineStyle = _paperListLineStyle(node, styles);
      final height = lineStyle.height!;
      if (!isTask) {
        final markerStyle = config.style!.copyWith(
          fontSize: lineStyle.fontSize,
          height: height,
          fontWeight: isBullet ? FontWeight.bold : lineStyle.fontWeight,
          leadingDistribution: lineStyle.leadingDistribution,
        );
        if (isOrdered) {
          return quill.QuillNumberPoint(
            index: index!,
            indentLevelCounts: config.indentLevelCounts,
            count: config.count,
            style: markerStyle,
            attrs: config.attrs,
            width: config.width!,
            padding: config.padding!,
          );
        }
        return quill.QuillBulletPoint(
          style: markerStyle,
          width: config.width!,
          padding: config.padding!,
        );
      }
      final firstLineHeight =
          MediaQuery.textScalerOf(context).scale(lineStyle.fontSize!) * height;
      return SizedBox(
        key: const Key('note-todo-leading'),
        height: firstLineHeight,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: size / 2),
            child: Semantics(
              button: true,
              checked: checked,
              enabled: enabled,
              child: SizedBox.square(
                key: const Key('note-todo-checkbox'),
                dimension: size,
                child: Material(
                  color: checked
                      ? enabled
                            ? context.appColors.accent
                            : context.appColors.muted
                      : context.appColors.surface,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: enabled
                          ? context.appColors.muted
                          : context.appColors.line,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: InkWell(
                    onTap: enabled
                        ? () => config.onCheckboxTap(!checked)
                        : null,
                    child: checked
                        ? AppIcon(
                            Icons.check,
                            size: 16,
                            color: context.appColors.onAccent,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

quill.DefaultStyles _paperQuillStyles(BuildContext context) {
  final defaults = quill.DefaultStyles.getInstance(context);
  final body = DefaultTextStyle.of(context).style
      .merge(AppTypography.editorBody)
      .copyWith(color: context.appColors.ink, decoration: TextDecoration.none);
  final paragraph = quill.DefaultTextBlockStyle(
    body,
    quill.HorizontalSpacing.zero,
    const quill.VerticalSpacing(0, AppSpacing.sm),
    const quill.VerticalSpacing(0, AppSpacing.sm),
    null,
  );
  quill.DefaultTextBlockStyle heading(double size, double spaceBefore) =>
      quill.DefaultTextBlockStyle(
        body.copyWith(fontSize: size, height: 1.4, fontWeight: FontWeight.w700),
        quill.HorizontalSpacing.zero,
        quill.VerticalSpacing(spaceBefore, AppSpacing.xs),
        quill.VerticalSpacing.zero,
        null,
      );

  final codeTextStyle = TextStyle(
    color: context.appColors.ink,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Noto Sans Mono CJK SC', 'sans-serif'],
    fontSize: 14,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
    wordSpacing: 0,
  );
  return quill.DefaultStyles(
    paragraph: paragraph,
    h1: heading(28, AppSpacing.xl),
    h2: heading(24, AppSpacing.lg),
    h3: heading(20, AppSpacing.md),
    h4: heading(18, AppSpacing.sm),
    h5: heading(16, AppSpacing.sm),
    h6: heading(16, AppSpacing.sm),
    placeHolder: paragraph.copyWith(
      style: body.copyWith(color: context.appColors.muted),
    ),
    lists: defaults.lists!.copyWith(
      // Inherit the paragraph or heading so list formatting cannot reset its
      // font size and line height to Quill's compact defaults.
      style: const TextStyle(),
      verticalSpacing: const quill.VerticalSpacing(0, AppSpacing.sm),
      lineSpacing: const quill.VerticalSpacing(0, AppSpacing.xxs),
      indentWidthBuilder: _paperListIndentWidth,
    ),
    leading: paragraph.copyWith(
      verticalSpacing: quill.VerticalSpacing.zero,
      lineSpacing: quill.VerticalSpacing.zero,
    ),
    quote: paragraph.copyWith(
      style: TextStyle(color: context.appColors.muted),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(width: 3, color: context.appColors.line),
        ),
      ),
    ),
    indent: paragraph,
    align: paragraph,
    code: quill.DefaultTextBlockStyle(
      codeTextStyle,
      quill.HorizontalSpacing.zero,
      const quill.VerticalSpacing(AppSpacing.xs, AppSpacing.sm),
      quill.VerticalSpacing.zero,
      BoxDecoration(
        color: context.appColors.paperSecondary,
        border: Border.all(color: context.appColors.line),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
    ),
    inlineCode: quill.InlineCodeStyle(
      style: codeTextStyle.copyWith(
        color: context.appColors.mechanicalBlue,
        fontSize: 13.5,
        // Let the enclosing paragraph or heading strut set the line height.
        height: 1,
      ),
      backgroundColor: context.appColors.accentSoft,
      radius: const Radius.circular(3),
    ),
    link: TextStyle(
      color: context.appColors.link,
      decoration: TextDecoration.underline,
      decorationColor: context.appColors.link,
    ),
  );
}

final class NoteQuillEditor extends StatefulWidget {
  const NoteQuillEditor({
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.scrollController,
    this.editorKey,
    this.resolveImage,
    this.resolveAssetPath,
    this.audioPlayback,
    this.onOpenAsset,
    this.onTranscribeAudio,
    this.onCopyImage,
    this.onEditImage,
    this.onViewImageOriginal,
    this.onShowImageDetails,
    this.onDropImages,
    this.readOnly = false,
    this.placeholder = '开始记录…',
    this.bottomContentPadding = 0,
    super.key,
  });

  final NoteEditorController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final ScrollController? scrollController;
  final GlobalKey<quill.QuillEditorState>? editorKey;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteAudioPlaybackDriver? audioPlayback;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final ValueChanged<NoteAsset>? onTranscribeAudio;
  final NoteImageAssetAction? onCopyImage;
  final NoteImageAssetAction? onEditImage;
  final NoteImageAssetAction? onViewImageOriginal;
  final NoteImageAssetAction? onShowImageDetails;
  final NoteExternalImageDropHandler? onDropImages;
  final bool readOnly;
  final String placeholder;
  final double bottomContentPadding;

  @override
  State<NoteQuillEditor> createState() => _NoteQuillEditorState();
}

/// A non-interactive projection that uses the same Quill and embed layout as
/// the editor. It is intended for paper-card previews where document order and
/// block positioning must remain faithful without creating editable fields.
final class NoteRichDocumentPreview extends StatefulWidget {
  const NoteRichDocumentPreview({
    required this.note,
    this.resolveImage,
    this.resolveAssetPath,
    super.key,
  });

  final Note note;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;

  @override
  State<NoteRichDocumentPreview> createState() =>
      _NoteRichDocumentPreviewState();
}

final class _NoteRichDocumentPreviewState
    extends State<NoteRichDocumentPreview> {
  late NoteEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant NoteRichDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.revision == widget.note.revision &&
        oldWidget.note.document.toJsonString() ==
            widget.note.document.toJsonString() &&
        oldWidget.note.assets == widget.note.assets) {
      return;
    }
    final previous = _controller;
    _controller = _createController();
    previous.dispose();
  }

  NoteEditorController _createController() {
    final controller = NoteEditorController(
      document: widget.note.document,
      assets: widget.note.assets,
    );
    controller.quillController.readOnly = true;
    return controller;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: quill.QuillEditor.basic(
      controller: _controller.quillController,
      config: quill.QuillEditorConfig(
        customStyles: _paperQuillStyles(context),
        scrollable: false,
        autoFocus: false,
        showCursor: false,
        enableInteractiveSelection: false,
        enableSelectionToolbar: false,
        padding: EdgeInsets.zero,
        customLeadingBlockBuilder: _paperLeadingBlockBuilder,
        embedBuilders: [
          _NoteFileReferencesEmbedBuilder(session: _controller),
          _NoteAssetEmbedBuilder(
            session: _controller,
            resolveImage: widget.resolveImage,
            resolveAssetPath: widget.resolveAssetPath,
            audioPlayback: null,
            onOpenAsset: null,
            onTranscribeAudio: null,
            selectedAssetId: null,
            onAssetInteraction: _ignoreInteraction,
            onSelectAsset: _ignoreAttachment,
            onToggleAssetSelection: _ignoreAttachment,
            onAssetDragStarted: _ignoreDragStart,
            onAssetDragUpdate: _ignoreOffset,
            onAssetDragEnded: _ignoreInteraction,
          ),
          const _NoteDividerEmbedBuilder(
            onInteraction: _ignoreInteraction,
            onToggleActions: _ignoreOffsetIndex,
          ),
          const _NoteTableEmbedBuilder(
            onInteraction: _ignoreInteraction,
            onToggleActions: _ignoreOffsetIndex,
          ),
        ],
      ),
    ),
  );

  static void _ignoreInteraction() {}

  static void _ignoreAttachment(NoteAttachmentId _) {}

  static void _ignoreDragStart(_NoteEmbedDragData _) {}

  static void _ignoreOffset(Offset _) {}

  static void _ignoreOffsetIndex(int _) {}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

final class _NoteQuillEditorState extends State<NoteQuillEditor> {
  final _fallbackEditorKey = GlobalKey<quill.QuillEditorState>();
  GlobalKey<quill.QuillEditorState> get _quillEditorKey =>
      widget.editorKey ?? _fallbackEditorKey;
  final _editorStackKey = GlobalKey();
  late final ScrollController _fallbackScrollController;
  late final FocusNode _fallbackFocusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _fallbackFocusNode;
  TextSelection? _previousEditingSelection;
  bool _correctingCaret = false;
  bool _caretCorrectionScheduled = false;
  NoteAttachmentId? _activeAssetId;
  ({NoteEmbedKind kind, int offset})? _activeBlock;
  _NoteEmbedDragData? _draggingBlock;
  int? _dropOffset;
  double? _dropIndicatorY;
  var _externalImageDragActive = false;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _fallbackScrollController = ScrollController();
    _fallbackFocusNode = FocusNode();
    _effectiveFocusNode.addListener(_editingFocusChanged);
    widget.controller.quillController.addListener(_editingSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant NoteQuillEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.quillController.removeListener(
        _editingSelectionChanged,
      );
      widget.controller.quillController.addListener(_editingSelectionChanged);
      _previousEditingSelection = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _fallbackFocusNode).removeListener(
        _editingFocusChanged,
      );
      _effectiveFocusNode.addListener(_editingFocusChanged);
    }
  }

  void _editingFocusChanged() => _correctEditingCaret(createParagraph: true);

  void _editingSelectionChanged() => _correctEditingCaret();

  void _correctEditingCaret({
    bool createParagraph = false,
    bool deferred = false,
  }) {
    if (!mounted ||
        _correctingCaret ||
        widget.readOnly ||
        !_effectiveFocusNode.hasFocus) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_caretCorrectionScheduled) {
        _caretCorrectionScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _caretCorrectionScheduled = false;
          _correctEditingCaret(
            createParagraph: createParagraph,
            deferred: true,
          );
        });
      }
      return;
    }
    final controller = widget.controller.quillController;
    final previous = _previousEditingSelection;
    final current = controller.selection;
    _correctingCaret = true;
    try {
      final mayCreateParagraph = createParagraph;
      final corrected = widget.controller.placeCaretOutsideBlock(
        backwards:
            !createParagraph &&
            previous != null &&
            current.extentOffset < previous.extentOffset,
        // Selection updates (including undo/redo) never insert document text.
        // Focus and actual typing can create a missing paragraph explicitly.
        createParagraph: deferred && mayCreateParagraph,
      );
      // replaceText/compose may notify before their final caret is installed.
      // Wait until that edit completes before inserting a missing paragraph.
      if (!corrected &&
          !deferred &&
          mayCreateParagraph &&
          current.isCollapsed &&
          widget.controller.isBlockEmbedAtOffset(current.extentOffset) &&
          !_caretCorrectionScheduled) {
        _caretCorrectionScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _caretCorrectionScheduled = false;
          _correctEditingCaret(
            createParagraph: createParagraph,
            deferred: true,
          );
        });
      }
      _previousEditingSelection = controller.selection;
    } finally {
      _correctingCaret = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = _effectiveFocusNode;
    final scrollController = _effectiveScrollController;
    final resolveImage = widget.resolveImage;
    final resolveAssetPath = widget.resolveAssetPath;
    final audioPlayback = widget.audioPlayback;
    final onOpenAsset = widget.onOpenAsset;
    final onCopyImage = widget.onCopyImage;
    final onEditImage = widget.onEditImage;
    final onViewImageOriginal = widget.onViewImageOriginal;
    final onShowImageDetails = widget.onShowImageDetails;
    final readOnly = widget.readOnly;
    final placeholder = widget.placeholder;
    controller.quillController.readOnly = readOnly;
    void dismissEditorFocus() {
      focusNode.unfocus(disposition: UnfocusDisposition.scope);
    }

    bool handleAssetTap(
      Offset globalPosition,
      TextPosition Function(Offset offset) getPosition, {
      required bool toggleImageSelection,
    }) {
      if (toggleImageSelection && !readOnly && controller.endsWithBlockEmbed) {
        final rawEditor =
            _quillEditorKey.currentState?.editableTextKey.currentState;
        if (rawEditor != null) {
          final lastLine = rawEditor.renderEditor.childAtPosition(
            TextPosition(
              offset: controller.quillController.document.length - 1,
            ),
          );
          final bottom = lastLine
              .localToGlobal(Offset(0, lastLine.size.height))
              .dy;
          if (globalPosition.dy >= bottom &&
              controller.appendParagraphAfterLastEmbed()) {
            rawEditor.requestKeyboard();
            return true;
          }
        }
      }
      final position = getPosition(globalPosition);
      if (!controller.isBlockEmbedAtOffset(position.offset)) {
        if (_activeAssetId != null || _activeBlock != null) {
          setState(() {
            _activeAssetId = null;
            _activeBlock = null;
          });
        }
        return false;
      }
      dismissEditorFocus();
      if (toggleImageSelection) {
        final asset = controller.attachmentAtOffset(position.offset);
        if (asset?.kind == NoteAssetKind.image) {
          if (readOnly) {
            if (asset != null) onOpenAsset?.call(asset);
          } else {
            setState(() {
              _activeBlock = null;
              _activeAssetId = _activeAssetId == asset!.id ? null : asset.id;
            });
          }
        }
      }
      return true;
    }

    final activeAsset = _activeAssetId == null
        ? null
        : controller.asset(_activeAssetId!);
    final activeImage = activeAsset?.kind == NoteAssetKind.image
        ? activeAsset
        : null;
    final activeBlock = _activeBlock;
    final showsContextActions = activeImage != null || activeBlock != null;
    final editor = quill.QuillEditor.basic(
      key: _quillEditorKey,
      controller: controller.quillController,
      focusNode: focusNode,
      scrollController: scrollController,
      config: quill.QuillEditorConfig(
        customStyles: _paperQuillStyles(context),
        autoFocus: widget.autofocus,
        expands: true,
        scrollable: true,
        readOnlyMouseCursor: SystemMouseCursors.text,
        padding: EdgeInsets.fromLTRB(
          24,
          14,
          24,
          (showsContextActions ? 104 : 48) + widget.bottomContentPadding,
        ),
        placeholder: placeholder,
        enableInteractiveSelection: true,
        enableSelectionToolbar: true,
        textInputAction: TextInputAction.newline,
        customLeadingBlockBuilder: _paperLeadingBlockBuilder,
        onTapDown: (details, getPosition) => handleAssetTap(
          details.globalPosition,
          getPosition,
          toggleImageSelection: false,
        ),
        onTapUp: (details, getPosition) => handleAssetTap(
          details.globalPosition,
          getPosition,
          toggleImageSelection: true,
        ),
        embedBuilders: [
          _NoteFileReferencesEmbedBuilder(
            session: controller,
            onInteraction: dismissEditorFocus,
            onDragStarted: _startBlockDrag,
            onDragUpdate: _updateDropLocation,
            onDragEnded: _finishBlockDrag,
          ),
          _NoteAssetEmbedBuilder(
            session: controller,
            resolveImage: resolveImage,
            resolveAssetPath: resolveAssetPath,
            audioPlayback: audioPlayback,
            onOpenAsset: onOpenAsset,
            onTranscribeAudio: widget.onTranscribeAudio,
            selectedAssetId: _activeAssetId,
            onAssetInteraction: dismissEditorFocus,
            onSelectAsset: (id) {
              if (_activeAssetId == id && _activeBlock == null) return;
              setState(() {
                _activeBlock = null;
                _activeAssetId = id;
              });
            },
            onToggleAssetSelection: (id) => setState(() {
              _activeBlock = null;
              _activeAssetId = _activeAssetId == id ? null : id;
            }),
            onAssetDragStarted: _startBlockDrag,
            onAssetDragUpdate: _updateDropLocation,
            onAssetDragEnded: _finishBlockDrag,
          ),
          _NoteDividerEmbedBuilder(
            onInteraction: dismissEditorFocus,
            onToggleActions: (offset) =>
                _toggleBlockActions(NoteEmbedKind.divider, offset),
          ),
          _NoteTableEmbedBuilder(
            onInteraction: dismissEditorFocus,
            onToggleActions: (offset) =>
                _toggleBlockActions(NoteEmbedKind.table, offset),
          ),
        ],
      ),
    );
    final editorDropTarget = DragTarget<_NoteEmbedDragData>(
      onWillAcceptWithDetails: (_) => !readOnly,
      onLeave: (_) => _clearDropLocation(),
      onAcceptWithDetails: (details) {
        final targetOffset = _dropOffset;
        if (targetOffset != null) {
          controller.moveBlockEmbed(
            expectedEmbed: details.data.expectedEmbed,
            sourceOffset: details.data.sourceOffset,
            targetOffset: targetOffset,
          );
        }
        _finishBlockDrag();
      },
      builder: (context, _, _) => Stack(
        key: _editorStackKey,
        fit: StackFit.expand,
        children: [
          editor,
          if ((_draggingBlock != null || _externalImageDragActive) &&
              _dropIndicatorY != null)
            Positioned(
              key: const Key('note-asset-drop-indicator'),
              top: _dropIndicatorY! - 2,
              left: 24,
              right: 24,
              child: const IgnorePointer(child: _AssetDropIndicator()),
            ),
          if (_externalImageDragActive)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('note-external-image-drop-overlay'),
                  decoration: BoxDecoration(
                    color: context.appColors.accentSoft.withValues(alpha: .16),
                    border: Border.all(
                      color: context.appColors.mechanicalBlue.withValues(
                        alpha: .62,
                      ),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.paperSecondary,
                        border: Border(
                          left: BorderSide(
                            color: context.appColors.mechanicalBlue,
                          ),
                          right: BorderSide(color: context.appColors.line),
                          top: BorderSide(color: context.appColors.line),
                          bottom: BorderSide(color: context.appColors.line),
                        ),
                      ),
                      child: Text(
                        context.l10n.releaseToInsertImages,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: context.appColors.mechanicalBlue,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!readOnly &&
              activeImage != null &&
              activeImage.kind == NoteAssetKind.image)
            Positioned(
              left: 24,
              right: 24,
              bottom: 12,
              child: _ImageActionBar(
                key: ValueKey('note-image-actions-${activeImage.id.value}'),
                asset: activeImage,
                onViewOriginal: onViewImageOriginal == null
                    ? null
                    : () => onViewImageOriginal(activeImage),
                onCopy: onCopyImage == null
                    ? null
                    : () => onCopyImage(activeImage),
                onEdit: onEditImage == null
                    ? null
                    : () => onEditImage(activeImage),
                onShowDetails: onShowImageDetails == null
                    ? null
                    : () => onShowImageDetails(activeImage),
                onRemove: () {
                  controller.removeAsset(activeImage.id);
                  setState(() => _activeAssetId = null);
                },
              ),
            ),
          if (!readOnly && activeBlock != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 12,
              child: _BlockActionBar(
                key: ValueKey(
                  'note-block-actions-${activeBlock.kind.name}-'
                  '${activeBlock.offset}',
                ),
                kind: activeBlock.kind,
                onEdit: activeBlock.kind == NoteEmbedKind.table
                    ? () => _editTable(activeBlock.offset)
                    : null,
                onRemove: () {
                  controller.removeEmbedAt(activeBlock.offset);
                  setState(() => _activeBlock = null);
                },
              ),
            ),
        ],
      ),
    );
    final onDropImages = widget.onDropImages;
    if (readOnly || onDropImages == null) return editorDropTarget;
    return NoteExternalImageDropRegion(
      enabled: !readOnly,
      captureDocumentOffset: _captureExternalDropOffset,
      onDropImages: onDropImages,
      onDropActiveChanged: _setExternalImageDragActive,
      child: editorDropTarget,
    );
  }

  Future<void> _editTable(int offset) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final table = widget.controller.tableAtOffset(offset);
    if (table == null) {
      if (mounted) setState(() => _activeBlock = null);
      return;
    }
    final result = await AppOverlay.bottomSheet<NoteTable>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NoteTableEditorSheet(initial: table),
    );
    if (!mounted || result == null) return;
    final replaced = widget.controller.replaceTableAt(offset, result);
    setState(() {
      _activeBlock = replaced
          ? (kind: NoteEmbedKind.table, offset: offset)
          : null;
    });
  }

  void _toggleBlockActions(NoteEmbedKind kind, int offset) {
    setState(() {
      _activeAssetId = null;
      final active = _activeBlock;
      _activeBlock = active?.kind == kind && active?.offset == offset
          ? null
          : (kind: kind, offset: offset);
    });
  }

  void _startBlockDrag(_NoteEmbedDragData data) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activeAssetId = null;
      _activeBlock = null;
      _draggingBlock = data;
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  void _finishBlockDrag() {
    if (!mounted ||
        (_draggingBlock == null &&
            _dropOffset == null &&
            _dropIndicatorY == null)) {
      return;
    }
    setState(() {
      _draggingBlock = null;
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  void _clearDropLocation() {
    if (!mounted || (_dropOffset == null && _dropIndicatorY == null)) return;
    setState(() {
      _dropOffset = null;
      _dropIndicatorY = null;
    });
  }

  int? _captureExternalDropOffset(Offset globalOffset) {
    final stackBox =
        _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        !stackBox.paintBounds.contains(stackBox.globalToLocal(globalOffset))) {
      _clearDropLocation();
      return null;
    }
    _updateDropLocation(globalOffset);
    final dropOffset = _dropOffset;
    if (dropOffset != null) return dropOffset;
    final selection = widget.controller.quillController.selection;
    final fallbackOffset = selection.extentOffset < 0
        ? 0
        : selection.extentOffset;
    return widget.controller.blockDropOffsetFor(
      fallbackOffset,
      afterLine: true,
    );
  }

  void _setExternalImageDragActive(bool active) {
    if (!mounted || _externalImageDragActive == active) return;
    setState(() {
      _externalImageDragActive = active;
      if (!active && _draggingBlock == null) {
        _dropOffset = null;
        _dropIndicatorY = null;
      }
    });
  }

  void _updateDropLocation(Offset globalOffset) {
    final editorState = _quillEditorKey.currentState;
    final rawEditorState = editorState?.editableTextKey.currentState;
    final stackBox =
        _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (rawEditorState == null || stackBox == null || !mounted) return;
    final stackLocal = stackBox.globalToLocal(globalOffset);
    if (!stackBox.paintBounds.contains(stackLocal)) {
      _clearDropLocation();
      return;
    }
    final renderEditor = rawEditorState.renderEditor;
    final position = renderEditor.getPositionForOffset(globalOffset);
    final caret = renderEditor.getLocalRectForCaret(position);
    final localDrag = renderEditor.globalToLocal(globalOffset);
    final afterLine = localDrag.dy >= caret.center.dy;
    final targetOffset = widget.controller.blockDropOffsetFor(
      position.offset,
      afterLine: afterLine,
    );
    final indicatorGlobal = renderEditor.localToGlobal(
      Offset(caret.left, afterLine ? caret.bottom : caret.top),
    );
    final indicatorY = stackBox
        .globalToLocal(indicatorGlobal)
        .dy
        .clamp(6.0, stackBox.size.height - 6.0);
    _autoScrollForDrag(globalOffset, stackBox);
    if (_dropOffset == targetOffset &&
        _dropIndicatorY != null &&
        (_dropIndicatorY! - indicatorY).abs() < .5) {
      return;
    }
    setState(() {
      _dropOffset = targetOffset;
      _dropIndicatorY = indicatorY;
    });
  }

  void _autoScrollForDrag(Offset globalOffset, RenderBox stackBox) {
    final scrollController = _effectiveScrollController;
    if (!scrollController.hasClients) return;
    final local = stackBox.globalToLocal(globalOffset);
    const edge = 72.0;
    final delta = local.dy < edge
        ? -18.0
        : local.dy > stackBox.size.height - edge
        ? 18.0
        : 0.0;
    if (delta == 0) return;
    final position = scrollController.position;
    scrollController.jumpTo(
      (scrollController.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.quillController.removeListener(_editingSelectionChanged);
    _effectiveFocusNode.removeListener(_editingFocusChanged);
    _fallbackFocusNode.dispose();
    _fallbackScrollController.dispose();
    super.dispose();
  }
}

final class NoteQuillToolbar extends StatelessWidget {
  const NoteQuillToolbar({
    required this.controller,
    this.onOpenAssistant,
    this.onInsertImage,
    this.onInsertVideo,
    this.onInsertFileReferences,
    this.onRecordAudio,
    this.onDone,
    this.assistantTooltip = 'AI 创作',
    this.imageTooltip = '插入图片',
    this.videoTooltip = '插入视频',
    this.recordTooltip = '录音',
    this.dividerTooltip = '插入分隔线',
    this.doneLabel,
    super.key,
  });

  final NoteEditorController controller;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onInsertImage;
  final VoidCallback? onInsertVideo;
  final VoidCallback? onInsertFileReferences;
  final VoidCallback? onRecordAudio;
  final VoidCallback? onDone;
  final String assistantTooltip;
  final String imageTooltip;
  final String videoTooltip;
  final String recordTooltip;
  final String dividerTooltip;
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final quillController = controller.quillController;
    final labels = quill.FlutterQuillLocalizations.of(context)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.paperPrimary,
        border: Border(top: BorderSide(color: context.appColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('quill-toolbar-scroll-view'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: const Key('quill-toolbar-actions'),
                    children: [
                      if (onOpenAssistant != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-open-inline-assistant'),
                          tooltip: assistantTooltip,
                          onPressed: onOpenAssistant!,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      if (onInsertFileReferences != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-insert-file-references'),
                          tooltip: context.l10n.fileReferencesSelect,
                          onPressed: onInsertFileReferences!,
                          icon: Icons.attach_file_rounded,
                        ),
                      if (onInsertImage != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-insert-image'),
                          tooltip: imageTooltip,
                          onPressed: onInsertImage!,
                          icon: Icons.image_outlined,
                        ),
                      if (onInsertVideo != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-insert-video'),
                          tooltip: videoTooltip,
                          onPressed: onInsertVideo!,
                          icon: Icons.video_library_outlined,
                        ),
                      if (onRecordAudio != null)
                        _NoteToolbarActionButton(
                          key: const Key('quill-record-audio'),
                          tooltip: recordTooltip,
                          onPressed: onRecordAudio!,
                          icon: Icons.graphic_eq_rounded,
                        ),
                      quill.QuillToolbarHistoryButton(
                        key: const Key('quill-toolbar-undo'),
                        controller: quillController,
                        isUndo: true,
                        options: quill.QuillToolbarHistoryButtonOptions(
                          childBuilder:
                              _quillChild<
                                quill.QuillToolbarHistoryButtonExtraOptions
                              >(
                                (extra) => _NoteToolbarActionButton(
                                  tooltip: labels.undo,
                                  icon: Icons.undo_outlined,
                                  onPressed: extra.canPressed
                                      ? extra.onPressed
                                      : null,
                                ),
                              ),
                        ),
                      ),
                      quill.QuillToolbarHistoryButton(
                        key: const Key('quill-toolbar-redo'),
                        controller: quillController,
                        isUndo: false,
                        options: quill.QuillToolbarHistoryButtonOptions(
                          childBuilder:
                              _quillChild<
                                quill.QuillToolbarHistoryButtonExtraOptions
                              >(
                                (extra) => _NoteToolbarActionButton(
                                  tooltip: labels.redo,
                                  icon: Icons.redo_outlined,
                                  onPressed: extra.canPressed
                                      ? extra.onPressed
                                      : null,
                                ),
                              ),
                        ),
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-bold'),
                        controller: quillController,
                        attribute: quill.Attribute.bold,
                        options: _outlineStyleOptions(
                          Icons.format_bold,
                          labels.bold,
                        ),
                      ),
                      quill.QuillToolbarToggleCheckListButton(
                        key: const Key('quill-toolbar-checklist'),
                        controller: quillController,
                        options: quill.QuillToolbarToggleCheckListButtonOptions(
                          childBuilder:
                              _quillChild<
                                quill.QuillToolbarToggleCheckListButtonExtraOptions
                              >(
                                (extra) => _NoteToolbarActionButton(
                                  tooltip: labels.checkedList,
                                  icon: Icons.check_box,
                                  onPressed: extra.onPressed,
                                  isSelected: extra.isToggled,
                                ),
                              ),
                        ),
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-bullets'),
                        controller: quillController,
                        attribute: quill.Attribute.ul,
                        options: _outlineStyleOptions(
                          Icons.format_list_bulleted,
                          labels.bulletList,
                        ),
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-numbered-list'),
                        controller: quillController,
                        attribute: quill.Attribute.ol,
                        options: _outlineStyleOptions(
                          Icons.format_list_numbered,
                          labels.numberedList,
                        ),
                      ),
                      for (final increase in [true, false])
                        quill.QuillToolbarIndentButton(
                          key: Key(
                            increase
                                ? 'quill-toolbar-indent-increase'
                                : 'quill-toolbar-indent-decrease',
                          ),
                          controller: quillController,
                          isIncrease: increase,
                          options: quill.QuillToolbarIndentButtonOptions(
                            childBuilder:
                                _quillChild<
                                  quill.QuillToolbarIndentButtonExtraOptions
                                >(
                                  (extra) => _NoteToolbarActionButton(
                                    tooltip: increase
                                        ? labels.increaseIndent
                                        : labels.decreaseIndent,
                                    icon: increase
                                        ? Icons.format_indent_increase
                                        : Icons.format_indent_decrease,
                                    onPressed: extra.controller.readOnly
                                        ? null
                                        : extra.onPressed,
                                  ),
                                ),
                          ),
                        ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-quote'),
                        controller: quillController,
                        attribute: quill.Attribute.blockQuote,
                        options: _outlineStyleOptions(
                          Icons.format_quote,
                          labels.quote,
                        ),
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-italic'),
                        controller: quillController,
                        attribute: quill.Attribute.italic,
                        options: _outlineStyleOptions(
                          Icons.format_italic,
                          labels.italic,
                        ),
                      ),
                      quill.QuillToolbarToggleStyleButton(
                        key: const Key('quill-toolbar-underline'),
                        controller: quillController,
                        attribute: quill.Attribute.underline,
                        options: _outlineStyleOptions(
                          Icons.format_underline,
                          labels.underline,
                        ),
                      ),
                      quill.QuillToolbarSelectHeaderStyleDropdownButton(
                        key: const Key('quill-toolbar-heading'),
                        controller: quillController,
                        options:
                            quill.QuillToolbarSelectHeaderStyleDropdownButtonOptions(
                              childBuilder:
                                  _quillChild<
                                    quill.QuillToolbarSelectHeaderStyleDropdownButtonExtraOptions
                                  >(
                                    (extra) => _NoteToolbarHeadingButton(
                                      controller: extra.controller,
                                      currentValue: extra.currentValue,
                                    ),
                                  ),
                            ),
                      ),
                      _NoteToolbarLinkButton(
                        key: const Key('quill-toolbar-link'),
                        controller: quillController,
                        tooltip: labels.link,
                      ),
                      _NoteToolbarActionButton(
                        key: const Key('quill-toolbar-divider'),
                        tooltip: dividerTooltip,
                        onPressed: controller.insertDivider,
                        icon: Icons.horizontal_rule_rounded,
                      ),
                      quill.QuillToolbarClearFormatButton(
                        key: const Key('quill-toolbar-clear-format'),
                        controller: quillController,
                        options: quill.QuillToolbarClearFormatButtonOptions(
                          childBuilder:
                              _quillChild<
                                quill.QuillToolbarClearFormatButtonExtraOptions
                              >(
                                (extra) => _NoteToolbarActionButton(
                                  tooltip: labels.clearFormat,
                                  icon: Icons.format_clear,
                                  onPressed: extra.onPressed,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (doneLabel case final label?)
                _NoteToolbarDoneButton(label: label, onPressed: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

// Quill 11.5's options resolver erases the builder's generic parameters. This
// bridge accepts that raw signature, then restores the correct state type.
Widget Function(dynamic, dynamic) _quillChild<E>(Widget Function(E) builder) =>
    (dynamic _, dynamic extra) => builder(extra as E);

// Keep Quill's own callbacks and selection tracking; only replace the visuals.
quill.QuillToolbarToggleStyleButtonOptions _outlineStyleOptions(
  IconData icon,
  String tooltip,
) => quill.QuillToolbarToggleStyleButtonOptions(
  childBuilder: _quillChild<quill.QuillToolbarToggleStyleButtonExtraOptions>(
    (extra) => _NoteToolbarActionButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: extra.onPressed,
      isSelected: extra.isToggled,
    ),
  ),
);

final class _NoteToolbarHeadingButton extends StatelessWidget {
  const _NoteToolbarHeadingButton({
    required this.controller,
    required this.currentValue,
  });

  final quill.QuillController controller;
  final quill.Attribute currentValue;

  @override
  Widget build(BuildContext context) {
    final labels = quill.FlutterQuillLocalizations.of(context)!;
    String label(quill.Attribute attribute) => switch (attribute) {
      quill.Attribute.h1 => labels.heading1,
      quill.Attribute.h2 => labels.heading2,
      quill.Attribute.h3 => labels.heading3,
      quill.Attribute.h4 => labels.heading4,
      quill.Attribute.h5 => labels.heading5,
      quill.Attribute.h6 => labels.heading6,
      _ => labels.normal,
    };
    return AppAnchoredMenuButton<quill.Attribute>(
      tooltip: labels.headerStyle,
      onSelected: controller.formatSelection,
      actions: [
        for (final attribute in [
          quill.Attribute.h1,
          quill.Attribute.h2,
          quill.Attribute.h3,
          quill.Attribute.header,
        ])
          AppMenuAction(
            value: attribute,
            label: label(attribute),
            selected: currentValue == attribute,
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label(currentValue),
                style: TextStyle(fontSize: 14, color: context.appColors.muted),
              ),
              const SizedBox(width: 4),
              AppIcon(
                Icons.expand_more_rounded,
                size: 18,
                color: context.appColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _NoteToolbarDoneButton extends StatelessWidget {
  const _NoteToolbarDoneButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 28,
        child: VerticalDivider(
          width: 9,
          thickness: 1,
          color: context.appColors.line,
        ),
      ),
      SizedBox(
        height: 44,
        child: TextButton(
          key: const Key('quill-toolbar-done'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: context.appColors.ink,
            disabledForegroundColor: context.appColors.muted,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 44),
            shape: const RoundedRectangleBorder(),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ],
  );
}

final class _NoteToolbarActionButton extends StatelessWidget {
  const _NoteToolbarActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.isSelected = false,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: isSelected,
    color: isSelected ? context.appColors.ink : context.appColors.muted,
    disabledColor: context.appColors.subtle,
    style: isSelected
        ? ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(
              context.appColors.surfaceMuted,
            ),
          )
        : null,
    iconSize: 21,
    padding: const EdgeInsets.all(10),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: AppIcon(icon),
  );
}

final class _NoteToolbarLinkButton extends StatefulWidget {
  const _NoteToolbarLinkButton({
    required this.controller,
    required this.tooltip,
    super.key,
  });

  final quill.QuillController controller;
  final String tooltip;

  @override
  State<_NoteToolbarLinkButton> createState() => _NoteToolbarLinkButtonState();
}

final class _NoteToolbarLinkButtonState extends State<_NoteToolbarLinkButton> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant _NoteToolbarLinkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSheet() async {
    final initial = quill.QuillTextLink.prepare(widget.controller);
    final result = await showNoteLinkEditorSheet(
      context,
      initialText: initial.text,
      initialLink: initial.link,
    );
    if (result == null || !mounted) return;
    result.submit(widget.controller);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _NoteToolbarActionButton(
    tooltip: widget.tooltip,
    icon: Icons.link,
    isSelected: quill.QuillTextLink.isSelected(widget.controller),
    onPressed: () => unawaited(_openSheet()),
  );
}

final class _NoteEmbedDragData {
  const _NoteEmbedDragData({
    required this.expectedEmbed,
    required this.sourceOffset,
  });

  final NoteEmbed expectedEmbed;
  final int sourceOffset;
}

final class _NoteFileReferencesEmbedBuilder extends quill.EmbedBuilder {
  const _NoteFileReferencesEmbedBuilder({
    required this.session,
    this.onInteraction,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnded,
  });
  final NoteEditorController session;
  final VoidCallback? onInteraction;
  final ValueChanged<_NoteEmbedDragData>? onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnded;

  @override
  String get key => NoteEmbed.fileReferencesType;

  @override
  String toPlainText(quill.Embed node) =>
      NoteEmbed.parse(node.value.toJson()).fileReferenceText;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embed = NoteEmbed.parse(embedContext.node.value.toJson());
    final card = NoteFileReferenceCard(
      references: embed.fileReferences,
      onInteraction: onInteraction,
      onRemove: embedContext.readOnly
          ? null
          : () => session.removeEmbedAt(embedContext.node.documentOffset),
    );
    if (embedContext.readOnly || onDragStarted == null) return card;
    return _MovableNoteEmbed(
      key: ValueKey(
        'move-note-file-references-${embedContext.node.documentOffset}',
      ),
      label: context.l10n.fileReferences,
      hint: context.l10n.moveFileReferencesHint,
      data: _NoteEmbedDragData(
        expectedEmbed: embed,
        sourceOffset: embedContext.node.documentOffset,
      ),
      onDragStarted: onDragStarted!,
      onDragUpdate: onDragUpdate!,
      onDragEnded: onDragEnded!,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width - 48, 320),
          child: NoteFileReferenceCard(references: embed.fileReferences),
        ),
      ),
      child: card,
    );
  }
}

final class _NoteAssetEmbedBuilder extends quill.EmbedBuilder {
  const _NoteAssetEmbedBuilder({
    required this.session,
    required this.resolveImage,
    required this.resolveAssetPath,
    required this.audioPlayback,
    required this.onOpenAsset,
    required this.onTranscribeAudio,
    required this.selectedAssetId,
    required this.onAssetInteraction,
    required this.onSelectAsset,
    required this.onToggleAssetSelection,
    required this.onAssetDragStarted,
    required this.onAssetDragUpdate,
    required this.onAssetDragEnded,
  });

  final NoteEditorController session;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteAudioPlaybackDriver? audioPlayback;
  final ValueChanged<NoteAsset>? onOpenAsset;
  final ValueChanged<NoteAsset>? onTranscribeAudio;
  final NoteAttachmentId? selectedAssetId;
  final VoidCallback onAssetInteraction;
  final ValueChanged<NoteAttachmentId> onSelectAsset;
  final ValueChanged<NoteAttachmentId> onToggleAssetSelection;
  final ValueChanged<_NoteEmbedDragData> onAssetDragStarted;
  final ValueChanged<Offset> onAssetDragUpdate;
  final VoidCallback onAssetDragEnded;

  @override
  String get key => NoteEmbed.attachmentType;

  @override
  String toPlainText(quill.Embed node) {
    final embed = NoteEmbed.parse(node.value.toJson());
    final asset = session.asset(embed.attachmentId!);
    return asset == null ? '【附件】' : '【${asset.displayTitle}】';
  }

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embed = NoteEmbed.parse(embedContext.node.value.toJson());
    final asset = session.asset(embed.attachmentId!);
    if (asset == null) {
      return const _MissingAssetCard();
    }
    final imageProvider = asset.kind == NoteAssetKind.image
        ? resolveImage?.call(asset)
        : null;
    final Widget block;
    if (asset.kind == NoteAssetKind.image) {
      block = _ImageAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        provider: imageProvider,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: onAssetInteraction,
        onToggleSelection: () => onToggleAssetSelection(asset.id),
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
      );
    } else if (asset.kind == NoteAssetKind.audio) {
      block = _AudioAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        filePath: resolveAssetPath?.call(asset),
        playback: audioPlayback,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: onAssetInteraction,
        onSelect: () => onSelectAsset(asset.id),
        onToggleSelection: () => onToggleAssetSelection(asset.id),
        onRename: (displayName) {
          final current = session.asset(asset.id);
          if (current != null) {
            session.updateAsset(current.copyWith(displayName: displayName));
          }
        },
        onTranscribe: onTranscribeAudio == null
            ? null
            : () => onTranscribeAudio!(asset),
        onRemove: () {
          if (audioPlayback?.activeAssetId == asset.id.value) {
            unawaited(audioPlayback?.stop());
          }
          session.removeEmbedAt(embedContext.node.documentOffset);
        },
      );
    } else if (asset.kind == NoteAssetKind.video) {
      block = _VideoAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: onAssetInteraction,
        onToggleSelection: () => onToggleAssetSelection(asset.id),
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
        onRename: (displayName) =>
            session.updateAsset(asset.copyWith(displayName: displayName)),
        onRemove: () => session.removeEmbedAt(embedContext.node.documentOffset),
      );
    } else {
      return _FileAssetBlock(
        key: ValueKey('note-asset-${asset.id.value}'),
        asset: asset,
        readOnly: embedContext.readOnly,
        selected: selectedAssetId == asset.id,
        onInteraction: () {
          onAssetInteraction();
          onToggleAssetSelection(asset.id);
        },
        onOpen: onOpenAsset == null ? null : () => onOpenAsset!(asset),
        onRemove: () => session.removeEmbedAt(embedContext.node.documentOffset),
      );
    }

    if (embedContext.readOnly) return block;
    return _MovableNoteEmbed(
      key: ValueKey('move-note-asset-${asset.id.value}'),
      label: asset.displayTitle,
      hint: context.l10n.moveAttachmentHint,
      feedback: _AssetDragFeedback(
        asset: asset,
        imageProvider: imageProvider,
        width: math.min(MediaQuery.sizeOf(context).width - 48, 320),
      ),
      data: _NoteEmbedDragData(
        expectedEmbed: NoteEmbed.attachment(asset.id),
        sourceOffset: embedContext.node.documentOffset,
      ),
      onDragStarted: onAssetDragStarted,
      onDragUpdate: onAssetDragUpdate,
      onDragEnded: onAssetDragEnded,
      child: block,
    );
  }
}

final class _MovableNoteEmbed extends StatelessWidget {
  const _MovableNoteEmbed({
    required this.label,
    required this.hint,
    required this.feedback,
    required this.data,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.child,
    super.key,
  });

  final String label;
  final String hint;
  final Widget feedback;
  final _NoteEmbedDragData data;
  final ValueChanged<_NoteEmbedDragData> onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    hint: hint,
    child: LongPressDraggable<_NoteEmbedDragData>(
      data: data,
      delay: const Duration(milliseconds: 360),
      hapticFeedbackOnStart: true,
      rootOverlay: true,
      onDragStarted: () => onDragStarted(data),
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnded(),
      feedback: feedback,
      childWhenDragging: Opacity(opacity: .26, child: child),
      child: child,
    ),
  );
}

final class _AssetDragFeedback extends StatelessWidget {
  const _AssetDragFeedback({
    required this.asset,
    required this.imageProvider,
    required this.width,
  });

  final NoteAsset asset;
  final ImageProvider? imageProvider;
  final double width;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      width: width,
      constraints: const BoxConstraints(maxHeight: 190),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: context.appColors.accent, width: 1.5),
        boxShadow: context.appColors.floatingShadows,
      ),
      child: asset.kind == NoteAssetKind.image
          ? imageProvider == null
                ? _AssetFallback(asset: asset, minHeight: 130)
                : Image(
                    image: imageProvider!,
                    height: 170,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _AssetFallback(asset: asset, minHeight: 130),
                  )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  AppIcon(
                    switch (asset.kind) {
                      NoteAssetKind.audio => Icons.graphic_eq_rounded,
                      NoteAssetKind.video => Icons.video_library_outlined,
                      NoteAssetKind.image => Icons.image_outlined,
                      NoteAssetKind.file => Icons.insert_drive_file_outlined,
                    },
                    color: context.appColors.accent,
                    size: 27,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      asset.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

final class _AssetDropIndicator extends StatelessWidget {
  const _AssetDropIndicator();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.accent,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
      Expanded(
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: context.appColors.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.accent,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
    ],
  );
}

enum _AudioAssetAction { rename, transcribe, remove }

enum _VideoAssetAction { rename, remove }

final class _AssetSelectionFrame extends StatelessWidget {
  const _AssetSelectionFrame({
    required this.asset,
    required this.selected,
    required this.borderRadius,
    required this.child,
  });

  final NoteAsset asset;
  final bool selected;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Keep the interactive subtree mounted while pointer-down selects a card.
    // Reparenting it into a new Stack used to lose the first menu tap.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('note-asset-selection-${asset.id.value}'),
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(color: context.appColors.accent, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _AudioAssetBlock extends StatelessWidget {
  const _AudioAssetBlock({
    required this.asset,
    required this.filePath,
    required this.playback,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onSelect,
    required this.onToggleSelection,
    required this.onRename,
    required this.onTranscribe,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final String? filePath;
  final NoteAudioPlaybackDriver? playback;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback onSelect;
  final VoidCallback onToggleSelection;
  final ValueChanged<String?> onRename;
  final VoidCallback? onTranscribe;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final driver = playback;
    final content = (driver == null)
        ? _buildCard(context, null)
        : ListenableBuilder(
            listenable: driver,
            builder: (context, _) => _buildCard(context, driver),
          );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onInteraction(),
      child: GestureDetector(
        key: ValueKey('note-audio-selection-target-${asset.id.value}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onInteraction();
          onToggleSelection();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: content,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, NoteAudioPlaybackDriver? driver) {
    final active = driver?.activeAssetId == asset.id.value;
    final status = active ? driver!.status : NoteAudioPlaybackStatus.idle;
    final loading = status == NoteAudioPlaybackStatus.loading;
    final playing = status == NoteAudioPlaybackStatus.playing;
    final failed = status == NoteAudioPlaybackStatus.failed;
    final storedDuration = Duration(milliseconds: asset.durationMs ?? 0);
    final duration = active && driver!.duration > Duration.zero
        ? driver.duration
        : storedDuration;
    final position = active ? driver!.position : Duration.zero;
    final maximum = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();

    return Semantics(
      label: '${context.l10n.record}：${asset.displayTitle}',
      selected: selected,
      child: _AssetSelectionFrame(
        asset: asset,
        selected: selected,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Material(
          color: context.appColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            side: BorderSide(color: context.appColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 180) {
                return _buildCompactPreview(context, duration);
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    IconButton(
                      key: ValueKey('play-note-audio-${asset.id.value}'),
                      tooltip: playing
                          ? context.l10n.pauseRecording
                          : context.l10n.playRecording,
                      onPressed: driver == null || filePath == null
                          ? null
                          : () {
                              onInteraction();
                              onSelect();
                              unawaited(
                                driver.toggle(
                                  assetId: asset.id.value,
                                  filePath: filePath!,
                                ),
                              );
                            },
                      style: IconButton.styleFrom(
                        backgroundColor: context.appColors.accentSoft,
                        foregroundColor: context.appColors.accent,
                        disabledBackgroundColor: context.appColors.surfaceMuted,
                        fixedSize: const Size.square(44),
                      ),
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : AppIcon(
                              playing
                                  ? Icons.pause_rounded
                                  : failed
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                failed
                                    ? context.l10n.recordingPlaybackFailed
                                    : _formatAudioDuration(position),
                                style: TextStyle(
                                  color: failed
                                      ? context.appColors.danger
                                      : context.appColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                      disabledThumbRadius: 4,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                  ),
                                  child: Slider(
                                    key: ValueKey(
                                      'note-audio-progress-${asset.id.value}',
                                    ),
                                    value: value,
                                    max: maximum,
                                    onChanged:
                                        !active ||
                                            driver == null ||
                                            duration <= Duration.zero
                                        ? null
                                        : (next) {
                                            onInteraction();
                                            onSelect();
                                            unawaited(
                                              driver.seek(
                                                assetId: asset.id.value,
                                                position: Duration(
                                                  milliseconds: next.round(),
                                                ),
                                              ),
                                            );
                                          },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatAudioDuration(duration),
                                style: TextStyle(
                                  color: context.appColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!readOnly)
                      Listener(
                        onPointerDown: (_) {
                          onInteraction();
                          onSelect();
                        },
                        child: AppAnchoredMenuButton<_AudioAssetAction>(
                          key: ValueKey('note-audio-actions-${asset.id.value}'),
                          tooltip: context.l10n.recordingActions,
                          icon: const AppIcon(
                            Icons.more_vert_rounded,
                            size: 20,
                          ),
                          actions: [
                            AppMenuAction(
                              value: _AudioAssetAction.rename,
                              icon: Icons.edit_outlined,
                              label: context.l10n.renameAttachment,
                            ),
                            AppMenuAction(
                              value: _AudioAssetAction.transcribe,
                              icon: Icons.graphic_eq_rounded,
                              label: context.l10n.recognizeAudio,
                              enabled: onTranscribe != null,
                            ),
                            AppMenuAction(
                              value: _AudioAssetAction.remove,
                              icon: Icons.delete_outline_rounded,
                              label: context.l10n.remove,
                              destructive: true,
                            ),
                          ],
                          onSelected: (action) {
                            onInteraction();
                            onSelect();
                            switch (action) {
                              case _AudioAssetAction.rename:
                                unawaited(_rename(context));
                              case _AudioAssetAction.transcribe:
                                onTranscribe?.call();
                              case _AudioAssetAction.remove:
                                onRemove();
                            }
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPreview(BuildContext context, Duration duration) =>
      Padding(
        key: ValueKey('compact-note-audio-${asset.id.value}'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Row(
          children: [
            AppIcon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: context.appColors.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                asset.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (duration > Duration.zero) ...[
              const SizedBox(width: 5),
              Text(
                _formatAudioDuration(duration),
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );

  Future<void> _rename(BuildContext context) async {
    final result = await showNoteAttachmentTitleSheet(
      context,
      initialValue: asset.displayTitle,
      fieldKey: const Key('audio-attachment-title'),
    );
    if (result != null) onRename(result.displayName);
  }
}

final class _NoteDividerEmbedBuilder extends quill.EmbedBuilder {
  const _NoteDividerEmbedBuilder({
    required this.onInteraction,
    required this.onToggleActions,
  });

  final VoidCallback onInteraction;
  final ValueChanged<int> onToggleActions;

  @override
  String get key => NoteEmbed.dividerType;

  @override
  String toPlainText(quill.Embed node) => '——';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) =>
      Semantics(
        label: context.l10n.divider,
        button: !embedContext.readOnly,
        child: GestureDetector(
          key: ValueKey('note-divider-${embedContext.node.documentOffset}'),
          behavior: HitTestBehavior.opaque,
          onTap: embedContext.readOnly
              ? null
              : () {
                  onInteraction();
                  onToggleActions(embedContext.node.documentOffset);
                },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: context.appColors.line),
          ),
        ),
      );
}

final class _NoteTableEmbedBuilder extends quill.EmbedBuilder {
  const _NoteTableEmbedBuilder({
    required this.onInteraction,
    required this.onToggleActions,
  });

  final VoidCallback onInteraction;
  final ValueChanged<int> onToggleActions;

  @override
  String get key => NoteEmbed.tableType;

  @override
  String toPlainText(quill.Embed node) =>
      NoteEmbed.parse(node.value.toJson()).table!.plainText;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final table = NoteEmbed.parse(embedContext.node.value.toJson()).table!;
    final offset = embedContext.node.documentOffset;
    return _NoteTableBlock(
      key: ValueKey('note-table-$offset'),
      table: table,
      readOnly: embedContext.readOnly,
      onTap: () {
        onInteraction();
        onToggleActions(offset);
      },
    );
  }
}

final class _NoteTableBlock extends StatelessWidget {
  const _NoteTableBlock({
    required this.table,
    required this.readOnly,
    required this.onTap,
    super.key,
  });

  final NoteTable table;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.tableDimensions(table.columnCount, table.rows.length),
    button: !readOnly,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: readOnly ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(
              constraints.maxWidth,
              table.columnCount * 116.0,
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(color: context.appColors.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Table(
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: context.appColors.line,
                        ),
                        verticalInside: BorderSide(
                          color: context.appColors.line,
                        ),
                      ),
                      children: [
                        for (
                          var rowIndex = 0;
                          rowIndex < table.rows.length;
                          rowIndex++
                        )
                          TableRow(
                            decoration: rowIndex == 0
                                ? BoxDecoration(
                                    color: context.appColors.surfaceMuted,
                                  )
                                : null,
                            children: [
                              for (
                                var columnIndex = 0;
                                columnIndex < table.columnCount;
                                columnIndex++
                              )
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    table.rows[rowIndex][columnIndex],
                                    textAlign: switch (table
                                        .alignments[columnIndex]) {
                                      NoteTableAlignment.start =>
                                        TextAlign.start,
                                      NoteTableAlignment.center =>
                                        TextAlign.center,
                                      NoteTableAlignment.end => TextAlign.end,
                                    },
                                    style: TextStyle(
                                      color: context.appColors.ink,
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: rowIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

final class _ImageAssetBlock extends StatelessWidget {
  const _ImageAssetBlock({
    required this.asset,
    required this.provider,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onToggleSelection,
    required this.onOpen,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider? provider;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback onToggleSelection;
  final VoidCallback? onOpen;

  void _handleImageTap() {
    onInteraction();
    if (readOnly) {
      onOpen?.call();
      return;
    }
    onToggleSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '图片：${asset.displayTitle}',
      button: true,
      selected: selected,
      onTap: _handleImageTap,
      child: Padding(
        key: ValueKey('note-image-selection-target-${asset.id.value}'),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: _AssetSelectionFrame(
          asset: asset,
          selected: selected,
          borderRadius: BorderRadius.circular(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: provider == null
                ? _AssetFallback(asset: asset, minHeight: 180)
                : _NaturalRatioImage(
                    key: ValueKey('note-image-${asset.id.value}'),
                    asset: asset,
                    provider: provider!,
                  ),
          ),
        ),
      ),
    );
  }
}

final class _NaturalRatioImage extends StatefulWidget {
  const _NaturalRatioImage({
    required this.asset,
    required this.provider,
    super.key,
  });

  final NoteAsset asset;
  final ImageProvider provider;

  @override
  State<_NaturalRatioImage> createState() => _NaturalRatioImageState();
}

final class _NaturalRatioImageState extends State<_NaturalRatioImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _NaturalRatioImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == stream.key) return;
    _stopListening();
    _imageInfo?.dispose();
    _imageInfo = null;
    _failed = false;
    _stream = stream;
    _listener = ImageStreamListener(
      _handleImage,
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(_listener!);
  }

  void _handleImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final previous = _imageInfo;
    setState(() {
      _imageInfo = info;
      _failed = false;
    });
    previous?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _AssetFallback(asset: widget.asset, minHeight: 180);
    }
    final info = _imageInfo;
    if (info == null) {
      return SizedBox(
        width: double.infinity,
        height: 180,
        child: ColoredBox(
          color: context.appColors.paperSecondary,
          child: Center(
            child: AppIcon(
              Icons.photo_outlined,
              color: context.appColors.subtle,
            ),
          ),
        ),
      );
    }
    final ratio = info.image.width / info.image.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          width: width,
          height: width / ratio,
          child: RawImage(
            image: info.image,
            width: width,
            height: width / ratio,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _stopListening();
    _imageInfo?.dispose();
    super.dispose();
  }
}

final class _ImageActionBar extends StatelessWidget {
  const _ImageActionBar({
    required this.asset,
    required this.onViewOriginal,
    required this.onCopy,
    required this.onEdit,
    required this.onShowDetails,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final Future<void> Function()? onViewOriginal;
  final Future<void> Function()? onCopy;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onShowDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '图片操作：${asset.displayTitle}',
    container: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: context.appColors.line),
        boxShadow: context.appColors.floatingShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Row(
          children: [
            _ImageActionButton(
              key: ValueKey('view-original-note-image-${asset.id.value}'),
              icon: Icons.open_in_full_rounded,
              label: context.l10n.viewOriginalImage,
              onPressed: onViewOriginal == null
                  ? null
                  : () => unawaited(onViewOriginal!()),
            ),
            _ImageActionButton(
              key: ValueKey('copy-note-image-${asset.id.value}'),
              icon: Icons.content_copy_rounded,
              label: context.l10n.copy,
              onPressed: onCopy == null ? null : () => unawaited(onCopy!()),
            ),
            _ImageActionButton(
              key: ValueKey('edit-note-image-${asset.id.value}'),
              icon: Icons.tune_rounded,
              label: context.l10n.imageActions,
              onPressed: onEdit == null ? null : () => unawaited(onEdit!()),
            ),
            _ImageActionButton(
              key: ValueKey('details-note-image-${asset.id.value}'),
              icon: Icons.info_outline_rounded,
              label: context.l10n.details,
              onPressed: onShowDetails == null
                  ? null
                  : () => unawaited(onShowDetails!()),
            ),
            _ImageActionButton(
              key: ValueKey('remove-note-asset-${asset.id.value}'),
              icon: Icons.delete_outline_rounded,
              label: context.l10n.delete,
              destructive: true,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    ),
  );
}

final class _BlockActionBar extends StatelessWidget {
  const _BlockActionBar({
    required this.kind,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final NoteEmbedKind kind;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final table = kind == NoteEmbedKind.table;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: context.appColors.line),
        boxShadow: context.appColors.floatingShadows,
      ),
      child: Padding(
        padding: table
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 7)
            : const EdgeInsets.fromLTRB(14, 7, 8, 7),
        child: table
            ? Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('edit-note-table'),
                      onPressed: onEdit,
                      icon: const AppIcon(Icons.edit_outlined, size: 19),
                      label: Text(context.l10n.editTable),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: context.appColors.line,
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('remove-note-table'),
                      onPressed: onRemove,
                      icon: const AppIcon(
                        Icons.delete_outline_rounded,
                        size: 19,
                      ),
                      label: Text(context.l10n.deleteTable),
                      style: TextButton.styleFrom(
                        foregroundColor: context.appColors.danger,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  AppIcon(
                    Icons.horizontal_rule,
                    size: 20,
                    color: context.appColors.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      context.l10n.divider,
                      style: TextStyle(
                        color: context.appColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('remove-note-${kind.name}'),
                    onPressed: onRemove,
                    icon: const AppIcon(Icons.delete_outline_rounded, size: 19),
                    label: Text(context.l10n.delete),
                    style: TextButton.styleFrom(
                      foregroundColor: context.appColors.danger,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

final class _NoteTableEditorSheet extends StatefulWidget {
  const _NoteTableEditorSheet({required this.initial});

  final NoteTable initial;

  @override
  State<_NoteTableEditorSheet> createState() => _NoteTableEditorSheetState();
}

final class _NoteTableEditorSheetState extends State<_NoteTableEditorSheet> {
  late final List<List<TextEditingController>> _cells;
  late final List<NoteTableAlignment> _alignments;

  int get _columnCount => _cells.first.length;

  @override
  void initState() {
    super.initState();
    _cells = [
      for (final row in widget.initial.rows)
        [for (final value in row) TextEditingController(text: value)],
    ];
    _alignments = [...widget.initial.alignments];
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    if (_cells.length >= NoteTable.maxRows) return;
    setState(() {
      _cells.add(List.generate(_columnCount, (_) => TextEditingController()));
    });
  }

  void _removeRow(int index) {
    if (index == 0 || index >= _cells.length) return;
    setState(() {
      final removed = _cells.removeAt(index);
      for (final controller in removed) {
        controller.dispose();
      }
    });
  }

  void _addColumn() {
    if (_columnCount >= NoteTable.maxColumns) return;
    setState(() {
      for (final row in _cells) {
        row.add(TextEditingController());
      }
      _alignments.add(NoteTableAlignment.start);
    });
  }

  void _removeColumn(int index) {
    if (_columnCount <= 1 || index < 0 || index >= _columnCount) return;
    setState(() {
      for (final row in _cells) {
        row.removeAt(index).dispose();
      }
      _alignments.removeAt(index);
    });
  }

  void _finish() {
    Navigator.pop(
      context,
      NoteTable(
        rows: [
          for (final row in _cells) [for (final cell in row) cell.text],
        ],
        alignments: _alignments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final canAddRow = _cells.length < NoteTable.maxRows;
    final canAddColumn = _columnCount < NoteTable.maxColumns;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: FractionallySizedBox(
        key: const Key('note-table-editor'),
        heightFactor: .86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.editTable,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.tableEditorDescription(
                            _columnCount,
                            _cells.length,
                          ),
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('note-table-add-column'),
                    tooltip: context.l10n.addColumn,
                    onPressed: canAddColumn ? _addColumn : null,
                    icon: const AppIcon(Icons.view_column_outlined),
                  ),
                  IconButton(
                    key: const Key('note-table-add-row'),
                    tooltip: context.l10n.addRow,
                    onPressed: canAddRow ? _addRow : null,
                    icon: const AppIcon(Icons.table_rows_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.appColors.surface,
                          border: Border.all(color: context.appColors.line),
                          borderRadius: BorderRadius.circular(AppRadius.large),
                        ),
                        child: Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.top,
                          columnWidths: {
                            0: const FixedColumnWidth(48),
                            for (
                              var column = 0;
                              column < _columnCount;
                              column++
                            )
                              column + 1: const FixedColumnWidth(190),
                          },
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: context.appColors.line,
                            ),
                            verticalInside: BorderSide(
                              color: context.appColors.line,
                            ),
                          ),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: context.appColors.accentSoft,
                              ),
                              children: [
                                TableCell(
                                  verticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  child: AppIcon(
                                    Icons.view_column_outlined,
                                    size: 19,
                                    color: context.appColors.muted,
                                  ),
                                ),
                                for (
                                  var column = 0;
                                  column < _columnCount;
                                  column++
                                )
                                  _TableHeaderEditorCell(
                                    controller: _cells.first[column],
                                    alignment: _alignments[column],
                                    canRemove: _columnCount > 1,
                                    onAlignmentChanged: (alignment) => setState(
                                      () => _alignments[column] = alignment,
                                    ),
                                    onRemove: () => _removeColumn(column),
                                  ),
                              ],
                            ),
                            for (var row = 1; row < _cells.length; row++)
                              TableRow(
                                decoration: BoxDecoration(
                                  color: row.isEven
                                      ? context.appColors.canvas.withValues(
                                          alpha: .55,
                                        )
                                      : context.appColors.surface,
                                ),
                                children: [
                                  TableCell(
                                    verticalAlignment:
                                        TableCellVerticalAlignment.middle,
                                    child: IconButton(
                                      key: ValueKey(
                                        'note-table-remove-row-$row',
                                      ),
                                      tooltip: context.l10n.deleteRow(row),
                                      onPressed: () => _removeRow(row),
                                      icon: const AppIcon(
                                        Icons.remove_circle_outline_rounded,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                  for (
                                    var column = 0;
                                    column < _columnCount;
                                    column++
                                  )
                                    _TableBodyEditorCell(
                                      key: ValueKey(
                                        'note-table-cell-$row-$column',
                                      ),
                                      controller: _cells[row][column],
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: canAddRow ? _addRow : null,
                    icon: const AppIcon(Icons.add_rounded),
                    label: Text(context.l10n.addRow),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                  FilledButton(
                    key: const Key('note-table-save'),
                    onPressed: _finish,
                    child: Text(context.l10n.saveTable),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TableHeaderEditorCell extends StatelessWidget {
  const _TableHeaderEditorCell({
    required this.controller,
    required this.alignment,
    required this.canRemove,
    required this.onAlignmentChanged,
    required this.onRemove,
  });

  final TextEditingController controller;
  final NoteTableAlignment alignment;
  final bool canRemove;
  final ValueChanged<NoteTableAlignment> onAlignmentChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('note-table-header-${controller.hashCode}'),
                controller: controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                maxLength: NoteTable.maxCellCharacters,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.tableHeader,
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: context.l10n.deleteColumn,
                onPressed: onRemove,
                icon: const AppIcon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 6),
        AppAnchoredMenuButton<NoteTableAlignment>(
          tooltip: context.l10n.cellAlignment,
          onSelected: onAlignmentChanged,
          actions: [
            AppMenuAction(
              value: NoteTableAlignment.start,
              icon: Icons.format_align_left_rounded,
              label: context.l10n.alignLeft,
              selected: alignment == NoteTableAlignment.start,
            ),
            AppMenuAction(
              value: NoteTableAlignment.center,
              icon: Icons.format_align_center_rounded,
              label: context.l10n.alignCenter,
              selected: alignment == NoteTableAlignment.center,
            ),
            AppMenuAction(
              value: NoteTableAlignment.end,
              icon: Icons.format_align_right_rounded,
              label: context.l10n.alignRight,
              selected: alignment == NoteTableAlignment.end,
            ),
          ],
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (alignment) {
                        NoteTableAlignment.start => context.l10n.alignLeft,
                        NoteTableAlignment.center => context.l10n.alignCenter,
                        NoteTableAlignment.end => context.l10n.alignRight,
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const AppIcon(Icons.arrow_drop_down_rounded, size: 19),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

final class _TableBodyEditorCell extends StatelessWidget {
  const _TableBodyEditorCell({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: TextField(
      controller: controller,
      contextMenuBuilder: buildAppEditableTextContextMenu,
      minLines: 1,
      maxLines: 6,
      maxLength: NoteTable.maxCellCharacters,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.content,
        counterText: '',
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 11,
        ),
      ),
    ),
  );
}

final class _ImageActionButton extends StatelessWidget {
  const _ImageActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon,
              size: 19,
              color: destructive
                  ? context.appColors.danger
                  : context.appColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: destructive
                    ? context.appColors.danger
                    : context.appColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatAudioDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

final class _VideoAssetBlock extends StatelessWidget {
  const _VideoAssetBlock({
    required this.asset,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onToggleSelection,
    required this.onOpen,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback onToggleSelection;
  final VoidCallback? onOpen;
  final ValueChanged<String?> onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: '${context.l10n.video}：${asset.displayTitle}',
    child: GestureDetector(
      key: ValueKey('note-video-selection-target-${asset.id.value}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onInteraction();
        if (readOnly) {
          onOpen?.call();
        } else {
          onToggleSelection();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _AssetSelectionFrame(
          asset: asset,
          selected: selected,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Material(
            color: context.appColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: BorderSide(color: context.appColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  key: ValueKey('play-note-video-${asset.id.value}'),
                  onTap: onOpen == null
                      ? null
                      : () {
                          onInteraction();
                          onOpen!();
                        },
                  child: Container(
                    height: 148,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.appColors.surfaceMuted,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          right: 18,
                          top: 18,
                          child: AppIcon(
                            Icons.movie_outlined,
                            size: 62,
                            color: context.appColors.subtle.withValues(
                              alpha: .3,
                            ),
                          ),
                        ),
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: context.appColors.accentSoft,
                            shape: BoxShape.circle,
                            boxShadow: context.appColors.floatingShadows,
                          ),
                          child: AppIcon(
                            Icons.play_arrow_rounded,
                            size: 36,
                            color: context.appColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 7, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              asset.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.appColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (asset.durationMs case final duration?)
                                  _formatAudioDuration(
                                    Duration(milliseconds: duration),
                                  ),
                                _formatAssetBytes(asset.byteLength),
                              ].join(' · '),
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!readOnly)
                        AppAnchoredMenuButton<_VideoAssetAction>(
                          key: ValueKey('note-video-actions-${asset.id.value}'),
                          tooltip: context.l10n.video,
                          icon: const AppIcon(
                            Icons.more_vert_rounded,
                            size: 20,
                          ),
                          actions: [
                            AppMenuAction(
                              value: _VideoAssetAction.rename,
                              icon: Icons.edit_outlined,
                              label: context.l10n.renameAttachment,
                            ),
                            AppMenuAction(
                              value: _VideoAssetAction.remove,
                              icon: Icons.delete_outline_rounded,
                              label: context.l10n.remove,
                              destructive: true,
                            ),
                          ],
                          onSelected: (action) {
                            onInteraction();
                            switch (action) {
                              case _VideoAssetAction.rename:
                                unawaited(_rename(context));
                              case _VideoAssetAction.remove:
                                onRemove();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _rename(BuildContext context) async {
    final result = await showNoteAttachmentTitleSheet(
      context,
      initialValue: asset.displayTitle,
      fieldKey: const Key('video-attachment-title'),
    );
    if (result != null) onRename(result.displayName);
  }
}

String _formatAssetBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

final class _FileAssetBlock extends StatelessWidget {
  const _FileAssetBlock({
    required this.asset,
    required this.readOnly,
    required this.selected,
    required this.onInteraction,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final NoteAsset asset;
  final bool readOnly;
  final bool selected;
  final VoidCallback onInteraction;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: asset.displayTitle,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _AssetSelectionFrame(
        asset: asset,
        selected: selected,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Material(
          color: context.appColors.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              onInteraction();
              onOpen?.call();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: AppIcon(
                      _iconFor(asset.kind),
                      color: context.appColors.accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          asset.mimeType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!readOnly) _RemoveButton(onPressed: onRemove),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  static IconData _iconFor(NoteAssetKind kind) => switch (kind) {
    NoteAssetKind.image => Icons.image_outlined,
    NoteAssetKind.audio => Icons.graphic_eq_rounded,
    NoteAssetKind.video => Icons.play_circle_outline_rounded,
    NoteAssetKind.file => Icons.insert_drive_file_outlined,
  };
}

final class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.appColors.surface.withValues(alpha: .92),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: '移除',
      onPressed: onPressed,
      icon: const AppIcon(Icons.close_rounded, size: 18),
      color: context.appColors.muted,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
    ),
  );
}

final class _AssetFallback extends StatelessWidget {
  const _AssetFallback({required this.asset, required this.minHeight});

  final NoteAsset asset;
  final double minHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minHeight),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(Icons.broken_image_outlined, color: context.appColors.muted),
          const SizedBox(height: 8),
          Text(
            asset.displayTitle,
            style: TextStyle(color: context.appColors.muted),
          ),
        ],
      ),
    ),
  );
}

final class _MissingAssetCard extends StatelessWidget {
  const _MissingAssetCard();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.softCoral,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Text('附件不可用', style: TextStyle(color: context.appColors.coral)),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

/// The block editor keeps this zero-width boundary inside block fields so
/// mobile keyboards can report backspace at the start of an otherwise empty
/// block. It must never become part of a user's copied or cut text.
const editorBlockBoundary = '\u200B';

const _supportedAppContextMenuActions = {
  ContextMenuButtonType.cut,
  ContextMenuButtonType.copy,
  ContextMenuButtonType.paste,
  ContextMenuButtonType.selectAll,
  ContextMenuButtonType.share,
};

/// FKNotes' app-wide context menu for editable and selectable text.
///
/// Filtering the framework-provided actions also prevents Android services
/// and third-party apps from injecting unrelated menu entries.
Widget buildAppEditableTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  Future<void> Function()? onPaste,
  Future<void> Function()? onCopy,
  Future<void> Function()? onCut,
  VoidCallback? onQuote,
}) {
  final items = editableTextState.contextMenuButtonItems
      .where((item) => _supportedAppContextMenuActions.contains(item.type))
      .toList(growable: false);
  return _buildAppTextSelectionToolbar(
    anchors: editableTextState.contextMenuAnchors,
    items: items,
    customActions: [
      if (onQuote != null)
        _AppContextMenuAction(
          label: context.l10n.quote,
          icon: Icons.format_quote,
          onPressed: () {
            ContextMenuController.removeAny();
            onQuote();
          },
        ),
    ],
    beforeAction: (type) {
      final customAction = switch (type) {
        ContextMenuButtonType.copy => onCopy,
        ContextMenuButtonType.cut => onCut,
        _ => null,
      };
      if (customAction != null) {
        ContextMenuController.removeAny();
        customAction();
        return true;
      }
      _excludeBlockBoundary(editableTextState);
      if (type != ContextMenuButtonType.paste || onPaste == null) return false;
      ContextMenuController.removeAny();
      onPaste();
      return true;
    },
  );
}

/// FKNotes' app-wide context menu for a multi-widget [SelectionArea].
Widget buildAppSelectableRegionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState, {
  VoidCallback? onQuote,
}) {
  final items = selectableRegionState.contextMenuButtonItems
      .where((item) => _supportedAppContextMenuActions.contains(item.type))
      .toList(growable: false);
  return _buildAppTextSelectionToolbar(
    anchors: selectableRegionState.contextMenuAnchors,
    items: items,
    customActions: [
      if (onQuote != null)
        _AppContextMenuAction(
          label: context.l10n.quote,
          icon: Icons.format_quote,
          onPressed: () {
            selectableRegionState.hideToolbar();
            onQuote();
            selectableRegionState.clearSelection();
          },
        ),
    ],
  );
}

Widget _buildAppTextSelectionToolbar({
  required TextSelectionToolbarAnchors anchors,
  required List<ContextMenuButtonItem> items,
  List<_AppContextMenuAction> customActions = const [],
  bool Function(ContextMenuButtonType type)? beforeAction,
}) {
  if (items.isEmpty && customActions.isEmpty) return const SizedBox.shrink();
  return TextSelectionToolbar(
    anchorAbove: anchors.primaryAnchor,
    anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
    toolbarBuilder: (context, child) => Material(
      color: context.appColors.surface,
      elevation: AppMenuTokens.elevation,
      shadowColor: context.appColors.shadow.withValues(alpha: .16),
      surfaceTintColor: Colors.transparent,
      shape: AppMenuTokens.shape,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: child,
      ),
    ),
    children: [
      for (final item in items)
        _AppContextMenuButton(
          type: item.type,
          onPressed: item.onPressed == null
              ? null
              : () {
                  final handled = beforeAction?.call(item.type) ?? false;
                  if (!handled) item.onPressed!.call();
                },
        ),
      for (final action in customActions)
        _AppCustomContextMenuButton(action: action),
    ],
  );
}

class _AppContextMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _AppContextMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

class _AppCustomContextMenuButton extends StatelessWidget {
  final _AppContextMenuAction action;

  const _AppCustomContextMenuButton({required this.action});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: action.onPressed,
    style: _buttonStyle(context),
    icon: AppIcon(action.icon, size: 18),
    label: Text(action.label),
  );
}

void _excludeBlockBoundary(EditableTextState editableTextState) {
  final controller = editableTextState.widget.controller;
  final value = controller.value;
  final selection = value.selection;
  if (!value.text.startsWith(editorBlockBoundary) || !selection.isValid) {
    return;
  }
  final base = selection.baseOffset < editorBlockBoundary.length
      ? editorBlockBoundary.length
      : selection.baseOffset;
  final extent = selection.extentOffset < editorBlockBoundary.length
      ? editorBlockBoundary.length
      : selection.extentOffset;
  if (base == selection.baseOffset && extent == selection.extentOffset) return;
  controller.selection = selection.copyWith(
    baseOffset: base,
    extentOffset: extent,
  );
}

class _AppContextMenuButton extends StatelessWidget {
  final ContextMenuButtonType type;
  final VoidCallback? onPressed;

  const _AppContextMenuButton({required this.type, this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: _buttonStyle(context),
    icon: AppIcon(_icon, size: 18),
    label: Text(_label(context)),
  );

  String _label(BuildContext context) => switch (type) {
    ContextMenuButtonType.cut => context.l10n.cut,
    ContextMenuButtonType.copy => context.l10n.copy,
    ContextMenuButtonType.paste => context.l10n.paste,
    ContextMenuButtonType.selectAll => context.l10n.selectAll,
    ContextMenuButtonType.share => context.l10n.share,
    _ => '',
  };

  IconData get _icon => switch (type) {
    ContextMenuButtonType.cut => Icons.content_cut_rounded,
    ContextMenuButtonType.copy => Icons.content_copy_rounded,
    ContextMenuButtonType.paste => Icons.content_paste_rounded,
    ContextMenuButtonType.selectAll => Icons.select_all_rounded,
    ContextMenuButtonType.share => Icons.ios_share_rounded,
    _ => Icons.more_horiz_rounded,
  };
}

ButtonStyle _buttonStyle(BuildContext context) => TextButton.styleFrom(
  foregroundColor: context.appColors.ink,
  disabledForegroundColor: context.appColors.muted,
  minimumSize: const Size(0, 44),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
);

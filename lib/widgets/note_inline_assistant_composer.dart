import 'package:flutter/material.dart';

import '../app.dart';
import '../editor/note_assistant_editing.dart';
import '../l10n/l10n.dart';
import 'app_popup_menu.dart';
import 'editor_context_menu.dart';
import 'app_icon.dart';

typedef NoteInlineAssistantSubmit =
    void Function(String instruction, NoteInlineAssistantTarget? target);

final class NoteInlineAssistantComposer extends StatelessWidget {
  const NoteInlineAssistantComposer({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.generating,
    required this.hasResult,
    required this.resultLabel,
    required this.target,
    required this.selectionAvailable,
    required this.error,
    required this.onSubmit,
    required this.onTargetChanged,
    required this.onStop,
    required this.onRetry,
    required this.onUndo,
    required this.onContinue,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final bool generating;
  final bool hasResult;
  final String resultLabel;
  final NoteInlineAssistantTarget target;
  final bool selectionAvailable;
  final String? error;
  final NoteInlineAssistantSubmit onSubmit;
  final ValueChanged<NoteInlineAssistantTarget> onTargetChanged;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback onUndo;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('quill-inline-assistant'),
    color: context.appColors.toolLayer,
    child: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.appColors.line)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _content(context),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (loading || generating) {
      return _GenerationStatus(
        key: const ValueKey('generating'),
        label: loading
            ? context.l10n.inlineAssistantLoading
            : context.l10n.inlineAssistantWriting,
        onStop: onStop,
      );
    }
    if (error != null) {
      return _ResultStatus(
        key: const ValueKey('error'),
        icon: Icons.error_outline_rounded,
        iconColor: context.appColors.warning,
        label: error!,
        primaryLabel: context.l10n.retry,
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: context.l10n.close,
        onSecondary: onClose,
      );
    }
    if (hasResult) {
      return _ResultStatus(
        key: const ValueKey('complete'),
        icon: Icons.auto_awesome_rounded,
        iconColor: context.appColors.accent,
        label: resultLabel,
        primaryLabel: context.l10n.inlineAssistantContinue,
        primaryIcon: Icons.arrow_forward_rounded,
        onPrimary: onContinue,
        secondaryLabel: context.l10n.undo,
        onSecondary: onUndo,
      );
    }
    return _PromptComposer(
      key: const ValueKey('prompt'),
      controller: controller,
      focusNode: focusNode,
      target: target,
      selectionAvailable: selectionAvailable,
      onSubmit: onSubmit,
      onTargetChanged: onTargetChanged,
      onClose: onClose,
    );
  }
}

final class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.focusNode,
    required this.target,
    required this.selectionAvailable,
    required this.onSubmit,
    required this.onTargetChanged,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final NoteInlineAssistantTarget target;
  final bool selectionAvailable;
  final NoteInlineAssistantSubmit onSubmit;
  final ValueChanged<NoteInlineAssistantTarget> onTargetChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.appColors.accentSoft,
              borderRadius: BorderRadius.circular(context.appRadii.small),
            ),
            child: AppIcon(
              Icons.auto_awesome_rounded,
              color: context.appColors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.writeWithAi,
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                AppAnchoredMenuButton<NoteInlineAssistantTarget>(
                  key: const Key('inline-assistant-target'),
                  tooltip: context.l10n.processingScope,
                  actions: [
                    AppMenuAction(
                      value: NoteInlineAssistantTarget.cursor,
                      label: context.l10n.inlineAssistantInsertAtCursor,
                      selected: target == NoteInlineAssistantTarget.cursor,
                    ),
                    if (selectionAvailable)
                      AppMenuAction(
                        value: NoteInlineAssistantTarget.selection,
                        label: context.l10n.inlineAssistantReplaceSelection,
                        selected: target == NoteInlineAssistantTarget.selection,
                      ),
                    AppMenuAction(
                      value: NoteInlineAssistantTarget.currentLine,
                      label: context.l10n.inlineAssistantEditCurrentBlock,
                      selected: target == NoteInlineAssistantTarget.currentLine,
                    ),
                    AppMenuAction(
                      value: NoteInlineAssistantTarget.document,
                      label: context.l10n.inlineAssistantEditFullNote,
                      selected: target == NoteInlineAssistantTarget.document,
                    ),
                    AppMenuAction(
                      value: NoteInlineAssistantTarget.metadata,
                      label: context.l10n.inlineAssistantEditMetadata,
                      selected: target == NoteInlineAssistantTarget.metadata,
                    ),
                  ],
                  onSelected: onTargetChanged,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _targetLabel(context, target),
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 2),
                      AppIcon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: context.appColors.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('close-inline-assistant'),
            tooltip: context.l10n.close,
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const AppIcon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SuggestionChip(
              label: context.l10n.inlineAssistantGenerateMetadata,
              onPressed: (value) =>
                  onSubmit(value, NoteInlineAssistantTarget.metadata),
            ),
            const SizedBox(width: 7),
            _SuggestionChip(
              label: context.l10n.inlineAssistantContinueWriting,
              onPressed: (value) =>
                  onSubmit(value, NoteInlineAssistantTarget.cursor),
            ),
            const SizedBox(width: 7),
            _SuggestionChip(
              label: context.l10n.inlineAssistantMakeList,
              onPressed: (value) => onSubmit(value, _replacementTarget),
            ),
            const SizedBox(width: 7),
            _SuggestionChip(
              label: context.l10n.inlineAssistantExpandIdea,
              onPressed: (value) => onSubmit(value, _replacementTarget),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Container(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(context.appRadii.extraLarge),
            border: Border.all(color: context.appColors.line),
          ),
          padding: const EdgeInsets.fromLTRB(14, 3, 6, 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('quill-inline-assistant-input'),
                  controller: controller,
                  focusNode: focusNode,
                  contextMenuBuilder: buildAppEditableTextContextMenu,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: context.l10n.inlineAssistantHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const Key('submit-inline-assistant'),
                tooltip: context.l10n.startGenerating,
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => onSubmit(value.text.trim(), null),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(42),
                  backgroundColor: context.appColors.accent,
                  foregroundColor: context.appColors.onAccent,
                  disabledBackgroundColor: context.appColors.surfaceMuted,
                  disabledForegroundColor: context.appColors.muted,
                ),
                icon: AppIcon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: value.text.trim().isEmpty
                      ? context.appColors.muted
                      : context.appColors.onAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  NoteInlineAssistantTarget get _replacementTarget => switch (target) {
    NoteInlineAssistantTarget.cursor => NoteInlineAssistantTarget.currentLine,
    NoteInlineAssistantTarget.selection when !selectionAvailable =>
      NoteInlineAssistantTarget.currentLine,
    NoteInlineAssistantTarget.metadata => NoteInlineAssistantTarget.document,
    _ => target,
  };
}

String _targetLabel(BuildContext context, NoteInlineAssistantTarget target) =>
    switch (target) {
      NoteInlineAssistantTarget.cursor =>
        context.l10n.inlineAssistantInsertAtCursor,
      NoteInlineAssistantTarget.selection =>
        context.l10n.inlineAssistantReplaceSelection,
      NoteInlineAssistantTarget.currentLine =>
        context.l10n.inlineAssistantEditCurrentBlock,
      NoteInlineAssistantTarget.document =>
        context.l10n.inlineAssistantEditFullNote,
      NoteInlineAssistantTarget.metadata =>
        context.l10n.inlineAssistantEditMetadata,
    };

final class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onPressed});

  final String label;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    avatar: const AppIcon(Icons.north_east_rounded, size: 14),
    onPressed: () => onPressed(label),
    backgroundColor: context.appColors.surface,
    side: BorderSide(color: context.appColors.line),
    labelStyle: TextStyle(
      color: context.appColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    visualDensity: VisualDensity.compact,
  );
}

final class _GenerationStatus extends StatelessWidget {
  const _GenerationStatus({
    required this.label,
    required this.onStop,
    super.key,
  });

  final String label;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(context.appRadii.extraLarge),
      border: Border.all(color: context.appColors.line),
      boxShadow: context.appColors.lowShadows,
    ),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton.icon(
          key: const Key('stop-inline-assistant'),
          onPressed: onStop,
          icon: const AppIcon(Icons.stop_rounded, size: 18),
          label: Text(context.l10n.stopGenerating),
        ),
      ],
    ),
  );
}

final class _ResultStatus extends StatelessWidget {
  const _ResultStatus({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(15, 12, 10, 10),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(context.appRadii.extraLarge),
      border: Border.all(color: context.appColors.line),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.appColors.surfaceMuted,
                borderRadius: BorderRadius.circular(context.appRadii.small),
              ),
              child: AppIcon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const Key('continue-inline-assistant'),
              onPressed: onPrimary,
              icon: AppIcon(primaryIcon, size: 17),
              label: Text(primaryLabel),
            ),
          ],
        ),
      ],
    ),
  );
}

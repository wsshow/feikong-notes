import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/local_llm.dart';
import '../services/note_assistant_prompt_builder.dart';
import 'editor_context_menu.dart';
import 'app_icon.dart';

bool canInsertNoteAssistantOutput({
  required String output,
  required LocalLlmFinishReason? finishReason,
}) =>
    output.trim().isNotEmpty &&
    (finishReason == LocalLlmFinishReason.completed ||
        finishReason == LocalLlmFinishReason.maxTokens ||
        finishReason == LocalLlmFinishReason.canceled);

Future<NoteAssistantInvocation?> showNoteAssistantTaskSheet(
  BuildContext context, {
  Set<NoteAssistantScope> availableScopes = const {NoteAssistantScope.fullNote},
  NoteAssistantScope initialScope = NoteAssistantScope.fullNote,
  bool allowChat = true,
}) {
  assert(availableScopes.isNotEmpty);
  return AppOverlay.bottomSheet<NoteAssistantInvocation>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NoteAssistantTaskSheet(
      availableScopes: Set.unmodifiable(availableScopes),
      initialScope: availableScopes.contains(initialScope)
          ? initialScope
          : availableScopes.first,
      allowChat: allowChat,
    ),
  );
}

class _NoteAssistantTaskSheet extends StatefulWidget {
  final Set<NoteAssistantScope> availableScopes;
  final NoteAssistantScope initialScope;
  final bool allowChat;

  const _NoteAssistantTaskSheet({
    required this.availableScopes,
    required this.initialScope,
    required this.allowChat,
  });

  @override
  State<_NoteAssistantTaskSheet> createState() =>
      _NoteAssistantTaskSheetState();
}

class _NoteAssistantTaskSheetState extends State<_NoteAssistantTaskSheet> {
  final _controller = TextEditingController();
  late NoteAssistantScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustomInstruction() {
    final instruction = _controller.text.trim();
    if (instruction.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(
      context,
      NoteAssistantInvocation(
        action: NoteAssistantAction.custom(instruction),
        scope: _scope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.agentTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.agentAutomaticTaskHint,
                style: TextStyle(color: context.appColors.muted),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.processingScope,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in NoteAssistantScope.values)
                    if (widget.availableScopes.contains(scope))
                      ChoiceChip(
                        key: Key('note-assistant-scope-${scope.name}'),
                        label: Text(_scopeLabel(context, scope)),
                        selected: _scope == scope,
                        onSelected: (_) => setState(() => _scope = scope),
                      ),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.allowChat) ...[
                ListTile(
                  key: const Key('note-assistant-open-chat'),
                  contentPadding:
                      context.appComponents.edgeAlignedInteractivePadding,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.appColors.accentSoft,
                      borderRadius: BorderRadius.circular(
                        context.appRadii.medium,
                      ),
                    ),
                    child: AppIcon(
                      Icons.forum_outlined,
                      color: context.appColors.accent,
                    ),
                  ),
                  title: Text(
                    context.l10n.chatWithThisNote,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(context.l10n.chatWithThisNoteDescription),
                  trailing: const AppIcon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(
                    context,
                    NoteAssistantInvocation.chat(scope: _scope),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              TextField(
                key: const Key('note-assistant-custom-instruction'),
                controller: _controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.assistantCustomHint,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('note-assistant-submit-custom'),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : _submitCustomInstruction,
                  icon: const AppIcon(Icons.arrow_upward_rounded),
                  label: Text(context.l10n.startGenerating),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      context.l10n.quickActions,
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              _TaskTile(
                task: NoteAssistantTask.summarize,
                scope: _scope,
                icon: Icons.summarize_outlined,
                subtitle: context.l10n.assistantSummarizeDescription,
              ),
              _TaskTile(
                task: NoteAssistantTask.extractTodos,
                scope: _scope,
                icon: Icons.checklist_rounded,
                subtitle: context.l10n.assistantExtractTodosDescription,
              ),
              _TaskTile(
                task: NoteAssistantTask.polish,
                scope: _scope,
                icon: Icons.auto_fix_high_rounded,
                subtitle: context.l10n.assistantPolishDescription,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final NoteAssistantTask task;
  final NoteAssistantScope scope;
  final IconData icon;
  final String subtitle;

  const _TaskTile({
    required this.task,
    required this.scope,
    required this.icon,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    key: Key('note-assistant-task-${task.name}'),
    contentPadding: context.appComponents.edgeAlignedInteractivePadding,
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: context.appColors.softGreen,
        borderRadius: BorderRadius.circular(context.appRadii.medium),
      ),
      child: AppIcon(icon, color: context.appColors.moss),
    ),
    title: Text(
      _taskLabel(context, task),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle),
    trailing: const AppIcon(Icons.chevron_right_rounded),
    onTap: () => Navigator.pop(
      context,
      NoteAssistantInvocation(
        action: NoteAssistantAction.preset(task),
        scope: scope,
      ),
    ),
  );
}

String _scopeLabel(BuildContext context, NoteAssistantScope scope) =>
    switch (scope) {
      NoteAssistantScope.selection => context.l10n.scopeSelection,
      NoteAssistantScope.currentBlock => context.l10n.scopeCurrentBlock,
      NoteAssistantScope.fullNote => context.l10n.scopeFullNote,
    };

String _taskLabel(BuildContext context, NoteAssistantTask task) =>
    switch (task) {
      NoteAssistantTask.summarize => context.l10n.assistantSummarize,
      NoteAssistantTask.extractTodos => context.l10n.assistantExtractTodos,
      NoteAssistantTask.polish => context.l10n.assistantPolish,
    };

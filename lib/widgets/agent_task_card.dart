import 'dart:async';
import 'dart:convert';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../agent/agent_run_timing.dart';
import '../agent/agent_service.dart';
import '../agent/agent_number_format.dart';
import '../agent/model_profile.dart';
import '../agent/note_tools.dart' show taskCreatedNoteIds, taskNoteChanges;
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../pages/note_quill_editor_page.dart';
import '../pages/private_notes_page.dart';
import 'private_notes_scope.dart';
import '../services/device_authentication_service.dart';
import 'agent_permission_sheet.dart';
import 'agent_model_picker.dart';
import 'app_copy_button.dart';
import 'app_feedback.dart';
import 'app_icon.dart';
import 'chat_image_attachments.dart';
import 'chat_note_reference_cards.dart';
import 'chat_text_quote_cards.dart';
import 'chat_user_message_surface.dart';
import 'editor_context_menu.dart';
import 'fk_markdown_view.dart';

const _transientAgentErrors = {
  'incompleteResponse',
  'incompleteStream',
  'modelTransport',
  'requestTimeout',
  'serviceUnavailable',
  'rateLimited',
  'httpError',
};

bool _canRetryAgentRun(AgentRun run) =>
    !run.historyOnly &&
    (run.status == RunStatus.cancelled ||
        run.status == RunStatus.failed &&
            _transientAgentErrors.contains(run.errorCode));

class AgentTaskCard extends StatefulWidget {
  final AgentService service;
  final AgentRun run;
  final bool conversation;
  final Future<void> Function(Json source)? onOpenSource;
  final Future<void> Function(String text)? onWriteBack;
  final ValueChanged<ConversationQuote>? onOpenQuote;
  final ChatQuoteSelectionCallback? onQuoteSelection;
  const AgentTaskCard({
    super.key,
    required this.service,
    required this.run,
    this.conversation = false,
    this.onOpenSource,
    this.onWriteBack,
    this.onOpenQuote,
    this.onQuoteSelection,
  });
  @override
  State<AgentTaskCard> createState() => _AgentTaskCardState();
}

class _AgentTaskCardState extends State<AgentTaskCard> {
  bool _busy = false;
  Timer? _durationTicker;

  @override
  void initState() {
    super.initState();
    _syncDurationTicker();
  }

  @override
  void didUpdateWidget(covariant AgentTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDurationTicker();
  }

  @override
  void dispose() {
    _durationTicker?.cancel();
    super.dispose();
  }

  void _syncDurationTicker() {
    if (!agentRunDurationIsLive(widget.run)) {
      _durationTicker?.cancel();
      _durationTicker = null;
      return;
    }
    _durationTicker ??= Timer.periodic(agentRunDurationRefreshInterval, (_) {
      if (!mounted) return;
      if (!agentRunDurationIsLive(widget.run)) {
        _durationTicker?.cancel();
        _durationTicker = null;
        return;
      }
      setState(() {});
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.agentError(e is HarnessException ? e.code : 'task'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue({bool retry = false, bool revealOnly = false}) async {
    if (revealOnly) {
      if (widget.service.privateNotes.protected) {
        await widget.service.privateNotes.unlock(
          prompt: DeviceAuthenticationPrompt(
            reason: context.l10n.agentPrivateUnlock,
          ),
        );
      }
      final scope = await widget.service.grant(
        profileId: 'local',
        privateAccess: true,
      );
      await widget.service.renewViewGrant(widget.run.id, scope);
      return;
    }
    ModelProfile? profile;
    try {
      profile = await widget.service.profiles.get(widget.run.profileId);
    } catch (_) {
      final profiles = await widget.service.profiles.list();
      final selectedId = await widget.service.profiles.selectedId();
      if (!mounted) return;
      profile = await showAgentModelPicker(
        context,
        profiles: profiles,
        selectedId: selectedId,
      );
    }
    if (profile == null || !mounted) return;
    final sourceIds = {
      ...widget.run.messages
          .expand((message) => message.sources)
          .map((source) => source['noteId'])
          .whereType<String>(),
      ...taskCreatedNoteIds(widget.run),
    };
    final grant = await prepareAgentTask(
      context,
      service: widget.service,
      profile: profile,
      noteIds: sourceIds,
      previous: widget.run.scope,
      limits: widget.run.limits,
      skillId: widget.run.skillId,
      historyRequiresPrivateAccess: widget.run.requiresPrivateAccess,
    );
    if (grant == null) return;
    if (retry) {
      await widget.service.retry(
        widget.run.id,
        grant.scope,
        profileId: profile.id,
      );
    } else {
      await widget.service.resume(
        widget.run.id,
        grant.scope,
        profileId: profile.id,
      );
    }
  }

  Future<void> _regenerate() async {
    final run = widget.run;
    final profile = await widget.service.profiles.get(run.profileId);
    if (!mounted) return;
    final sourceIds = {
      ...run.messages
          .expand((message) => message.sources)
          .map((source) => source['noteId'])
          .whereType<String>(),
      ...taskCreatedNoteIds(run),
    };
    final grant = await prepareAgentTask(
      context,
      service: widget.service,
      profile: profile,
      noteIds: sourceIds,
      previous: run.scope,
      limits: run.limits,
      skillId: run.skillId,
      historyRequiresPrivateAccess: run.requiresPrivateAccess,
    );
    if (grant == null) return;
    await widget.service.regenerate(run.id, grant.scope, profileId: profile.id);
  }

  Future<void> _source(Json source) async {
    if (!widget.service.canDisplay(widget.run)) return;
    final raw = source['noteId'] as String?;
    if (raw == null) return;
    final id = NoteId.parse(raw);
    final repo = await widget.service.repository();
    final private = await repo.isPrivateNote(id);
    if (!mounted) return;
    if (private != widget.run.scope.privateNotes) {
      throw const HarnessException(
        'noteMissing',
        'The note belongs to another workspace.',
      );
    }
    if (widget.onOpenSource != null &&
        (!private || PrivateNotesScope.maybeOf(context) != null)) {
      await widget.onOpenSource!(source);
      return;
    }
    if (private) {
      if (widget.service.privateNotes.protected) {
        throw const HarnessException('privateLocked', 'Renew private access.');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrivateNotesPage(
            session: widget.service.privateNotes,
            initialNoteId: id,
          ),
        ),
      );
    } else if (widget.onOpenSource != null) {
      await widget.onOpenSource!(source);
    } else {
      final note = await repo.get(id);
      if (note == null) {
        throw const HarnessException('noteMissing', 'Note unavailable.');
      }
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteQuillEditorPage(initialNote: note),
          ),
        );
      }
    }
  }

  Future<void> _showNoteCollection({
    required String title,
    required Map<String, Json> noteSources,
    Map<String, Json> webSources = const {},
    bool visitedWebFallback = false,
    bool noteChanges = false,
  }) async {
    if (_busy || !widget.service.canDisplay(widget.run)) return;
    await _act(() async {
      final repo = await widget.service.repository();
      final noteEntries = <_AgentNoteEntry>[];
      for (final entry in noteSources.entries) {
        Note? note;
        try {
          final id = NoteId.parse(entry.key);
          final private = await repo.isPrivateNote(id);
          note = await repo.get(id, privateSpace: private);
        } catch (_) {
          note = null;
        }
        noteEntries.add(_AgentNoteEntry(reference: entry.value, note: note));
      }
      if (!mounted || !widget.service.canDisplay(widget.run)) return;
      final selected = await AppOverlay.bottomSheet<Json>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _AgentNoteCollectionSheet(
          title: title,
          notes: noteEntries,
          webSources: webSources,
          visitedWebFallback: visitedWebFallback,
          noteChanges: noteChanges,
        ),
      );
      if (selected != null && mounted) await _source(selected);
    });
  }

  Future<void> _review(PendingTool pending) async {
    if (!widget.service.canDisplay(widget.run)) return;
    final decision = await AppOverlay.bottomSheet<_ProposalDecision>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ProposalSheet(
        pending: pending,
        service: widget.service,
        run: widget.run,
      ),
    );
    if (decision == null) return;
    if (decision.arguments != null) {
      await widget.service.runtime.amendApproval(
        pending.approvalId!,
        expectedDigest: pending.preview!.digest,
        arguments: decision.arguments!,
      );
    } else {
      await widget.service.runtime.approve(
        pending.approvalId!,
        accept: decision.accept,
        expectedDigest: pending.preview!.digest,
      );
    }
  }

  Future<void> _verify(PendingTool pending) async {
    final input = TextEditingController();
    final done = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.agentReconcile),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.agentReconcileNotice),
              TextField(
                controller: input,
                decoration: InputDecoration(
                  labelText: context.l10n.agentVerificationNote,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.agentEffectNone),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.agentEffectDone),
          ),
        ],
      ),
    );
    final evidence = input.text.trim();
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    if (done != null) {
      await widget.service.runtime.reconcile(
        widget.run.id,
        pending.operationId,
        ToolResult({
          'verifiedByUser': true,
          'completed': done,
          'evidence': evidence,
        }, isError: !done),
      );
    }
  }

  Future<void> _undo(Json action) async {
    final l = context.l10n;
    final yes = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.agentUndo),
        content: Text(l.agentUndoConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.agentUndo),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.service.undo(widget.run.id, action['operationId'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final run = widget.run;
    final answer = run.status == RunStatus.completed ? run.answer : '';
    final visible = widget.service.canDisplay(run);
    final child = run.parentId != null;
    final sources = <String, Json>{};
    final noteChangeSources = <String, Json>{};
    final webSources = <String, Json>{};
    final noteChanges = taskNoteChanges(run);
    for (final source in _runEvidenceSources(run)) {
      if (source['noteId'] case final String id) {
        final change = noteChanges[id];
        if (change?['created'] != true) {
          sources[id] = source;
        }
        if (change != null) {
          noteChangeSources[id] = {...source, ...change};
        }
      }
      final webSource = _cleanWebSourceForDisplay(source);
      final url = Uri.tryParse(webSource['url'] as String? ?? '');
      if (url != null &&
          {'https', 'http'}.contains(url.scheme) &&
          url.hasAuthority) {
        webSources[url.toString()] = webSource;
      }
    }
    final visitedWebFallback = webSources.isEmpty;
    if (visitedWebFallback) {
      for (final source in _runVisitedWebSources(run)) {
        webSources[source['url'] as String] = source;
      }
    }
    for (final change in noteChanges.entries) {
      noteChangeSources.putIfAbsent(change.key, () => change.value);
    }
    final children = widget.service.runs
        .where((r) => r.parentId == run.id)
        .toList();
    if (widget.conversation) {
      return _buildConversation(
        context,
        sources: sources,
        webSources: webSources,
        visitedWebFallback: visitedWebFallback && webSources.isNotEmpty,
        noteChangeSources: noteChangeSources,
        visible: visible,
      );
    }
    return Card(
      key: ValueKey('agent-task-${run.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(l.agentStatus(run.status.name))),
                Text(
                  l.agentUsage(
                    run.roundCount,
                    formatAgentTokenCount(run.tokens),
                  ),
                ),
                if (run.estimatedUsage)
                  Text(
                    l.agentEstimatedUsage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            Text(
              run.scope.online
                  ? l.agentOnline
                  : run.scope.networkTools
                  ? l.agentLocalNetworkNotice
                  : l.agentOfflineNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (run.scope.writeNotes || run.scope.externalWrites)
              Text(
                run.scope.requireApproval
                    ? l.agentApprovalManual
                    : l.agentApprovalAutomatic,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (!visible) ...[
              const SizedBox(height: 12),
              Text(l.agentPrivateHidden),
              if (!child)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _act(() => _continue(revealOnly: true)),
                  child: Text(l.agentContinue),
                ),
            ] else ...[
              const SizedBox(height: 12),
              SelectableText(
                run.goal,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (run.plan.isNotEmpty)
                ExpansionTile(
                  title: Text(l.agentPlan),
                  initiallyExpanded: !run.status.terminal,
                  children: [
                    for (final step in run.plan)
                      ListTile(
                        dense: true,
                        leading: Text(
                          step['status'] == 'completed' ? '✓' : '○',
                        ),
                        title: Text(step['title'] as String? ?? ''),
                      ),
                  ],
                ),
              if (answer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FkMarkdownView(data: answer),
                ),
              if (run.errorCode != null)
                Text(
                  l.agentError(run.errorCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final pending in run.pending.where(
                (p) =>
                    run.status == RunStatus.waitingApproval &&
                    p.approvalId != null &&
                    p.phase == PendingPhase.prepared,
              ))
                FilledButton(
                  key: ValueKey('agent-review-${pending.operationId}'),
                  onPressed: _busy ? null : () => _act(() => _review(pending)),
                  child: Text(l.agentReview),
                ),
              if (run.status == RunStatus.needsReconciliation) ...[
                Text(l.agentReconcileNotice),
                for (final pending in run.pending.where(
                  (p) => p.phase == PendingPhase.executing,
                ))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _act(() => _verify(pending)),
                    child: Text(l.agentReconcile),
                  ),
              ],
              if (sources.isNotEmpty || webSources.isNotEmpty)
                _AgentCollectionRow(
                  key: ValueKey('agent-sources-${run.id}'),
                  label: l.agentSources,
                  summary: visitedWebFallback && webSources.isNotEmpty
                      ? l.agentVisitedWebSources
                      : _collectionSummary(l, sources, webSources),
                  onTap: () => _showNoteCollection(
                    title: l.agentSources,
                    noteSources: sources,
                    webSources: webSources,
                    visitedWebFallback:
                        visitedWebFallback && webSources.isNotEmpty,
                  ),
                ),
              if (noteChangeSources.isNotEmpty)
                _AgentCollectionRow(
                  key: ValueKey('agent-note-changes-${run.id}'),
                  label: l.agentNoteChanges,
                  summary: _collectionSummary(l, noteChangeSources),
                  onTap: () => _showNoteCollection(
                    title: l.agentNoteChanges,
                    noteSources: noteChangeSources,
                    noteChanges: true,
                  ),
                ),
              if (run.actions.isNotEmpty ||
                  run.events.any((e) => e.type == 'toolStarted'))
                ExpansionTile(
                  title: Text(l.agentActions),
                  children: [
                    for (final event
                        in run.events
                            .where(
                              (e) => {
                                'toolStarted',
                                'toolCompleted',
                              }.contains(e.type),
                            )
                            .toList()
                            .reversed
                            .take(20))
                      ListTile(
                        dense: true,
                        title: Text(
                          l.agentActionName(
                            event.data['name'] as String? ?? 'tool',
                          ),
                        ),
                        subtitle: Text(
                          event.type == 'toolStarted'
                              ? l.agentStatus('running')
                              : l.agentStatus(
                                  (event.data['result'] as Json?)?['isError'] ==
                                          true
                                      ? 'failed'
                                      : 'completed',
                                ),
                        ),
                      ),
                    for (final action in run.actions)
                      ListTile(
                        title: Text(
                          l.agentActionName(action['name'] as String),
                        ),
                        subtitle: Text(
                          action['undone'] == true
                              ? l.agentUndone
                              : _actionSummary(action),
                        ),
                        trailing:
                            action['name'] == 'propose_note_changes' &&
                                action['undone'] != true &&
                                run.status.terminal
                            ? TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _act(() => _undo(action)),
                                child: Text(l.agentUndo),
                              )
                            : null,
                      ),
                  ],
                ),
              if (children.isNotEmpty)
                ExpansionTile(
                  title: Text(l.agentChildren),
                  children: [
                    for (final run in children)
                      AgentTaskCard(
                        service: widget.service,
                        run: run,
                        onOpenSource: widget.onOpenSource,
                      ),
                  ],
                ),
              if (!child)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if ({
                      RunStatus.running,
                      RunStatus.queued,
                      RunStatus.waitingApproval,
                    }.contains(run.status))
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(() => widget.service.pause(run.id)),
                        child: Text(l.agentPause),
                      ),
                    if (!run.status.terminal &&
                        run.status != RunStatus.needsReconciliation)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(() => widget.service.cancel(run.id)),
                        child: Text(l.agentStop),
                      ),
                    if ({
                      RunStatus.paused,
                      RunStatus.interrupted,
                    }.contains(run.status))
                      TextButton(
                        onPressed: _busy ? null : () => _act(_continue),
                        child: Text(l.agentContinue),
                      ),
                    if (_canRetryAgentRun(run))
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(() => _continue(retry: true)),
                        child: Text(l.agentRetry),
                      ),
                    if (answer.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          if (widget.service.canDisplay(run)) {
                            Clipboard.setData(ClipboardData(text: answer));
                          }
                        },
                        child: Text(l.copy),
                      ),
                    if (run.status == RunStatus.completed &&
                        widget.onWriteBack != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(() => widget.onWriteBack!(answer)),
                        child: Text(l.writeReplyToNote),
                      ),
                    if (run.status.terminal)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _act(() => widget.service.deleteRun(run.id)),
                        child: Text(l.agentDeleteTask),
                      ),
                  ],
                ),
            ],
            if (_busy || run.status == RunStatus.running)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation(
    BuildContext context, {
    required Map<String, Json> sources,
    required Map<String, Json> webSources,
    required bool visitedWebFallback,
    required Map<String, Json> noteChangeSources,
    required bool visible,
  }) {
    final l = context.l10n;
    final run = widget.run;
    final userImages = _runUserImages(run);
    final userNoteSources = _runUserNoteSources(run);
    final userQuotes = _runUserQuotes(run);
    final active =
        !run.status.terminal &&
        run.status != RunStatus.paused &&
        run.status != RunStatus.interrupted &&
        run.status != RunStatus.needsReconciliation;
    final generationEvents = _generationEvents(run);
    final timeline = [
      ..._processTimeline(run, generationEvents),
      if (active && run.draft.trim().isNotEmpty)
        _ProcessTimelineEntry.stage(
          seq: run.seq + 1,
          id: '${run.id}-live-stage',
          text: run.draft,
        ),
    ];
    final answer = run.status == RunStatus.completed ? run.answer : '';
    final toolCount = run.toolCallCount;
    final processAvailable = run.roundCount > 0 || timeline.isNotEmpty;
    final duration = agentRunDuration(run);
    final finished =
        run.status.terminal ||
        run.status == RunStatus.paused ||
        run.status == RunStatus.interrupted;
    final showReplyActions =
        answer.isNotEmpty ||
        run.status == RunStatus.completed ||
        {RunStatus.failed, RunStatus.cancelled}.contains(run.status);

    return Material(
      color: Colors.transparent,
      child: Padding(
        key: ValueKey('agent-task-${run.id}'),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .82,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (userQuotes.isNotEmpty) ...[
                      ChatTextQuoteCards(
                        quotes: userQuotes,
                        keyPrefix: 'agent-user-quote-${run.id}',
                        alignment: Alignment.centerRight,
                        onOpen: widget.onOpenQuote,
                      ),
                      if (userNoteSources.isNotEmpty ||
                          userImages.isNotEmpty ||
                          run.goal.isNotEmpty)
                        const SizedBox(height: 7),
                    ],
                    if (userNoteSources.isNotEmpty) ...[
                      ChatNoteReferenceCards(
                        notes: [
                          for (final source in userNoteSources)
                            ChatNoteReferenceItem(
                              id: source['noteId'] as String,
                              title: switch (source['title']) {
                                String title when title.trim().isNotEmpty =>
                                  title.trim(),
                                _ => l.untitled,
                              },
                            ),
                        ],
                        keyPrefix: 'agent-user-note-${run.id}',
                        onOpen: (item) => _act(
                          () => _source(
                            userNoteSources.firstWhere(
                              (source) => source['noteId'] == item.id,
                            ),
                          ),
                        ),
                      ),
                      if (userImages.isNotEmpty || run.goal.isNotEmpty)
                        const SizedBox(height: 7),
                    ],
                    if (userImages.isNotEmpty) ...[
                      ChatImageAttachments(
                        images: userImages,
                        imageKeyPrefix: 'agent-user-image-${run.id}',
                        stripKey: 'agent-user-image-strip-${run.id}',
                      ),
                      const SizedBox(height: 7),
                    ],
                    if (run.goal.isNotEmpty)
                      ChatUserMessageSurface(
                        key: ValueKey('agent-user-message-${run.id}'),
                        width: null,
                        padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
                        quietColor: context.appColors.accentSoft,
                        child: SelectableText(
                          run.goal,
                          contextMenuBuilder: (context, state) =>
                              buildAppEditableTextContextMenu(
                                context,
                                state,
                                onQuote: widget.onQuoteSelection == null
                                    ? null
                                    : () {
                                        final value =
                                            state.widget.controller.value;
                                        final selection = value.selection;
                                        if (!selection.isValid ||
                                            selection.isCollapsed) {
                                          return;
                                        }
                                        final selected = selection
                                            .textInside(value.text)
                                            .trim();
                                        if (selected.isNotEmpty) {
                                          widget.onQuoteSelection!(
                                            'run:${run.id}',
                                            run.goal,
                                            selected,
                                          );
                                        }
                                      },
                              ),
                          style: TextStyle(
                            color: ChatUserMessageSurface.foregroundColor(
                              context,
                            ),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 2),
                      child: Text(
                        _clock(run.createdAt),
                        key: ValueKey('agent-user-time-${run.id}'),
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!visible) ...[
              Text(l.agentPrivateHidden),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _act(() => _continue(revealOnly: true)),
                child: Text(l.agentContinue),
              ),
            ] else ...[
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: processAvailable
                    ? ExpansionTile(
                        key: ValueKey(
                          'agent-process-${run.id}-${run.status.name}',
                        ),
                        tilePadding:
                            context.appComponents.edgeAlignedInteractivePadding,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        initiallyExpanded: active,
                        title: Text(
                          toolCount > 0
                              ? l.agentRunSummary(
                                  l.agentStatus(run.status.name),
                                  run.roundCount,
                                  toolCount,
                                  formatAgentRunDuration(duration),
                                )
                              : l.agentRunSummaryWithoutTools(
                                  l.agentStatus(run.status.name),
                                  run.roundCount,
                                  formatAgentRunDuration(duration),
                                ),
                          key: ValueKey('agent-run-summary-${run.id}'),
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        children: [
                          _AgentProcessTimeline(
                            key: ValueKey('agent-process-timeline-${run.id}'),
                            items: [
                              if (timeline.isEmpty)
                                _ProcessTimelineItem(
                                  id: '${run.id}-model',
                                  icon: Icons.psychology_alt_outlined,
                                  child: _ProcessDetail(
                                    label: l.agentModelRounds(run.roundCount),
                                  ),
                                ),
                              for (var i = 0; i < timeline.length; i++)
                                _timelineItem(
                                  context,
                                  run,
                                  generationEvents,
                                  timeline[i],
                                  active: active && i == timeline.length - 1,
                                ),
                            ],
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          l.agentStatus(run.status.name),
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              Divider(height: 1, color: context.appColors.line),
              const SizedBox(height: 14),
              if (answer.isEmpty && active && timeline.isEmpty)
                LocalAgentGenerationIndicator(
                  label: _activityLabel(l, run, generationEvents),
                )
              else if (answer.isNotEmpty)
                FkMarkdownView(
                  data: answer,
                  onQuoteSelection: widget.onQuoteSelection == null
                      ? null
                      : (selected) => widget.onQuoteSelection!(
                          'run:${run.id}',
                          answer,
                          selected,
                        ),
                ),
              if (run.errorCode != null) ...[
                const SizedBox(height: 10),
                Text(
                  l.agentError(run.errorCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              for (final pending in run.pending.where(
                (pending) =>
                    run.status == RunStatus.waitingApproval &&
                    pending.approvalId != null &&
                    pending.phase == PendingPhase.prepared,
              )) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: ValueKey('agent-review-${pending.operationId}'),
                  onPressed: _busy ? null : () => _act(() => _review(pending)),
                  icon: const AppIcon(Icons.fact_check_outlined),
                  label: Text(l.agentReview),
                ),
              ],
              if (run.status == RunStatus.needsReconciliation) ...[
                const SizedBox(height: 12),
                Text(l.agentReconcileNotice),
                for (final pending in run.pending.where(
                  (pending) => pending.phase == PendingPhase.executing,
                ))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _act(() => _verify(pending)),
                    child: Text(l.agentReconcile),
                  ),
              ],
              if (sources.isNotEmpty || webSources.isNotEmpty) ...[
                const SizedBox(height: 8),
                _AgentCollectionRow(
                  key: ValueKey('agent-sources-${run.id}'),
                  label: l.agentSources,
                  summary: visitedWebFallback
                      ? l.agentVisitedWebSources
                      : _collectionSummary(l, sources, webSources),
                  onTap: () => _showNoteCollection(
                    title: l.agentSources,
                    noteSources: sources,
                    webSources: webSources,
                    visitedWebFallback: visitedWebFallback,
                  ),
                ),
              ],
              if (noteChangeSources.isNotEmpty) ...[
                if (sources.isEmpty && webSources.isEmpty)
                  const SizedBox(height: 8),
                _AgentCollectionRow(
                  key: ValueKey('agent-note-changes-${run.id}'),
                  label: l.agentNoteChanges,
                  summary: _collectionSummary(l, noteChangeSources),
                  onTap: () => _showNoteCollection(
                    title: l.agentNoteChanges,
                    noteSources: noteChangeSources,
                    noteChanges: true,
                  ),
                ),
              ],
              if (finished) ...[
                const SizedBox(height: 12),
                Wrap(
                  key: showReplyActions
                      ? ValueKey('agent-reply-actions-${run.id}')
                      : null,
                  spacing: 3,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      processAvailable
                          ? l.agentRunFinishedAt(_clock(run.updatedAt))
                          : l.agentRunFinished(
                              _clock(run.updatedAt),
                              formatAgentRunDuration(duration),
                            ),
                      key: ValueKey('agent-run-finished-${run.id}'),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (answer.isNotEmpty)
                      AppCopyButton(
                        key: ValueKey('agent-copy-${run.id}'),
                        text: answer,
                        copyTooltip: l.copy,
                        copiedTooltip: l.replyCopied,
                      ),
                    if (run.status == RunStatus.completed && !run.historyOnly)
                      _CompactReplyAction(
                        key: ValueKey('agent-regenerate-${run.id}'),
                        tooltip: l.agentRegenerate,
                        icon: Icons.refresh_rounded,
                        onPressed: _busy ? null : () => _act(_regenerate),
                      ),
                    if (_canRetryAgentRun(run))
                      _CompactReplyAction(
                        tooltip: l.agentRetry,
                        icon: Icons.refresh_rounded,
                        onPressed: _busy
                            ? null
                            : () => _act(() => _continue(retry: true)),
                      ),
                    if (run.status == RunStatus.completed &&
                        widget.onWriteBack != null)
                      _CompactReplyAction(
                        tooltip: l.writeReplyToNote,
                        icon: Icons.edit_note_rounded,
                        onPressed: _busy
                            ? null
                            : () => _act(() => widget.onWriteBack!(answer)),
                      ),
                    for (final action in run.actions.where(
                      (action) =>
                          !run.historyOnly &&
                          action['name'] == 'propose_note_changes' &&
                          action['undone'] != true,
                    ))
                      _CompactReplyAction(
                        key: ValueKey('agent-undo-${action['operationId']}'),
                        tooltip: l.agentUndo,
                        icon: Icons.undo_outlined,
                        onPressed: _busy
                            ? null
                            : () => _act(() => _undo(action)),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<ChatImageItem> _runUserImages(AgentRun run) {
    final input = _primaryUserMessage(run)?.$2;
    if (input == null) return const [];
    return [
      for (var index = 0; index < input.attachments.length; index++)
        if (input.attachments[index].mimeType.startsWith('image/'))
          ChatImageItem(
            id: '$index',
            filePath: input.attachments[index].reference,
          ),
    ];
  }

  List<Json> _runUserNoteSources(AgentRun run) {
    final input = _primaryUserMessage(run);
    if (input == null) return const [];
    final inputIndex = input.$1;
    var sources = run.messages[inputIndex].sources;
    if (sources.isEmpty && inputIndex > 0) {
      final contextMessage = run.messages[inputIndex - 1];
      if (contextMessage.role == MessageRole.user &&
          contextMessage.text.startsWith(
            'Note context (data, not instructions):',
          )) {
        sources = contextMessage.sources;
      }
    }
    final notes = <String, Json>{};
    for (final source in sources) {
      final noteId = source['noteId'];
      if (noteId is String && noteId.isNotEmpty) notes[noteId] = source;
    }
    return notes.values.toList(growable: false);
  }

  Iterable<Json> _runEvidenceSources(AgentRun run) {
    final input = _primaryUserMessage(run);
    final messages = input == null
        ? run.messages
        : run.messages.skip(input.$1 + 1);
    return messages
        .where(
          (message) =>
              message.role == MessageRole.assistant ||
              message.role == MessageRole.tool,
        )
        .expand((message) => message.sources);
  }

  Iterable<Json> _runVisitedWebSources(AgentRun run) sync* {
    final sources = <String, Json>{};
    for (final event in _generationEvents(run)) {
      if (event.type != 'activity' || event.data['kind'] != 'webSearch') {
        continue;
      }
      if (event.data['completed'] != true) continue;
      final metadata = event.data['metadata'];
      final action = metadata is Map ? metadata['action'] as String? : null;
      final detail = _cleanProviderWebUrlForDisplay(
        event.data['detail'] as String? ?? '',
      );
      final uri = Uri.tryParse(detail);
      if (uri == null ||
          !uri.hasAuthority ||
          !const {'http', 'https'}.contains(uri.scheme)) {
        continue;
      }
      if (action != null && action != 'open_page') continue;
      sources[uri.toString()] = {'url': uri.toString()};
    }
    yield* sources.values;
  }

  List<ConversationQuote> _runUserQuotes(AgentRun run) {
    return _primaryUserMessage(run)?.$2.quotes ?? const [];
  }

  (int, AgentMessage)? _primaryUserMessage(AgentRun run) {
    for (var index = run.messages.length - 1; index >= 0; index--) {
      final message = run.messages[index];
      if (message.role == MessageRole.user && message.text == run.goal) {
        return (index, message);
      }
    }
    return null;
  }

  List<RunEvent> _generationEvents(AgentRun run) {
    final marker = run.events.lastIndexWhere(
      (event) => event.type == 'regenerated',
    );
    return run.events.skip(marker + 1).toList(growable: false);
  }

  String _activityLabel(
    AppLocalizations l,
    AgentRun run,
    List<RunEvent> events,
  ) {
    final event = events.lastWhere(
      (event) =>
          event.type == 'activity' ||
          event.type == 'reasoning' ||
          event.type == 'toolStarted',
      orElse: () => RunEvent(
        runId: run.id,
        seq: 0,
        type: 'activity',
        data: const {'kind': 'thinking'},
        time: run.createdAt,
      ),
    );
    if (event.type == 'toolStarted') {
      return l.agentRunningTool(
        l.agentActionName(event.data['name'] as String? ?? 'tool'),
      );
    }
    if (event.type == 'reasoning') return l.agentThinkingNow;
    return switch (event.data['kind']) {
      'loadingModel' => l.agentLoadingModel,
      'webSearch' => l.agentSearchingWeb,
      'compressing' => l.agentCompressingContext,
      _ => l.agentThinkingNow,
    };
  }

  String _clock(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';

  String _pendingStatus(AppLocalizations l, PendingTool pending) =>
      switch (pending.phase) {
        PendingPhase.prepared => l.agentStatus('waitingApproval'),
        PendingPhase.executing => l.agentStatus('running'),
        PendingPhase.completed => l.agentStatus(
          pending.result?.isError == true ? 'failed' : 'completed',
        ),
        PendingPhase.rejected => l.agentStatus('cancelled'),
        _ => l.agentStatus('queued'),
      };

  String _toolProcessStatus(
    AppLocalizations l,
    AgentRun run,
    _ToolProcessEntry tool,
  ) {
    final pending = tool.pending;
    if (pending != null) return _pendingStatus(l, pending);
    if (tool.result != null) {
      return l.agentStatus(tool.failed ? 'failed' : 'completed');
    }
    return l.agentStatus(run.status.terminal ? 'failed' : 'running');
  }

  List<_ProcessTimelineEntry> _processTimeline(
    AgentRun run,
    List<RunEvent> events,
  ) {
    final entries = <_ProcessTimelineEntry>[];
    final eventRounds = agentExecutionRoundOrdinals(events);
    final repairedProviderRounds = events.any((event) {
      final stored = event.data['round'] as int?;
      final effective = eventRounds[event.seq];
      return stored != null && effective != null && stored != effective;
    });
    final completeReasoning = <int, String>{};
    for (final item in run.reasoning) {
      final request = item['round'] as int? ?? item['request'] as int?;
      final text = item['text'] as String?;
      if (request != null && text != null) {
        completeReasoning[request] = '${completeReasoning[request] ?? ''}$text';
      }
    }
    final retainedReasoning = <int, String>{};
    for (final event in events.where((event) => event.type == 'reasoning')) {
      final request =
          eventRounds[event.seq] ??
          event.data['round'] as int? ??
          event.data['request'] as int? ??
          1;
      retainedReasoning[request] =
          '${retainedReasoning[request] ?? ''}${event.data['text'] as String? ?? ''}';
    }
    final incompleteReasoning = <int>{
      for (final entry in completeReasoning.entries)
        if (!repairedProviderRounds &&
            retainedReasoning[entry.key] != entry.value)
          entry.key,
    };
    // Older runs capped their event list before stream fragments were folded.
    // Their aggregate remains intact on AgentRun, so repair only those rounds.
    final restoredReasoning = <int>{};
    final reasoningRequests = <int>{};
    final traces = <String, _ProcessTimelineEntry>{};
    final activities = <String, _ProcessTimelineEntry>{};
    final pendingById = {
      for (final pending in run.pending) pending.operationId: pending,
    };
    final callsById = {
      for (final call in run.messages.expand((message) => message.calls))
        call.id: call,
    };

    ToolCall? matchingCall(RunEvent event, PendingTool? pending) {
      final callId = event.data['callId'] as String?;
      return pending?.call ?? (callId == null ? null : callsById[callId]);
    }

    void applyResult(_ToolProcessEntry tool, Object? rawResult) {
      if (rawResult is! Map) return;
      final result = Map<String, dynamic>.from(rawResult);
      final data = result['data'];
      tool.result = data is Map
          ? Map<String, dynamic>.from(data)
          : {'value': data};
      tool.failed = result['isError'] == true;
      tool.sources = (result['sources'] as List? ?? const [])
          .whereType<Map>()
          .map((source) => Map<String, dynamic>.from(source))
          .toList(growable: false);
    }

    for (final event in events) {
      switch (event.type) {
        case 'reasoning':
          final request =
              eventRounds[event.seq] ??
              event.data['round'] as int? ??
              event.data['request'] as int? ??
              1;
          final chunk = incompleteReasoning.contains(request)
              ? restoredReasoning.add(request)
                    ? completeReasoning[request] ?? ''
                    : ''
              : event.data['text'] as String? ?? '';
          if (chunk.isEmpty) continue;
          final previous = entries.lastOrNull;
          if (previous?.kind == _ProcessTimelineKind.reasoning &&
              previous?.request == request) {
            previous!.text += chunk;
          } else {
            final firstSegment = reasoningRequests.add(request);
            final value = _ProcessTimelineEntry.reasoning(
              seq: event.seq,
              id: firstSegment
                  ? '${run.id}-$request'
                  : '${run.id}-$request-${event.seq}',
              request: request,
              ordinal: request,
            );
            value.text = chunk;
            entries.add(value);
          }
        case 'modelResponse':
          final responseText = (event.data['text'] as String? ?? '').trim();
          if (responseText.isNotEmpty) {
            entries.add(
              _ProcessTimelineEntry.stage(
                seq: event.seq,
                id: '${run.id}-${event.seq}',
                text: responseText,
              ),
            );
          }
        case 'steeringConsumed':
          final text = (event.data['text'] as String? ?? '').trim();
          if (text.isNotEmpty) {
            entries.add(
              _ProcessTimelineEntry.instruction(
                seq: event.seq,
                id: '${run.id}-${event.data['id'] ?? event.seq}',
                text: text,
              ),
            );
          }
        case 'plan':
          final steps = (event.data['steps'] as List? ?? const [])
              .whereType<Map>()
              .map((step) => Map<String, dynamic>.from(step))
              .toList(growable: false);
          if (steps.isNotEmpty) {
            entries.add(
              _ProcessTimelineEntry.plan(
                seq: event.seq,
                id: '${run.id}-${event.seq}',
                steps: steps,
              ),
            );
          }
        case 'activity':
          final activityKind = event.data['kind'] as String? ?? '';
          if (activityKind.isEmpty) continue;
          final activityId = event.data['id'] as String?;
          final activityRound =
              eventRounds[event.seq] ??
              event.data['round'] ??
              event.data['request'] ??
              0;
          final activityKey = activityId == null
              ? '$activityKind:$activityRound'
              : '$activityKind:$activityId';
          final existing = activities[activityKey];
          final rawMetadata = event.data['metadata'];
          final activityMetadata = rawMetadata is Map
              ? Map<String, dynamic>.from(rawMetadata)
              : const <String, dynamic>{};
          if (existing != null) {
            if (event.data['detail'] case final String detail
                when detail.trim().isNotEmpty) {
              existing.activityDetail = detail.trim();
            }
            existing.activityCompleted |= event.data['completed'] == true;
            existing.activityLifecycleKnown |= event.data.containsKey(
              'completed',
            );
            if (activityMetadata.isNotEmpty) {
              existing.activityMetadata = {
                ...existing.activityMetadata,
                ...activityMetadata,
              };
            }
            continue;
          }
          final value = _ProcessTimelineEntry.activity(
            seq: event.seq,
            id: '${run.id}-${activityId ?? event.seq}',
            activityKind: activityKind,
            activityId: activityId,
            activityDetail: event.data['detail'] as String?,
            activityMetadata: activityMetadata,
            activityCompleted: event.data['completed'] == true,
            activityLifecycleKnown: event.data.containsKey('completed'),
          );
          activities[activityKey] = value;
          entries.add(value);
        case 'approvalRequired':
        case 'toolStarted':
        case 'toolCompleted':
          final operationId = event.data['operationId'] as String?;
          if (operationId == null || operationId.isEmpty) continue;
          final pending = pendingById[operationId];
          final call = matchingCall(event, pending);
          final name = event.data['name'] as String? ?? call?.name ?? 'tool';
          if (name == 'update_plan') continue;
          final rawArguments = event.data['arguments'];
          final entry = traces.putIfAbsent(operationId, () {
            final value = _ProcessTimelineEntry.tool(
              seq: event.seq,
              id: operationId,
              tool: _ToolProcessEntry(
                operationId: operationId,
                name: name,
                arguments: rawArguments is Map
                    ? Map<String, dynamic>.from(rawArguments)
                    : call?.arguments ?? const {},
              ),
            );
            entries.add(value);
            return value;
          });
          final tool = entry.tool!;
          tool.name = name;
          if (rawArguments is Map) {
            tool.arguments = Map<String, dynamic>.from(rawArguments);
          } else if (call != null) {
            tool.arguments = call.arguments;
          }
          tool.pending = pending;
          if (event.type == 'toolCompleted') {
            applyResult(tool, event.data['result']);
          }
        default:
          continue;
      }
    }

    var fallbackSeq = events.lastOrNull?.seq ?? 0;
    for (final pending in run.pending) {
      if (pending.call.name == 'update_plan') continue;
      final entry = traces.putIfAbsent(pending.operationId, () {
        final value = _ProcessTimelineEntry.tool(
          seq: ++fallbackSeq,
          id: pending.operationId,
          tool: _ToolProcessEntry(
            operationId: pending.operationId,
            name: pending.call.name,
            arguments: pending.call.arguments,
          ),
        );
        entries.add(value);
        return value;
      });
      final tool = entry.tool!;
      tool.pending = pending;
      if (pending.result case final result?) {
        tool.result = result.data;
        tool.failed = result.isError;
        tool.sources = result.sources;
      }
    }
    entries.sort((a, b) => a.seq.compareTo(b.seq));
    return entries;
  }

  _ProcessTimelineItem _timelineItem(
    BuildContext context,
    AgentRun run,
    List<RunEvent> events,
    _ProcessTimelineEntry entry, {
    required bool active,
  }) {
    final l = context.l10n;
    switch (entry.kind) {
      case _ProcessTimelineKind.reasoning:
        return _ProcessTimelineItem(
          id: entry.id,
          icon: Icons.psychology_alt_outlined,
          active: active,
          child: _ReasoningProcessDetail(
            processKey: entry.id,
            title: l.agentReasoningRound(entry.ordinal ?? 1),
            content: entry.text,
          ),
        );
      case _ProcessTimelineKind.stage:
        return _ProcessTimelineItem(
          id: entry.id,
          icon: Icons.chat_bubble_outline_rounded,
          active: active,
          child: _StageProcessDetail(
            processKey: entry.id,
            title: l.agentStageExplanation,
            content: entry.text,
          ),
        );
      case _ProcessTimelineKind.instruction:
        return _ProcessTimelineItem(
          id: entry.id,
          icon: Icons.arrow_forward_rounded,
          child: _StageProcessDetail(
            processKey: entry.id,
            title: l.agentFollowUpMessage,
            content: entry.text,
          ),
        );
      case _ProcessTimelineKind.plan:
        return _ProcessTimelineItem(
          id: entry.id,
          icon: Icons.alt_route_rounded,
          active: active,
          child: _PlanProcessDetail(
            processKey: entry.id,
            title: l.agentPlanUpdated,
            summary: _planSummary(l, entry.steps),
            steps: entry.steps,
          ),
        );
      case _ProcessTimelineKind.activity:
        final searchCompleted =
            entry.activityKind == 'webSearch' &&
            (entry.activityCompleted ||
                (!entry.activityLifecycleKnown && run.status.terminal));
        final webSearchAction = _webSearchAction(entry);
        final activity = switch (entry.activityKind) {
          'loadingModel' => (Icons.memory_rounded, l.agentLoadingModel),
          'webSearch' => (
            Icons.travel_explore_rounded,
            switch (webSearchAction) {
              'open_page' =>
                searchCompleted ? l.agentWebPageOpened : l.agentOpeningWebPage,
              'find_in_page' =>
                searchCompleted
                    ? l.agentWebPageFindCompleted
                    : l.agentFindingInWebPage,
              _ => searchCompleted ? l.agentWebSearchUsed : l.agentSearchingWeb,
            },
          ),
          'compressing' => (
            Icons.multiline_chart_rounded,
            l.agentCompressingContext,
          ),
          _ => (Icons.psychology_alt_outlined, l.agentThinkingNow),
        };
        return _ProcessTimelineItem(
          id: entry.id,
          icon: activity.$1,
          active: active && !searchCompleted,
          child: entry.activityKind == 'webSearch'
              ? _WebSearchProcessDetail(
                  processKey: entry.id,
                  title: activity.$2,
                  content: _cleanProviderWebUrlForDisplay(
                    entry.activityDetail ?? '',
                  ),
                  results: _webSearchResults(run, events, entry),
                  contentLabel: switch (webSearchAction) {
                    'open_page' => l.agentWebPageAddress,
                    'find_in_page' => l.agentWebFindContent,
                    _ => l.agentWebSearchContent,
                  },
                  resultsLabel: webSearchAction == 'search'
                      ? l.agentWebSearchResults
                      : l.agentWebRelatedSources,
                  emptyMessage: _webSearchEmptyMessage(
                    l,
                    webSearchAction,
                    entry.activityMetadata['resultDisclosure'] as String?,
                  ),
                  completed: searchCompleted,
                )
              : _ProcessDetail(label: activity.$2),
        );
      case _ProcessTimelineKind.tool:
        final tool = entry.tool!;
        final completed =
            tool.result != null ||
            tool.pending?.phase == PendingPhase.completed ||
            tool.pending?.phase == PendingPhase.rejected;
        return _ProcessTimelineItem(
          id: entry.id,
          icon: _toolIcon(tool.name),
          active: active && !completed,
          failed: tool.failed,
          child: _ToolProcessDetail(
            operationId: tool.operationId,
            name: l.agentActionName(tool.name),
            summary: _toolSummary(l, tool),
            status: _toolProcessStatus(l, run, tool),
            duration: _toolDuration(run, tool.operationId, events),
            arguments: _prettyJson(tool.arguments),
            result: tool.result == null ? null : _prettyJson(tool.result),
            failed: tool.failed,
          ),
        );
    }
  }

  IconData _toolIcon(String name) => switch (name) {
    'search_notes' => Icons.search_rounded,
    'read_notes' => Icons.description_outlined,
    'propose_note_changes' => Icons.edit_note_rounded,
    'web_search' => Icons.travel_explore_rounded,
    'web_fetch' => Icons.language_rounded,
    'delegate' => Icons.groups_2_outlined,
    _ => Icons.settings_suggest_outlined,
  };

  List<Json> _webSearchResults(
    AgentRun run,
    List<RunEvent> events,
    _ProcessTimelineEntry entry,
  ) {
    final directResults =
        (entry.activityMetadata['results'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (source) =>
                  _cleanWebSourceForDisplay(Map<String, dynamic>.from(source)),
            )
            .where((source) => (source['url'] as String? ?? '').isNotEmpty)
            .toList(growable: false);
    final rawSources = _runEvidenceSources(
      run,
    ).where((source) => source['url'] is String).toList(growable: false);
    if (rawSources.isEmpty) return _uniqueWebSources(directResults);
    final activityId = entry.activityId;
    if (activityId != null) {
      final matched = rawSources
          .where(
            (source) =>
                source['providerCallId'] == activityId ||
                _providerWebCallId(source['url'] as String? ?? '') ==
                    activityId,
          )
          .map(_cleanWebSourceForDisplay)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return _uniqueWebSources([...directResults, ...matched]);
      }
    }
    final sources = rawSources
        .map(_cleanWebSourceForDisplay)
        .toList(growable: false);
    final detail = _cleanProviderWebUrlForDisplay(entry.activityDetail ?? '');
    final detailUri = Uri.tryParse(detail);
    if (detailUri != null && detailUri.hasAuthority) {
      final matched = sources
          .where((source) => source['url'] == detail)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return _uniqueWebSources([...directResults, ...matched]);
      }
    }
    final searchIds = <String>{
      for (final event in events)
        if (event.type == 'activity' &&
            event.data['kind'] == 'webSearch' &&
            event.data['id'] is String)
          event.data['id'] as String,
    };
    return searchIds.length <= 1
        ? _uniqueWebSources([...directResults, ...sources])
        : _uniqueWebSources(directResults);
  }

  String _webSearchAction(_ProcessTimelineEntry entry) {
    final action = entry.activityMetadata['action'];
    if (const {'search', 'open_page', 'find_in_page'}.contains(action)) {
      return action as String;
    }
    final detail = _cleanProviderWebUrlForDisplay(entry.activityDetail ?? '');
    final uri = Uri.tryParse(detail);
    return uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'http' || uri.scheme == 'https')
        ? 'open_page'
        : 'search';
  }

  String _webSearchEmptyMessage(
    AppLocalizations l,
    String action,
    String? disclosure,
  ) {
    final pageAction = action == 'open_page' || action == 'find_in_page';
    return switch (disclosure) {
      'empty' => l.agentWebSearchNoResults,
      'providerManaged' =>
        pageAction
            ? l.agentWebPageProviderManaged
            : l.agentWebSearchProviderManaged,
      'error' => l.agentWebSearchFailed,
      _ =>
        pageAction
            ? l.agentWebPageDetailsUnavailable
            : l.agentWebSearchDetailsUnavailable,
    };
  }

  String _planSummary(AppLocalizations l, List<Json> steps) {
    final current = steps
        .where((step) => step['status'] == 'in_progress')
        .firstOrNull;
    final next = steps.where((step) => step['status'] == 'pending').firstOrNull;
    final parts = <String>[
      if (current?['title'] case final String title) l.agentPlanCurrent(title),
      if (next?['title'] case final String title) l.agentPlanNext(title),
    ];
    return parts.isEmpty ? l.agentPlanCompleted : parts.join(' · ');
  }

  String _toolSummary(AppLocalizations l, _ToolProcessEntry tool) {
    final notes = tool.result?['notes'] as List? ?? const [];
    final sourceTitles = <String>{
      for (final source in tool.sources)
        if ((source['title'] as String?)?.trim().isNotEmpty == true)
          (source['title'] as String).trim(),
      for (final raw in notes)
        if (raw is Map && (raw['title'] as String?)?.trim().isNotEmpty == true)
          (raw['title'] as String).trim(),
    }.toList(growable: false);
    final titles = _shortTitles(l, sourceTitles);
    return switch (tool.name) {
      'search_notes' => [
        if ((tool.arguments['query'] as String?)?.trim() case final query?
            when query.isNotEmpty)
          l.agentToolSearchQuery(query),
        if (notes.isNotEmpty) l.agentToolFoundNotes(notes.length),
      ].join(' · '),
      'read_notes' =>
        titles.isNotEmpty
            ? titles
            : l.agentToolReadNotes(
                (tool.arguments['ids'] as List? ?? const []).length,
              ),
      'propose_note_changes' =>
        titles.isNotEmpty
            ? titles
            : l.agentToolChangedNotes(
                (tool.arguments['changes'] as List? ?? const []).length,
              ),
      'web_fetch' =>
        Uri.tryParse(tool.arguments['url'] as String? ?? '')?.host ?? '',
      'delegate' => tool.arguments['task'] as String? ?? '',
      _ => tool.arguments.values.whereType<String>().firstOrNull ?? '',
    };
  }

  String _shortTitles(AppLocalizations l, List<String> titles) {
    if (titles.isEmpty) return '';
    final separator = l.localeName.startsWith('zh') ? '、' : ', ';
    final visible = titles.take(2).join(separator);
    return titles.length > 2 ? '$visible · +${titles.length - 2}' : visible;
  }

  Duration? _toolDuration(
    AgentRun run,
    String operationId,
    List<RunEvent> generationEvents,
  ) {
    final events = generationEvents.where(
      (event) => event.data['operationId'] == operationId,
    );
    final started = events
        .where((event) => event.type == 'toolStarted')
        .firstOrNull;
    final completed = events
        .where((event) => event.type == 'toolCompleted')
        .firstOrNull;
    if (started == null) return null;
    final end =
        completed?.time ??
        (run.status.terminal ? run.updatedAt : DateTime.now());
    final elapsed = end.difference(started.time);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  String _prettyJson(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  String _collectionSummary(
    AppLocalizations l,
    Map<String, Json> noteSources, [
    Map<String, Json> webSources = const {},
  ]) {
    final titles = <String>[
      for (final source in noteSources.values)
        (source['title'] as String?)?.trim().isNotEmpty == true
            ? (source['title'] as String).trim()
            : l.untitled,
      for (final source in webSources.entries)
        (source.value['title'] as String?)?.trim().isNotEmpty == true
            ? (source.value['title'] as String).trim()
            : Uri.parse(source.key).host,
    ];
    final separator = l.localeName.startsWith('zh') ? '、' : ', ';
    final visible = titles.take(2).join(separator);
    return titles.length > 2 ? '$visible · +${titles.length - 2}' : visible;
  }

  String _actionSummary(Json action) {
    final changes =
        (((action['preview'] as Json?)?['data'] as Json?)?['changes']
            as List? ??
        []);
    return changes
        .map((c) {
          final before = c['before'] as Json?;
          final after = c['after'] as Json?;
          final title = after?['title'] ?? before?['title'] ?? '';
          final next = c['kind'] == 'delete'
              ? 'r0'
              : 'r${(c['baseRevision'] as int) + 1}';
          return '$title · r${c['baseRevision']} → $next';
        })
        .join('\n');
  }
}

class _CompactReplyAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _CompactReplyAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 34,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: AppIcon(icon, size: 17),
    ),
  );
}

class _ToolProcessEntry {
  final String operationId;
  String name;
  Json arguments;
  Json? result;
  List<Json> sources = const [];
  bool failed = false;
  PendingTool? pending;

  _ToolProcessEntry({
    required this.operationId,
    required this.name,
    required this.arguments,
  });
}

enum _ProcessTimelineKind {
  reasoning,
  stage,
  instruction,
  plan,
  tool,
  activity,
}

class _ProcessTimelineEntry {
  final int seq;
  final String id;
  final _ProcessTimelineKind kind;
  final int? request;
  final int? ordinal;
  String text;
  final List<Json> steps;
  final String? activityKind;
  final String? activityId;
  String? activityDetail;
  Json activityMetadata;
  bool activityCompleted;
  bool activityLifecycleKnown;
  final _ToolProcessEntry? tool;

  _ProcessTimelineEntry._({
    required this.seq,
    required this.id,
    required this.kind,
    this.request,
    this.ordinal,
    this.text = '',
    this.steps = const [],
    this.activityKind,
    this.activityId,
    this.activityDetail,
    this.activityMetadata = const {},
    this.activityCompleted = false,
    this.activityLifecycleKnown = false,
    this.tool,
  });

  factory _ProcessTimelineEntry.reasoning({
    required int seq,
    required String id,
    required int request,
    required int ordinal,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.reasoning,
    request: request,
    ordinal: ordinal,
  );

  factory _ProcessTimelineEntry.stage({
    required int seq,
    required String id,
    required String text,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.stage,
    text: text,
  );

  factory _ProcessTimelineEntry.instruction({
    required int seq,
    required String id,
    required String text,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.instruction,
    text: text,
  );

  factory _ProcessTimelineEntry.plan({
    required int seq,
    required String id,
    required List<Json> steps,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.plan,
    steps: steps,
  );

  factory _ProcessTimelineEntry.tool({
    required int seq,
    required String id,
    required _ToolProcessEntry tool,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.tool,
    tool: tool,
  );

  factory _ProcessTimelineEntry.activity({
    required int seq,
    required String id,
    required String activityKind,
    String? activityId,
    String? activityDetail,
    Json activityMetadata = const {},
    bool activityCompleted = false,
    bool activityLifecycleKnown = false,
  }) => _ProcessTimelineEntry._(
    seq: seq,
    id: id,
    kind: _ProcessTimelineKind.activity,
    activityKind: activityKind,
    activityId: activityId,
    activityDetail: activityDetail,
    activityMetadata: activityMetadata,
    activityCompleted: activityCompleted,
    activityLifecycleKnown: activityLifecycleKnown,
  );
}

class _ProcessTimelineItem {
  final String id;
  final IconData icon;
  final Widget child;
  final bool active;
  final bool failed;

  const _ProcessTimelineItem({
    required this.id,
    required this.icon,
    required this.child,
    this.active = false,
    this.failed = false,
  });
}

class _AgentProcessTimeline extends StatelessWidget {
  final List<_ProcessTimelineItem> items;

  const _AgentProcessTimeline({super.key, required this.items});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var index = 0; index < items.length; index++)
          _AgentProcessTimelineNode(
            key: ValueKey('agent-process-node-${items[index].id}'),
            item: items[index],
            first: index == 0,
            last: index == items.length - 1,
          ),
      ],
    ),
  );
}

class _AgentProcessTimelineNode extends StatelessWidget {
  final _ProcessTimelineItem item;
  final bool first;
  final bool last;

  const _AgentProcessTimelineNode({
    super.key,
    required this.item,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final line = context.appColors.line;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: ValueKey('agent-process-line-${item.id}'),
            width: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (!first)
                  Positioned(
                    top: 0,
                    left: 17,
                    width: 1,
                    height: 18,
                    child: ColoredBox(color: line),
                  ),
                if (!last)
                  Positioned(
                    top: 18,
                    bottom: 0,
                    left: 17,
                    width: 1,
                    child: ColoredBox(color: line),
                  ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: _AgentProcessMarker(item: item),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 1),
              child: item.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentProcessMarker extends StatelessWidget {
  final _ProcessTimelineItem item;

  const _AgentProcessMarker({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final error = Theme.of(context).colorScheme.error;
    final color = item.failed
        ? error
        : item.active
        ? Theme.of(context).colorScheme.primary
        : colors.muted;
    return SizedBox.square(
      dimension: 27,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: colors.paperPrimary,
              shape: BoxShape.circle,
              border: Border.all(
                color: item.active ? Colors.transparent : colors.line,
              ),
            ),
          ),
          if (item.active)
            RepaintBoundary(
              child: SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: color,
                ),
              ),
            ),
          AppIcon(item.icon, size: 14, color: color),
        ],
      ),
    );
  }
}

class _ProcessDetail extends StatelessWidget {
  final String label;
  final bool emphasized;
  const _ProcessDetail({required this.label, this.emphasized = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasized ? context.appColors.ink : context.appColors.muted,
            fontSize: 12,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _processPreview(String content) {
  const maxCharacters = 512;
  final runes = content.runes;
  var bounded = runes.length <= maxCharacters
      ? content
      : String.fromCharCodes(runes.take(maxCharacters));
  if (runes.length > maxCharacters) {
    final boundary = bounded.lastIndexOf(RegExp(r'\s'));
    if (boundary >= maxCharacters ~/ 2) {
      bounded = bounded.substring(0, boundary);
    }
  }
  return bounded.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _providerWebCallId(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.fragment.isEmpty) return null;
  for (final part in uri.fragment.split('&')) {
    final separator = part.indexOf('=');
    final rawKey = separator < 0 ? part : part.substring(0, separator);
    final rawValue = separator < 0 ? '' : part.substring(separator + 1);
    try {
      if (Uri.decodeQueryComponent(rawKey) == 'ws_call_id') {
        return Uri.decodeQueryComponent(rawValue);
      }
    } on FormatException {
      if (rawKey == 'ws_call_id') return rawValue;
    }
  }
  return null;
}

String _cleanProviderWebUrlForDisplay(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.fragment.isEmpty) {
    return _stripProviderCallId(trimmed);
  }
  final parts = uri.fragment.split('&');
  final retained = parts
      .where((part) {
        final separator = part.indexOf('=');
        final rawKey = separator < 0 ? part : part.substring(0, separator);
        try {
          return Uri.decodeQueryComponent(rawKey) != 'ws_call_id';
        } on FormatException {
          return rawKey != 'ws_call_id';
        }
      })
      .toList(growable: false);
  if (retained.length == parts.length) return _stripProviderCallId(trimmed);
  final cleaned = retained.isEmpty
      ? trimmed.substring(0, trimmed.lastIndexOf('#'))
      : uri.replace(fragment: retained.join('&')).toString();
  return _stripProviderCallId(cleaned);
}

String _stripProviderCallId(String value) => value
    .replaceAll(
      RegExp(
        r'(?:\s*[,，;；]\s*)?[#?&]?ws_call_id\s*=\s*[^&\s,，;；]+',
        caseSensitive: false,
      ),
      '',
    )
    .replaceFirst(RegExp(r'\s*[,，;；]\s*$'), '')
    .trim();

Json _cleanWebSourceForDisplay(Json source) {
  final result = Map<String, dynamic>.from(source);
  if (source['url'] case final String url) {
    result['url'] = _cleanProviderWebUrlForDisplay(url);
  }
  return result;
}

List<Json> _uniqueWebSources(Iterable<Json> sources) {
  final result = <Json>[];
  final indexes = <String, int>{};
  for (final source in sources) {
    final url = source['url'] as String? ?? '';
    if (url.isEmpty) continue;
    final existingIndex = indexes[url];
    if (existingIndex == null) {
      indexes[url] = result.length;
      result.add(source);
      continue;
    }
    final existing = result[existingIndex];
    result[existingIndex] = {
      ...source,
      ...existing,
      for (final key in const ['title', 'snippet', 'publishedAt'])
        if ((existing[key] as String?)?.trim().isEmpty ?? true)
          if ((source[key] as String?)?.trim().isNotEmpty == true)
            key: source[key],
    };
  }
  return result;
}

class _WebSearchProcessDetail extends StatelessWidget {
  final String processKey;
  final String title;
  final String content;
  final List<Json> results;
  final String contentLabel;
  final String resultsLabel;
  final String emptyMessage;
  final bool completed;

  const _WebSearchProcessDetail({
    required this.processKey,
    required this.title,
    required this.content,
    required this.results,
    required this.contentLabel,
    required this.resultsLabel,
    required this.emptyMessage,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _processPreview(content);
    final resultSummary = results
        .map((source) => source['title'] as String? ?? '')
        .where((value) => value.trim().isNotEmpty)
        .join('、');
    final summary = normalized.isNotEmpty
        ? normalized
        : _processPreview(resultSummary);
    if (summary.isEmpty && !completed) {
      return _ProcessDetail(label: title, emphasized: true);
    }
    return _ProcessDisclosure(
      key: ValueKey('agent-web-search-$processKey'),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.appColors.muted, fontSize: 12),
      ),
      child: Container(
        key: ValueKey('agent-web-search-details-$processKey'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appColors.paperSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.appColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.trim().isNotEmpty) ...[
              _ProcessSectionLabel(contentLabel),
              const SizedBox(height: 4),
              SelectableText(
                content.trim(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (results.isNotEmpty) ...[
              if (content.trim().isNotEmpty) const SizedBox(height: 10),
              _ProcessSectionLabel(resultsLabel),
              const SizedBox(height: 5),
              for (var index = 0; index < results.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _WebSearchResult(source: results[index]),
              ],
            ] else if (completed) ...[
              if (content.trim().isNotEmpty) const SizedBox(height: 10),
              _ProcessSectionLabel(resultsLabel),
              const SizedBox(height: 4),
              Text(
                emptyMessage,
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessSectionLabel extends StatelessWidget {
  final String text;
  const _ProcessSectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.appColors.muted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _WebSearchResult extends StatelessWidget {
  final Json source;
  const _WebSearchResult({required this.source});

  @override
  Widget build(BuildContext context) {
    final url = source['url'] as String? ?? '';
    final title = (source['title'] as String?)?.trim();
    final snippet = (source['snippet'] as String?)?.trim();
    final publishedAt = (source['publishedAt'] as String?)?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title?.isNotEmpty == true)
          SelectableText(
            title!,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        if (title?.isNotEmpty == true) const SizedBox(height: 2),
        SelectableText(
          url,
          style: TextStyle(color: context.appColors.muted, fontSize: 11),
        ),
        if (snippet?.isNotEmpty == true) ...[
          const SizedBox(height: 3),
          Text(
            snippet!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, height: 1.35),
          ),
        ],
        if (publishedAt?.isNotEmpty == true) ...[
          const SizedBox(height: 3),
          Text(
            publishedAt!,
            style: TextStyle(color: context.appColors.muted, fontSize: 10.5),
          ),
        ],
      ],
    );
  }
}

class _ReasoningProcessDetail extends StatelessWidget {
  final String processKey;
  final String title;
  final String content;
  const _ReasoningProcessDetail({
    required this.processKey,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) => _ProcessDisclosure(
    key: ValueKey('agent-reasoning-$processKey'),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      _processPreview(content),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.appColors.muted, fontSize: 12),
    ),
    child: content.isEmpty
        ? const SizedBox.shrink()
        : Container(
            key: ValueKey('agent-reasoning-details-$processKey'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.appColors.paperSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appColors.line),
            ),
            child: FkMarkdownView(data: content, compact: true),
          ),
  );
}

class _StageProcessDetail extends StatelessWidget {
  final String processKey;
  final String title;
  final String content;

  const _StageProcessDetail({
    required this.processKey,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) => _ProcessDisclosure(
    key: ValueKey('agent-stage-$processKey'),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      _processPreview(content),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.appColors.muted, fontSize: 12),
    ),
    child: Container(
      key: ValueKey('agent-stage-details-$processKey'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appColors.paperSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appColors.line),
      ),
      child: FkMarkdownView(data: content, compact: true),
    ),
  );
}

class _PlanProcessDetail extends StatelessWidget {
  final String processKey;
  final String title;
  final String summary;
  final List<Json> steps;

  const _PlanProcessDetail({
    required this.processKey,
    required this.title,
    required this.summary,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) => _ProcessDisclosure(
    key: ValueKey('agent-plan-$processKey'),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      summary,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.appColors.muted, fontSize: 12),
    ),
    child: Container(
      key: ValueKey('agent-plan-details-$processKey'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.appColors.paperSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appColors.line),
      ),
      child: Column(
        children: [
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    switch (step['status']) {
                      'completed' => Icons.check_circle_rounded,
                      'in_progress' => Icons.play_circle_outline_rounded,
                      _ => Icons.radio_button_unchecked_rounded,
                    },
                    size: 16,
                    color: step['status'] == 'in_progress'
                        ? Theme.of(context).colorScheme.primary
                        : context.appColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step['title'] as String? ?? '',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _ToolProcessDetail extends StatelessWidget {
  final String operationId;
  final String name;
  final String summary;
  final String status;
  final Duration? duration;
  final String arguments;
  final String? result;
  final bool failed;
  const _ToolProcessDetail({
    required this.operationId,
    required this.name,
    required this.summary,
    required this.status,
    required this.duration,
    required this.arguments,
    required this.result,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final durationLabel = duration == null
        ? null
        : duration!.inMilliseconds < 1000
        ? '${duration!.inMilliseconds} ms'
        : '${(duration!.inMilliseconds / 1000).toStringAsFixed(1)} s';
    return _ProcessDisclosure(
      key: ValueKey('agent-tool-$operationId'),
      title: Text(
        name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Row(
        children: [
          if (summary.isNotEmpty) ...[
            Expanded(
              child: Text(
                summary.replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          Text(
            [status, ?durationLabel].join(' · '),
            style: TextStyle(
              color: failed
                  ? Theme.of(context).colorScheme.error
                  : context.appColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
      child: Container(
        key: ValueKey('agent-tool-details-$operationId'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appColors.paperSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.appColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.agentToolInput,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              arguments,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            if (result != null) ...[
              const SizedBox(height: 9),
              Text(
                context.l10n.agentToolResult,
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                result!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Content-sized disclosure used by process rows. [ExpansionTile] delegates to
/// a fixed-height [ListTile], which clips a two-line plan summary at larger
/// text scales and produced the visible RenderFlex overflow stripe.
class _ProcessDisclosure extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget child;

  const _ProcessDisclosure({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  State<_ProcessDisclosure> createState() => _ProcessDisclosureState();
}

class _ProcessDisclosureState extends State<_ProcessDisclosure> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: _expanded,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.title,
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            widget.subtitle!,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: AppIcon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 19,
                        color: context.appColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (_expanded)
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 4, 9),
          child: widget.child,
        ),
    ],
  );
}

class _AgentCollectionRow extends StatelessWidget {
  final String label;
  final String summary;
  final VoidCallback onTap;

  const _AgentCollectionRow({
    super.key,
    required this.label,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: 5),
            AppIcon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.appColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AgentNoteEntry {
  final Json reference;
  final Note? note;

  const _AgentNoteEntry({required this.reference, required this.note});
}

class _AgentNoteCollectionSheet extends StatelessWidget {
  final String title;
  final List<_AgentNoteEntry> notes;
  final Map<String, Json> webSources;
  final bool visitedWebFallback;
  final bool noteChanges;

  const _AgentNoteCollectionSheet({
    required this.title,
    required this.notes,
    required this.webSources,
    required this.visitedWebFallback,
    required this.noteChanges,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('agent-note-collection-sheet'),
    height: MediaQuery.sizeOf(context).height * .68,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Divider(height: 1, color: context.appColors.line),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              for (final entry in notes)
                _AgentNoteCollectionTile(
                  entry: entry,
                  noteChanges: noteChanges,
                ),
              if (visitedWebFallback && webSources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                  child: Text(
                    context.l10n.agentVisitedWebSources,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              for (final source in webSources.entries)
                _AgentWebSourceTile(url: source.key, source: source.value),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AgentNoteCollectionTile extends StatelessWidget {
  final _AgentNoteEntry entry;
  final bool noteChanges;

  const _AgentNoteCollectionTile({
    required this.entry,
    required this.noteChanges,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final note = entry.note;
    final referenceTitle = (entry.reference['title'] as String?)?.trim();
    final title = note?.title.trim().isNotEmpty == true
        ? note!.title.trim()
        : referenceTitle?.isNotEmpty == true
        ? referenceTitle!
        : l.untitled;
    final format = DateFormat('yyyy/M/d HH:mm', l.localeName);
    final metadata = <String>[];
    final deleted = noteChanges && entry.reference['deleted'] == true;
    final created = noteChanges && entry.reference['created'] == true;
    final operationLabel = noteChanges
        ? deleted
              ? l.agentNoteDeleted
              : created
              ? l.agentNoteCreated
              : switch (entry.reference['kind']) {
                  'append' => l.agentNoteAppended,
                  'metadata' => l.agentNoteMetadataUpdated,
                  _ => l.agentNoteEdited,
                }
        : null;
    if (note != null) {
      if (created) {
        metadata.add(
          '${l.creationTime} ${format.format(note.createdAt.toLocal())}',
        );
      }
      metadata.add(
        l.calendarUpdatedAt(format.format(note.updatedAt.toLocal())),
      );
      if (noteChanges) {
        metadata.add('r${note.revision}');
      }
    } else if (deleted) {
      if (entry.reference['previousRevision'] case final int revision) {
        metadata.add('r$revision');
      }
    } else {
      metadata.add(l.sourceNoteUnavailable);
    }
    final tags =
        note?.tags ??
        (entry.reference['tags'] as List? ?? const [])
            .whereType<String>()
            .toList();
    final rawId = entry.reference['noteId'] as String?;
    return InkWell(
      key: rawId == null ? null : ValueKey('agent-source-note-$rawId'),
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: note == null || deleted
          ? null
          : () => Navigator.pop(context, entry.reference),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (operationLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: deleted
                                ? Theme.of(context).colorScheme.errorContainer
                                : context.appColors.paperSecondary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            operationLabel,
                            style: TextStyle(
                              color: deleted
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer
                                  : context.appColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        for (final tag in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.appColors.paperSecondary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    metadata.join(' · '),
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (note != null && !deleted) ...[
              const SizedBox(width: 10),
              AppIcon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.appColors.muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentWebSourceTile extends StatelessWidget {
  final String url;
  final Json source;

  const _AgentWebSourceTile({required this.url, required this.source});

  @override
  Widget build(BuildContext context) {
    final title = (source['title'] as String?)?.trim();
    final uri = Uri.parse(url);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title?.isNotEmpty == true ? title! : uri.host,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          FkMarkdownView(data: '[$url]($url)', compact: true),
        ],
      ),
    );
  }
}

class LocalAgentGenerationIndicator extends StatelessWidget {
  final String label;
  const LocalAgentGenerationIndicator({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('agent-generation-status'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 17,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _ProposalDecision {
  final bool accept;
  final Json? arguments;
  const _ProposalDecision(this.accept, [this.arguments]);
}

class _ProposalSheet extends StatefulWidget {
  final PendingTool pending;
  final AgentService service;
  final AgentRun run;
  const _ProposalSheet({
    required this.pending,
    required this.service,
    required this.run,
  });
  @override
  State<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends State<_ProposalSheet> {
  late final Json _arguments = jsonCopy(widget.pending.call.arguments);
  late final List<Json> _changes =
      (widget.pending.preview!.data['changes'] as List? ?? []).cast<Json>();
  late final Set<int> _selected = {for (var i = 0; i < _changes.length; i++) i};
  bool _adjusted = false;
  Future<void> _edit(int i) async {
    final args = _arguments['changes'][i] as Json;
    if (args['kind'] == 'delete') return;
    final body = TextEditingController(text: args['text'] as String? ?? '');
    final after = _changes[i]['after'] as Json?;
    final before = _changes[i]['before'] as Json?;
    final title = TextEditingController(
      text:
          args['title'] as String? ??
          after?['title'] as String? ??
          before?['title'] as String? ??
          '',
    );
    final yes = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.agentEditProposal),
        content: _PrivacyGuard(
          service: widget.service,
          run: widget.run,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: context.l10n.title),
                ),
                if (args['kind'] != 'metadata')
                  TextField(
                    controller: body,
                    minLines: 3,
                    maxLines: 12,
                    maxLength: 12000,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      setState(() {
        if (args['kind'] != 'metadata') args['text'] = body.text;
        args['title'] = title.text;
        _adjusted = true;
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      body.dispose();
      title.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => _PrivacyGuard(
    service: widget.service,
    run: widget.run,
    child: _buildProposal(context),
  );

  Widget _buildProposal(BuildContext context) {
    final l = context.l10n;
    final data = widget.pending.preview!.data;
    final adjusted = _adjusted || _selected.length != _changes.length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.agentReview, style: Theme.of(context).textTheme.titleLarge),
            Expanded(
              child: ListView(
                children: [
                  if (_changes.isEmpty) ...[
                    Text(
                      '${data['server'] ?? widget.pending.call.name}\n${data['endpoint'] ?? ''}',
                    ),
                    Text(l.agentReconcileNotice),
                    SelectableText(canonicalJson(data['arguments'] ?? data)),
                  ],
                  for (var i = 0; i < _changes.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              value: _selected.contains(i),
                              title: Text(
                                (_changes[i]['after'] as Json?)?['title']
                                        as String? ??
                                    (_changes[i]['before'] as Json?)?['title']
                                        as String? ??
                                    l.untitled,
                              ),
                              subtitle: Text(
                                '${_changes[i]['kind'] == 'delete' ? '${l.agentNoteDeleted} · ' : ''}r${_changes[i]['baseRevision']} · ${_changes[i]['noteId']}',
                              ),
                              onChanged: (v) => setState(() {
                                if (v!) {
                                  _selected.add(i);
                                } else {
                                  _selected.remove(i);
                                }
                              }),
                            ),
                            Text(
                              l.agentBefore,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            SelectableText(
                              _changes[i]['beforeText'] as String? ?? '',
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.agentAfter,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            SelectableText(
                              _changes[i]['afterText'] as String? ?? '',
                            ),
                            Text(
                              '${(_changes[i]['before'] as Json?)?['tags'] ?? []} → ${(_changes[i]['after'] as Json?)?['tags'] ?? []}',
                            ),
                            if (_changes[i]['kind'] != 'delete')
                              TextButton(
                                onPressed: () => _edit(i),
                                child: Text(l.agentEditProposal),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            FilledButton(
              key: const Key('agent-approve-proposal'),
              onPressed: _changes.isNotEmpty && _selected.isEmpty
                  ? null
                  : () {
                      if (adjusted) {
                        final selected = _selected.toList()..sort();
                        Navigator.pop(
                          context,
                          _ProposalDecision(false, {
                            'changes': [
                              for (final i in selected)
                                _arguments['changes'][i],
                            ],
                          }),
                        );
                      } else {
                        Navigator.pop(context, const _ProposalDecision(true));
                      }
                    },
              child: Text(adjusted ? l.agentAdjustPreview : l.agentApprove),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const _ProposalDecision(false)),
              child: Text(l.agentReject),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyGuard extends StatelessWidget {
  final AgentService service;
  final AgentRun run;
  final Widget child;
  const _PrivacyGuard({
    required this.service,
    required this.run,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => service.canDisplay(run)
        ? child
        : Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.agentPrivateHidden),
          ),
  );
}

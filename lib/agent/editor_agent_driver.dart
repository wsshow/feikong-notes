import 'package:fknotes_harness/fknotes_harness.dart';

import '../models/local_llm.dart';
import '../models/note.dart';
import 'agent_service.dart';
import 'model_profile.dart';

abstract interface class NoteInlineAssistantDriver {
  Future<void> load();
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request);
  Future<void> cancel();
}

/// Uses the same durable runtime as chat, while Quill retains exclusive
/// ownership of its draft, selection, preview and undo history.
class HarnessEditorDriver implements NoteInlineAssistantDriver {
  HarnessEditorDriver({AgentService? service}) : _provided = service;
  final AgentService? _provided;
  AgentService get service => _provided ?? AgentService.instance;
  late ModelProfile profile;
  late RunScope scope;
  late RunLimits limits;
  late Note note;
  late String instruction;
  String? _runId;
  bool _cancelled = false;

  void configure({
    required ModelProfile profile,
    required RunScope scope,
    required RunLimits limits,
    required Note note,
    required String instruction,
  }) {
    this.profile = profile;
    this.scope = scope;
    this.limits = limits;
    this.note = note;
    this.instruction = instruction;
    _runId = null;
    _cancelled = false;
  }

  @override
  Future<void> load() => service.initialize();

  @override
  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    if (_cancelled) return;
    if (!scope.permitsNote(note.id.value) ||
        note.isPrivate != scope.privateNotes) {
      throw const HarnessException(
        'noteScope',
        'Grant access to the current draft.',
      );
    }
    final id = await service.start(
      sessionId: 'editor:${note.id.value}',
      input: instruction,
      profileId: profile.id,
      scope: scope,
      limits: limits,
      skillId: 'editor',
      system: request.messages
          .where((m) => m.role == LocalLlmRole.system)
          .map((m) => m.content)
          .join('\n'),
      history: [
        for (final message in request.messages.where(
          (m) => m.role != LocalLlmRole.system,
        ))
          AgentMessage(
            role: MessageRole.user,
            text: message.content,
            sources: [
              {
                'noteId': note.id.value,
                'title': note.title,
                'revision': note.revision,
              },
            ],
          ),
      ],
    );
    _runId = id;
    if (_cancelled) await service.cancel(id);
    var run = (await service.runtime.get(id))!;
    var visible = run.answer;
    if (visible.isNotEmpty) yield LocalLlmTextDelta(visible, replace: true);
    LocalLlmGenerationCompleted finished(AgentRun r) {
      if (r.status == RunStatus.failed) {
        throw HarnessException(
          r.errorCode ?? 'task',
          'Editor task did not complete.',
        );
      }
      return LocalLlmGenerationCompleted(
        reason: r.status == RunStatus.completed
            ? LocalLlmFinishReason.completed
            : LocalLlmFinishReason.canceled,
      );
    }

    bool stopped(AgentRun r) =>
        r.status.terminal ||
        {RunStatus.paused, RunStatus.interrupted}.contains(r.status);
    if (stopped(run)) {
      yield finished(run);
      return;
    }
    await for (final event in service.runtime.watch(id, afterSeq: run.seq)) {
      if (!{
        'text',
        'draftReset',
        'status',
        'snapshot',
        'completed',
      }.contains(event.type)) {
        continue;
      }
      run = (await service.runtime.get(id))!;
      if (run.answer != visible) {
        visible = run.answer;
        yield LocalLlmTextDelta(visible, replace: true);
      }
      if (stopped(run)) {
        yield finished(run);
        return;
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final id = _runId;
    if (id != null) await service.cancel(id);
  }
}

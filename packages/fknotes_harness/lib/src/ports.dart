import 'dart:async';

import 'models.dart';

class CancellationToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) {
      throw const HarnessException('cancelled', 'Execution was cancelled.');
    }
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

class ModelRequest {
  final List<AgentMessage> messages;
  final List<ToolSpec> tools;
  final int maxOutputTokens;
  final bool webSearch;
  const ModelRequest({
    required this.messages,
    required this.tools,
    required this.maxOutputTokens,
    this.webSearch = false,
  });
}

sealed class ModelEvent {
  const ModelEvent();
}

class ModelText extends ModelEvent {
  final String text;
  const ModelText(this.text);
}

/// Reasoning text explicitly emitted by the selected model/provider.
class ModelReasoning extends ModelEvent {
  final String text;
  const ModelReasoning(this.text);
}

class ModelActivity extends ModelEvent {
  final String kind;
  final String? id;
  final String? detail;
  final Json data;
  final bool completed;
  const ModelActivity(
    this.kind, {
    this.id,
    this.detail,
    this.data = const {},
    this.completed = false,
  });
}

class ModelCompleted extends ModelEvent {
  final AgentMessage message;
  final int? inputTokens;
  final int? outputTokens;
  final String finishReason;
  const ModelCompleted(
    this.message, {
    this.inputTokens,
    this.outputTokens,
    this.finishReason = 'stop',
  });
}

abstract interface class ModelPort {
  String get id;
  bool get isRemote;
  ModelCapabilities get capabilities;
  Stream<ModelEvent> generate(ModelRequest request, CancellationToken cancel);
}

typedef ModelResolver = Future<ModelPort> Function(String profileId);
typedef RunAuthorizer =
    Future<void> Function(AgentRun run, {ToolSpec? tool, bool sendingToModel});

abstract interface class RunStore {
  Future<AgentRun?> get(String id);
  Future<List<AgentRun>> list({String? sessionId});

  /// Atomic compare-and-swap. A new run has expectedRevision zero.
  Future<void> save(AgentRun run, {required int expectedRevision});
  Future<void> delete(String id);
}

class MemoryRunStore implements RunStore {
  final _records = <String, AgentRun>{};
  @override
  Future<AgentRun?> get(String id) async => _records[id]?.clone();
  @override
  Future<List<AgentRun>> list({String? sessionId}) async =>
      _records.values
          .where((r) => sessionId == null || r.sessionId == sessionId)
          .map((r) => r.clone())
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  @override
  Future<void> save(AgentRun run, {required int expectedRevision}) async {
    if ((_records[run.id]?.revision ?? 0) != expectedRevision ||
        run.revision != expectedRevision + 1) {
      throw const HarnessException(
        'writeConflict',
        'Run changed in another executor.',
      );
    }
    _records[run.id] = run.clone();
  }

  @override
  Future<void> delete(String id) async {
    _records.remove(id);
  }
}

class ToolContext {
  final AgentRun run;
  final String operationId;
  final String argumentsDigest;
  final CancellationToken cancel;
  final Future<void> Function() ensureActive;
  const ToolContext({
    required this.run,
    required this.operationId,
    required this.argumentsDigest,
    required this.cancel,
    required this.ensureActive,
  });
}

abstract class AgentTool {
  ToolSpec get spec;

  /// No side effects; returns a stable preview bound to current data versions.
  Future<ToolPreview> prepare(ToolContext context, Json arguments) async =>
      ToolPreview(data: arguments);

  /// Recover a committed result before re-preparing or executing a write.
  Future<ToolResult?> recover(ToolContext context, Json arguments) async =>
      null;
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  );
}

class AgentSkill {
  final String id;
  final String instructions;
  final Set<String>? allowedTools;
  const AgentSkill(this.id, this.instructions, {this.allowedTools});
  static const builtIn = [
    AgentSkill(
      'editor',
      'Return only text that can directly replace or extend the active note target. '
          'Do not add explanations, preambles, code fences, tool commentary, or unsupported facts. '
          'Preserve the requested language, meaning, and format. The editor owns application and undo. Do not invoke tools.',
      allowedTools: {},
    ),
    AgentSkill(
      'assistant',
      'Help the user work with notes. Use tools when needed; cite note IDs returned by tools.',
    ),
    AgentSkill(
      'summarize',
      'Find the relevant notes, summarize the evidence with sources, and separate facts from suggestions.',
    ),
    AgentSkill(
      'rewrite',
      'Improve clarity while preserving meaning, formatting and attachments. Use the note change tool and follow the task approval policy.',
    ),
    AgentSkill(
      'tasks',
      'Extract actionable checklists from the selected notes. Do not invent commitments or deadlines.',
    ),
    AgentSkill(
      'organize',
      'Inspect relevant notes, create a short plan, group related information and propose note/title/tag changes.',
    ),
  ];
}

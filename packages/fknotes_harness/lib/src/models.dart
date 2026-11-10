import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

Json jsonCopy(Json value) => _copyJsonValue(value) as Json;

Object? _copyJsonValue(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _copyJsonValue(entry.value),
    };
  }
  if (value is List) return value.map(_copyJsonValue).toList();
  return value;
}

String canonicalJson(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((e) => e.toString()).toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    return item;
  }

  return jsonEncode(sorted(value));
}

String contentDigest(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

class HarnessException implements Exception {
  final String code;
  final String message;
  final bool retryable;

  /// Safe, side-effect-free validation failures the model can correct. This
  /// never authorizes retrying an external operation with an unknown result.
  final bool toolObservation;
  const HarnessException(
    this.code,
    this.message, {
    this.retryable = false,
    this.toolObservation = false,
  });
  @override
  String toString() => '$code: $message';
}

enum RunStatus {
  queued,
  running,
  waitingApproval,
  paused,
  interrupted,
  cancelling,
  completed,
  cancelled,
  failed,
  needsReconciliation,
}

extension RunStatusState on RunStatus {
  bool get terminal =>
      this == RunStatus.completed ||
      this == RunStatus.cancelled ||
      this == RunStatus.failed;
}

enum MessageRole { system, user, assistant, tool }

enum ToolRisk { read, write }

enum ToolIdempotency { readOnly, transactional, external }

enum PendingPhase {
  pending,
  prepared,
  approved,
  executing,
  completed,
  rejected,
}

class RunScope {
  final bool online;
  final bool networkTools;
  final bool readNotes;
  final bool writeNotes;
  final bool externalWrites;

  /// Applies only to already granted writes; it never grants tool access.
  final bool requireApproval;
  final bool allNotes;
  final bool privateNotes;
  final int? privateGeneration;
  final String? modelBinding;
  final Set<String> networkBindings;
  final Set<String> noteIds;
  const RunScope({
    this.online = false,
    this.networkTools = false,
    this.readNotes = false,
    this.writeNotes = false,
    this.externalWrites = false,
    this.requireApproval = false,
    this.allNotes = false,
    this.privateNotes = false,
    this.privateGeneration,
    this.modelBinding,
    this.networkBindings = const {},
    this.noteIds = const {},
  });
  bool permitsNote(String id) =>
      readNotes && (allNotes || noteIds.contains(id));
  RunScope readOnly() => RunScope(
    requireApproval: requireApproval,
    online: online,
    networkTools: networkTools,
    readNotes: readNotes,
    allNotes: allNotes,
    privateNotes: privateNotes,
    privateGeneration: privateGeneration,
    modelBinding: modelBinding,
    networkBindings: Set.of(networkBindings),
    noteIds: Set.of(noteIds),
  );
  Json toJson() => {
    'online': online,
    'networkTools': networkTools,
    'readNotes': readNotes,
    'writeNotes': writeNotes,
    'externalWrites': externalWrites,
    'requireApproval': requireApproval,
    'allNotes': allNotes,
    'privateNotes': privateNotes,
    'privateGeneration': privateGeneration,
    'modelBinding': modelBinding,
    'networkBindings': networkBindings.toList(),
    'noteIds': noteIds.toList(),
  };
  factory RunScope.fromJson(Json j) => RunScope(
    online: j['online'] == true,
    networkTools: j['networkTools'] == true,
    readNotes: j['readNotes'] == true,
    writeNotes: j['writeNotes'] == true,
    externalWrites: j['externalWrites'] == true,
    // Old persisted tasks retain the manual approval contract they started with.
    requireApproval: j['requireApproval'] != false,
    allNotes: j['allNotes'] == true,
    privateNotes: j['privateNotes'] == true,
    privateGeneration: j['privateGeneration'] as int?,
    modelBinding: j['modelBinding'] as String?,
    networkBindings: Set<String>.from(j['networkBindings'] as List? ?? []),
    noteIds: Set<String>.from(j['noteIds'] as List? ?? []),
  );
}

class RunLimits {
  final int maxRequests;
  final int maxTokens;
  final int maxOutputTokens;
  final int maxRetries;
  final int maxChildren;
  final int maxDepth;
  final Duration activeTimeout;
  final Duration requestTimeout;
  const RunLimits({
    this.maxRequests = 20,
    this.maxTokens = 64000,
    this.maxOutputTokens = 2048,
    this.maxRetries = 2,
    this.maxChildren = 2,
    this.maxDepth = 1,
    this.activeTimeout = const Duration(minutes: 10),
    this.requestTimeout = const Duration(seconds: 90),
  });
  void validate() {
    if (maxRequests < 1 ||
        maxTokens < 1 ||
        maxOutputTokens < 1 ||
        maxRetries < 0 ||
        maxChildren < 1 ||
        maxDepth < 0 ||
        activeTimeout <= Duration.zero ||
        requestTimeout <= Duration.zero) {
      throw const HarnessException(
        'invalidLimits',
        'Run limits must be positive.',
      );
    }
  }

  Json toJson() => {
    'maxRequests': maxRequests,
    'maxTokens': maxTokens,
    'maxOutputTokens': maxOutputTokens,
    'maxRetries': maxRetries,
    'maxChildren': maxChildren,
    'maxDepth': maxDepth,
    'activeMs': activeTimeout.inMilliseconds,
    'requestMs': requestTimeout.inMilliseconds,
  };
  factory RunLimits.fromJson(Json j) => RunLimits(
    maxRequests: j['maxRequests'] as int? ?? 20,
    maxTokens: j['maxTokens'] as int? ?? 64000,
    maxOutputTokens: j['maxOutputTokens'] as int? ?? 2048,
    maxRetries: j['maxRetries'] as int? ?? 2,
    maxChildren: j['maxChildren'] as int? ?? 2,
    maxDepth: j['maxDepth'] as int? ?? 1,
    activeTimeout: Duration(milliseconds: j['activeMs'] as int? ?? 600000),
    requestTimeout: Duration(milliseconds: j['requestMs'] as int? ?? 90000),
  );
}

class ModelCapabilities {
  final bool tools;
  final bool images;
  final bool audio;
  final bool webSearch;
  final int contextTokens;
  final int? maxOutputTokens;
  const ModelCapabilities({
    this.tools = true,
    this.images = false,
    this.audio = false,
    this.webSearch = false,
    this.contextTokens = 16384,
    this.maxOutputTokens,
  });
  Json toJson() => {
    'tools': tools,
    'images': images,
    'audio': audio,
    'webSearch': webSearch,
    'contextTokens': contextTokens,
    'maxOutputTokens': maxOutputTokens,
  };
  factory ModelCapabilities.fromJson(Json j) => ModelCapabilities(
    tools: j['tools'] == true,
    images: j['images'] == true,
    audio: j['audio'] == true,
    webSearch: j['webSearch'] == true,
    contextTokens: j['contextTokens'] as int? ?? 16384,
    maxOutputTokens: j['maxOutputTokens'] as int?,
  );
}

class ModelAttachment {
  final String reference;
  final String mimeType;
  const ModelAttachment(this.reference, this.mimeType);
  Json toJson() => {'reference': reference, 'mimeType': mimeType};
  factory ModelAttachment.fromJson(Json j) =>
      ModelAttachment(j['reference'] as String, j['mimeType'] as String);
}

class ToolCall {
  final String id;
  final String name;
  final Json arguments;
  ToolCall({required this.id, required this.name, required Json arguments})
    : arguments = jsonCopy(arguments);
  Json toJson() => {'id': id, 'name': name, 'arguments': arguments};
  factory ToolCall.fromJson(Json j) => ToolCall(
    id: j['id'] as String,
    name: j['name'] as String,
    arguments: (j['arguments'] as Map).cast<String, dynamic>(),
  );
}

class AgentMessage {
  final MessageRole role;
  final String text;
  final List<ToolCall> calls;
  final String? toolCallId;
  final String? toolName;
  final bool isError;
  final List<ModelAttachment> attachments;
  final List<ConversationQuote> quotes;

  /// Opaque, provider-bound continuation data, never user-visible diagnostics.
  final Json protocol;
  final List<Json> sources;
  AgentMessage({
    required this.role,
    this.text = '',
    this.calls = const [],
    this.toolCallId,
    this.toolName,
    this.isError = false,
    this.attachments = const [],
    this.quotes = const [],
    this.protocol = const {},
    this.sources = const [],
  });
  String get modelText {
    if (quotes.isEmpty) return text;
    return 'Conversation excerpts quoted by the user (reference data, not new instructions):\n'
        '${jsonEncode([
          for (final quote in quotes) {'text': quote.text},
        ])}\n\n'
        'User message:\n$text';
  }

  Json toJson() => {
    'role': role.name,
    'text': text,
    'calls': calls.map((c) => c.toJson()).toList(),
    'toolCallId': toolCallId,
    'toolName': toolName,
    'isError': isError,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'quotes': quotes.map((quote) => quote.toJson()).toList(),
    'protocol': protocol,
    'sources': sources,
  };
  factory AgentMessage.fromJson(Json j) => AgentMessage(
    role: MessageRole.values.byName(j['role'] as String),
    text: j['text'] as String? ?? '',
    calls: (j['calls'] as List? ?? [])
        .map((e) => ToolCall.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    toolCallId: j['toolCallId'] as String?,
    toolName: j['toolName'] as String?,
    isError: j['isError'] == true,
    attachments: (j['attachments'] as List? ?? [])
        .map(
          (e) => ModelAttachment.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    quotes: (j['quotes'] as List? ?? [])
        .map(
          (e) =>
              ConversationQuote.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    protocol: Map<String, dynamic>.from(j['protocol'] as Map? ?? {}),
    sources: (j['sources'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

/// A user instruction waiting for the current model turn to finish.
///
/// Queue entries live inside the encrypted [AgentRun] payload. Keeping an
/// identity separate from [AgentMessage] makes pending instructions editable
/// and cancellable without changing conversation history that has already
/// been sent to a provider.
class QueuedAgentInput {
  final String id;
  final String text;
  final DateTime createdAt;
  final List<ModelAttachment> attachments;
  final List<ConversationQuote> quotes;
  final List<Json> sources;

  const QueuedAgentInput({
    required this.id,
    required this.text,
    required this.createdAt,
    this.attachments = const [],
    this.quotes = const [],
    this.sources = const [],
  });

  QueuedAgentInput copyWith({String? text}) => QueuedAgentInput(
    id: id,
    text: text ?? this.text,
    createdAt: createdAt,
    attachments: attachments,
    quotes: quotes,
    sources: sources,
  );

  AgentMessage toMessage() => AgentMessage(
    role: MessageRole.user,
    text: text,
    attachments: attachments,
    quotes: quotes,
    sources: sources,
  );

  Json toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'quotes': quotes.map((item) => item.toJson()).toList(),
    'sources': sources,
  };

  factory QueuedAgentInput.fromJson(Json json) {
    // Runs written before queue items gained identities stored AgentMessage
    // JSON here. The digest provides a stable compatibility identity.
    final id = switch (json['id']) {
      final String value when value.isNotEmpty => value,
      _ => 'legacy-${contentDigest(json).substring(0, 16)}',
    };
    return QueuedAgentInput(
      id: id,
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      attachments: (json['attachments'] as List? ?? const [])
          .map(
            (item) => ModelAttachment.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      quotes: (json['quotes'] as List? ?? const [])
          .map(
            (item) => ConversationQuote.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      sources: (json['sources'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }
}

/// A durable reference to text selected from an earlier conversation item.
///
/// [text] is a snapshot so the reference remains understandable after model
/// regeneration. Offsets are retained for best-effort navigation in the UI.
class ConversationQuote {
  final String id;
  final String sourceId;
  final String text;
  final int startOffset;
  final int endOffset;
  final int sourceLength;

  const ConversationQuote({
    required this.id,
    required this.sourceId,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.sourceLength,
  });

  Json toJson() => {
    'id': id,
    'sourceId': sourceId,
    'text': text,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'sourceLength': sourceLength,
  };

  factory ConversationQuote.fromJson(Json json) => ConversationQuote(
    id: json['id'] as String? ?? '',
    sourceId: json['sourceId'] as String? ?? '',
    text: json['text'] as String? ?? '',
    startOffset: json['startOffset'] as int? ?? 0,
    endOffset: json['endOffset'] as int? ?? 0,
    sourceLength: json['sourceLength'] as int? ?? 0,
  );
}

class ToolSpec {
  final String name;
  final String description;
  final Json schema;
  final ToolRisk risk;
  final ToolIdempotency idempotency;
  final bool network;
  final Duration timeout;
  const ToolSpec({
    required this.name,
    required this.description,
    required this.schema,
    this.risk = ToolRisk.read,
    this.idempotency = ToolIdempotency.readOnly,
    this.network = false,
    this.timeout = const Duration(seconds: 60),
  });
  Json toJson() => {
    'name': name,
    'description': description,
    'parameters': schema,
  };
}

class ToolPreview {
  final Json data;
  final Json versions;
  final bool requiresApproval;
  const ToolPreview({
    required this.data,
    this.versions = const {},
    this.requiresApproval = false,
  });
  String get digest => contentDigest({
    'data': data,
    'versions': versions,
    'requiresApproval': requiresApproval,
  });
  Json toJson() => {
    'data': data,
    'versions': versions,
    'requiresApproval': requiresApproval,
  };
  factory ToolPreview.fromJson(Json j) => ToolPreview(
    data: Map<String, dynamic>.from(j['data'] as Map),
    versions: Map<String, dynamic>.from(j['versions'] as Map? ?? {}),
    requiresApproval: j['requiresApproval'] == true,
  );
}

class ToolResult {
  final Json data;
  final bool isError;
  final List<Json> sources;
  const ToolResult(this.data, {this.isError = false, this.sources = const []});
  Json toJson() => {'data': data, 'isError': isError, 'sources': sources};
  factory ToolResult.fromJson(Json j) => ToolResult(
    Map<String, dynamic>.from(j['data'] as Map),
    isError: j['isError'] == true,
    sources: (j['sources'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

class PendingTool {
  final String operationId;
  final ToolCall call;
  final String argumentsDigest;
  PendingPhase phase;
  ToolPreview? preview;
  String? approvalId;
  String? approvedDigest;
  String? approvalMode;
  DateTime? approvalExpires;
  ToolResult? result;
  PendingTool({
    required this.operationId,
    required this.call,
    this.phase = PendingPhase.pending,
    this.preview,
    this.approvalId,
    this.approvedDigest,
    this.approvalMode,
    this.approvalExpires,
    this.result,
  }) : argumentsDigest = contentDigest(call.arguments);
  Json toJson() => {
    'operationId': operationId,
    'call': call.toJson(),
    'phase': phase.name,
    'preview': preview?.toJson(),
    'approvalId': approvalId,
    'approvedDigest': approvedDigest,
    'approvalMode': approvalMode,
    'approvalExpires': approvalExpires?.toIso8601String(),
    'result': result?.toJson(),
  };
  factory PendingTool.fromJson(Json j) => PendingTool(
    operationId: j['operationId'] as String,
    call: ToolCall.fromJson(Map<String, dynamic>.from(j['call'] as Map)),
    phase: PendingPhase.values.byName(j['phase'] as String),
    preview: j['preview'] == null
        ? null
        : ToolPreview.fromJson(Map<String, dynamic>.from(j['preview'] as Map)),
    approvalId: j['approvalId'] as String?,
    approvedDigest: j['approvedDigest'] as String?,
    approvalMode: j['approvalMode'] as String?,
    approvalExpires: j['approvalExpires'] == null
        ? null
        : DateTime.parse(j['approvalExpires'] as String),
    result: j['result'] == null
        ? null
        : ToolResult.fromJson(Map<String, dynamic>.from(j['result'] as Map)),
  );
}

class RunEvent {
  final String runId;
  final int seq;
  final String type;
  final Json data;
  final DateTime time;
  const RunEvent({
    required this.runId,
    required this.seq,
    required this.type,
    required this.data,
    required this.time,
  });
  Json toJson() => {
    'runId': runId,
    'seq': seq,
    'type': type,
    'data': data,
    'time': time.toIso8601String(),
  };
  factory RunEvent.fromJson(Json j) => RunEvent(
    runId: j['runId'] as String,
    seq: j['seq'] as int,
    type: j['type'] as String,
    data: Map<String, dynamic>.from(j['data'] as Map),
    time: DateTime.parse(j['time'] as String),
  );
}

/// Returns the observable agent round for every retained execution event.
///
/// Most tool loops start a new model request for every ReAct round and emit a
/// [RunEvent] of type `roundStarted`. Provider-managed tools are different: a
/// single HTTP response can contain several `reasoning -> webSearch` cycles.
/// Older runs therefore persisted every cycle with the initial round number.
/// A generation event after a provider tool is the first observable event of
/// the next round, unless a newer `roundStarted` event already established it.
Map<int, int> agentExecutionRoundOrdinals(Iterable<RunEvent> source) {
  final all = source.toList(growable: false);
  final marker = all.lastIndexWhere((event) => event.type == 'regenerated');
  final events = all.skip(marker + 1);
  final rounds = <int, int>{};
  final providerTools = <String>{};
  var currentRound = 0;
  var providerToolSinceGeneration = false;

  for (final event in events) {
    final explicitRound = event.data['round'] as int?;
    if (event.type == 'roundStarted') {
      if (explicitRound != null && explicitRound > currentRound) {
        currentRound = explicitRound;
      } else if (currentRound == 0) {
        currentRound = explicitRound ?? 1;
      }
      providerToolSinceGeneration = false;
      rounds[event.seq] = currentRound;
      continue;
    }

    final generationEvent = const {
      'reasoning',
      'text',
      'modelResponse',
      'completed',
    }.contains(event.type);
    if (explicitRound != null && explicitRound > currentRound) {
      currentRound = explicitRound;
      providerToolSinceGeneration = false;
    } else if (generationEvent && providerToolSinceGeneration) {
      currentRound = currentRound == 0 ? explicitRound ?? 1 : currentRound + 1;
      providerToolSinceGeneration = false;
    } else if (generationEvent && currentRound == 0) {
      currentRound = explicitRound ?? 1;
    }
    if (currentRound > 0) rounds[event.seq] = currentRound;

    if (event.type == 'activity' && event.data['kind'] == 'webSearch') {
      final storedKey = event.data['toolCallKey'];
      final activityId = event.data['id'];
      final key = storedKey is String && storedKey.isNotEmpty
          ? storedKey
          : activityId is String && activityId.isNotEmpty
          ? 'webSearch:$activityId'
          : 'webSearch:${explicitRound ?? currentRound}:${event.seq}';
      if (providerTools.add(key)) providerToolSinceGeneration = true;
    }
  }
  return rounds;
}

int agentExecutionRoundCount(Iterable<RunEvent> events) {
  var result = 0;
  for (final round in agentExecutionRoundOrdinals(events).values) {
    if (round > result) result = round;
  }
  return result;
}

class TaskRequest {
  final String sessionId;
  final String input;
  final String profileId;
  final String noteStoreEpoch;
  final RunScope scope;
  final RunLimits limits;
  final List<AgentMessage> history;
  final List<ModelAttachment> attachments;
  final List<Json> inputSources;
  final List<ConversationQuote> inputQuotes;
  final String system;
  final String skillId;
  final bool historyRequiresPrivateAccess;
  const TaskRequest({
    required this.sessionId,
    required this.input,
    required this.profileId,
    required this.noteStoreEpoch,
    this.scope = const RunScope(),
    this.limits = const RunLimits(),
    this.history = const [],
    this.attachments = const [],
    this.inputSources = const [],
    this.inputQuotes = const [],
    this.system = '',
    this.skillId = 'assistant',
    this.historyRequiresPrivateAccess = false,
  });
}

/// Mutable only inside the runtime's per-run serialized mutation queue.
class AgentRun {
  static const schemaVersion = 1;
  final String id;
  final String sessionId;
  final String? parentId;
  final String rootId;
  final String? retryOf;
  String? predecessorId;
  final int depth;
  String profileId;
  String noteStoreEpoch;
  RunScope scope;
  final RunLimits limits;
  final String system;
  final String skillId;
  String goal;
  final DateTime createdAt;
  DateTime updatedAt;
  RunStatus status;
  int revision;
  int epoch;
  int requestCount;
  int roundCount;
  int toolCallCount;
  int tokens;
  int reservedTokens;
  int activeMs;
  int seq;
  bool estimatedUsage;
  bool requiresPrivateAccess;

  /// Portable transcripts restored from backup remain readable but cannot
  /// replay the execution state that existed on another device.
  final bool historyOnly;
  bool conversationQueuePending;
  String draft;
  String summary;
  int contextStart;
  String? errorCode;
  String? errorMessage;
  final List<AgentMessage> messages;
  final List<PendingTool> pending;
  final List<QueuedAgentInput> steering;
  final List<RunEvent> events;
  final List<Json> reasoning;
  final List<Json> plan;
  final List<Json> actions;
  final List<String> children;
  final List<String> providerToolCallKeys;
  AgentRun({
    required this.id,
    required this.sessionId,
    required this.profileId,
    required this.noteStoreEpoch,
    required this.scope,
    required this.limits,
    required this.system,
    required this.skillId,
    this.goal = '',
    required this.createdAt,
    this.parentId,
    String? rootId,
    this.retryOf,
    this.predecessorId,
    this.depth = 0,
    DateTime? updatedAt,
    this.status = RunStatus.queued,
    this.revision = 0,
    this.epoch = 0,
    this.requestCount = 0,
    this.roundCount = 0,
    this.toolCallCount = 0,
    this.tokens = 0,
    this.reservedTokens = 0,
    this.activeMs = 0,
    this.seq = 0,
    this.estimatedUsage = false,
    bool requiresPrivateAccess = false,
    this.historyOnly = false,
    this.conversationQueuePending = false,
    this.draft = '',
    this.summary = '',
    this.contextStart = 0,
    this.errorCode,
    this.errorMessage,
    List<AgentMessage>? messages,
    List<PendingTool>? pending,
    List<QueuedAgentInput>? steering,
    List<RunEvent>? events,
    List<Json>? reasoning,
    List<Json>? plan,
    List<Json>? actions,
    List<String>? children,
    List<String>? providerToolCallKeys,
  }) : requiresPrivateAccess = requiresPrivateAccess || scope.privateNotes,
       rootId = rootId ?? id,
       updatedAt = updatedAt ?? createdAt,
       messages = messages ?? [],
       pending = pending ?? [],
       steering = steering ?? [],
       events = events ?? [],
       reasoning = reasoning ?? [],
       plan = plan ?? [],
       actions = actions ?? [],
       children = children ?? [],
       providerToolCallKeys = providerToolCallKeys ?? [];
  AgentRun clone() => AgentRun.fromJson(jsonCopy(toJson()));
  String get answer {
    if (draft.isNotEmpty) return draft;
    final input = messages.lastIndexWhere((m) => m.role == MessageRole.user);
    return messages
            .skip(input + 1)
            .where((m) => m.role == MessageRole.assistant && m.calls.isEmpty)
            .lastOrNull
            ?.text ??
        '';
  }

  Json toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'sessionId': sessionId,
    'parentId': parentId,
    'rootId': rootId,
    'retryOf': retryOf,
    'predecessorId': predecessorId,
    'depth': depth,
    'profileId': profileId,
    'noteStoreEpoch': noteStoreEpoch,
    'scope': scope.toJson(),
    'limits': limits.toJson(),
    'system': system,
    'skillId': skillId,
    'goal': goal,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'revision': revision,
    'epoch': epoch,
    'requestCount': requestCount,
    'roundCount': roundCount,
    'toolCallCount': toolCallCount,
    'tokens': tokens,
    'reservedTokens': reservedTokens,
    'activeMs': activeMs,
    'seq': seq,
    'estimatedUsage': estimatedUsage,
    'requiresPrivateAccess': requiresPrivateAccess,
    'historyOnly': historyOnly,
    'conversationQueuePending': conversationQueuePending,
    'draft': draft,
    'summary': summary,
    'contextStart': contextStart,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'messages': messages.map((m) => m.toJson()).toList(),
    'pending': pending.map((p) => p.toJson()).toList(),
    'steering': steering.map((m) => m.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'reasoning': reasoning,
    'plan': plan,
    'actions': actions,
    'children': children,
    'providerToolCallKeys': providerToolCallKeys,
  };
  factory AgentRun.fromJson(Json j) {
    if (j['schemaVersion'] != schemaVersion) {
      throw const HarnessException('schemaVersion', 'Unsupported run version.');
    }
    final legacyStats = j['roundCount'] == null || j['toolCallCount'] == null
        ? _legacyRunStats(j)
        : const (0, 0);
    final events = (j['events'] as List)
        .map((e) => RunEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final storedRoundCount = j['roundCount'] as int? ?? legacyStats.$1;
    final inferredRoundCount = agentExecutionRoundCount(events);
    return AgentRun(
      id: j['id'] as String,
      requiresPrivateAccess: j['requiresPrivateAccess'] == true,
      sessionId: j['sessionId'] as String,
      parentId: j['parentId'] as String?,
      rootId: j['rootId'] as String,
      retryOf: j['retryOf'] as String?,
      predecessorId: j['predecessorId'] as String?,
      depth: j['depth'] as int,
      profileId: j['profileId'] as String,
      noteStoreEpoch: j['noteStoreEpoch'] as String,
      scope: RunScope.fromJson(Map<String, dynamic>.from(j['scope'] as Map)),
      limits: RunLimits.fromJson(Map<String, dynamic>.from(j['limits'] as Map)),
      system: j['system'] as String,
      skillId: j['skillId'] as String,
      goal: j['goal'] as String? ?? '',
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      status: RunStatus.values.byName(j['status'] as String),
      revision: j['revision'] as int,
      epoch: j['epoch'] as int,
      requestCount: j['requestCount'] as int,
      roundCount: storedRoundCount >= inferredRoundCount
          ? storedRoundCount
          : inferredRoundCount,
      toolCallCount: j['toolCallCount'] as int? ?? legacyStats.$2,
      tokens: j['tokens'] as int,
      reservedTokens: j['reservedTokens'] as int? ?? 0,
      activeMs: j['activeMs'] as int? ?? 0,
      seq: j['seq'] as int,
      estimatedUsage: j['estimatedUsage'] == true,
      historyOnly: j['historyOnly'] == true,
      conversationQueuePending: j['conversationQueuePending'] == true,
      draft: j['draft'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      contextStart: j['contextStart'] as int? ?? 0,
      errorCode: j['errorCode'] as String?,
      errorMessage: j['errorMessage'] as String?,
      messages: (j['messages'] as List)
          .map(
            (e) => AgentMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      pending: (j['pending'] as List)
          .map((e) => PendingTool.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      steering: (j['steering'] as List? ?? [])
          .map(
            (e) =>
                QueuedAgentInput.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      events: events,
      reasoning: (j['reasoning'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      plan: (j['plan'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      actions: (j['actions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      children: List<String>.from(j['children'] as List? ?? []),
      providerToolCallKeys: List<String>.from(
        j['providerToolCallKeys'] as List? ?? const [],
      ),
    );
  }
}

(int, int) _legacyRunStats(Json json) {
  final rawEvents = (json['events'] as List? ?? const [])
      .whereType<Map>()
      .map((event) => Map<String, dynamic>.from(event))
      .toList();
  final marker = rawEvents.lastIndexWhere(
    (event) => event['type'] == 'regenerated',
  );
  final events = rawEvents.skip(marker + 1);
  final explicitRounds = <int>{};
  var responseRounds = 0;
  var completedRounds = 0;
  final operationIds = <String>{};
  final providerCalls = <String>{};
  var anonymousProviderCalls = 0;
  final anonymousOpen = <Object?>{};
  for (final event in events) {
    final type = event['type'];
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : const <String, dynamic>{};
    if (type == 'roundStarted' && data['round'] is int) {
      explicitRounds.add(data['round'] as int);
    } else if (type == 'modelResponse') {
      responseRounds++;
    } else if (type == 'completed') {
      completedRounds++;
    }
    if (const {
          'toolStarted',
          'toolCompleted',
          'approvalRequired',
        }.contains(type) &&
        data['operationId'] is String) {
      operationIds.add(data['operationId'] as String);
    }
    if (type != 'activity' || data['kind'] != 'webSearch') continue;
    final round = data['round'] ?? data['request'] ?? 0;
    final id = data['id'];
    if (id is String && id.isNotEmpty) {
      providerCalls.add('webSearch:$id');
    } else if (data['completed'] == true) {
      if (!anonymousOpen.remove(round)) anonymousProviderCalls++;
    } else if (anonymousOpen.add(round)) {
      anonymousProviderCalls++;
    }
  }
  final inferredRounds = explicitRounds.isNotEmpty
      ? explicitRounds.length
      : responseRounds + completedRounds;
  final requests = json['requestCount'] as int? ?? 0;
  return (
    inferredRounds > 0 ? inferredRounds : requests,
    operationIds.length + providerCalls.length + anonymousProviderCalls,
  );
}

import 'dart:async';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:test/test.dart';

class ScriptModel implements ModelPort {
  final FutureOr<ModelCompleted> Function(ModelRequest, CancellationToken, int)
  script;
  final bool remote;
  final bool tools;
  final bool webSearch;
  final int contextTokens;
  final int? maxOutputTokens;
  final requests = <ModelRequest>[];
  ScriptModel(
    this.script, {
    this.remote = false,
    this.tools = true,
    this.webSearch = false,
    this.contextTokens = 16384,
    this.maxOutputTokens,
  });
  @override
  String get id => remote ? 'remote' : 'local';
  @override
  bool get isRemote => remote;
  @override
  ModelCapabilities get capabilities => ModelCapabilities(
    tools: tools,
    webSearch: webSearch,
    contextTokens: contextTokens,
    maxOutputTokens: maxOutputTokens,
  );
  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    requests.add(request);
    yield await script(request, cancel, requests.length);
  }
}

class ScriptStreamModel implements ModelPort {
  final Stream<ModelEvent> Function(ModelRequest, CancellationToken, int)
  script;
  final requests = <ModelRequest>[];
  ScriptStreamModel(this.script);
  @override
  String get id => 'stream';
  @override
  bool get isRemote => false;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> generate(ModelRequest request, CancellationToken cancel) {
    requests.add(request);
    return script(request, cancel, requests.length);
  }
}

class ReasoningModel implements ModelPort {
  @override
  String get id => 'reasoning';
  @override
  bool get isRemote => false;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    yield const ModelReasoning('先检查');
    yield const ModelReasoning('现有内容。');
    yield reply('done');
  }
}

ModelCompleted reply(String text) => ModelCompleted(
  AgentMessage(role: MessageRole.assistant, text: text),
  inputTokens: 20,
  outputTokens: 10,
);
ModelCompleted call(
  String name, {
  Json args = const {},
  String id = 'call-1',
  String text = '',
}) => ModelCompleted(
  AgentMessage(
    role: MessageRole.assistant,
    text: text,
    calls: [ToolCall(id: id, name: name, arguments: args)],
  ),
  inputTokens: 20,
  outputTokens: 10,
);

class TestTool extends AgentTool {
  final bool write;
  final bool external;
  final bool network;
  final bool requiresApproval;
  int calls = 0;
  int version = 1;
  final receipts = <String, ToolResult>{};
  Future<void> Function()? afterWrite;
  TestTool({
    this.write = false,
    this.external = false,
    this.network = false,
    this.requiresApproval = false,
  });
  @override
  ToolSpec get spec => ToolSpec(
    name: 'echo',
    description: 'Test tool',
    schema: {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'},
      },
      'additionalProperties': false,
    },
    risk: write ? ToolRisk.write : ToolRisk.read,
    network: network,
    idempotency: external
        ? ToolIdempotency.external
        : write
        ? ToolIdempotency.transactional
        : ToolIdempotency.readOnly,
  );
  @override
  Future<ToolPreview> prepare(ToolContext context, Json arguments) async =>
      ToolPreview(
        data: arguments,
        versions: {'note': version},
        requiresApproval: requiresApproval,
      );
  @override
  Future<ToolResult?> recover(ToolContext context, Json arguments) async =>
      receipts[context.operationId];
  @override
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  ) async {
    await context.ensureActive();
    calls++;
    final result = ToolResult({
      'value': arguments['value'] ?? 'ok',
      'revision': ++version,
    });
    if (write && !external) receipts[context.operationId] = result;
    await afterWrite?.call();
    return result;
  }
}

class FailOnceStore extends MemoryRunStore {
  bool failCompletedTool = false;
  @override
  Future<void> save(AgentRun run, {required int expectedRevision}) async {
    if (failCompletedTool &&
        run.pending.any((p) => p.phase == PendingPhase.completed)) {
      failCompletedTool = false;
      throw StateError('simulated loss after note transaction');
    }
    await super.save(run, expectedRevision: expectedRevision);
  }
}

class CountingStore extends MemoryRunStore {
  int saves = 0;

  @override
  Future<void> save(AgentRun run, {required int expectedRevision}) async {
    saves++;
    await super.save(run, expectedRevision: expectedRevision);
  }
}

TaskRequest task({
  RunScope scope = const RunScope(
    readNotes: true,
    writeNotes: true,
    requireApproval: true,
  ),
  RunLimits limits = const RunLimits(),
  List<AgentMessage> history = const [],
  List<Json> inputSources = const [],
  List<ConversationQuote> inputQuotes = const [],
}) => TaskRequest(
  sessionId: 'session',
  input: 'Organize the selected notes',
  profileId: 'test',
  noteStoreEpoch: 'db-1',
  scope: scope,
  limits: limits,
  history: history,
  inputSources: inputSources,
  inputQuotes: inputQuotes,
);
HarnessRuntime runtime(
  ModelPort model, {
  RunStore? store,
  List<AgentTool> tools = const [],
  RunAuthorizer? authorize,
  Future<void> Function(Duration, CancellationToken)? retrySleep,
}) => HarnessRuntime(
  store: store ?? MemoryRunStore(),
  resolveModel: (_) async => model,
  authorize: authorize ?? (run, {tool, sendingToModel = false}) async {},
  tools: tools,
  retrySleep:
      retrySleep ??
      (duration, token) async {
        token.check();
      },
);
Future<AgentRun> settled(HarnessRuntime runtime, String id) async {
  await runtime.settle(id);
  return (await runtime.get(id))!;
}

Future<void> approve(
  HarnessRuntime runtime,
  AgentRun run, {
  bool accept = true,
}) async {
  final p = run.pending.firstWhere((p) => p.phase == PendingPhase.prepared);
  await runtime.approve(
    p.approvalId!,
    accept: accept,
    expectedDigest: p.preview!.digest,
  );
}

void main() {
  test('jsonCopy recursively isolates nested collections', () {
    final original = <String, dynamic>{
      'nested': {
        'items': [
          {'value': 1},
        ],
      },
    };
    final copied = jsonCopy(original);
    ((copied['nested'] as Json)['items'] as List).clear();
    expect(((original['nested'] as Json)['items'] as List), hasLength(1));
  });

  test('keeps current input sources on the persisted user message', () async {
    final harness = runtime(
      ScriptModel((request, cancel, index) => reply('ok')),
    );
    final id = await harness.start(
      task(
        inputSources: const [
          {'noteId': 'note-1', 'title': 'Project plan'},
        ],
      ),
    );
    final run = await settled(harness, id);

    expect(run.messages.first.sources, const [
      {'noteId': 'note-1', 'title': 'Project plan'},
    ]);
  });

  test(
    'persists conversation quotes and exposes them as model context',
    () async {
      final model = ScriptModel((request, cancel, index) => reply('ok'));
      final harness = runtime(model);
      const quote = ConversationQuote(
        id: 'quote-1',
        sourceId: 'run:earlier',
        text: 'Earlier answer excerpt',
        startOffset: 12,
        endOffset: 34,
        sourceLength: 80,
      );

      final id = await harness.start(task(inputQuotes: const [quote]));
      final run = await settled(harness, id);

      expect(run.messages.first.quotes.single.toJson(), quote.toJson());
      final userMessage = model.requests.single.messages.lastWhere(
        (message) => message.role == MessageRole.user,
      );
      expect(userMessage.text, 'Organize the selected notes');
      expect(userMessage.modelText, contains('Earlier answer excerpt'));
      expect(
        AgentMessage.fromJson(
          run.messages.first.toJson(),
        ).quotes.single.toJson(),
        quote.toJson(),
      );
    },
  );

  test(
    'regenerates a completed answer in place with one user message',
    () async {
      final model = ScriptModel(
        (request, cancel, index) => reply(index == 1 ? 'first' : 'second'),
      );
      final harness = runtime(model);
      final id = await harness.start(task());
      final first = await settled(harness, id);
      final createdAt = first.createdAt;
      expect(first.answer, 'first');

      await harness.regenerate(id);
      final regenerated = await settled(harness, id);

      expect(regenerated.id, id);
      expect(regenerated.createdAt, createdAt);
      expect(regenerated.answer, 'second');
      expect(
        regenerated.messages.where((m) => m.role == MessageRole.user),
        hasLength(1),
      );
      expect(regenerated.requestCount, 1);
      expect(
        regenerated.events.where((event) => event.type == 'regenerated'),
        hasLength(1),
      );
      expect(model.requests, hasLength(2));
      await harness.close();
    },
  );

  test(
    'persists provider reasoning separately from the final answer',
    () async {
      final harness = runtime(ReasoningModel());
      final id = await harness.start(task());
      final run = await settled(harness, id);
      expect(run.answer, 'done');
      expect(run.reasoning, [
        {'round': 1, 'request': 1, 'text': '先检查现有内容。'},
      ]);
      expect(
        run.events.where((event) => event.type == 'reasoning'),
        hasLength(1),
      );
      expect(
        run.events.where((event) => event.type == 'duration'),
        hasLength(1),
      );
      await harness.close();
    },
  );

  test('system prompt defers to supplied capability definitions', () async {
    final model = ScriptModel(
      (request, cancel, index) => reply('done'),
      remote: true,
      webSearch: true,
    );
    final harness = runtime(model, tools: [TestTool(network: true)]);
    final id = await harness.start(
      task(scope: const RunScope(online: true, networkTools: true)),
    );
    await settled(harness, id);

    final request = model.requests.single;
    final system = request.messages
        .firstWhere((message) => message.role == MessageRole.system)
        .text;
    expect(request.tools.map((tool) => tool.name), [
      'echo',
      'update_plan',
      'delegate',
    ]);
    expect(request.webSearch, isTrue);
    expect(
      system,
      contains('Use only capabilities supplied with the current request'),
    );
    expect(system, contains('describe their user-facing capabilities'));
    expect(
      system,
      contains(
        'Never enumerate the note library merely to inspect its structure',
      ),
    );
    expect(
      system,
      contains('create a new note directly unless the user explicitly asks'),
    );
    expect(system, isNot(contains('The complete tool list')));
    expect(system, isNot(contains('Use only tools in this exact list')));
    expect(system, isNot(contains('web_search')));
    expect(system, isNot(contains('open_page')));
    expect(system, isNot(contains('find_in_page')));
    await harness.close();
  });

  for (final requested in [393216, 524288]) {
    test(
      'remote output honors a 384K model limit for request $requested',
      () async {
        final model = ScriptModel(
          (r, t, i) => reply('done'),
          remote: true,
          contextTokens: 1048576,
          maxOutputTokens: 393216,
        );
        final harness = runtime(model);
        final id = await harness.start(
          task(
            scope: const RunScope(online: true),
            limits: RunLimits(maxOutputTokens: requested, maxTokens: 1441792),
          ),
        );
        expect((await settled(harness, id)).status, RunStatus.completed);
        expect(model.requests.single.maxOutputTokens, 393216);
        await harness.close();
      },
    );
  }
  for (final remote in [false, true]) {
    group(remote ? 'remote contract' : 'local contract', () {
      test('granted writes run automatically without approval', () async {
        final tool = TestTool(write: true);
        final model = ScriptModel(
          (r, t, i) => i == 1 ? call('echo') : reply('saved'),
          remote: remote,
        );
        final harness = runtime(model, tools: [tool]);
        final id = await harness.start(
          task(
            scope: RunScope(online: remote, readNotes: true, writeNotes: true),
          ),
        );
        final run = await settled(harness, id);
        expect(run.status, RunStatus.completed);
        expect(tool.calls, 1);
        expect(run.events.where((e) => e.type == 'approvalRequired'), isEmpty);
        expect(run.actions.single['approvalMode'], 'automatic');
        expect(run.actions.single['preview'], isNotNull);
        await harness.close();
      });
      test(
        'a tool preview can require approval for a destructive write',
        () async {
          final tool = TestTool(write: true, requiresApproval: true);
          final harness = runtime(
            ScriptModel((r, t, i) => i == 1 ? call('echo') : reply('deleted')),
            tools: [tool],
          );
          final id = await harness.start(
            task(
              scope: RunScope(
                online: remote,
                readNotes: true,
                writeNotes: true,
              ),
            ),
          );
          var run = await settled(harness, id);
          expect(run.status, RunStatus.waitingApproval);
          expect(tool.calls, 0);
          expect(
            run.events.singleWhere((e) => e.type == 'approvalRequired').data,
            containsPair('mandatory', true),
          );

          await approve(harness, run);
          run = await settled(harness, id);
          expect(run.status, RunStatus.completed);
          expect(tool.calls, 1);
          expect(run.actions.single['approvalMode'], 'manual');
          await harness.close();
        },
      );
      test(
        'runs a full tool loop with paired results and durable events',
        () async {
          final tool = TestTool();
          final model = ScriptModel(
            (req, token, i) =>
                i == 1 ? call('echo', args: {'value': 'hello'}) : reply('done'),
            remote: remote,
          );
          final harness = runtime(model, tools: [tool]);
          final id = await harness.start(
            task(scope: RunScope(online: remote, readNotes: true)),
          );
          final run = await settled(harness, id);
          expect(run.status, RunStatus.completed);
          expect(tool.calls, 1);
          expect(run.messages.map((m) => m.role), [
            MessageRole.user,
            MessageRole.assistant,
            MessageRole.tool,
            MessageRole.assistant,
          ]);
          expect(
            model.requests.last.messages
                .where((m) => m.role == MessageRole.tool)
                .single
                .toolCallId,
            'call-1',
          );
          expect(run.requestCount, 2);
          expect(run.roundCount, 2);
          expect(run.toolCallCount, 1);
          expect(run.tokens, 60);
          final events = await harness
              .watch(id)
              .take(run.events.length)
              .toList();
          expect(events.map((e) => e.seq).toSet().length, events.length);
          final started = run.events.singleWhere(
            (event) => event.type == 'toolStarted',
          );
          expect(started.data['callId'], 'call-1');
          expect(started.data['arguments'], {'value': 'hello'});
          final completed = run.events.singleWhere(
            (event) => event.type == 'toolCompleted',
          );
          expect(completed.data['callId'], 'call-1');
          expect(
            ((completed.data['result'] as Json)['data'] as Json)['value'],
            'hello',
          );
          await harness.close();
        },
      );
      test(
        'compacts streamed reasoning without losing its beginning',
        () async {
          final expected = StringBuffer();
          final model = ScriptStreamModel((request, cancel, round) async* {
            for (var index = 0; index < 650; index++) {
              final chunk = '$index,';
              expected.write(chunk);
              yield ModelReasoning(chunk);
              yield const ModelText('');
            }
            yield reply('done');
          });
          final harness = runtime(model);
          final id = await harness.start(task());
          final run = await settled(harness, id);
          final reasoningEvents = run.events
              .where((event) => event.type == 'reasoning')
              .toList(growable: false);

          expect(run.status, RunStatus.completed);
          expect(run.events.length, lessThan(500));
          expect(
            reasoningEvents
                .map((event) => event.data['text'] as String? ?? '')
                .join(),
            expected.toString(),
          );
          expect(run.reasoning.single['text'], expected.toString());
          await harness.close();
        },
      );
      test('does not execute write until approved', () async {
        final tool = TestTool(write: true);
        final model = ScriptModel(
          (r, t, i) => i == 1 ? call('echo') : reply('saved'),
          remote: remote,
        );
        final harness = runtime(model, tools: [tool]);
        final id = await harness.start(
          task(
            scope: RunScope(
              online: remote,
              readNotes: true,
              writeNotes: true,
              requireApproval: true,
            ),
          ),
        );
        var run = await settled(harness, id);
        expect(run.status, RunStatus.waitingApproval);
        expect(tool.calls, 0);
        await approve(harness, run);
        run = await settled(harness, id);
        expect(run.status, RunStatus.completed);
        expect(tool.calls, 1);
        await harness.close();
      });
    });
  }

  test(
    'legacy scopes retain approval and skipping never grants writes',
    () async {
      final old = RunScope.fromJson({'writeNotes': true});
      expect(old.requireApproval, isTrue);
      final scope = RunScope.fromJson(const RunScope().toJson());
      expect(scope.requireApproval, isFalse);
      final tool = TestTool(write: true);
      final harness = runtime(
        ScriptModel((r, t, i) => i == 1 ? call('echo') : reply('denied')),
        tools: [tool],
      );
      final id = await harness.start(task(scope: scope));
      final run = await settled(harness, id);
      expect(tool.calls, 0);
      expect(
        run.messages.where((m) => m.role == MessageRole.tool).single.isError,
        isTrue,
      );
      await harness.close();
    },
  );

  test('automatic writes recover receipts without a second mutation', () async {
    final store = FailOnceStore()..failCompletedTool = true;
    final tool = TestTool(write: true);
    final harness = runtime(
      ScriptModel((r, t, i) => i == 1 ? call('echo') : reply('saved')),
      store: store,
      tools: [tool],
    );
    final id = await harness.start(
      task(scope: const RunScope(writeNotes: true)),
    );
    expect((await settled(harness, id)).status, RunStatus.failed);
    final retry = await harness.retry(
      id,
      scope: const RunScope(writeNotes: true, requireApproval: true),
    );
    final run = await settled(harness, retry);
    expect(run.status, RunStatus.completed);
    expect(tool.calls, 1);
    expect(run.actions.single['approvalMode'], 'automatic');
    await harness.close();
  });

  test(
    'approval survives runtime recreation and is bound to current version',
    () async {
      final store = MemoryRunStore();
      final tool = TestTool(write: true);
      final model = ScriptModel(
        (r, t, i) => i == 1 ? call('echo') : reply('done'),
      );
      final original = runtime(model, store: store, tools: [tool]);
      final id = await original.start(task());
      final first = await settled(original, id);
      await original.close();
      tool.version++;
      final restored = runtime(model, store: store, tools: [tool]);
      await restored.recover();
      await approve(restored, first);
      var changed = await settled(restored, id);
      expect(changed.status, RunStatus.waitingApproval);
      expect(
        changed.pending.single.approvalId,
        isNot(first.pending.single.approvalId),
      );
      expect(tool.calls, 0);
      await approve(restored, changed);
      changed = await settled(restored, id);
      expect(changed.status, RunStatus.completed);
      expect(tool.calls, 1);
      await restored.close();
    },
  );

  test('rejecting a proposal feeds rejection back without writing', () async {
    final tool = TestTool(write: true);
    final model = ScriptModel(
      (r, t, i) => i == 1 ? call('echo') : reply('not changed'),
    );
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(task());
    await approve(harness, await settled(harness, id), accept: false);
    final run = await settled(harness, id);
    expect(tool.calls, 0);
    expect(
      run.messages.where((m) => m.role == MessageRole.tool).single.isError,
      isTrue,
    );
    await harness.close();
  });

  test('changing task while waiting invalidates the old approval', () async {
    final tool = TestTool(write: true);
    final model = ScriptModel(
      (r, t, i) => i == 1 ? call('echo') : reply('new answer'),
    );
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(task());
    final before = await settled(harness, id);
    await harness.steer(id, 'Only explain, do not edit');
    final after = await settled(harness, id);
    expect(after.status, RunStatus.completed);
    expect(tool.calls, 0);
    await expectLater(
      approve(harness, before),
      throwsA(isA<HarnessException>()),
    );
    await harness.close();
  });

  test(
    'queued instructions can be edited and cancelled before consumption',
    () async {
      final release = Completer<ModelCompleted>();
      final model = ScriptModel(
        (request, token, index) =>
            index == 1 ? release.future : reply('follow-up complete'),
      );
      final harness = runtime(model);
      final id = await harness.start(task());
      while (model.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final first = await harness.steer(id, 'first draft');
      final second = await harness.steer(id, 'remove me');
      await harness.editSteering(id, first, 'edited instruction');
      await harness.cancelSteering(id, second);
      final queued = await harness.get(id);
      expect(queued!.steering.map((item) => item.text), ['edited instruction']);

      release.complete(reply('initial complete'));
      final completed = await settled(harness, id);
      expect(completed.status, RunStatus.completed);
      expect(model.requests, hasLength(2));
      expect(model.requests.last.messages.last.text, 'edited instruction');
      expect(
        completed.events.where((event) => event.type == 'steeringCancelled'),
        hasLength(1),
      );
      await harness.close();
    },
  );

  test(
    'queued instructions run one at a time in their original order',
    () async {
      final release = Completer<ModelCompleted>();
      final model = ScriptModel((request, token, index) {
        if (index == 1) return release.future;
        return reply('completed follow-up ${index - 1}');
      });
      final harness = runtime(model);
      final id = await harness.start(task());
      while (model.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await harness.steer(id, 'queued one');
      await harness.steer(id, 'queued two');

      release.complete(reply('initial complete'));
      final completed = await settled(harness, id);
      expect(completed.status, RunStatus.completed);
      expect(model.requests, hasLength(3));
      expect(model.requests[1].messages.last.text, 'queued one');
      expect(model.requests[2].messages.last.text, 'queued two');
      expect(completed.steering, isEmpty);
      await harness.close();
    },
  );

  test('normal queued messages become distinct conversation turns', () async {
    final release = Completer<ModelCompleted>();
    final model = ScriptModel((request, token, index) {
      if (index == 1) return release.future;
      return reply('answer $index');
    });
    final harness = runtime(model);
    final firstId = await harness.start(task());
    while (model.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    final secondId = await harness.enqueue(firstId, 'second question');
    final thirdId = await harness.enqueue(secondId, 'third question');
    expect((await harness.get(secondId))!.conversationQueuePending, isTrue);
    expect((await harness.get(thirdId))!.conversationQueuePending, isTrue);
    expect(model.requests, hasLength(1));

    release.complete(reply('answer 1'));
    final first = await settled(harness, firstId);
    final second = await settled(harness, secondId);
    final third = await settled(harness, thirdId);

    expect(first.answer, 'answer 1');
    expect(second.answer, 'answer 2');
    expect(third.answer, 'answer 3');
    expect(second.conversationQueuePending, isFalse);
    expect(third.conversationQueuePending, isFalse);
    expect(model.requests, hasLength(3));
    expect(model.requests[1].messages.last.text, 'second question');
    expect(model.requests[2].messages.last.text, 'third question');
    await harness.close();
  });

  test(
    'editing reserves a queued message until the editor releases it',
    () async {
      final release = Completer<ModelCompleted>();
      final model = ScriptModel((request, token, index) {
        if (index == 1) return release.future;
        return reply('edited answer');
      });
      final harness = runtime(model);
      final firstId = await harness.start(task());
      while (model.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final queuedId = await harness.enqueue(firstId, 'draft question');
      await harness.beginQueuedEdit(queuedId);

      release.complete(reply('first answer'));
      await settled(harness, firstId);
      expect((await harness.get(queuedId))!.conversationQueuePending, isTrue);
      expect(model.requests, hasLength(1));

      await harness.finishQueuedEdit(queuedId, 'edited question');
      final queued = await settled(harness, queuedId);
      expect(queued.goal, 'edited question');
      expect(queued.answer, 'edited answer');
      expect(model.requests, hasLength(2));
      expect(model.requests.last.messages.last.text, 'edited question');
      await harness.close();
    },
  );

  test('promoting a queued message steers the active run', () async {
    final release = Completer<ModelCompleted>();
    final model = ScriptModel((request, token, index) {
      if (index == 1) return release.future;
      return reply('steered answer');
    });
    final harness = runtime(model);
    final activeId = await harness.start(task());
    while (model.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final queuedId = await harness.enqueue(activeId, 'change direction');

    await harness.promoteQueued(queuedId, activeId);
    expect(await harness.get(queuedId), isNull);
    expect(
      (await harness.get(activeId))!.steering.single.text,
      'change direction',
    );

    release.complete(reply('superseded answer'));
    final completed = await settled(harness, activeId);
    expect(completed.answer, 'steered answer');
    expect(model.requests, hasLength(2));
    expect(model.requests.last.messages.last.text, 'change direction');
    await harness.close();
  });

  test('cancelling a queued turn reconnects the remaining queue', () async {
    final release = Completer<ModelCompleted>();
    final model = ScriptModel((request, token, index) {
      if (index == 1) return release.future;
      return reply('remaining answer');
    });
    final harness = runtime(model);
    final activeId = await harness.start(task());
    while (model.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final cancelledId = await harness.enqueue(activeId, 'cancel me');
    final remainingId = await harness.enqueue(cancelledId, 'keep me');

    await harness.cancelQueued(cancelledId);
    expect(await harness.get(cancelledId), isNull);
    expect((await harness.get(remainingId))!.predecessorId, activeId);

    release.complete(reply('first answer'));
    await settled(harness, activeId);
    final remaining = await settled(harness, remainingId);
    expect(remaining.answer, 'remaining answer');
    expect(model.requests.last.messages.last.text, 'keep me');
    await harness.close();
  });

  test(
    'cancelling an idle model completes promptly and late tools never run',
    () async {
      final release = Completer<ModelCompleted>();
      final entered = Completer<void>();
      final tool = TestTool();
      final model = ScriptModel((r, t, i) {
        entered.complete();
        return release.future;
      });
      final harness = runtime(model, tools: [tool]);
      final id = await harness.start(task());
      await entered.future;
      await harness.cancel(id).timeout(const Duration(seconds: 1));
      expect((await harness.get(id))!.status, RunStatus.cancelled);
      release.complete(call('echo'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tool.calls, 0);
      await harness.close();
    },
  );

  test('pause cancels current request; resume uses the same task', () async {
    final entered = Completer<void>();
    final release = Completer<ModelCompleted>();
    final model = ScriptModel((r, t, i) {
      if (i == 1) {
        entered.complete();
        return release.future;
      }
      return reply('resumed');
    });
    final harness = runtime(model);
    final id = await harness.start(task());
    await entered.future;
    await harness.pause(id);
    expect((await harness.get(id))!.status, RunStatus.paused);
    await harness.resume(id);
    expect((await settled(harness, id)).answer, 'resumed');
    release.complete(reply('stale'));
    await harness.close();
  });

  test(
    'write receipt recovers a lost result without duplicate mutation',
    () async {
      final store = FailOnceStore();
      final tool = TestTool(write: true);
      final model = ScriptModel(
        (r, t, i) => i == 1 ? call('echo') : reply('saved'),
      );
      final harness = runtime(model, store: store, tools: [tool]);
      final id = await harness.start(task());
      final waiting = await settled(harness, id);
      store.failCompletedTool = true;
      await approve(harness, waiting);
      var run = await settled(harness, id);
      expect(run.status, RunStatus.failed);
      expect(tool.calls, 1);
      final retry = await harness.retry(id);
      run = await settled(harness, retry);
      expect(run.status, RunStatus.completed);
      expect(tool.calls, 1);
      expect(run.retryOf, id);
      await harness.close();
    },
  );

  for (final error in [
    StateError('lost reply'),
    const HarnessException(
      'toolFailure',
      'Unknown outcome',
      toolObservation: true,
    ),
  ]) {
    test(
      'external effect with ${error.runtimeType} requires reconciliation',
      () async {
        final tool = TestTool(write: true, external: true)
          ..afterWrite = () async {
            throw error;
          };
        final model = ScriptModel((r, t, i) => call('echo'));
        final harness = runtime(model, tools: [tool]);
        final id = await harness.start(task());
        await approve(harness, await settled(harness, id));
        final run = await settled(harness, id);
        expect(run.status, RunStatus.needsReconciliation);
        expect(tool.calls, 1);
        await expectLater(harness.resume(id), throwsA(isA<HarnessException>()));
        await harness.close();
      },
    );
  }

  test('offline scope prevents provider calls and network tools', () async {
    final model = ScriptModel((r, t, i) => reply('not reached'), remote: true);
    final harness = runtime(model);
    final id = await harness.start(task());
    expect((await settled(harness, id)).errorCode, 'onlineDenied');
    expect(model.requests, isEmpty);
    await harness.close();
    final tool = TestTool(network: true);
    final local = ScriptModel(
      (r, t, i) => i == 1 ? call('echo') : reply('denied'),
    );
    final offline = runtime(local, tools: [tool]);
    final localId = await offline.start(task());
    final run = await settled(offline, localId);
    expect(tool.calls, 0);
    expect(
      run.messages.where((m) => m.role == MessageRole.tool).single.text,
      contains('toolDenied'),
    );
    await offline.close();
  });

  test(
    'revoked authorization is checked again before tool execution',
    () async {
      var authorized = true;
      final tool = TestTool();
      final model = ScriptModel((r, t, i) {
        authorized = false;
        return call('echo');
      });
      final harness = runtime(
        model,
        tools: [tool],
        authorize: (r, {tool, sendingToModel = false}) async {
          if (!authorized) {
            throw const HarnessException(
              'permissionExpired',
              'Reauthorize this task.',
            );
          }
        },
      );
      final id = await harness.start(task());
      expect((await settled(harness, id)).errorCode, 'permissionExpired');
      expect(tool.calls, 0);
      await harness.close();
    },
  );

  test('invalid arguments and unknown tools are never executed', () async {
    final tool = TestTool();
    final model = ScriptModel(
      (r, t, i) => i == 1
          ? call('echo', args: {'value': 99})
          : i == 2
          ? call('missing')
          : reply('done'),
    );
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(task());
    final run = await settled(harness, id);
    expect(run.status, RunStatus.completed);
    expect(tool.calls, 0);
    expect(
      run.messages
          .where((m) => m.role == MessageRole.tool)
          .every((m) => m.isError),
      isTrue,
    );
    await harness.close();
  });

  test(
    'models without tool support cannot execute a fabricated call',
    () async {
      final tool = TestTool();
      final model = ScriptModel((r, t, i) => call('echo'), tools: false);
      final harness = runtime(model, tools: [tool]);
      final id = await harness.start(task());
      expect((await settled(harness, id)).errorCode, 'unsupportedTools');
      expect(model.requests.single.tools, isEmpty);
      expect(tool.calls, 0);
      await harness.close();
    },
  );

  test('request budget bounds a non-terminating tool loop', () async {
    final tool = TestTool();
    final model = ScriptModel(
      (r, t, i) => call('echo', args: {'value': '$i'}, id: '$i'),
    );
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(
      task(limits: const RunLimits(maxRequests: 2)),
    );
    final run = await settled(harness, id);
    expect(run.errorCode, 'budgetExceeded');
    expect(model.requests, hasLength(2));
    await harness.close();
  });

  test('child agents share request budget and have no write tools', () async {
    final tool = TestTool(write: true);
    final model = ScriptModel((r, t, i) {
      if (i == 1) return call('delegate', args: {'task': 'Find facts'});
      return reply('evidence');
    });
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(task());
    final run = await settled(harness, id);
    expect(run.status, RunStatus.completed);
    expect(run.children, hasLength(1));
    final child = (await harness.get(run.children.single))!;
    expect(child.scope.writeNotes, isFalse);
    expect(model.requests[1].tools.map((t) => t.name), isNot(contains('echo')));
    expect(
      model.requests[1].tools.map((t) => t.name),
      isNot(contains('delegate')),
    );
    expect(run.requestCount, 3);
    expect(run.roundCount, 2);
    expect(child.roundCount, 1);
    expect(tool.calls, 0);
    await harness.close();
  });

  test(
    'request timeout retries within budget and leaves no live executor',
    () async {
      final release = Completer<ModelCompleted>();
      final model = ScriptModel((r, t, i) => release.future);
      final harness = runtime(model);
      final id = await harness.start(
        task(
          limits: const RunLimits(
            requestTimeout: Duration(milliseconds: 20),
            maxRetries: 1,
          ),
        ),
      );
      final run = await settled(harness, id);
      expect(run.errorCode, 'requestTimeout');
      expect(run.requestCount, 2);
      expect(run.roundCount, 1);
      release.complete(reply('late'));
      await harness.close();
    },
  );

  test(
    'transient model failures retry with bounded backoff metadata',
    () async {
      final delays = <Duration>[];
      final model = ScriptModel((request, cancel, call) {
        if (call == 1) {
          throw const HarnessException(
            'serviceUnavailable',
            'Temporary provider failure.',
            retryable: true,
          );
        }
        return reply('recovered');
      });
      final harness = runtime(
        model,
        retrySleep: (duration, token) async {
          token.check();
          delays.add(duration);
        },
      );
      final id = await harness.start(task());
      final run = await settled(harness, id);

      expect(run.status, RunStatus.completed);
      expect(run.answer, 'recovered');
      expect(run.requestCount, 2);
      expect(run.roundCount, 1);
      expect(model.requests, hasLength(2));
      expect(delays, [const Duration(milliseconds: 250)]);
      final retry = run.events.singleWhere((event) => event.type == 'retry');
      expect(retry.data, {
        'attempt': 1,
        'delayMs': 250,
        'code': 'serviceUnavailable',
      });
      await harness.close();
    },
  );

  test('a partially received model response is never replayed', () async {
    final model = ScriptStreamModel((request, cancel, call) async* {
      yield const ModelReasoning('已经收到部分响应');
      throw const HarnessException(
        'serviceUnavailable',
        'Connection failed after response started.',
        retryable: true,
      );
    });
    final harness = runtime(model);
    final id = await harness.start(task());
    final run = await settled(harness, id);

    expect(run.status, RunStatus.failed);
    expect(run.errorCode, 'serviceUnavailable');
    expect(model.requests, hasLength(1));
    expect(run.roundCount, 1);
    expect(run.events.where((event) => event.type == 'retry'), isEmpty);
    await harness.close();
  });

  test('truncated output cannot trigger tools', () async {
    final tool = TestTool();
    final model = ScriptModel(
      (r, t, i) => ModelCompleted(call('echo').message, finishReason: 'length'),
    );
    final harness = runtime(model, tools: [tool]);
    final id = await harness.start(task());
    expect((await settled(harness, id)).errorCode, 'incompleteResponse');
    expect(tool.calls, 0);
    await harness.close();
  });

  test(
    'counts every tool call instance and deduplicates lifecycle events',
    () async {
      final tool = TestTool();
      final model = ScriptStreamModel((request, cancel, round) async* {
        if (round == 1) {
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'same-tool-1',
                  name: 'echo',
                  arguments: const {'value': 'first'},
                ),
                ToolCall(
                  id: 'same-tool-2',
                  name: 'echo',
                  arguments: const {'value': 'second'},
                ),
              ],
            ),
          );
          return;
        }
        yield const ModelActivity('webSearch', id: 'search-1');
        yield const ModelActivity('webSearch', id: 'search-1', completed: true);
        yield const ModelActivity('webSearch', id: 'search-2');
        yield const ModelActivity('webSearch', id: 'search-2', completed: true);
        yield reply('done');
      });
      final harness = runtime(model, tools: [tool]);
      final id = await harness.start(task());
      final run = await settled(harness, id);

      expect(run.status, RunStatus.completed);
      expect(run.roundCount, 3);
      expect(tool.calls, 2);
      expect(run.toolCallCount, 4);
      expect(run.providerToolCallKeys, hasLength(2));
      final legacyJson = run.toJson()
        ..remove('roundCount')
        ..remove('toolCallCount')
        ..remove('providerToolCallKeys');
      final migrated = AgentRun.fromJson(legacyJson);
      expect(migrated.roundCount, 3);
      expect(migrated.toolCallCount, 4);
      await harness.close();
    },
  );

  test('provider-managed tools advance observable agent rounds', () async {
    final model = ScriptStreamModel((request, cancel, call) async* {
      yield const ModelReasoning('先搜索今天的新闻。');
      yield const ModelActivity('webSearch', id: 'search-1');
      yield const ModelActivity('webSearch', id: 'search-1', completed: true);
      yield const ModelReasoning('再打开两篇关键报道。');
      yield const ModelActivity('webSearch', id: 'search-2');
      yield const ModelActivity('webSearch', id: 'search-2', completed: true);
      yield const ModelReasoning('现在整理最终结果。');
      yield reply('完成');
    });
    final harness = runtime(model);
    final id = await harness.start(task());
    final run = await settled(harness, id);

    expect(run.status, RunStatus.completed);
    expect(run.requestCount, 1);
    expect(run.roundCount, 3);
    expect(run.toolCallCount, 2);
    expect(run.reasoning.map((item) => item['round']), [1, 2, 3]);
    expect(
      run.events
          .where((event) => event.type == 'roundStarted')
          .map((event) => event.data['round']),
      [1, 2, 3],
    );
    expect(
      run.events
          .where((event) => event.type == 'activity')
          .map((event) => event.data['round']),
      [1, 1, 2, 2],
    );
    await harness.close();
  });

  test('provider-managed search evidence is persisted and bounded', () async {
    final oversized = List.filled(900, 'x').join();
    final rawResults = <Json>[
      for (var index = 0; index < 12; index++)
        {
          'url':
              'https://example.com/$index#section&ws_call_id=internal-$index',
          'title': 'Result $index',
          'snippet': oversized,
          'publishedAt': '2026-08-30',
          'ignored': 'must not persist',
        },
      {'url': 'javascript:alert(1)', 'title': 'unsafe'},
    ];
    final model = ScriptStreamModel((request, cancel, call) async* {
      yield ModelActivity(
        'webSearch',
        id: 'search-evidence',
        detail: 'current news',
        data: {
          'action': 'search',
          'resultDisclosure': 'available',
          'results': rawResults,
          'ignored': 'must not persist',
        },
        completed: true,
      );
      yield reply('done');
    });
    final harness = runtime(model);
    final id = await harness.start(task());
    final run = await settled(harness, id);

    final event = run.events.singleWhere(
      (event) =>
          event.type == 'activity' && event.data['id'] == 'search-evidence',
    );
    final metadata = (event.data['metadata'] as Map).cast<String, dynamic>();
    expect(metadata['action'], 'search');
    expect(metadata['resultDisclosure'], 'available');
    final results = (metadata['results'] as List).cast<Json>();
    expect(results, hasLength(10));
    expect(results.first.keys, {'url', 'title', 'snippet', 'publishedAt'});
    expect((results.first['snippet'] as String).runes.length, 801);
    expect(canonicalJson(metadata), isNot(contains('ws_call_id')));
    expect(canonicalJson(metadata), isNot(contains('must not persist')));
    expect(canonicalJson(metadata), isNot(contains('javascript:')));
    await harness.close();
  });

  test('repairs provider-managed rounds in persisted legacy runs', () async {
    final model = ScriptStreamModel((request, cancel, call) async* {
      yield const ModelReasoning('第一段');
      yield const ModelActivity('webSearch', id: 'search-1');
      yield const ModelActivity('webSearch', id: 'search-1', completed: true);
      yield const ModelReasoning('第二段');
      yield const ModelActivity('webSearch', id: 'search-2');
      yield const ModelActivity('webSearch', id: 'search-2', completed: true);
      yield const ModelReasoning('第三段');
      yield reply('完成');
    });
    final harness = runtime(model);
    final id = await harness.start(task());
    final json = (await settled(harness, id)).toJson();
    json['roundCount'] = 1;
    final events = (json['events'] as List).cast<Json>();
    events.removeWhere(
      (event) =>
          event['type'] == 'roundStarted' &&
          (event['data'] as Json)['round'] != 1,
    );
    for (final event in events) {
      final data = event['data'] as Json;
      if (data['round'] is int) data['round'] = 1;
    }

    final restored = AgentRun.fromJson(json);
    final ordinals = agentExecutionRoundOrdinals(restored.events);
    expect(restored.roundCount, 3);
    expect(
      restored.events
          .where((event) => event.type == 'reasoning')
          .map((event) => ordinals[event.seq]),
      [1, 2, 3],
    );
    await harness.close();
  });

  test(
    'dense streaming fragments are coalesced without changing content',
    () async {
      final model = ScriptStreamModel((request, cancel, call) async* {
        for (var index = 0; index < 200; index++) {
          yield const ModelReasoning('思');
        }
        yield const ModelActivity('webSearch');
        for (var index = 0; index < 200; index++) {
          yield const ModelReasoning('考');
        }
        yield reply('完成');
      });
      final harness = runtime(model);
      final id = await harness.start(task());
      final run = await settled(harness, id);

      expect(run.status, RunStatus.completed);
      expect(
        run.reasoning.map((item) => item['text']).join(),
        '${'思' * 200}${'考' * 200}',
      );
      expect(
        run.events.where((event) => event.type == 'reasoning'),
        hasLength(2),
      );
      await harness.close();
    },
  );

  test('timed streaming keeps persistence writes bounded', () async {
    const fragments = 40;
    final expected = List.generate(fragments, (index) => '$index,').join();
    final store = CountingStore();
    final model = ScriptStreamModel((request, cancel, call) async* {
      for (var index = 0; index < fragments; index++) {
        yield ModelText('$index,');
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      yield reply(expected);
    });
    final harness = runtime(model, store: store);
    final id = await harness.start(task());
    final run = await settled(harness, id);

    expect(run.answer, expected);
    expect(
      run.events.where((event) => event.type == 'text').length,
      lessThanOrEqualTo(4),
    );
    expect(store.saves, lessThanOrEqualTo(12));
    await harness.close();
  });

  test('context selection never separates a tool call from its result', () {
    final messages = [
      AgentMessage(role: MessageRole.user, text: 'old' * 1000),
      call('echo').message,
      AgentMessage(
        role: MessageRole.tool,
        text: 'result',
        toolCallId: 'call-1',
      ),
      AgentMessage(role: MessageRole.user, text: 'next'),
    ];
    final selected = ContextWindow.select(messages, 300);
    expect(selected.messages.map((m) => m.role), [
      MessageRole.assistant,
      MessageRole.tool,
      MessageRole.user,
    ]);
    expect(selected.omitted, hasLength(1));
  });

  test(
    'context selection keeps every result in multi-call exchanges atomic',
    () {
      final firstExchange = [
        AgentMessage(
          role: MessageRole.assistant,
          calls: [
            ToolCall(id: 'a', name: 'echo', arguments: {'value': 'a'}),
            ToolCall(id: 'b', name: 'echo', arguments: {'value': 'b'}),
          ],
        ),
        AgentMessage(role: MessageRole.tool, text: 'a', toolCallId: 'a'),
        AgentMessage(role: MessageRole.tool, text: 'b', toolCallId: 'b'),
      ];
      final recent = [
        AgentMessage(role: MessageRole.user, text: 'continue'),
        call('echo', id: 'c').message,
        AgentMessage(role: MessageRole.tool, text: 'c', toolCallId: 'c'),
        AgentMessage(role: MessageRole.assistant, text: 'done'),
      ];
      final messages = [
        AgentMessage(role: MessageRole.user, text: 'old' * 1000),
        ...firstExchange,
        ...recent,
      ];
      final recentBudget = recent.fold<int>(
        0,
        (sum, message) => sum + ContextWindow.messageTokens(message),
      );

      final selected = ContextWindow.select(messages, recentBudget);

      expect(selected.messages, hasLength(recent.length));
      expect(selected.messages.map((message) => message.toJson()), [
        for (final message in recent) message.toJson(),
      ]);
      expect(selected.omitted, hasLength(1 + firstExchange.length));
      expect(
        selected.omitted.where((message) => message.toolCallId != null),
        hasLength(2),
      );
    },
  );

  test(
    'independent read calls execute concurrently and preserve result order',
    () async {
      final bothStarted = Completer<void>();
      final tool = TestTool();
      tool.afterWrite = () async {
        if (tool.calls == 2 && !bothStarted.isCompleted) bothStarted.complete();
        await bothStarted.future;
      };
      final model = ScriptModel(
        (r, t, i) => i == 1
            ? ModelCompleted(
                AgentMessage(
                  role: MessageRole.assistant,
                  calls: [
                    ToolCall(
                      id: 'a',
                      name: 'echo',
                      arguments: {'value': 'first'},
                    ),
                    ToolCall(
                      id: 'b',
                      name: 'echo',
                      arguments: {'value': 'second'},
                    ),
                  ],
                ),
                inputTokens: 20,
                outputTokens: 10,
              )
            : reply('done'),
      );
      final harness = runtime(model, tools: [tool]);
      final id = await harness.start(task());
      final run = await settled(
        harness,
        id,
      ).timeout(const Duration(seconds: 2));
      expect(tool.calls, 2);
      expect(
        run.messages
            .where((m) => m.role == MessageRole.tool)
            .map((m) => m.toolCallId),
        ['a', 'b'],
      );
      await harness.close();
    },
  );

  test(
    'compression uses the same budget and preserves the current goal',
    () async {
      final model = ScriptModel(
        (r, t, i) => reply(i == 1 ? 'Earlier evidence: note-1' : 'done'),
        tools: false,
        contextTokens: 4096,
      );
      final harness = runtime(model);
      final id = await harness.start(
        task(
          history: [
            AgentMessage(
              role: MessageRole.user,
              text: 'old unrelated conversation ' * 2000,
            ),
            AgentMessage(role: MessageRole.assistant, text: 'prior answer'),
          ],
        ),
      );
      final run = await settled(harness, id);
      expect(run.status, RunStatus.completed);
      expect(run.requestCount, 2);
      expect(run.roundCount, 1);
      expect(run.summary, contains('note-1'));
      expect(run.messages.first.text.length, greaterThan(10000));
      expect(
        model.requests.last.messages.map((m) => m.text).join(),
        contains(run.goal),
      );
      expect(
        model.requests.last.messages.map((m) => m.text).join(),
        isNot(contains('old unrelated conversation')),
      );
      await harness.close();
    },
  );

  test(
    'planning and approved action artifacts survive serialization',
    () async {
      final tool = TestTool(write: true);
      final model = ScriptModel(
        (r, t, i) => switch (i) {
          1 => call(
            'update_plan',
            text: 'I will update the plan before editing.',
            args: {
              'steps': [
                {'title': 'Edit note', 'status': 'in_progress'},
              ],
            },
          ),
          2 => call('echo'),
          _ => reply('done'),
        },
      );
      final harness = runtime(model, tools: [tool]);
      final id = await harness.start(task());
      await approve(harness, await settled(harness, id));
      final run = (await settled(harness, id)).clone();
      expect(run.plan.single['title'], 'Edit note');
      expect(run.actions, hasLength(1));
      expect(run.actions.single['preview'], isNotNull);
      final processEvents = run.events
          .where(
            (event) => {
              'modelResponse',
              'toolStarted',
              'plan',
              'toolCompleted',
            }.contains(event.type),
          )
          .toList();
      expect(processEvents.take(4).map((event) => event.type), [
        'modelResponse',
        'toolStarted',
        'plan',
        'toolCompleted',
      ]);
      expect(
        processEvents.first.data['text'],
        'I will update the plan before editing.',
      );
      expect(
        processEvents[2].data['operationId'],
        processEvents[1].data['operationId'],
      );
      await harness.close();
    },
  );

  test('startup recovery never automatically restarts a model', () async {
    final store = MemoryRunStore();
    final model = ScriptModel((r, t, i) => reply('done'));
    final harness = runtime(model, store: store);
    final id = await harness.start(task());
    final run = await settled(harness, id);
    await harness.close();
    final oldRevision = run.revision;
    run.status = RunStatus.running;
    run.reservedTokens = 50;
    run.revision++;
    await store.save(run, expectedRevision: oldRevision);
    final restored = runtime(model, store: store);
    await restored.recover();
    final recovered = (await restored.get(id))!;
    expect(recovered.status, RunStatus.interrupted);
    expect(recovered.epoch, run.epoch + 1);
    expect(recovered.reservedTokens, 0);
    expect(model.requests, hasLength(1));
    await restored.close();
  });

  test('store rejects stale writers and isolates returned objects', () async {
    final store = MemoryRunStore();
    final harness = runtime(
      ScriptModel((r, t, i) => reply('done')),
      store: store,
    );
    final id = await harness.start(task());
    final run = await settled(harness, id);
    run.messages.clear();
    expect((await store.get(id))!.messages, isNotEmpty);
    await expectLater(
      store.save(run, expectedRevision: run.revision - 1),
      throwsA(isA<HarnessException>()),
    );
    await harness.close();
  });
}

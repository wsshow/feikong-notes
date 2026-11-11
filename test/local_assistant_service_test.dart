import 'dart:async';

import 'package:fknotes/agent/agent_attachment_loader.dart';
import 'package:fknotes/agent/local_model_adapter.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_assistant_service.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final inference = LocalInferenceCoordinator.instance;
  const model = LocalLlmModelDescriptor(
    id: 'assistant-model',
    name: 'Assistant model',
    configPath: '/models/config.json',
    nativeContextTokens: 8192,
  );

  setUp(inference.resetForTesting);
  tearDown(inference.resetForTesting);

  test(
    'local ModelPort normalizes the complete template and hides reasoning',
    () async {
      const toolModel = LocalLlmModelDescriptor(
        id: 'tools',
        name: 'Tools',
        configPath: '/models/config.json',
        nativeContextTokens: 8192,
        capabilities: LocalLlmCapabilities(toolCalling: true),
      );
      final engine = _BlockingUnloadEngine()
        ..output = [
          '查找',
          '<fknotes_',
          'tool>{"name":"search_notes","arguments":{"query":"工作"}}</fknotes_tool>',
        ];
      final coordinator = LocalLlmCoordinator(engine);
      final service = LocalAssistantService.forTesting(
        coordinator: coordinator,
        selectedModelId: () async => model.id,
        descriptor: (id) async => id == 'tools' ? toolModel : model,
        inference: inference,
      );
      final port = LocalModelAdapter(
        service: service,
        descriptor: toolModel,
        attachments: AgentAttachmentLoader(FileStorageService.instance),
      );
      final events = await port
          .generate(
            ModelRequest(
              messages: [AgentMessage(role: MessageRole.user, text: 'find')],
              tools: [],
              maxOutputTokens: 100,
            ),
            CancellationToken(),
          )
          .toList();
      expect(engine.loadedModel!.id, 'tools');
      expect(events.whereType<ModelText>().map((e) => e.text).join(), '查找');
      expect(
        events
            .whereType<ModelCompleted>()
            .single
            .message
            .calls
            .single
            .arguments,
        {'query': '工作'},
      );
      expect(port.isRemote, false);
      await service.unload();
      await coordinator.dispose();
    },
  );

  test(
    'local ModelPort cancels native generation without executing late output',
    () async {
      final engine = _BlockingUnloadEngine()..blockNextGeneration = true;
      final coordinator = LocalLlmCoordinator(engine);
      final service = LocalAssistantService.forTesting(
        coordinator: coordinator,
        selectedModelId: () async => model.id,
        descriptor: (_) async => model,
        inference: inference,
      );
      final port = LocalModelAdapter(
        service: service,
        descriptor: model,
        attachments: AgentAttachmentLoader(FileStorageService.instance),
      );
      final cancel = CancellationToken();
      final result = port
          .generate(
            ModelRequest(
              messages: [AgentMessage(role: MessageRole.user, text: 'hello')],
              tools: [],
              maxOutputTokens: 100,
            ),
            cancel,
          )
          .toList();
      final expectation = expectLater(
        result,
        throwsA(
          isA<HarnessException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await engine.generationStarted.future;
      cancel.cancel();
      await expectation;
      expect(engine.operations, contains('cancel:assistant-model'));
      await service.unload();
      await coordinator.dispose();
    },
  );

  test('a queued reload reacquires the lease after an older unload', () async {
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
    );
    await service.loadSelectedModel();
    expect(inference.activity?.type, LocalInferenceTaskType.assistant);

    engine.blockNextUnload = true;
    final unloading = service.unload();
    await engine.unloadStarted.future;
    final reloading = service.loadSelectedModel();
    engine.releaseUnload.complete();

    await unloading;
    await reloading;

    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(coordinator.loadedModel, model);
    expect(inference.activity?.type, LocalInferenceTaskType.assistant);
    expect(engine.operations, [
      'load:assistant-model',
      'unload:assistant-model',
      'load:assistant-model',
    ]);

    await service.unload();
    await coordinator.dispose();
  });

  test('pausing preserves a loaded model and its idle deadline', () async {
    var now = DateTime.utc(2026, 7, 15, 12);
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
      clock: () => now,
    );
    await service.loadSelectedModel();

    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(engine.operations, isNot(contains('unload:assistant-model')));

    now = now.add(const Duration(minutes: 1));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(engine.operations, isNot(contains('unload:assistant-model')));

    await service.unload();
    await coordinator.dispose();
  });

  test(
    'background generation continues and idles only after completion',
    () async {
      var now = DateTime.utc(2026, 7, 15, 12);
      final engine = _BlockingUnloadEngine()..blockNextGeneration = true;
      final coordinator = LocalLlmCoordinator(engine);
      final service = LocalAssistantService.forTesting(
        coordinator: coordinator,
        selectedModelId: () async => model.id,
        descriptor: (_) async => model,
        inference: inference,
        clock: () => now,
      );
      await service.loadSelectedModel();

      final generation = service
          .generate(
            LocalLlmGenerationRequest(
              messages: const [
                LocalLlmMessage(role: LocalLlmRole.user, content: '你好'),
              ],
            ),
          )
          .toList();
      await engine.generationStarted.future;

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.generating);
      expect(engine.operations, isNot(contains('cancel:assistant-model')));
      expect(engine.operations, isNot(contains('unload:assistant-model')));

      engine.releaseGeneration.complete();
      await generation;
      expect(coordinator.snapshot.state, LocalLlmEngineState.ready);

      now = now.add(const Duration(minutes: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.ready);

      now = now.add(const Duration(minutes: 2));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await engine.unloadStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.idle);

      await coordinator.dispose();
    },
  );

  test(
    'iOS backgrounding cancels generation and releases the model lease',
    () async {
      final engine = _BlockingUnloadEngine()..blockNextGeneration = true;
      final coordinator = LocalLlmCoordinator(engine);
      final service = LocalAssistantService.forTesting(
        coordinator: coordinator,
        selectedModelId: () async => model.id,
        descriptor: (_) async => model,
        inference: inference,
        suspendInBackground: true,
      );
      await service.loadSelectedModel();
      final generation = service
          .generate(
            LocalLlmGenerationRequest(
              messages: const [
                LocalLlmMessage(role: LocalLlmRole.user, content: 'synthetic'),
              ],
            ),
          )
          .toList();
      await engine.generationStarted.future;
      service.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(engine.operations, isNot(contains('cancel:assistant-model')));
      service.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await generation;
      await engine.unloadStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(engine.operations, contains('cancel:assistant-model'));
      expect(coordinator.snapshot.state, LocalLlmEngineState.idle);
      expect(inference.activity, isNull);
      await coordinator.dispose();
    },
  );

  test('detaching still releases the loaded model immediately', () async {
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
    );
    await service.loadSelectedModel();

    service.didChangeAppLifecycleState(AppLifecycleState.detached);
    await engine.unloadStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.snapshot.state, LocalLlmEngineState.idle);
    expect(inference.activity, isNull);
    await coordinator.dispose();
  });
}

class _BlockingUnloadEngine implements LocalLlmEngine {
  List<String> output = ['你好'];
  final operations = <String>[];
  final unloadStarted = Completer<void>();
  final releaseUnload = Completer<void>();
  final generationStarted = Completer<void>();
  final releaseGeneration = Completer<void>();
  bool blockNextUnload = false;
  bool blockNextGeneration = false;
  LocalLlmModelDescriptor? _model;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;

  @override
  String get id => 'blocking-test-engine';

  @override
  LocalLlmModelDescriptor? get loadedModel => _model;

  @override
  LocalLlmEngineState get state => _state;

  @override
  Future<LocalLlmEngineAvailability> probe() async =>
      const LocalLlmEngineAvailability(
        supported: true,
        engine: 'blocking-test-engine',
      );

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    operations.add('load:${model.id}');
    _model = model;
    _state = LocalLlmEngineState.ready;
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    operations.add('generate:${_model?.id}');
    _state = LocalLlmEngineState.generating;
    if (!generationStarted.isCompleted) generationStarted.complete();
    if (blockNextGeneration) {
      blockNextGeneration = false;
      await releaseGeneration.future;
    }
    for (final text in output) {
      yield LocalLlmTextDelta(text);
    }
    yield const LocalLlmGenerationCompleted(
      reason: LocalLlmFinishReason.completed,
    );
    _state = LocalLlmEngineState.ready;
  }

  @override
  Future<void> cancel() async {
    operations.add('cancel:${_model?.id}');
    if (!releaseGeneration.isCompleted) releaseGeneration.complete();
    _state = LocalLlmEngineState.ready;
  }

  @override
  Future<void> unload() async {
    operations.add('unload:${_model?.id}');
    _state = LocalLlmEngineState.unloading;
    if (!unloadStarted.isCompleted) unloadStarted.complete();
    if (blockNextUnload) {
      blockNextUnload = false;
      await releaseUnload.future;
    }
    _model = null;
    _state = LocalLlmEngineState.idle;
  }
}

import 'dart:io';

import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/mnn_local_llm_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native MNN CPU load, stream, cancel, unload and reload', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final config = File('${support.path}/mnn-smoke/config.json');
      expect(
        await config.exists(),
        isTrue,
        reason: 'Seed the validation app with tool/prepare_ios_mnn_smoke.py',
      );
      final engine = MnnLocalLlmEngine();
      final availability = await engine.probe();
      expect(availability.supported, isTrue);
      expect(availability.version, contains('3.6.0'));
      expect(availability.capabilities.backends, {LocalLlmBackend.cpu});
      final model = LocalLlmModelDescriptor(
        id: 'simulator-smoke',
        name: 'Synthetic smoke prompts / SmolLM2-135M',
        configPath: config.path,
        nativeContextTokens: 2048,
        recommendedContextTokens: 1024,
      );
      const options = LocalLlmLoadOptions(
        backend: LocalLlmBackend.metal, // A device preference must fall back.
        threads: 2,
        contextTokens: 1024,
      );
      try {
        await engine.loadModel(model, options: options);
        expect(engine.activeBackend, LocalLlmBackend.cpu);
        final first = await engine
            .generate(_request('Say hello.', 16))
            .toList();
        expect(
          first.whereType<LocalLlmTextDelta>().map((e) => e.text).join(),
          isNotEmpty,
        );
        expect(
          first
              .whereType<LocalLlmGenerationCompleted>()
              .single
              .metrics
              .generatedTokens,
          greaterThan(0),
        );

        // Cancel a dispatched request during prefill. Waiting for a text delta
        // would make cancellation depend on whether this tiny model emits EOS.
        final cancellation = engine
            .generate(
              _request(
                'Summarize this synthetic text: ${List.filled(60, 'A space station orbits a planet.').join(' ')}',
                512,
              ),
            )
            .toList();
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (engine.state != LocalLlmEngineState.generating &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(engine.state, LocalLlmEngineState.generating);
        await engine.cancel();
        final canceled = await cancellation;
        expect(
          canceled.whereType<LocalLlmGenerationCompleted>().single.reason,
          LocalLlmFinishReason.canceled,
        );
        expect(engine.state, LocalLlmEngineState.ready);
        final afterCancel = await engine
            .generate(_request('Say hello.', 16))
            .toList();
        expect(afterCancel.whereType<LocalLlmTextDelta>(), isNotEmpty);
        await engine.unload();
        expect(engine.state, LocalLlmEngineState.idle);
        expect(engine.loadedModel, isNull);
        await engine.loadModel(model, options: options);
        final again = await engine
            .generate(_request('Say hello.', 16))
            .toList();
        expect(again.whereType<LocalLlmTextDelta>(), isNotEmpty);
      } finally {
        await engine.unload();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

LocalLlmGenerationRequest _request(String prompt, int tokens) =>
    LocalLlmGenerationRequest(
      messages: [LocalLlmMessage(role: LocalLlmRole.user, content: prompt)],
      options: LocalLlmGenerationOptions(maxNewTokens: tokens),
    );

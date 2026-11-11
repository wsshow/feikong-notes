import 'dart:async';
import 'dart:io';

import 'package:fknotes/services/ios_foreground_work.dart';
import 'package:fknotes/services/model_download_transport.dart';
import 'package:fknotes/services/realtime_dictation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test(
    'permission-sheet inactivity does not cancel; hidden cancels exactly once',
    () {
      var canceled = 0;
      final lease = IosForegroundWork(
        enabled: true,
        onSuspend: () => canceled++,
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(canceled, 0);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(canceled, 1);
      expect(lease.interrupted, isTrue);
      lease.dispose();
    },
  );

  test('already hidden work cannot start and disposed leases do not fire', () {
    var canceled = 0;
    final lease = IosForegroundWork(enabled: true, onSuspend: () => canceled++);
    lease.dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(canceled, 0);
    final hidden = IosForegroundWork(
      enabled: true,
      onSuspend: () => canceled++,
    );
    expect(hidden.interrupted, isTrue);
    hidden.dispose();
  });

  test(
    'iOS suspension aborts an HTTP wait while keeping resumable bytes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final directory = await Directory.systemTemp.createTemp(
        'fknotes-ios-download-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      server.listen((request) {
        received.complete();
      });
      try {
        final partial = await File(
          '${directory.path}/model.part',
        ).writeAsBytes([1, 2, 3]);
        final download =
            ModelDownloadTransport(
              clientFactory: () => HttpOverrides.runWithHttpOverrides(
                HttpClient.new,
                _LoopbackHttpOverrides(),
              ),
            ).download(
              sources: [
                ModelDownloadSource(
                  uri: Uri.parse('http://127.0.0.1:${server.port}/model'),
                  label: 'synthetic',
                ),
              ],
              partial: partial,
              expectedBytes: 6,
              userAgent: 'synthetic/test',
              onProgress: (_) {},
            );
        final canceled = expectLater(
          download,
          throwsA(isA<ModelDownloadCanceled>()),
        );
        await received.future.timeout(const Duration(seconds: 3));
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await canceled;
        expect(await partial.readAsBytes(), [1, 2, 3]);
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'background dictation teardown preserves committed and partial text',
    () async {
      final dictation = RealtimeDictationService.instance;
      dictation.status = RealtimeDictationStatus.listening;
      dictation.committedText = '合成';
      dictation.partialText = '文字';
      await dictation.suspendForBackground();
      expect(dictation.status, RealtimeDictationStatus.idle);
      expect(dictation.text, '合成文字');
      expect(dictation.partialText, isEmpty);
      await dictation.suspendForBackground();
      expect(dictation.text, '合成文字');
    },
  );
}

class _LoopbackHttpOverrides extends HttpOverrides {}

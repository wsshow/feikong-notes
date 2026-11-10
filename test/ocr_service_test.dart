import 'dart:async';
import 'dart:io';

import 'package:fknotes/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_text_recognizer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes-ocr-test-');
    file = await File('${directory.path}/image.png').writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('passes the original path to the bundled Chinese recognizer', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'text': '  中文\nEnglish 123  ', 'blocks': []};
    });
    final result = await OcrService.instance.recognizeText(file.path);
    expect(result.status, OcrStatus.recognized);
    expect(result.text, '中文\nEnglish 123');
    expect(calls.single.method, 'vision#startTextRecognizer');
    expect(calls.single.arguments['script'], 1);
    expect(calls.single.arguments['imageData']['path'], file.path);
    expect(calls.single.arguments['imageData']['type'], 'file');
  });

  test(
    'distinguishes no text, native failure and missing file and recovers',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        if (calls == 1) throw PlatformException(code: 'unavailable');
        return {'text': ' \n ', 'blocks': []};
      });
      expect(
        (await OcrService.instance.recognizeText(
          '${directory.path}/missing.png',
        )).didFail,
        isTrue,
      );
      expect(calls, 0);
      expect(
        (await OcrService.instance.recognizeText(file.path)).didFail,
        isTrue,
      );
      expect(
        (await OcrService.instance.recognizeText(file.path)).status,
        OcrStatus.noText,
      );
      expect(calls, 2);
    },
  );

  test(
    'serializes native calls even when a previous sheet was dismissed',
    () async {
      final started = Completer<void>();
      final finishFirst = Completer<void>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        if (calls == 1) {
          started.complete();
          await finishFirst.future;
        }
        return {'text': 'result $calls', 'blocks': []};
      });
      final first = OcrService.instance.recognizeText(file.path);
      await started.future;
      final second = OcrService.instance.recognizeText(file.path);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      finishFirst.complete();
      expect((await first).text, 'result 1');
      expect((await second).text, 'result 2');
      expect(calls, 2);
    },
  );
}

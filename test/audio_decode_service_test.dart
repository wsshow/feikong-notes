import 'dart:io';

import 'package:fknotes/services/audio_decode_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/audio_decode');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late File source;
  late String output;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('audio-decode-test');
    source = await File('${root.path}/recording.m4a').writeAsBytes([1, 2, 3]);
    output = '${root.path}/temporary/recognition.wav';
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform prepares temporary audio without replacing M4A', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'decodeToWav');
        expect(call.arguments, {
          'sourcePath': source.path,
          'outputPath': output,
        });
        await File(output).writeAsBytes(List.filled(46, 0));
        return output;
      });
      final service = AudioDecodeService(channel: channel, platform: platform);
      expect(await service.prepare(source.path, outputPath: output), output);
      expect(await source.readAsBytes(), [1, 2, 3]);
    });
  }

  test('WAV input remains owned by the caller', () async {
    final wave = await source.rename('${root.path}/original.WAV');
    messenger.setMockMethodCallHandler(
      channel,
      (_) => throw StateError('Unexpected decode'),
    );
    final service = AudioDecodeService(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    expect(await service.prepare(wave.path, outputPath: output), wave.path);
    expect(await File(output).exists(), isFalse);
  });

  for (final code in ['audio_decode_failed', 'cancelled']) {
    test('$code removes partial output and preserves source', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        await File(output).writeAsBytes([0, 0]);
        throw PlatformException(code: code);
      });
      final service = AudioDecodeService(
        channel: channel,
        platform: TargetPlatform.iOS,
      );
      await expectLater(
        service.prepare(source.path, outputPath: output),
        throwsA(isA<PlatformException>()),
      );
      expect(await File(output).exists(), isFalse);
      expect(await source.readAsBytes(), [1, 2, 3]);
    });
  }

  test('empty or unexpected native result cannot enter recognition', () async {
    final service = AudioDecodeService(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    for (final response in [null, source.path, output]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        await File(output).writeAsBytes(List.filled(44, 0));
        return response;
      });
      await expectLater(
        service.prepare(source.path, outputPath: output),
        throwsStateError,
      );
      expect(await File(output).exists(), isFalse);
    }
  });

  test('iOS cancellation addresses only the requested output', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'cancel');
      expect(call.arguments, {'outputPath': output});
      return null;
    });
    await AudioDecodeService(
      channel: channel,
      platform: TargetPlatform.iOS,
    ).cancel(output);
  });

  test('rejects output that would replace the source', () async {
    final service = AudioDecodeService(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    await expectLater(
      service.prepare(source.path, outputPath: source.path),
      throwsArgumentError,
    );
    expect(await source.readAsBytes(), [1, 2, 3]);
  });

  test('cancellation before dispatch never starts native decoding', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) => fail('Unexpected decode'),
    );
    final service = AudioDecodeService(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    await expectLater(
      service.prepare(source.path, outputPath: output, isCancelled: () => true),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    expect(await File(output).exists(), isFalse);
  });
}

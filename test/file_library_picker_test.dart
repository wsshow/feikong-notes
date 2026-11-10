import 'dart:async';
import 'dart:io';

import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/services/file_library_picker.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/file_library');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-library-picker');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
    await root.delete(recursive: true);
  });

  Future<void> progress(String token) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('progress', {'token': token, 'bytes': 2, 'total': 4}),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  test(
    'keeps content URIs native and commits streamed copies with progress',
    () async {
      var copies = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickFiles') {
          return [
            {'uri': 'content://documents/42', 'name': 'report.xlsx', 'size': 4},
          ];
        }
        if (call.method == 'copyFile') {
          copies++;
          final args = call.arguments as Map;
          await progress(args['token'] as String);
          await File(args['destination'] as String).writeAsBytes([1, 2, 3, 4]);
          return 4;
        }
        return null;
      });
      final picker = FileLibraryPicker(
        channel: channel,
        useAndroidPicker: true,
      );
      final files = await picker.pickFiles();
      expect(files.single.path, startsWith('content://'));
      expect(files.single.name, 'report.xlsx');
      final updates = <int>[];
      final store = FileLibraryStore(rootPath: root.path);
      final entry = await store.importFile(
        files.single,
        onProgress: (bytes, total) => updates.add(bytes),
      );
      expect(copies, 1);
      expect(updates, [2, 4]);
      expect(entry.size, 4);
      expect(await store.fileFor(entry).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('cancels native copy and never commits a partial file', () async {
    var cancelled = false;
    var cancelRequested = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickFiles') {
        return [
          {'uri': 'content://documents/42', 'name': 'large.mp4', 'size': 4},
        ];
      }
      if (call.method == 'cancel') {
        cancelRequested = true;
        return null;
      }
      if (call.method == 'copyFile') {
        await progress((call.arguments as Map)['token'] as String);
        throw PlatformException(code: 'cancelled');
      }
      return null;
    });
    final picker = FileLibraryPicker(channel: channel, useAndroidPicker: true);
    final source = (await picker.pickFiles()).single;
    final store = FileLibraryStore(rootPath: root.path);
    await expectLater(
      store.importFile(
        source,
        onProgress: (_, total) => cancelled = true,
        isCancelled: () => cancelled,
      ),
      throwsA(
        isA<FileLibraryException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    expect(cancelRequested, true);
    expect(await store.load(), isEmpty);
  });
}

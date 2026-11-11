import 'dart:io';

import 'package:fknotes/widgets/note_external_image_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('fknotes/external_image_drop');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late Directory directory;
  late File file;
  late List<MethodCall> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes-drop-test-');
    file = await File('${directory.path}/image.png').writeAsBytes([1, 2, 3]);
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<void> drop(WidgetTester tester) async {
    await tester.runAsync(() async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('done', {
            'position': [20.0, 40.0],
            'files': [
              {
                'path': file.path,
                'name': 'image.png',
                'mimeType': 'image/png',
                'byteLength': 3,
              },
            ],
          }),
        ),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  for (final locked in [false, true]) {
    testWidgets('iOS image drops respect locked=$locked and release copies', (
      tester,
    ) async {
      var deliveries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AbsorbPointer(
              absorbing: locked,
              child: NoteExternalImageDropRegion(
                enabled: true,
                captureDocumentOffset: (_) => 3,
                onDropImages: (batch, offset) async {
                  expect(offset, 3);
                  expect(batch.images.single.bytes, [1, 2, 3]);
                  deliveries++;
                },
                onDropActiveChanged: (_) {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await drop(tester);
      expect(deliveries, locked ? 0 : 1);
      expect(
        calls
            .where((call) => call.method == 'deleteTemporaryFiles')
            .single
            .arguments,
        [file.path],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last.method, 'setEnabled');
      expect(calls.last.arguments, false);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}

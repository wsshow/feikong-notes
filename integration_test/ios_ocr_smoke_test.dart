import 'dart:io';
import 'dart:ui' as ui;

import 'package:fknotes/services/ocr_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Chinese OCR, empty image, failure and recognizer reuse', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory(
        '${(await getTemporaryDirectory()).path}/ocr-smoke',
      ).create();
      try {
        final mixed = await _image(
          directory,
          'mixed.png',
          '非空笔记\n中文识别测试\nFeikong Notes 123',
        );
        final result = await OcrService.instance.recognizeText(mixed.path);
        expect(result.status, OcrStatus.recognized);
        final compact = result.text.replaceAll(RegExp(r'\s'), '');
        expect(compact, contains('非空笔记'));
        expect(compact, contains('中文识别测试'));
        expect(compact, contains('FeikongNotes123'));

        final empty = await _image(directory, 'empty.png', '');
        expect(
          (await OcrService.instance.recognizeText(empty.path)).status,
          OcrStatus.noText,
        );
        final broken = await File(
          '${directory.path}/invalid.png',
        ).writeAsBytes([0, 1, 2]);
        expect(
          (await OcrService.instance.recognizeText(broken.path)).didFail,
          isTrue,
        );
        await OcrService.instance.dispose();
        expect(
          (await OcrService.instance.recognizeText(mixed.path)).hasText,
          isTrue,
        );
      } finally {
        await OcrService.instance.dispose();
        await directory.delete(recursive: true);
      }
    });
  });
}

Future<File> _image(Directory directory, String name, String text) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: 'Source Han Serif CN',
        fontSize: 64,
        color: Color(0xFF000000),
        height: 1.6,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 1100);
  painter.paint(canvas, const Offset(40, 40));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1200, 440);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final file = await File(
    '${directory.path}/$name',
  ).writeAsBytes(bytes.buffer.asUint8List());
  painter.dispose();
  picture.dispose();
  image.dispose();
  return file;
}

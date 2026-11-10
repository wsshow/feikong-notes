import 'dart:typed_data';

import 'package:fknotes/services/note_watermark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'burns readable place and time text into the lower-left camera area',
    () async {
      final source = img.Image(width: 1000, height: 700);
      img.fill(source, color: img.ColorRgb8(210, 120, 60));

      final output = await NoteWatermarkService.instance.applyLocationWatermark(
        Uint8List.fromList(img.encodeJpg(source, quality: 100)),
        NoteWatermarkLocation(
          latitude: 31.230416,
          longitude: 121.473701,
          accuracy: 8.4,
          placeName: '上海市 · 黄浦区 · 人民广场',
          capturedAt: DateTime(2026, 7, 29, 14, 5, 9),
        ),
      );
      final decoded = img.decodeJpg(output);

      expect(decoded, isNotNull);
      expect(decoded!.width, 1000);
      expect(decoded.height, 700);
      final untouched = decoded.getPixel(500, 100);
      final transparentPanelArea = decoded.getPixel(700, 520);
      expect(untouched.r, greaterThan(190));
      expect(
        (transparentPanelArea.r - untouched.r).abs(),
        lessThanOrEqualTo(12),
      );
      expect(
        (transparentPanelArea.g - untouched.g).abs(),
        lessThanOrEqualTo(12),
      );
      var hasReadableForeground = false;
      for (var y = 470; y < decoded.height - 20; y += 2) {
        for (var x = 20; x < 680; x += 2) {
          final pixel = decoded.getPixel(x, y);
          if ((pixel.r - untouched.r).abs() > 45 ||
              (pixel.g - untouched.g).abs() > 45 ||
              (pixel.b - untouched.b).abs() > 45) {
            hasReadableForeground = true;
            break;
          }
        }
        if (hasReadableForeground) break;
      }
      expect(hasReadableForeground, isTrue);
      expect(output, isNotEmpty);
    },
  );

  test('supports a custom Unicode place without GPS coordinates', () async {
    final source = img.Image(width: 900, height: 600);
    img.fill(source, color: img.ColorRgb8(82, 112, 134));

    final output = await NoteWatermarkService.instance.applyLocationWatermark(
      Uint8List.fromList(img.encodeJpg(source, quality: 100)),
      NoteWatermarkLocation(
        placeName: '公司会议室',
        capturedAt: DateTime(2026, 7, 29, 15),
      ),
    );

    final decoded = img.decodeJpg(output);
    expect(decoded, isNotNull);
    expect(decoded!.width, 900);
    expect(decoded.height, 600);
    expect(output, isNotEmpty);
  });

  test('builds a concise readable name from native placemark fields', () {
    expect(
      formatNoteWatermarkPlaceName(
        country: '中国',
        administrativeArea: '上海市',
        locality: '上海市',
        subLocality: '黄浦区',
        name: '人民广场',
      ),
      '上海市 · 黄浦区 · 人民广场',
    );
    expect(normalizeNoteWatermarkPlaceName('  公司\n会议室  '), '公司 会议室');
  });

  test('rejects undecodable watermark input', () async {
    await expectLater(
      NoteWatermarkService.instance.applyLocationWatermark(
        Uint8List.fromList([1, 2, 3]),
        NoteWatermarkLocation(
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          capturedAt: DateTime(2026),
        ),
      ),
      throwsFormatException,
    );
  });
}

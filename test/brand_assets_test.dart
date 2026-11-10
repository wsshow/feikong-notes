import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('brand master is the opaque elephant-and-note artwork', () {
    final source = image.decodePng(
      File('assets/brand/fknotes_logo_source.png').readAsBytesSync(),
    )!;

    expect((source.width, source.height), (512, 512));
    expect(source.every((pixel) => pixel.a == 255), isTrue);
    final corner = source.getPixel(0, 0);
    expect(corner.r, closeTo(247, 2));
    expect(corner.g, closeTo(243, 2));
    expect(corner.b, closeTo(240, 2));
    final elephant = source.getPixel(256, 256);
    expect(elephant.r, greaterThan(210));
    expect(elephant.g, inInclusiveRange(80, 150));
    expect(elephant.b, lessThan(110));

    final adaptiveForeground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();
    expect(
      adaptiveForeground,
      contains('@drawable/ic_launcher_foreground_image'),
    );
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptiveIcon, isNot(contains('ic_launcher_monochrome')));
  });

  test('generated platform icons have their required dimensions', () {
    const expectedSizes = <String, (int, int)>{
      'assets/brand/fknotes_logo_source.png': (512, 512),
      'assets/brand/fknotes_icon.png': (1024, 1024),
      'assets/brand/fknotes_mark.png': (1024, 1024),
      'android/app/src/main/res/drawable-nodpi/'
          'ic_launcher_foreground_image.png': (
        432,
        432,
      ),
      'android/app/src/main/res/drawable-nodpi/splash_mark.png': (240, 240),
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': (48, 48),
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': (72, 72),
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': (96, 96),
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': (144, 144),
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': (192, 192),
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png': (
        1024,
        1024,
      ),
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png': (
        264,
        264,
      ),
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': (
        16,
        16,
      ),
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': (
        1024,
        1024,
      ),
      'web/favicon.png': (32, 32),
      'web/icons/Icon-192.png': (192, 192),
      'web/icons/Icon-512.png': (512, 512),
      'web/icons/Icon-maskable-192.png': (192, 192),
      'web/icons/Icon-maskable-512.png': (512, 512),
    };

    for (final MapEntry(key: path, value: size) in expectedSizes.entries) {
      final decoded = image.decodeImage(File(path).readAsBytesSync());
      expect(decoded, isNotNull, reason: '$path should be decodable');
      expect(
        (decoded!.width, decoded.height),
        size,
        reason: '$path should have the platform-required dimensions',
      );
    }
  });

  test('app icon and launch mark preserve the supplied opaque artwork', () {
    final source = image.decodePng(
      File('assets/brand/fknotes_logo_source.png').readAsBytesSync(),
    )!;
    final icon = image.decodePng(
      File('assets/brand/fknotes_icon.png').readAsBytesSync(),
    )!;
    final mark = image.decodePng(
      File('assets/brand/fknotes_mark.png').readAsBytesSync(),
    )!;

    expect(icon.every((pixel) => pixel.a == 255), isTrue);
    expect(mark.every((pixel) => pixel.a == 255), isTrue);
    final sourceCenter = source.getPixel(source.width ~/ 2, source.height ~/ 2);
    final iconCenter = icon.getPixel(icon.width ~/ 2, icon.height ~/ 2);
    final markCenter = mark.getPixel(mark.width ~/ 2, mark.height ~/ 2);
    for (final channel in <(num, num)>[
      (sourceCenter.r, iconCenter.r),
      (sourceCenter.g, iconCenter.g),
      (sourceCenter.b, iconCenter.b),
      (sourceCenter.r, markCenter.r),
      (sourceCenter.g, markCenter.g),
      (sourceCenter.b, markCenter.b),
    ]) {
      expect(channel.$2, closeTo(channel.$1, 3));
    }
  });

  test('launcher icon keeps safe margins and the mark enlarges the mascot', () {
    final icon = image.decodePng(
      File('assets/brand/fknotes_icon.png').readAsBytesSync(),
    )!;
    final mark = image.decodePng(
      File('assets/brand/fknotes_mark.png').readAsBytesSync(),
    )!;
    final iconBounds = _colorArtworkBounds(icon);
    final markBounds = _colorArtworkBounds(mark);

    expect(iconBounds.width / icon.width, inInclusiveRange(.48, .58));
    expect(iconBounds.height / icon.height, inInclusiveRange(.50, .60));
    expect(iconBounds.left / icon.width, greaterThan(.20));
    expect(iconBounds.top / icon.height, greaterThan(.16));
    expect(iconBounds.right / icon.width, lessThan(.80));
    expect(markBounds.width / mark.width, greaterThan(.72));
    expect(markBounds.height / mark.height, greaterThan(.72));
  });
}

({int left, int top, int right, int bottom, int width, int height})
_colorArtworkBounds(image.Image source) {
  var minX = source.width;
  var minY = source.height;
  var maxX = 0;
  var maxY = 0;
  for (final pixel in source) {
    final isOrange = pixel.r > 150 && pixel.r > pixel.g + 35;
    final isDarkDetail = pixel.r < 170 && pixel.g < 170 && pixel.b < 170;
    if (isOrange || isDarkDetail) {
      minX = pixel.x < minX ? pixel.x : minX;
      minY = pixel.y < minY ? pixel.y : minY;
      maxX = pixel.x > maxX ? pixel.x : maxX;
      maxY = pixel.y > maxY ? pixel.y : maxY;
    }
  }
  return (
    left: minX,
    top: minY,
    right: maxX,
    bottom: maxY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

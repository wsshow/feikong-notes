import 'dart:io';
import 'dart:ui' as ui;

import 'package:fknotes/widgets/app_icon.dart';
import 'package:fknotes/widgets/app_icon_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every app icon token has local outline artwork', () {
    final catalog = File(
      'lib/widgets/app_icon_catalog.dart',
    ).readAsStringSync();
    final tokenPattern = RegExp(r'\bIcons\.(\w+)');
    final supported = tokenPattern
        .allMatches(catalog)
        .map((match) => match.group(1)!)
        .toSet();
    final missing = <String>[];
    final oldRenderers = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('app_icon_catalog.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final token in tokenPattern.allMatches(source)) {
        if (!supported.contains(token.group(1))) {
          missing.add('${file.path}: Icons.${token.group(1)}');
        }
      }
      if (RegExp(r'\bIcon\s*\(').hasMatch(source)) oldRenderers.add(file.path);
    }
    expect(missing, isEmpty, reason: 'Add new icons to the local catalog.');
    expect(
      oldRenderers,
      isEmpty,
      reason: 'Use AppIcon for app-owned controls.',
    );
    expect(
      appIconNames.values.toSet().difference(appIconPaths.keys.toSet()),
      isEmpty,
    );
  });

  test(
    'every vector parses and paints visible artwork at toolbar size',
    () async {
      for (final name in appIconPaths.keys) {
        final recorder = ui.PictureRecorder();
        final painter = AppIconPainter(name: name, color: Colors.black);
        final bounds = painter.artworkBounds;
        expect(bounds.left, greaterThanOrEqualTo(0), reason: name);
        expect(bounds.top, greaterThanOrEqualTo(0), reason: name);
        expect(bounds.right, lessThanOrEqualTo(24), reason: name);
        expect(bounds.bottom, lessThanOrEqualTo(24), reason: name);
        painter.paint(Canvas(recorder), const Size.square(24));
        final picture = recorder.endRecording();
        final bitmap = await picture.toImage(24, 24);
        final pixels = (await bitmap.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var visiblePixels = 0;
        for (var offset = 3; offset < pixels.lengthInBytes; offset += 4) {
          if (pixels.getUint8(offset) != 0) visiblePixels++;
        }
        expect(visiblePixels, greaterThan(0), reason: name);
        expect(visiblePixels, lessThan(24 * 24), reason: name);
        bitmap.dispose();
        picture.dispose();
      }
    },
  );

  testWidgets(
    'inherits size, opacity and semantics from the surrounding control',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: IconTheme(
                data: IconThemeData(
                  size: 30,
                  color: Color(0xFF123456),
                  opacity: .5,
                ),
                child: AppIcon(Icons.push_pin_outlined, semanticLabel: '置顶'),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(AppIcon)), const Size.square(30));
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
        expect(find.bySemanticsLabel('置顶'), findsOneWidget);
        final painter = _painter(tester);
        expect(painter.color.a, closeTo(.5, .001));
        expect(painter.color.r, closeTo(0x12 / 255, .001));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('keeps disabled colors and mirrors directional icons only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: IconButton(
              onPressed: null,
              disabledColor: Color(0xFF778899),
              icon: AppIcon(Icons.arrow_back_rounded),
            ),
          ),
        ),
      ),
    );
    expect(_painter(tester).color, const Color(0xFF778899));
    expect(_painter(tester).mirrored, isTrue);
  });

  testWidgets('framework navigation buttons use the same icon renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(actionIconTheme: appActionIconTheme),
        home: const Scaffold(
          body: Row(children: [BackButton(), CloseButton(), DrawerButton()]),
        ),
      ),
    );
    expect(find.byType(AppIcon), findsNWidgets(3));
    expect(find.byType(Icon), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets(
    'artwork stays centered at its requested size inside a larger target',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 56,
              child: AppIcon(Icons.add_rounded, size: 28),
            ),
          ),
        ),
      );
      final artwork = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is AppIconPainter,
      );
      expect(tester.getSize(artwork), const Size.square(28));
      expect(tester.getCenter(artwork), tester.getCenter(find.byType(AppIcon)));
    },
  );
}

AppIconPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<AppIconPainter>()
    .single;

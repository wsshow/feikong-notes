import 'dart:io';

import 'package:fknotes/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application modal surfaces use the shared overlay entrance', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path.endsWith('widgets/app_overlay.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (RegExp(r'\b(?:showDialog|showModalBottomSheet)<').hasMatch(source)) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty);
  });

  testWidgets('shared overlays preserve dialog and sheet results', (
    tester,
  ) async {
    int? dialogResult;
    String? sheetResult;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeStyle.paper, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      dialogResult = await AppOverlay.dialog<int>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Dialog'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, 7),
                              child: const Text('Close dialog'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open dialog'),
                  ),
                  TextButton(
                    onPressed: () async {
                      sheetResult = await AppOverlay.bottomSheet<String>(
                        context: context,
                        builder: (context) => SafeArea(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, 'done'),
                            child: const Text('Close sheet'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open sheet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pump();
    expect(find.text('Dialog'), findsOneWidget);
    await tester.tap(find.text('Close dialog'));
    await tester.pump();
    expect(dialogResult, 7);

    await tester.tap(find.text('Open sheet'));
    await tester.pump();
    expect(find.text('Close sheet'), findsOneWidget);
    await tester.tap(find.text('Close sheet'));
    await tester.pump();
    expect(sheetResult, 'done');
    expect(tester.takeException(), isNull);
  });
}

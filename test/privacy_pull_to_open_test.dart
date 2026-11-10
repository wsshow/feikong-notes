import 'dart:async';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/widgets/privacy_pull_to_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a light haptic fires once when the private hint appears', (
    tester,
  ) async {
    final haptics = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_App(onOpen: () async {}));
    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(
      const Offset(0, PrivacyPullToOpen.triggerDistance - 30),
    );
    await tester.pump();
    expect(haptics, isEmpty);
    expect(find.byKey(const Key('privacy-pull-hint')), findsNothing);
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(find.byKey(const Key('privacy-pull-hint')), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(haptics, hasLength(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics, hasLength(1));
  });

  testWidgets('only a deliberate pull released at the top opens the space', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_App(onOpen: () async => opened++));
    final list = find.byKey(const Key('list'));
    final initialPosition = tester.getTopLeft(find.text('Note 0'));
    final shortPull = await tester.startGesture(const Offset(100, 100));
    await shortPull.moveBy(
      const Offset(0, PrivacyPullToOpen.triggerDistance - 30),
    );
    await tester.pump();
    expect(find.byKey(const Key('privacy-pull-hint')), findsNothing);
    expect(
      tester.getTopLeft(find.text('Note 0')).dy,
      greaterThan(initialPosition.dy),
    );
    expect(opened, 0);
    await shortPull.up();
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.getTopLeft(find.text('Note 0')), initialPosition);

    final gesture = await tester.startGesture(
      tester.getTopLeft(list) + const Offset(60, 100),
    );
    await gesture.moveBy(
      const Offset(0, PrivacyPullToOpen.triggerDistance + 50),
    );
    await tester.pump();
    expect(opened, 0);
    expect(find.text('松开验证，进入隐私空间'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('canceling an armed gesture does not authenticate', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_App(onOpen: () async => opened++));
    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(
      const Offset(0, PrivacyPullToOpen.triggerDistance + 50),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.byKey(const Key('privacy-pull-hint')), findsNothing);
  });

  testWidgets('scrolling the list and disabled pulls never open the space', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_App(onOpen: () async => opened++));
    final list = find.byKey(const Key('list'));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(opened, 0);
    await tester.pumpWidget(_App(enabled: false, onOpen: () async => opened++));
    await tester.drag(list, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('a pending authentication cannot be triggered twice', (
    tester,
  ) async {
    var opened = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      _App(
        onOpen: () {
          opened++;
          return pending.future;
        },
      ),
    );
    await tester.drag(
      find.byKey(const Key('list')),
      const Offset(0, PrivacyPullToOpen.triggerDistance + 50),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.drag(
      find.byKey(const Key('list')),
      const Offset(0, PrivacyPullToOpen.triggerDistance + 50),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });
}

final class _App extends StatelessWidget {
  const _App({required this.onOpen, this.enabled = true});
  final Future<void> Function() onOpen;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: PrivacyPullToOpen(
        onOpen: onOpen,
        enabled: enabled,
        child: ListView.builder(
          key: const Key('list'),
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          itemCount: 30,
          itemBuilder: (_, index) =>
              SizedBox(height: 80, child: Text('Note $index')),
        ),
      ),
    ),
  );
}

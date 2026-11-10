import 'package:fknotes/widgets/app_copy_button.dart';
import 'package:fknotes/widgets/app_feedback.dart';
import 'package:fknotes/widgets/app_feedback_navigator_observer.dart';
import 'package:fknotes/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy action confirms success on the control itself', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCopyButton(
            text: '正文',
            copyTooltip: '复制',
            copiedTooltip: '已复制',
          ),
        ),
      ),
    );

    expect(find.byTooltip('复制'), findsOneWidget);
    await tester.tap(find.byType(AppCopyButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byTooltip('已复制'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('page feedback replaces stale feedback without a snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppFeedback.show(context, '第一条提示');
                AppFeedback.success(context, '最新提示');
              },
              child: const Text('显示提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('app-feedback')), findsOneWidget);
    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('最新提示'), findsOneWidget);
    expect(find.text('第一条提示'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });

  testWidgets('page feedback takes layout space instead of covering content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const SizedBox(key: Key('page-content'), height: 80),
                TextButton(
                  onPressed: () => AppFeedback.show(context, '页面状态'),
                  child: const Text('显示提示'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(find.byKey(const Key('page-content'))).dy;

    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final banner = tester.getRect(find.byType(MaterialBanner));
    final after = tester.getTopLeft(find.byKey(const Key('page-content'))).dy;
    expect(after, greaterThan(before));
    expect(after, greaterThanOrEqualTo(banner.bottom));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });

  testWidgets('reversible action is the only bottom snackbar feedback', (
    tester,
  ) async {
    var actionCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppFeedback.action(
                context,
                '已移到回收站',
                actionLabel: '撤销',
                onAction: () => actionCalled = true,
              ),
              child: const Text('删除'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('app-feedback-action')), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.text('撤销'));
    expect(actionCalled, isTrue);
  });

  testWidgets('error feedback stays user-dismissible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppFeedback.error(context, '可关闭错误'),
              child: const Text('显示错误'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示错误'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('可关闭错误'), findsOneWidget);
    expect(tester.widget<AppIcon>(find.byIcon(Icons.close)), isA<AppIcon>());

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('可关闭错误'), findsNothing);
  });

  testWidgets('feedback is dismissed when navigating to another page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AppFeedbackNavigatorObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => AppFeedback.show(context, '当前页提示'),
                  child: const Text('显示提示'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('下一页')),
                    ),
                  ),
                  child: const Text('打开下一页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('当前页提示'), findsOneWidget);

    await tester.tap(find.text('打开下一页'));
    await tester.pumpAndSettle();
    expect(find.text('下一页'), findsOneWidget);
    expect(find.text('当前页提示'), findsNothing);
  });
}

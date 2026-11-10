import 'package:fknotes/app.dart';
import 'package:fknotes/widgets/app_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an anchored menu opens below a top trigger without overlap', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topCenter, tooltip: '顶部菜单');

    final trigger = find.byTooltip('顶部菜单');
    final triggerRect = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(2));
    final menuTop = tester.getRect(items.first).top;
    expect(menuTop, greaterThan(triggerRect.bottom));
  });

  testWidgets('an anchored menu flips above a bottom trigger without overlap', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.bottomCenter, tooltip: '底部菜单');

    final trigger = find.byTooltip('底部菜单');
    final triggerRect = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(2));
    final menuBottom = tester.getRect(items.last).bottom;
    expect(menuBottom, lessThan(triggerRect.top));
  });

  for (final alignment in [Alignment.topLeft, Alignment.topRight]) {
    testWidgets('edge trigger $alignment keeps the panel inset', (
      tester,
    ) async {
      await _pumpMenu(
        tester,
        alignment: alignment,
        tooltip: '贴边菜单',
        anchorPadding: EdgeInsets.zero,
        screenPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      );
      final before = tester.getRect(find.byTooltip('贴边菜单'));
      await tester.tap(find.byTooltip('贴边菜单'));
      await tester.pumpAndSettle();

      final panel = tester.getRect(_menuPanel);
      expect(panel.left, greaterThanOrEqualTo(12 + AppMenuTokens.edgeInset));
      expect(
        panel.right,
        lessThanOrEqualTo(390 - 12 - AppMenuTokens.edgeInset),
      );
      expect(panel.top, greaterThanOrEqualTo(24 + AppMenuTokens.edgeInset));
      expect(tester.getRect(find.byTooltip('贴边菜单')), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menu keeps a soft shadow and generous interior spacing', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topRight, tooltip: '菜单');
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(_menuPanel);
    expect(surface.elevation, AppMenuTokens.elevation);
    expect(
      surface.shadowColor,
      AppPalette.paperLight.shadow.withValues(alpha: .16),
    );
    expect(surface.surfaceTintColor, Colors.transparent);
    expect((surface.shape! as RoundedRectangleBorder).side, BorderSide.none);

    final panel = tester.getRect(_menuPanel);
    final items = find.byType(MenuItemButton);
    expect(panel.width, greaterThanOrEqualTo(AppMenuTokens.minWidth));
    expect(tester.getRect(items.first).top - panel.top, 12);
    expect(panel.bottom - tester.getRect(items.last).bottom, 12);
    expect(tester.getRect(items.first).left - panel.left, 8);
    expect(
      tester.getRect(items.first).height,
      greaterThanOrEqualTo(AppMenuTokens.itemHeight),
    );
  });

  testWidgets('narrow screen and large text wrap labels without overflow', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      alignment: Alignment.topRight,
      tooltip: '大字菜单',
      screenSize: const Size(240, 640),
      textScaler: const TextScaler.linear(2),
      actions: const [
        AppMenuAction(
          value: 'share',
          icon: Icons.ios_share_rounded,
          label: 'Share this note as an image',
        ),
        AppMenuAction(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: '永久删除这篇笔记',
          destructive: true,
        ),
      ],
    );
    await tester.tap(find.byTooltip('大字菜单'));
    await tester.pumpAndSettle();

    final panel = tester.getRect(_menuPanel);
    expect(panel.left, greaterThanOrEqualTo(AppMenuTokens.edgeInset));
    expect(panel.right, lessThanOrEqualTo(240 - AppMenuTokens.edgeInset));
    expect(
      tester.getSize(find.text('Share this note as an image')).height,
      greaterThan(60),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long menu scrolls above a keyboard without covering its trigger',
    (tester) async {
      String? selected;
      await _pumpMenu(
        tester,
        alignment: Alignment.bottomRight,
        tooltip: '键盘菜单',
        screenSize: const Size(360, 720),
        screenPadding: const EdgeInsets.only(top: 24),
        viewInsets: const EdgeInsets.only(bottom: 300),
        anchorPadding: EdgeInsets.zero,
        actions: [
          for (var index = 0; index < 20; index++)
            AppMenuAction(value: '$index', label: '菜单项 $index'),
        ],
        onSelected: (value) => selected = value,
      );
      final trigger = tester.getRect(find.byTooltip('键盘菜单'));
      await tester.tap(find.byTooltip('键盘菜单'));
      await tester.pumpAndSettle();

      final panel = tester.getRect(_menuPanel);
      expect(panel.top, greaterThanOrEqualTo(24 + AppMenuTokens.edgeInset));
      expect(
        panel.bottom,
        lessThanOrEqualTo(trigger.top - AppMenuTokens.anchorGap),
      );
      expect(panel.bottom, lessThan(720 - 300));
      await tester.ensureVisible(find.text('菜单项 19'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('菜单项 19'));
      await tester.pumpAndSettle();
      expect(selected, '19');
      expect(_menuPanel, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected, disabled and destructive actions retain their behavior',
    (tester) async {
      final selected = <String>[];
      await _pumpMenu(
        tester,
        alignment: Alignment.topRight,
        tooltip: '状态菜单',
        actions: const [
          AppMenuAction(
            value: 'selected',
            icon: Icons.push_pin_outlined,
            label: '已置顶',
            selected: true,
          ),
          AppMenuAction(
            value: 'disabled',
            icon: Icons.save_outlined,
            label: '暂不可保存',
            enabled: false,
          ),
          AppMenuAction(
            value: 'delete',
            icon: Icons.delete_outline_rounded,
            label: '永久删除',
            destructive: true,
          ),
        ],
        onSelected: selected.add,
      );
      await tester.tap(find.byTooltip('状态菜单'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final disabled = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, '暂不可保存'),
      );
      expect(disabled.onPressed, isNull);
      expect(
        disabled.style!.iconColor!.resolve({WidgetState.disabled}),
        AppColors.subtle,
      );
      await tester.tap(find.text('暂不可保存'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(_menuPanel, findsOneWidget);

      final destructive = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, '永久删除'),
      );
      expect(destructive.style!.foregroundColor!.resolve({}), AppColors.danger);
      await tester.tap(find.text('永久删除'));
      await tester.pumpAndSettle();
      expect(selected, ['delete']);
      expect(_menuPanel, findsNothing);
    },
  );

  testWidgets('outside tap dismisses without activating the page underneath', (
    tester,
  ) async {
    var taps = 0;
    await _pumpMenu(
      tester,
      alignment: Alignment.topRight,
      tooltip: '菜单',
      onBackgroundTap: () => taps++,
    );
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('背景操作')));
    await tester.pumpAndSettle();
    expect(_menuPanel, findsNothing);
    expect(taps, 0);
    await tester.tap(find.text('背景操作'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Android back closes the menu and keeps the page', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topRight, tooltip: '菜单');
    final navigator = Navigator.of(tester.element(find.byType(Scaffold)));
    expect(navigator.canPop(), isFalse);
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isTrue);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(_menuPanel, findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('keyboard can open, traverse and dismiss the menu', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topRight, tooltip: '键盘操作');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_menuPanel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menuPanel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu uses the root overlay when opened inside a bottom sheet', (
    tester,
  ) async {
    await _pumpMenu(tester, alignment: Alignment.topRight, tooltip: '主页菜单');
    final pageContext = tester.element(find.byType(Scaffold));
    showModalBottomSheet<void>(
      context: pageContext,
      builder: (_) => SizedBox(
        height: 180,
        child: Align(
          alignment: Alignment.topRight,
          child: AppAnchoredMenuButton<String>(
            tooltip: '弹框内菜单',
            icon: const Icon(Icons.more_vert_rounded),
            actions: [
              for (var index = 0; index < 8; index++)
                AppMenuAction(value: '$index', label: '选项 $index'),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = tester.getRect(find.byTooltip('弹框内菜单'));
    await tester.tap(find.byTooltip('弹框内菜单'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(_menuPanel);
    expect(
      panel.bottom,
      lessThanOrEqualTo(trigger.top - AppMenuTokens.anchorGap),
    );
    expect(panel.left, greaterThanOrEqualTo(AppMenuTokens.edgeInset));
    expect(panel.right, lessThanOrEqualTo(390 - AppMenuTokens.edgeInset));
    await Navigator.of(pageContext).maybePop();
    await tester.pumpAndSettle();
    expect(_menuPanel, findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _menuPanel = find.byWidgetPredicate(
  (widget) =>
      widget is Material &&
      widget.shape == AppMenuTokens.shape &&
      widget.elevation == AppMenuTokens.elevation,
);

Future<void> _pumpMenu(
  WidgetTester tester, {
  required Alignment alignment,
  required String tooltip,
  Size screenSize = const Size(390, 844),
  EdgeInsets anchorPadding = const EdgeInsets.all(24),
  EdgeInsets screenPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
  List<AppMenuAction<String>>? actions,
  ValueChanged<String>? onSelected,
  VoidCallback? onBackgroundTap,
}) async {
  tester.view.physicalSize = screenSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: screenPadding,
          viewPadding: screenPadding,
          viewInsets: viewInsets,
          textScaler: textScaler,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.bottomLeft,
                child: TextButton(
                  onPressed: onBackgroundTap,
                  child: const Text('背景操作'),
                ),
              ),
              Align(
                alignment: alignment,
                child: Padding(
                  padding: anchorPadding,
                  child: AppAnchoredMenuButton<String>(
                    tooltip: tooltip,
                    icon: const Icon(Icons.more_vert_rounded),
                    actions:
                        actions ??
                        const [
                          AppMenuAction(
                            value: 'first',
                            icon: Icons.edit_outlined,
                            label: '第一项',
                          ),
                          AppMenuAction(
                            value: 'second',
                            icon: Icons.delete_outline_rounded,
                            label: '第二项',
                          ),
                        ],
                    onSelected: onSelected ?? (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

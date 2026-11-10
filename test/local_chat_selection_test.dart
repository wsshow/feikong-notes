import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('user message selection follows the active theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalChatUserMessageText(content: '选择这段用户消息')),
      ),
    );

    final selectable = find.byType(SelectableText);
    final selectionTheme = TextSelectionTheme.of(tester.element(selectable));
    final text = tester.widget<SelectableText>(selectable);

    expect(
      selectionTheme.selectionColor,
      AppPalette.paperLight.accent.withValues(alpha: .22),
    );
    expect(selectionTheme.selectionHandleColor, AppPalette.paperLight.accent);
    expect(text.style?.color, AppPalette.paperLight.ink);
    expect(tester.takeException(), isNull);
  });
}

import 'package:fknotes/app.dart';
import 'package:fknotes/widgets/editor_context_menu.dart';
import 'package:fknotes/widgets/fk_markdown_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editable text uses the branded Chinese action menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'FKNotes 选择菜单');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            contextMenuBuilder: buildAppEditableTextContextMenu,
            controller: controller,
            decoration: const InputDecoration(hintText: '输入内容'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('复制'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Ask Claude'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.elevation == AppMenuTokens.elevation &&
            widget.shadowColor ==
                AppPalette.paperLight.shadow.withValues(alpha: .16) &&
            widget.color == AppColors.surface &&
            widget.shape is RoundedRectangleBorder,
      ),
      findsOneWidget,
    );
  });

  testWidgets('Markdown selection uses the same app menu', (tester) async {
    String? quoted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data: '第一段支持选择。\n\n第二段也能一起选择。',
            onQuoteSelection: (value) => quoted = value,
          ),
        ),
      ),
    );

    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(area.contextMenuBuilder, isNotNull);
    expect(markdown.selectable, isFalse);
    expect(find.byType(SelectableText), findsNothing);

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.textContaining('第一段支持选择')),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getBottomRight(find.textContaining('第二段也能一起选择')),
    );
    await gesture.up();
    await tester.pump();

    final state = tester.state<SelectionAreaState>(find.byType(SelectionArea));
    final entry = OverlayEntry(
      builder: (context) =>
          area.contextMenuBuilder!(context, state.selectableRegion),
    );
    Overlay.of(tester.element(find.byType(SelectionArea))).insert(entry);
    addTearDown(entry.remove);
    await tester.pump();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    await tester.tap(find.text('引用'));
    await tester.pump();
    expect(quoted, contains('第一段支持选择'));
    expect(quoted, contains('第二段也能一起选择'));
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Ask Claude'), findsNothing);
  });
}

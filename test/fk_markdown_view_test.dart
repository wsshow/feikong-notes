import 'package:fknotes/widgets/fk_markdown_view.dart';
import 'package:fknotes/widgets/markdown_latex.dart';
import 'package:fknotes/markdown/markdown_front_matter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  test('front matter reading parser emits a literal table and normal body', () {
    final nodes = md.Document(extensionSet: fkMarkdownExtensionSet).parse(
      MarkdownFrontMatter.normalize('''
\uFEFF---
title: "**字面标题** <tag>"
platforms: [iOS, Android]
---

# 正文标题

**正文加粗**
'''),
    );
    expect(nodes.whereType<md.Element>().map((node) => node.tag), [
      'table',
      'h1',
      'p',
    ]);
    final table = nodes.first as md.Element;
    final header =
        (table.children!.first as md.Element).children!.first as md.Element;
    final cell = header.children!.last as md.Element;
    expect(cell.children, hasLength(1));
    expect(cell.children!.single, isA<md.Text>());
    expect(cell.textContent, '**字面标题** <tag>');
    expect(table.textContent, contains('[iOS, Android]'));
    expect((nodes.last as md.Element).children!.first, isA<md.Element>());
  });

  test(
    'front matter detection leaves incomplete invalid and nonleading content alone',
    () {
      for (final source in [
        '---\ntitle: 未闭合\n\n# 正文',
        '---\nplatforms: [iOS, Android\n---\n\n# 正文',
        '---\n普通段落\n---\n\n# 正文',
        '前文\n\n---\ntitle: 不是元数据\n---',
        '> ---\n> title: 引用示例\n> ---',
        '```yaml\n---\ntitle: 代码示例\n---\n```',
      ]) {
        expect(MarkdownFrontMatter.read(source), isNull);
        final nodes = md.Document(
          extensionSet: fkMarkdownExtensionSet,
        ).parse(source);
        expect(
          nodes.whereType<md.Element>().any((node) => node.tag == 'table'),
          isFalse,
        );
        expect(nodes.map((node) => node.textContent).join(), isNotEmpty);
      }
    },
  );

  test(
    'front matter keeps nested values without recursively expanding aliases',
    () {
      final metadata = MarkdownFrontMatter.read('''
---
title: 示例
settings:
  theme: sunny
  enabled: true
cycle: &self [*self]
---
''')!;
      expect(metadata.rows[1][1], contains('theme: sunny'));
      expect(metadata.rows[2][1], contains('*self'));
      expect(
        MarkdownFrontMatter.read('---\nvalue: ${'x' * 4001}\n---'),
        isNull,
      );
      final aliases = [
        for (var i = 0; i < 110; i++) 'copy$i: *value',
      ].join('\n');
      expect(
        MarkdownFrontMatter.read(
          '---\nvalue: &value ${'x' * 1000}\n$aliases\n---',
        ),
        isNull,
      );
    },
  );

  testWidgets('renders GFM model output instead of syntax markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data:
                '# 标题\n\n**重点**\n\n- [ ] 待办\n\n```dart\nfinal ok = true;\n```',
          ),
        ),
      ),
    );

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('重点'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.textContaining('final ok = true;'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('does not load remote images from private markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data: '![秘密图片](https://example.com/tracker.png)',
          ),
        ),
      ),
    );

    expect(find.text('未加载外部图片：秘密图片'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders GFM tables as a scrollable grid', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.only(bottom: 24)),
            child: SizedBox(
              width: 320,
              child: FkMarkdownView(
                data:
                    '| 类别 | 核心名称 | 简要描述 |\n'
                    '| :--- | :---: | ---: |\n'
                    '| 历史典故 | 桃园三结义 | 刘备、关羽、张飞三人在桃园结拜。 |',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('类别'), findsOneWidget);
    expect(find.text('桃园三结义'), findsOneWidget);
    expect(find.textContaining('| :---'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    final tableScrollFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final tableScroll = tester.widget<SingleChildScrollView>(tableScrollFinder);
    expect(tableScroll.padding, EdgeInsets.zero);
    expect(
      tester.getBottomLeft(tableScrollFinder).dy -
          tester.getBottomLeft(find.byType(Table)).dy,
      0,
      reason: 'the scrollbar viewport must end on the table bottom line',
    );
    expect(
      MediaQuery.paddingOf(tester.element(find.byType(Scrollbar))),
      EdgeInsets.zero,
      reason: 'page safe-area padding must not lift an embedded scrollbar',
    );
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isFalse,
    );
    final scrollbarTheme = tester.widget<ScrollbarTheme>(
      find.byType(ScrollbarTheme),
    );
    expect(scrollbarTheme.data.thickness!.resolve({}), 3);
    expect(scrollbarTheme.data.mainAxisMargin, 4);
    expect(scrollbarTheme.data.crossAxisMargin, 0);
  });

  testWidgets('external links require an explicit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(data: '[官网](https://example.com/path)'),
        ),
      ),
    );

    await tester.tap(find.text('官网'));
    await tester.pumpAndSettle();
    expect(find.text('打开外部链接？'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.text('继续打开'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('打开外部链接？'), findsNothing);
  });

  testWidgets('unsafe link schemes are rejected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(data: '[危险链接](javascript:alert(1))'),
        ),
      ),
    );

    await tester.tap(find.text('危险链接'));
    await tester.pump();
    expect(find.text('这个链接地址无效或使用了不受支持的协议'), findsOneWidget);
    expect(find.text('打开外部链接？'), findsNothing);
  });

  testWidgets('incomplete streaming Markdown remains renderable', (
    tester,
  ) async {
    Widget app(String data) => MaterialApp(
      home: Scaffold(body: FkMarkdownView(data: data)),
    );

    await tester.pumpWidget(app('## 代码示例\n\n```dart\nfinal value ='));
    expect(find.text('代码示例'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app('## 代码示例\n\n```dart\nfinal value = 1;\n```\n\n> 完成'),
    );
    expect(find.textContaining('final value = 1;'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders inline and display LaTeX equations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data:
                r'质能方程是 $E=mc^2$。'
                '\n\n'
                r'$$'
                '\n'
                r'\int_0^1 x^2\,dx=\frac{1}{3}'
                '\n'
                r'$$',
          ),
        ),
      ),
    );

    expect(find.textContaining(r'$E=mc^2$'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is Math),
      findsNWidgets(2),
    );
    expect(
      find.bySemanticsLabel(r'数学公式：\int_0^1 x^2\,dx=\frac{1}{3}'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps currency escaped dollars and code out of LaTeX', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(
            data:
                r'价格是 $100 和 $200，转义符号为 \$，代码 `$value`。'
                '\n\n'
                '```dart\nfinal price = r\'\$100\';\n```',
          ),
        ),
      ),
    );

    expect(find.textContaining('价格是'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is Math), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('math syntax leaves currency escaped dollars and code untouched', () {
    final document = md.Document(extensionSet: fkMarkdownExtensionSet);
    final nodes = document.parseLines([
      r'价格是 $100 和 $200，转义符号为 \$，代码 `$value`。',
      '',
      '```dart',
      r"final price = r'$100';",
      '```',
    ]);
    final mathElements = <md.Element>[];

    void collect(md.Node node) {
      if (node is! md.Element) return;
      if ({markdownInlineMathTag, markdownBlockMathTag}.contains(node.tag)) {
        mathElements.add(node);
      }
      node.children?.forEach(collect);
    }

    nodes.forEach(collect);
    expect(mathElements, isEmpty);
    expect(
      nodes.map((node) => node.textContent).join('\n'),
      contains(r'$value'),
    );
    expect(nodes.map((node) => node.textContent).join('\n'), contains(r'$100'));
  });

  testWidgets('unfinished and malformed streamed LaTeX degrades safely', (
    tester,
  ) async {
    Widget app(String data) => MaterialApp(
      home: Scaffold(body: FkMarkdownView(data: data)),
    );

    await tester.pumpWidget(app(r'正在生成：$$\frac{1}{'));
    expect(find.textContaining(r'$$\frac{1}{'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(r'错误公式 $\notARealCommand{x}$ 仍可阅读'));
    await tester.pump();
    expect(find.textContaining(r'$\notARealCommand{x}$'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

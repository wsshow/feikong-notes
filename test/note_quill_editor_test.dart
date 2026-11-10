// The pinned Flutter Quill clipboard hooks are intentionally exercised here.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:fknotes/app.dart';
import 'package:fknotes/editor/note_assistant_editing.dart';
import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/editor/note_markdown_codec.dart';
import 'package:fknotes/editor/note_outline.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_audio_playback_service.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:fknotes/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
// Render invariants are checked against the pinned, vendored Quill runtime.
// ignore: implementation_imports
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart'
    show RenderEditableTextLine;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'theme changes preserve editor content, selection and undo history',
    (tester) async {
      final appearance = ValueNotifier((AppThemeStyle.paper, Brightness.light));
      addTearDown(appearance.dispose);
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('主题不会改变正文'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<(AppThemeStyle, Brightness)>(
          valueListenable: appearance,
          builder: (context, value, _) => _EditorTestApp(
            theme: buildAppTheme(value.$1, value.$2),
            child: NoteQuillEditor(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.quillController.replaceText(
        2,
        0,
        '偏好',
        const TextSelection.collapsed(offset: 4),
      );
      await tester.pump();
      final state = tester.state(find.byType(NoteQuillEditor));
      final document = controller.quillController.document;
      final delta = document.toDelta().toJson();
      final selection = controller.quillController.selection;
      final size = tester.getRect(find.byType(NoteQuillEditor));
      for (final theme in [
        (AppThemeStyle.starlight, Brightness.light),
        (AppThemeStyle.starlight, Brightness.dark),
      ]) {
        appearance.value = theme;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(NoteQuillEditor)), same(state));
        expect(controller.quillController.document, same(document));
        expect(document.toDelta().toJson(), delta);
        expect(controller.quillController.selection, selection);
        expect(tester.getRect(find.byType(NoteQuillEditor)), size);
        expect(
          tester.element(find.byType(NoteQuillEditor)).appColors,
          AppPalette.forStyle(theme.$1, theme.$2),
        );
      }
      controller.quillController.undo();
      await tester.pump();
      expect(controller.snapshot().document.project().plainText, '主题不会改变正文');
      expect(tester.takeException(), isNull);
    },
  );

  group('NoteEditorController', () {
    test(
      'outline extracts formatted headings with exact embed and emoji offsets',
      () {
        final delta = Delta()
          ..insert('正文👋\n')
          ..insert(const NoteEmbed.divider().toDeltaData())
          ..insert('\n')
          ..insert('章', {'bold': true})
          ..insert('节😀', {'italic': true})
          ..insert('\n', {'header': 2})
          ..insert('\n', {'header': 4})
          ..insert('子节')
          ..insert('\n', {'header': 6})
          ..insert('# 只是正文\n')
          ..insert('节😀', {'bold': true})
          ..insert('\n', {'header': 1})
          ..insert('节😀')
          ..insert('\n', {'header': 3});
        final before = delta.toJson();
        final entries = NoteOutlineEntry.fromDelta(delta);
        expect(entries.map((entry) => entry.text), [
          '章节😀',
          '子节',
          '节😀',
          '节😀',
        ]);
        expect(entries.map((entry) => entry.level), [2, 6, 1, 3]);
        expect(entries.map((entry) => entry.depth), [0, 1, 0, 1]);
        final text = NoteDocument.fromDelta(
          delta,
        ).toQuillDocument().toPlainText();
        expect(entries.map((entry) => entry.offset), [
          text.indexOf('章节😀'),
          text.indexOf('子节'),
          text.indexOf('节😀', text.indexOf('#')),
          text.lastIndexOf('节😀'),
        ]);
        expect(delta.toJson(), before);
      },
    );

    test(
      'outline reads shared heading newlines and ignores unformatted text',
      () {
        final entries = NoteOutlineEntry.fromDelta(
          Delta()
            ..insert('第一节\n第二节\n', {'header': 1})
            ..insert('加粗不是标题', {'bold': true})
            ..insert('\n')
            ..insert('引用')
            ..insert('\n', {'blockquote': true})
            ..insert('任务')
            ..insert('\n', {'list': 'unchecked'}),
        );
        expect(entries.map((entry) => (entry.text, entry.offset)), [
          ('第一节', 0),
          ('第二节', 4),
        ]);
        expect(
          NoteOutlineEntry.fromDelta(Delta()..insert('\n', {'header': 1})),
          isEmpty,
        );
      },
    );

    test(
      'keeps native newlines and Quill inline styles in the Delta snapshot',
      () {
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('第一行'),
          assets: const [],
        );
        addTearDown(controller.dispose);

        controller.quillController.replaceText(
          3,
          0,
          '\n第二行',
          const TextSelection.collapsed(offset: 7),
        );
        controller.quillController.formatText(0, 3, quill.Attribute.bold);

        final snapshot = controller.snapshot();
        expect(snapshot.document.project().plainText, '第一行\n第二行');
        expect(snapshot.document.toDelta().toJson(), [
          {
            'insert': '第一行',
            'attributes': {'bold': true},
          },
          {'insert': '\n第二行\n'},
        ]);
      },
    );

    test(
      'inserts an image as an independent block in the current paragraph',
      () {
        final asset = _imageAsset();
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('前文后文'),
          assets: const [],
        );
        addTearDown(controller.dispose);
        controller.quillController.updateSelection(
          const TextSelection.collapsed(offset: 2),
          quill.ChangeSource.local,
        );

        controller.insertAsset(asset);
        final snapshot = controller.snapshot();

        expect(snapshot.assets, [asset]);
        expect(snapshot.document.project().plainText, '前文\n\n后文');
        expect(snapshot.document.project().referencedAttachmentIds, [asset.id]);
        expect(snapshot.document.toDelta().toJson(), [
          {'insert': '前文\n'},
          {'insert': NoteEmbed.attachment(asset.id).toDeltaData()},
          {'insert': '\n后文\n'},
        ]);
        expect(
          controller.quillController.selection,
          const TextSelection.collapsed(offset: 5),
        );
        expect(controller.isAttachmentEmbedAtOffset(3), isTrue);
        expect(controller.isAttachmentEmbedAtOffset(4), isTrue);
        expect(controller.isAttachmentEmbedAtOffset(5), isFalse);
      },
    );

    test(
      'inserts dropped images at the requested document offset in order',
      () {
        final first = _imageAsset();
        final second = _imageAsset('72b9ed8e-983d-4b35-9032-0bb05c456e45');
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('前\n后'),
          assets: const [],
        );
        addTearDown(controller.dispose);

        controller.insertAssetAt(first, 2);
        controller.insertAssetAt(second, 4);

        final snapshot = controller.snapshot();
        expect(snapshot.assets, [first, second]);
        expect(snapshot.document.toDelta().toJson(), [
          {'insert': '前\n'},
          {'insert': NoteEmbed.attachment(first.id).toDeltaData()},
          {'insert': '\n'},
          {'insert': NoteEmbed.attachment(second.id).toDeltaData()},
          {'insert': '\n后\n'},
        ]);
      },
    );

    test('replaces a structured table at its stable document offset', () {
      final original = NoteTable(
        rows: const [
          ['项目', '状态'],
          ['Quill', '完成'],
        ],
        alignments: const [NoteTableAlignment.start, NoteTableAlignment.end],
      );
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.table(original).toDeltaData())
            ..insert('\n尾注\n'),
        ),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final replacement = NoteTable(
        rows: const [
          ['组件', '进度', '负责人'],
          ['编辑器', '进行中', '小飞'],
        ],
        alignments: const [
          NoteTableAlignment.start,
          NoteTableAlignment.center,
          NoteTableAlignment.end,
        ],
      );

      expect(controller.tableAtOffset(0)?.rows, original.rows);
      expect(controller.replaceTableAt(0, replacement), isTrue);
      expect(controller.tableAtOffset(0)?.rows, replacement.rows);
      expect(
        controller.snapshot().document.project().plainText,
        contains('尾注'),
      );
      expect(controller.replaceTableAt(2, original), isFalse);
    });

    test('moves a media block atomically without changing its asset', () {
      final image = _imageAsset();
      final audio = _audioAsset();
      final original = Delta()
        ..insert(NoteEmbed.attachment(image.id).toDeltaData())
        ..insert('\n正文\n')
        ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
        ..insert('\n');
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(original),
        assets: [image, audio],
      );
      addTearDown(controller.dispose);

      expect(
        controller.moveAssetEmbed(
          attachmentId: image.id,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        isTrue,
      );
      expect(controller.snapshot().assets, [audio, image]);
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '正文\n'},
        {'insert': NoteEmbed.attachment(audio.id).toDeltaData()},
        {'insert': '\n'},
        {'insert': NoteEmbed.attachment(image.id).toDeltaData()},
        {'insert': '\n'},
      ]);

      controller.quillController.undo();
      expect(
        controller.snapshot().document.toDelta().toJson(),
        original.toJson(),
      );
    });

    test('moves a video card with the same block transaction', () {
      final video = _videoAsset();
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.attachment(video.id).toDeltaData())
            ..insert('\n正文\n'),
        ),
        assets: [video],
      );
      addTearDown(controller.dispose);

      expect(
        controller.moveAssetEmbed(
          attachmentId: video.id,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        isTrue,
      );
      expect(controller.snapshot().assets, [video]);
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '正文\n'},
        {'insert': NoteEmbed.attachment(video.id).toDeltaData()},
        {'insert': '\n'},
      ]);
    });

    test(
      'system image paste imports bytes into a domain asset embed',
      () async {
        final asset = _imageAsset();
        var importedBytes = Uint8List(0);
        final controller = NoteEditorController(
          document: NoteDocument.empty(),
          assets: const [],
          readClipboardImage: () async => Uint8List.fromList([1, 2, 3]),
          importImage: (bytes) async {
            importedBytes = bytes;
            return asset;
          },
        );
        addTearDown(controller.dispose);

        expect(await controller.quillController.clipboardPaste(), isTrue);

        expect(importedBytes, [1, 2, 3]);
        expect(controller.snapshot().assets, [asset]);
      },
    );

    test('plain-text Markdown paste becomes native Quill formatting', () async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
        readClipboardText: () async => '''
# 标题

正文 **加粗** 和 *斜体*

- 项目

1. 步骤

> 引用

```dart
final value = 1;
```
''',
      );
      addTearDown(controller.dispose);

      expect(await controller.quillController.clipboardPaste(), isTrue);

      final snapshot = controller.snapshot();
      final delta = snapshot.document.toDelta();
      expect(
        snapshot.document.project().plainText,
        '标题\n正文 加粗 和 斜体\n项目\n步骤\n引用\nfinal value = 1;',
      );
      expect(snapshot.document.project().plainText, isNot(contains('**')));
      expect(
        delta.operations,
        contains(
          isA<Operation>()
              .having((operation) => operation.data, 'text', '加粗')
              .having(
                (operation) => operation.attributes?['bold'],
                'bold',
                isTrue,
              ),
        ),
      );
      expect(
        delta.operations
            .where((operation) => operation.data == '\n')
            .map((operation) => operation.attributes)
            .whereType<Map<String, dynamic>>(),
        containsAll([
          containsPair('header', 1),
          containsPair('list', 'bullet'),
          containsPair('list', 'ordered'),
          containsPair('blockquote', true),
          containsPair('code-block', true),
        ]),
      );
    });

    test(
      'task Markdown paste keeps checked and unchecked list types',
      () async {
        final controller = NoteEditorController(
          document: NoteDocument.empty(),
          assets: const [],
          readClipboardText: () async => '☐ 待处理\n☑ 已完成',
        );
        addTearDown(controller.dispose);

        expect(await controller.quillController.clipboardPaste(), isTrue);

        expect(controller.snapshot().document.toDelta().toJson(), [
          {'insert': '待处理'},
          {
            'insert': '\n',
            'attributes': {'list': 'unchecked'},
          },
          {'insert': '已完成'},
          {
            'insert': '\n',
            'attributes': {'list': 'checked'},
          },
        ]);
      },
    );

    test('nested task Markdown preserves mixed list levels on paste', () async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
        readClipboardText: () async => '''
- [ ] 这是提醒测试
  - [ ] 子任务一
  - [ ] 测试
    - 详情
    - 111
''',
      );
      addTearDown(controller.dispose);

      expect(await controller.quillController.clipboardPaste(), isTrue);
      final snapshot = controller.snapshot().document;
      expect(snapshot.project().plainText, '这是提醒测试\n子任务一\n测试\n详情\n111');
      expect(
        snapshot
            .toDelta()
            .operations
            .where((op) => op.data == '\n')
            .map((op) => op.attributes),
        [
          {'list': 'unchecked'},
          {'list': 'unchecked', 'indent': 1},
          {'list': 'unchecked', 'indent': 1},
          {'list': 'bullet', 'indent': 2},
          {'list': 'bullet', 'indent': 2},
        ],
      );
      controller.quillController.undo();
      expect(controller.snapshot().document.project().isVisuallyEmpty, isTrue);
    });

    test('nested task state does not turn its ordinary parent into a task', () {
      final delta = NoteMarkdownCodec.decode('''
- 普通父项
  - [x] 完成子项
- [ ] 未完成父项
  - [x] 另一个完成子项
''');
      expect(
        delta.operations
            .where((op) => op.data == '\n')
            .map((op) => op.attributes),
        [
          {'list': 'bullet'},
          {'list': 'checked', 'indent': 1},
          {'list': 'unchecked'},
          {'list': 'checked', 'indent': 1},
        ],
      );
    });

    test(
      'partial-line indentation leaves unselected list siblings unchanged',
      () {
        final controller = NoteEditorController(
          document: NoteDocument.fromDelta(
            Delta()
              ..insert('甲乙丙\n丁戊己\n庚辛壬\n癸子丑\n', {'list': 'bullet', 'indent': 1}),
          ),
          assets: const [],
        );
        addTearDown(controller.dispose);
        final quillController = controller.quillController;
        quillController.updateSelection(
          const TextSelection(baseOffset: 5, extentOffset: 6),
          quill.ChangeSource.local,
        );
        quillController.indentSelection(true);
        for (var row = 0; row < 4; row++) {
          expect(
            quillController.document
                .collectStyle(row * 4, 0)
                .attributes['indent']
                ?.value,
            row == 1 ? 2 : 1,
            reason: 'only the selected second line changes depth',
          );
        }
      },
    );

    for (final depth in [5, 8]) {
      test(
        'selected list at depth $depth keeps its level when indent is capped',
        () {
          final controller = NoteEditorController(
            document: NoteDocument.fromDelta(
              Delta()
                ..insert('深层')
                ..insert('\n', {'list': 'unchecked', 'indent': depth})
                ..insert('浅层')
                ..insert('\n', {'list': 'bullet', 'indent': 2}),
            ),
            assets: const [],
          );
          addTearDown(controller.dispose);
          final quillController = controller.quillController;
          quillController.updateSelection(
            const TextSelection(baseOffset: 0, extentOffset: 5),
            quill.ChangeSource.local,
          );
          quillController.indentSelection(true);
          expect(
            quillController.document
                .collectStyle(0, 0)
                .attributes['indent']
                ?.value,
            depth,
          );
          expect(
            quillController.document
                .collectStyle(3, 0)
                .attributes['indent']
                ?.value,
            3,
          );
          quillController.indentSelection(false);
          expect(
            quillController.document
                .collectStyle(0, 0)
                .attributes['indent']
                ?.value,
            depth - 1,
          );
          expect(
            quillController.document
                .collectStyle(3, 0)
                .attributes['indent']
                ?.value,
            2,
          );
        },
      );
    }

    test('Enter continues a nested task and outdent keeps the task type', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert('子项')
            ..insert('\n', {'list': 'unchecked', 'indent': 1}),
        ),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final quillController = controller.quillController;
      quillController.replaceText(
        2,
        0,
        '\n',
        const TextSelection.collapsed(offset: 3),
      );
      expect(
        quillController.getSelectionStyle().attributes['list']?.value,
        'unchecked',
      );
      expect(
        quillController.getSelectionStyle().attributes['indent']?.value,
        1,
      );
      quillController.replaceText(
        3,
        0,
        '同级',
        const TextSelection.collapsed(offset: 5),
      );
      quillController.indentSelection(false);
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '子项'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked', 'indent': 1},
        },
        {'insert': '同级'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);
    });

    test('system text replacement converts task Markdown before insertion', () {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);

      controller.quillController.replaceText(
        0,
        0,
        '☐ 系统粘贴',
        const TextSelection.collapsed(offset: 6),
      );

      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '系统粘贴'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);
    });

    test('ordinary plain-text paste stays on Quill native path', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('原文'),
        assets: const [],
        readClipboardText: () async => '普通文本，没有 Markdown 语义。',
      );
      addTearDown(controller.dispose);
      final paste =
          controller.quillController.config.clipboardConfig!.onClipboardPaste!;

      expect(await paste(), isFalse);
      expect(controller.snapshot().document.project().plainText, '原文');
    });

    test('inline Markdown paste keeps the surrounding paragraph', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('前后'),
        assets: const [],
        readClipboardText: () async => '**重点**',
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 1),
        quill.ChangeSource.local,
      );

      expect(await controller.quillController.clipboardPaste(), isTrue);
      expect(controller.snapshot().document.project().plainText, '前重点后');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '前'},
        {
          'insert': '重点',
          'attributes': {'bold': true},
        },
        {'insert': '后\n'},
      ]);
    });

    test('block Markdown paste starts on a clean line', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('前后'),
        assets: const [],
        readClipboardText: () async => '# 标题',
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 1),
        quill.ChangeSource.local,
      );

      expect(await controller.quillController.clipboardPaste(), isTrue);
      expect(controller.snapshot().document.project().plainText, '前\n标题\n后');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '前\n标题'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '后\n'},
      ]);
    });

    test(
      'single structural Markdown block never becomes an inline embed',
      () async {
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('前后'),
          assets: const [],
          readClipboardText: () async => '---',
        );
        addTearDown(controller.dispose);
        controller.quillController.updateSelection(
          const TextSelection.collapsed(offset: 1),
          quill.ChangeSource.local,
        );

        expect(await controller.quillController.clipboardPaste(), isTrue);

        expect(controller.snapshot().document.toDelta().toJson(), [
          {'insert': '前\n'},
          {'insert': const NoteEmbed.divider().toDeltaData()},
          {'insert': '\n后\n'},
        ]);
      },
    );

    test('discards imported files when an embed cannot be inserted', () async {
      final asset = _imageAsset();
      NoteAsset? discarded;
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
        importImage: (_) async => asset,
        discardImportedAsset: (value) async => discarded = value,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.importImageBytes(Uint8List.fromList([1])),
        throwsArgumentError,
      );

      expect(discarded, asset);
      expect(controller.snapshot().assets, [asset]);
    });

    test('external rich paste strips path and URL image embeds', () async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final sanitize =
          controller.quillController.config.clipboardConfig!.onRichTextPaste!;
      final pasted = Delta()
        ..insert('安全文本', {'italic': true})
        ..insert({'image': 'https://tracker.example/image.png'});

      final clean = await sanitize(pasted, true);

      expect(clean?.toJson(), [
        {
          'insert': '安全文本',
          'attributes': {'italic': true},
        },
      ]);
    });

    test('snapshot reconciles assets after an embed is deleted', () {
      final asset = _imageAsset();
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
      );
      addTearDown(controller.dispose);

      controller.removeEmbedAt(0);

      expect(controller.snapshot().assets, isEmpty);
      expect(controller.snapshot().document.project().isVisuallyEmpty, isTrue);
    });

    test(
      'whole-document formatting crosses paragraphs and an image safely',
      () {
        final asset = _imageAsset();
        final document = NoteDocument.fromDelta(
          Delta()
            ..insert('第一段\n')
            ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
            ..insert('\n')
            ..insert('第二段\n'),
        );
        final controller = NoteEditorController(
          document: document,
          assets: [asset],
        );
        addTearDown(controller.dispose);

        controller.quillController.updateSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: controller.quillController.document.length - 1,
          ),
          quill.ChangeSource.local,
        );
        controller.quillController.formatSelection(quill.Attribute.bold);

        final snapshot = controller.snapshot();
        expect(snapshot.document.project().plainText, '第一段\n\n第二段');
        expect(snapshot.assets, [asset]);
        final embedOperation = snapshot.document
            .toDelta()
            .operations
            .singleWhere((operation) => operation.data is! String);
        expect(embedOperation.attributes, isNull);
      },
    );

    test('AI Markdown becomes native Delta formatting and list blocks', () {
      final delta = NoteMarkdownCodec.decode(
        '## 摘要\n\n**重点**与 [链接](https://example.com)\n\n- 一\n- 二',
      );
      final document = NoteDocument.fromDelta(delta);

      expect(document.project().plainText, '摘要\n重点与 链接\n一\n二');
      expect(delta.toJson(), [
        {'insert': '摘要'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {
          'insert': '重点',
          'attributes': {'bold': true},
        },
        {'insert': '与 '},
        {
          'insert': '链接',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': '\n一'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': '二'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
    });

    test('Markdown tables and rules become structured block embeds', () {
      final delta = NoteMarkdownCodec.decode('''
| 项目 | 状态 |
| :--- | ---: |
| Quill | 完成 |
| 分享图 | 待检查 |

---
''');
      final document = NoteDocument.fromDelta(delta);
      final embeds = delta.operations
          .where((operation) => operation.data is! String)
          .map((operation) => NoteEmbed.parse(operation.data))
          .toList(growable: false);

      expect(embeds.map((embed) => embed.kind), [
        NoteEmbedKind.table,
        NoteEmbedKind.divider,
      ]);
      expect(embeds.first.table!.rows, const [
        ['项目', '状态'],
        ['Quill', '完成'],
        ['分享图', '待检查'],
      ]);
      expect(embeds.first.table!.alignments, const [
        NoteTableAlignment.start,
        NoteTableAlignment.end,
      ]);
      expect(document.project().plainText, contains('Quill\t完成'));
      expect(document.project().plainText, isNot(contains('|')));
      expect(document.project().plainText, isNot(contains('---')));
    });

    test(
      'Markdown front matter preserves literal values and body semantics',
      () {
        final delta = NoteMarkdownCodec.decodeIfRich('''
\uFEFF---
title: "**字面标题** <tag>"
version: 1.0
platforms: [iOS, Android]
summary: |
  [ ] 保留任务示例
  第二行
...

## 正文

- [ ] 实际待办
''')!;
        final table = NoteEmbed.parse(delta.operations.first.data).table!;
        expect(table.rows, const [
          ['title', '**字面标题** <tag>'],
          ['version', '1.0'],
          ['platforms', '[iOS, Android]'],
          ['summary', '[ ] 保留任务示例\n第二行'],
        ]);
        expect(
          delta.operations.any((op) => op.attributes?['header'] == 2),
          isTrue,
        );
        expect(delta.operations.last.attributes, {'list': 'unchecked'});
        expect(
          NoteDocument.fromDelta(delta).project().plainText,
          contains('实际待办'),
        );
      },
    );

    test('Markdown front matter markers in code remain literal', () {
      final source = '---\ntitle: 代码示例\n---';
      final delta = NoteMarkdownCodec.decode('```yaml\n$source\n```');
      expect(NoteDocument.fromDelta(delta).project().plainText, source);
      expect(delta.operations.any((op) => op.data is! String), isFalse);
      expect(delta.operations.last.attributes, {'code-block': true});
    });

    test('loose Markdown list paragraphs keep their line boundary', () {
      final delta = NoteMarkdownCodec.decode('''
- 第一段

  第二段
''');

      expect(NoteDocument.fromDelta(delta).project().plainText, '第一段\n第二段');
      expect(delta.toJson(), [
        {'insert': '第一段'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': '第二段'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
    });

    test('task-like markers inside code blocks stay literal', () {
      final delta = NoteMarkdownCodec.decode('''
```
☐ fenced example
```

    ☑ indented example

	[ ] tab-indented example
''');

      expect(
        NoteDocument.fromDelta(delta).project().plainText,
        '☐ fenced example\n☑ indented example\n\n[ ] tab-indented example',
      );
      expect(
        delta.operations
            .where((operation) => operation.data == '\n')
            .every((operation) => operation.attributes?['code-block'] == true),
        isTrue,
      );
    });

    test('AI selection replacement is one native document transaction', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('保留 需要润色 结尾'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection(baseOffset: 3, extentOffset: 7),
        quill.ChangeSource.local,
      );
      final anchor = controller.captureAssistantAnchor();

      final applied = controller.applyAssistantMarkdown(
        anchor: anchor,
        scope: NoteAssistantEditScope.selection,
        placement: NoteAssistantEditPlacement.replace,
        markdown: '**已润色**',
      );

      expect(applied, isTrue);
      expect(controller.snapshot().document.project().plainText, '保留 已润色 结尾');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '保留 '},
        {
          'insert': '已润色',
          'attributes': {'bold': true},
        },
        {'insert': ' 结尾\n'},
      ]);
    });

    test('streamed AI insertion can be undone as one complete action', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('保留 需要改写 结尾'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection(baseOffset: 3, extentOffset: 7),
        quill.ChangeSource.local,
      );

      final session = controller.beginAssistantInsertion();
      expect(controller.updateAssistantInsertion(session, '**草稿**'), isTrue);
      expect(controller.updateAssistantInsertion(session, '**最终稿**'), isTrue);
      controller.finishAssistantInsertion(session);

      expect(controller.snapshot().document.project().plainText, '保留 最终稿 结尾');
      expect(controller.revertAssistantInsertion(session), isTrue);
      expect(controller.snapshot().document.project().plainText, '保留 需要改写 结尾');
      expect(
        controller.quillController.selection,
        const TextSelection(baseOffset: 3, extentOffset: 7),
      );
    });

    test('streamed AI can replace a paragraph or the whole document', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('第一段\n需要整理\n第三段'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 6),
        quill.ChangeSource.local,
      );
      final paragraphAnchor = controller.captureAssistantAnchor();
      final paragraphSession = controller.beginAssistantInsertion(
        anchor: paragraphAnchor,
        target: NoteInlineAssistantTarget.currentLine,
      );

      expect(
        controller.updateAssistantInsertion(paragraphSession, '- 第一项\n- 第二项'),
        isTrue,
      );
      controller.finishAssistantInsertion(paragraphSession);
      expect(
        controller.snapshot().document.project().plainText,
        '第一段\n第一项\n第二项\n第三段',
      );
      expect(controller.revertAssistantInsertion(paragraphSession), isTrue);
      expect(
        controller.snapshot().document.project().plainText,
        '第一段\n需要整理\n第三段',
      );

      final documentAnchor = controller.captureAssistantAnchor();
      final documentSession = controller.beginAssistantInsertion(
        anchor: documentAnchor,
        target: NoteInlineAssistantTarget.document,
      );
      expect(
        controller.updateAssistantInsertion(documentSession, '# 新标题\n\n新正文'),
        isTrue,
      );
      controller.finishAssistantInsertion(documentSession);
      expect(controller.snapshot().document.project().plainText, '新标题\n新正文');
      expect(controller.revertAssistantInsertion(documentSession), isTrue);
      expect(
        controller.snapshot().document.project().plainText,
        '第一段\n需要整理\n第三段',
      );
    });

    test('AI refuses stale anchors after the user keeps editing', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('原文'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final anchor = controller.captureAssistantAnchor();
      controller.quillController.replaceText(
        0,
        0,
        '新',
        const TextSelection.collapsed(offset: 1),
      );

      expect(
        controller.applyAssistantMarkdown(
          anchor: anchor,
          scope: NoteAssistantEditScope.document,
          placement: NoteAssistantEditPlacement.replace,
          markdown: '生成结果',
        ),
        isFalse,
      );
      expect(controller.snapshot().document.project().plainText, '新原文');
    });

    test('AI appends below the current line without merging paragraphs', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('第一行\n第二行'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 2),
        quill.ChangeSource.local,
      );
      final anchor = controller.captureAssistantAnchor();

      expect(
        controller.applyAssistantMarkdown(
          anchor: anchor,
          scope: NoteAssistantEditScope.currentLine,
          placement: NoteAssistantEditPlacement.insertBelow,
          markdown: '插入行',
        ),
        isTrue,
      );
      expect(
        controller.snapshot().document.project().plainText,
        '第一行\n插入行\n第二行',
      );
    });

    test('AI append preserves both existing and generated block styles', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert('原待办')
            ..insert('\n', {'list': 'unchecked'}),
        ),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final anchor = controller.captureAssistantAnchor();

      expect(
        controller.applyAssistantMarkdown(
          anchor: anchor,
          scope: NoteAssistantEditScope.document,
          placement: NoteAssistantEditPlacement.append,
          markdown: '# 新标题\n\n☑ 新待办',
        ),
        isTrue,
      );
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '原待办'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
        {'insert': '新标题'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '新待办'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
      ]);
    });
  });

  testWidgets('editor and card preview share the paper-themed code style', (
    tester,
  ) async {
    final document = NoteDocument.fromDelta(
      Delta()
        ..insert('final answer = 42;')
        ..insert('\n', {'code-block': true}),
    );
    final controller = NoteEditorController(
      document: document,
      assets: const [],
    );
    final now = DateTime.utc(2026, 7, 23, 12);
    final note = Note(
      id: NoteId.generate(),
      title: '代码笔记',
      document: document,
      assets: const [],
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Column(
          children: [
            Expanded(child: NoteQuillEditor(controller: controller)),
            SizedBox(height: 180, child: NoteRichDocumentPreview(note: note)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editors = tester
        .widgetList<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .toList();
    expect(editors, hasLength(2));
    for (final editor in editors) {
      final styles = editor.config.customStyles!;
      final code = styles.code!;
      expect(code.style.color, AppColors.ink);
      expect(code.decoration!.color, AppColors.paperSecondary);
      expect(code.decoration!.border, Border.all(color: AppColors.line));
      expect(styles.inlineCode!.backgroundColor, AppColors.accentSoft);
      expect(styles.inlineCode!.style.color, AppColors.mechanicalBlue);
    }
  });

  testWidgets('wide code blocks scroll independently without widening prose', (
    tester,
  ) async {
    const prose = '普通正文需要在手机宽度内正常换行，不应跟着代码块一起被横向挤开。';
    final code = List.filled(350, 'A').join();
    final firstCodeOffset = prose.length + 1;
    final asset = _imageAsset();
    final image = await _createTestImage(320, 160);
    final imageProvider = _SynchronousTestImageProvider(image);
    addTearDown(image.dispose);
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('$prose\n')
          ..insert(code)
          ..insert('\n', {'code-block': true})
          ..insert('$prose\n')
          ..insert(code)
          ..insert('\n', {'code-block': true})
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Center(
          child: SizedBox(
            width: 320,
            height: 560,
            child: NoteQuillEditor(
              controller: controller,
              resolveImage: (_) => imageProvider,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontal = find.byKey(const ValueKey('quill-code-block-scroll'));
    expect(horizontal, findsNWidgets(2));
    final raw = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    final render = raw.renderEditor;
    Rect caret(int offset) =>
        render.getLocalRectForCaret(TextPosition(offset: offset));
    expect(render.size.width, 320);
    final imageRect = tester.getRect(
      find.byKey(ValueKey('note-image-${asset.id.value}')),
    );
    expect(imageRect.width, lessThanOrEqualTo(272));
    expect(
      imageRect.left,
      greaterThanOrEqualTo(tester.getRect(horizontal.first).left),
    );
    expect(
      imageRect.right,
      lessThanOrEqualTo(tester.getRect(horizontal.first).right),
    );
    final proseCaret = caret(0);
    expect(
      caret(prose.length - 1).top,
      greaterThan(proseCaret.top),
      reason: '正文在同一篇含超长代码的笔记里仍然正常换行',
    );
    final codeCaret = caret(firstCodeOffset);
    expect(caret(firstCodeOffset + code.length).top, codeCaret.top);
    final scrollView = tester.widget<SingleChildScrollView>(horizontal.first);
    final secondScroll = tester.widget<SingleChildScrollView>(horizontal.last);
    expect(scrollView.scrollDirection, Axis.horizontal);
    expect(scrollView.controller!.position.maxScrollExtent, greaterThan(2000));
    expect(tester.getSize(horizontal.first).width, 272);
    expect(secondScroll.controller!.offset, 0);

    await tester.drag(horizontal.first, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(scrollView.controller!.offset, greaterThan(0));
    expect(secondScroll.controller!.offset, 0);
    expect(caret(0), proseCaret, reason: '滑动代码不移动正文');
    expect(caret(firstCodeOffset).left, lessThan(codeCaret.left));
    expect(render.size.width, 320);

    // Hit testing must use the same scroll transform as the painted caret.
    final visiblePosition = render.getPositionForOffset(
      tester.getRect(horizontal.first).center,
    );
    final visibleCaret = render.localToGlobal(
      caret(visiblePosition.offset).center,
    );
    expect(
      visibleCaret.dx,
      closeTo(tester.getRect(horizontal.first).center.dx, 10),
    );
    expect(visiblePosition.offset, greaterThan(firstCodeOffset));
    expect(
      controller.snapshot().document.toDelta().toJson(),
      controller.quillController.document.toDelta().toJson(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing long code reveals its caret and keeps native undo and IME',
    (tester) async {
      const before = '普通正文保持原来的宽度\n';
      const after = '代码之后的正文\n';
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(before)
            ..insert('x')
            ..insert('\n', {'code-block': true})
            ..insert(after),
        ),
        assets: const [],
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _EditorTestApp(
          child: Center(
            child: SizedBox(
              width: 320,
              height: 500,
              child: NoteQuillEditor(controller: controller, focusNode: focus),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = controller.snapshot().document.toDelta().toJson();
      focus.requestFocus();
      controller.quillController.updateSelection(
        TextSelection.collapsed(offset: before.length + 1),
        quill.ChangeSource.local,
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isRegistered, isTrue);
      final horizontal = find.byKey(const ValueKey('quill-code-block-scroll'));
      final scroll = tester
          .widget<SingleChildScrollView>(horizontal)
          .controller!;
      expect(scroll.position.maxScrollExtent, 0);
      final code = 'xA${List.filled(160, '中文\tA').join()}';
      final end = before.length + code.length;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$before$code\n$after',
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: end - 3, end: end),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      final raw = tester.state<quill.QuillRawEditorState>(
        find.byType(quill.QuillRawEditor),
      );
      final render = raw.renderEditor;
      final caret = render.localToGlobal(
        render.getLocalRectForCaret(TextPosition(offset: end)).center,
      );
      expect(
        tester.getRect(horizontal).contains(caret),
        isTrue,
        reason: '输入的末尾光标必须出现在代码块自己的可视范围',
      );
      expect(render.size.width, 320);
      expect(controller.quillController.selection.extentOffset, end);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$before$code\n$after',
          selection: TextSelection.collapsed(offset: end),
        ),
      );
      await tester.pumpAndSettle();
      final edited = controller.snapshot().document.toDelta().toJson();
      expect(
        controller.quillController.document.toPlainText(),
        '$before$code\n$after',
      );

      controller.quillController.undo();
      await tester.pumpAndSettle();
      expect(controller.snapshot().document.toDelta().toJson(), original);
      expect(scroll.position.maxScrollExtent, 0);
      expect(scroll.offset, 0);
      controller.quillController.redo();
      await tester.pumpAndSettle();
      expect(controller.snapshot().document.toDelta().toJson(), edited);
      expect(scroll.offset, greaterThan(0));
      expect(render.size.width, 320);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$before$code\n新的一行\n$after',
          selection: TextSelection.collapsed(offset: end + 5),
        ),
      );
      await tester.pumpAndSettle();
      expect(horizontal, findsOneWidget, reason: '回车后仍在同一个原生代码块中');
      expect(
        controller.quillController.document.root.children
            .whereType<quill.Block>()
            .single
            .children
            .length,
        2,
      );
      expect(render.size.width, 320);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection across scrolled code and prose uses document offsets',
    (tester) async {
      final code = List.filled(180, 'A').join();
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(code)
            ..insert('\n', {'code-block': true})
            ..insert('代码后面的正文\n'),
        ),
        assets: const [],
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _EditorTestApp(
          child: Center(
            child: SizedBox(
              width: 320,
              height: 400,
              child: NoteQuillEditor(controller: controller, focusNode: focus),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pumpAndSettle();
      final horizontal = find.byKey(const ValueKey('quill-code-block-scroll'));
      final scroll = tester
          .widget<SingleChildScrollView>(horizontal)
          .controller!;
      scroll.jumpTo(150);
      await tester.pumpAndSettle();
      final raw = tester.state<quill.QuillRawEditorState>(
        find.byType(quill.QuillRawEditor),
      );
      final render = raw.renderEditor;
      final base = render
          .getPositionForOffset(tester.getRect(horizontal).center)
          .offset;
      final selection = TextSelection(
        baseOffset: base,
        extentOffset: code.length + 4,
      );
      controller.quillController.updateSelection(
        selection,
        quill.ChangeSource.local,
      );
      await tester.pumpAndSettle();
      final endpoints = render.getEndpointsForSelection(selection);
      final baseCaret = render.getLocalRectForCaret(selection.base);
      final extentCaret = render.getLocalRectForCaret(selection.extent);
      expect(endpoints.first.point.dx, closeTo(baseCaret.left, 2));
      expect(endpoints.last.point.dx, closeTo(extentCaret.left, 2));
      raw.showToolbar();
      await tester.pumpAndSettle();
      final link = raw.selectionOverlay!.startHandleLayerLink;
      final handleX = link.leader!.offset.dx;
      scroll.jumpTo(scroll.offset + 40);
      await tester.pumpAndSettle();
      expect(
        link.leader!.offset.dx,
        closeTo(handleX - 40, 1),
        reason: '只滑动代码时，跨段选区的手柄也必须跟随移动',
      );
      raw.hideToolbar();
      expect(
        controller.quillController.getPlainText(),
        '${code.substring(base)}\n代码后',
      );
      final original = controller.snapshot().document.toDelta().toJson();
      controller.quillController.replaceText(
        selection.start,
        selection.end - selection.start,
        '',
        TextSelection.collapsed(offset: selection.start),
      );
      await tester.pumpAndSettle();
      controller.quillController.undo();
      await tester.pumpAndSettle();
      expect(controller.snapshot().document.toDelta().toJson(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'code keeps its caret visible after narrow layout and text scaling',
    (tester) async {
      final code = List.filled(100, '变量\tA👋').join();
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(code)
            ..insert('\n\n', {'code-block': true})
            ..insert('代码后的普通段落\n'),
        ),
        assets: const [],
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      Widget editor(double width, double textScale) => _EditorTestApp(
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(bottom: 24),
          ),
          child: Center(
            child: SizedBox(
              width: width,
              height: 480,
              child: NoteQuillEditor(controller: controller, focusNode: focus),
            ),
          ),
        ),
      );
      await tester.pumpWidget(editor(360, 1));
      await tester.pumpAndSettle();
      focus.requestFocus();
      controller.quillController.updateSelection(
        TextSelection.collapsed(offset: code.length),
        quill.ChangeSource.local,
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(editor(260, 2));
      await tester.pumpAndSettle();
      final raw = tester.state<quill.QuillRawEditorState>(
        find.byType(quill.QuillRawEditor),
      );
      final render = raw.renderEditor;
      final start = render.getLocalRectForCaret(const TextPosition(offset: 0));
      final end = render.getLocalRectForCaret(
        TextPosition(offset: code.length),
      );
      final horizontal = find.byKey(const ValueKey('quill-code-block-scroll'));
      expect(render.size.width, 260);
      final scrollbar = tester.widget<RawScrollbar>(
        find
            .ancestor(of: horizontal, matching: find.byType(RawScrollbar))
            .first,
      );
      expect(
        scrollbar.padding,
        const EdgeInsets.fromLTRB(4, 0, 4, 4),
        reason: '块内滚动条不能继承系统安全区而压住代码末行',
      );
      expect(start.top, end.top, reason: '系统字体放大后代码依然不软换行');
      expect(
        tester.getRect(horizontal).contains(render.localToGlobal(end.center)),
        isTrue,
      );
      expect(
        render.getLocalRectForCaret(TextPosition(offset: code.length + 1)).top,
        greaterThan(end.top),
        reason: '代码块保留空行高度',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('wrapped prose has readable line and paragraph gaps at $scale', (
      tester,
    ) async {
      const prose =
          '本规范用于统一儿童笔记 App 在日历、笔记、回忆、编辑器、搜索、AI 助手、'
          '个人中心及系统反馈页面中的视觉与交互语言，供产品、设计、研发、测试和内容团队共同使用。';
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('$prose\n第二段正文'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final original = controller.snapshot().document.toDelta().toJson();
      await tester.pumpWidget(
        _EditorTestApp(
          theme: buildAppTheme(AppThemeStyle.paper, Brightness.light),
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 320,
                height: 400,
                child: NoteQuillEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render = tester
          .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
          .renderEditor;
      Rect caret(int offset) =>
          render.getLocalRectForCaret(TextPosition(offset: offset));
      final lineTops = <double>{
        for (var offset = 0; offset < prose.length; offset++) caret(offset).top,
      }.toList();
      expect(lineTops.length, greaterThan(2));
      for (var line = 1; line < lineTops.length; line++) {
        expect(lineTops[line] - lineTops[line - 1], closeTo(28 * scale, .1));
      }
      expect(
        caret(prose.length + 1).top - lineTops.last,
        closeTo(28 * scale + 12, .1),
        reason: '段后留白与段内行距分别控制',
      );
      expect(render.size.width, 320);
      expect(
        find.byKey(const ValueKey('quill-code-block-scroll')),
        findsNothing,
      );
      // Hit testing and the caret must still agree after wrapping and scaling.
      final position = render.getPositionForOffset(
        render.localToGlobal(caret(5).center),
      );
      expect(position.offset, 5);
      expect(controller.snapshot().document.toDelta().toJson(), original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor and preview use identical rendered paragraph spacing', (
    tester,
  ) async {
    const firstParagraph = '第一段中文与 English';
    final document = NoteDocument.fromPlainText('$firstParagraph\n第二段正文');
    final controller = NoteEditorController(
      document: document,
      assets: const [],
    );
    addTearDown(controller.dispose);
    final note = Note.newDraft().copyWith(document: document);
    await tester.pumpWidget(
      _EditorTestApp(
        theme: buildAppTheme(AppThemeStyle.paper, Brightness.light),
        child: Column(
          children: [
            Expanded(child: NoteQuillEditor(controller: controller)),
            SizedBox(height: 180, child: NoteRichDocumentPreview(note: note)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraphs = find.descendant(
      of: find.byType(quill.QuillRawEditor),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('第一段中文'),
      ),
    );
    expect(paragraphs, findsNWidgets(2));
    for (final paragraph in tester.widgetList<RichText>(paragraphs)) {
      expect(paragraph.text.style!.fontSize, 16);
      expect(paragraph.text.style!.letterSpacing, 0);
      expect(paragraph.text.style!.wordSpacing, 0);
    }
    for (final element in find.byType(quill.QuillRawEditor).evaluate()) {
      final render =
          (element as StatefulElement).state as quill.QuillRawEditorState;
      final first = render.renderEditor.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final second = render.renderEditor.getLocalRectForCaret(
        const TextPosition(offset: firstParagraph.length + 1),
      );
      expect(second.top - first.top, closeTo(40, .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('list items and quoted paragraphs have distinct spacing', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('甲')
          ..insert('\n', {'list': 'ordered'})
          ..insert('乙')
          ..insert('\n', {'list': 'ordered'})
          ..insert('正文\n')
          ..insert('引用一')
          ..insert('\n', {'blockquote': true})
          ..insert('引用二')
          ..insert('\n', {'blockquote': true}),
      ),
      assets: const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _EditorTestApp(child: NoteQuillEditor(controller: controller)),
    );
    await tester.pumpAndSettle();
    final render = tester
        .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
        .renderEditor;
    double top(int offset) =>
        render.getLocalRectForCaret(TextPosition(offset: offset)).top;
    expect(top(2) - top(0), closeTo(32, .1));
    expect(top(4) - top(2), closeTo(40, .1));
    expect(top(11) - top(7), closeTo(40, .1));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('mixed nested lists align in editor and preview at $scale', (
      tester,
    ) async {
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert('父项')
          ..insert('\n', {'list': 'unchecked'})
          ..insert('子项')
          ..insert('\n', {'list': 'checked', 'indent': 1})
          ..insert('圆点')
          ..insert('\n', {'list': 'bullet', 'indent': 1})
          ..insert('子项')
          ..insert('\n', {'list': 'unchecked', 'indent': 1})
          ..insert('详情详情详情详情详情详情')
          ..insert('\n', {'list': 'bullet', 'indent': 2})
          ..insert('步骤')
          ..insert('\n', {'list': 'ordered', 'indent': 2}),
      );
      final controller = NoteEditorController(
        document: document,
        assets: const [],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _EditorTestApp(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 640,
                child: Row(
                  children: [
                    Expanded(child: NoteQuillEditor(controller: controller)),
                    Expanded(
                      child: NoteRichDocumentPreview(
                        note: Note.newDraft().copyWith(document: document),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final element in find.byType(quill.QuillRawEditor).evaluate()) {
        final render =
            ((element as StatefulElement).state as quill.QuillRawEditorState)
                .renderEditor;
        Rect caret(int offset) =>
            render.getLocalRectForCaret(TextPosition(offset: offset));
        expect(render.size.width, 320);
        expect(caret(3).left - caret(0).left, closeTo(24, .1));
        expect(caret(6).left, caret(3).left);
        expect(caret(9).left, caret(3).left);
        expect(caret(12).left - caret(9).left, closeTo(24, .1));
        expect(
          caret(25).left,
          greaterThanOrEqualTo(caret(12).left),
          reason: 'ordered markers may reserve extra space for their digits',
        );
        for (var offset = 12; offset < 24; offset++) {
          expect(caret(offset).right, lessThanOrEqualTo(320));
        }
      }
      expect(
        controller.snapshot().document.toDelta().toJson(),
        document.toDelta().toJson(),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('placeholder and typed text keep the same first-line geometry', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _EditorTestApp(child: NoteQuillEditor(controller: controller)),
    );
    await tester.pumpAndSettle();
    final render = tester
        .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
        .renderEditor;
    final before = render.getLocalRectForCaret(const TextPosition(offset: 0));
    controller.quillController.replaceText(
      0,
      0,
      '开始记录',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    final after = render.getLocalRectForCaret(const TextPosition(offset: 0));
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  for (final list in ['bullet', 'ordered', 'unchecked']) {
    for (final attributes in [
      <String, dynamic>{'list': list},
      <String, dynamic>{'list': list, 'header': 2},
      <String, dynamic>{'list': list, 'line-height': 2.0},
    ]) {
      testWidgets('list marker follows the first line with $attributes', (
        tester,
      ) async {
        final controller = NoteEditorController(
          document: NoteDocument.fromDelta(
            Delta()
              ..insert('这是一条在窄屏中自动换行的列表，需要保持标记与第一行正文对齐')
              ..insert('\n', attributes),
          ),
          assets: const [],
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _EditorTestApp(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 400,
                  child: NoteQuillEditor(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final render = tester
            .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
            .renderEditor;
        final first = render.getLocalRectForCaret(
          const TextPosition(offset: 0),
        );
        final marker = list == 'unchecked'
            ? find.byKey(const Key('note-todo-checkbox'))
            : find.descendant(
                of: find.byType(
                  list == 'ordered'
                      ? quill.QuillNumberPoint
                      : quill.QuillBulletPoint,
                ),
                matching: find.byType(Text),
              );
        expect(
          tester.getCenter(marker).dy,
          closeTo(render.localToGlobal(first.center).dy, 1),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('wrapped TODO marker stays aligned with the first text line', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('这是一条会在较窄编辑器中换行的待办事项，用来验证复选框始终跟正文第一行对齐')
          ..insert('\n', {'list': 'unchecked'}),
      ),
      assets: const [],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 260,
              height: 240,
              child: NoteQuillEditor(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byKey(const Key('note-todo-checkbox'));
    expect(checkbox, findsOneWidget);
    final rawEditorState = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    final caret = rawEditorState.renderEditor.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    final caretCenter = rawEditorState.renderEditor.localToGlobal(caret.center);

    expect(
      tester.getRect(checkbox).center.dy,
      closeTo(caretCenter.dy, 1),
      reason: 'TODO 复选框应跟换行正文的第一行垂直居中，而不是跟整个段落居中',
    );

    await tester.tap(checkbox);
    await tester.pump();
    expect(
      controller.snapshot().document.toDelta().operations.last.attributes,
      containsPair('list', 'checked'),
    );
  });

  testWidgets(
    'reveals copy actions details and delete only after tapping an image',
    (tester) async {
      final asset = _imageAsset();
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert('图片之前\n')
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n')
          ..insert('图片之后\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
      );
      final focusNode = FocusNode();
      var copyCalls = 0;
      var editCalls = 0;
      var viewOriginalCalls = 0;
      var detailsCalls = 0;
      final testImage = await _createTestImage(320, 320);
      final imageProvider = _SynchronousTestImageProvider(testImage);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(testImage.dispose);

      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(
            controller: controller,
            focusNode: focusNode,
            resolveImage: (_) => imageProvider,
            onCopyImage: (_) async => copyCalls++,
            onEditImage: (_) async => editCalls++,
            onViewImageOriginal: (_) async => viewOriginalCalls++,
            onShowImageDetails: (_) async => detailsCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinder = find.byKey(ValueKey('note-image-${asset.id.value}'));
      final editorFinder = find.byType(NoteQuillEditor);
      expect(imageFinder, findsOneWidget);
      expect(
        find.byKey(ValueKey('note-image-frame-${asset.id.value}')),
        findsNothing,
      );
      final imageSize = tester.getSize(imageFinder);
      expect(
        imageSize.width,
        closeTo(tester.getSize(editorFinder).width - 48, 1),
      );
      expect(imageSize.height, closeTo(imageSize.width, 1));
      expect(
        imageSize.height,
        greaterThan(260),
        reason: '图片高度应由原始比例决定，不再受旧的 260dp 上限约束',
      );
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
        findsNothing,
      );

      await tester.drag(imageFinder, const Offset(0, -80), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(ValueKey('note-asset-${asset.id.value}')),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      final visibleImageRect = tester.getRect(imageFinder);
      final visibleEditorRect = tester.getRect(editorFinder);
      await tester.tapAt(visibleImageRect.intersect(visibleEditorRect).center);
      await tester.pump(const Duration(milliseconds: 350));
      expect(focusNode.hasFocus, isFalse);
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsOneWidget,
      );
      final imageSelection = tester.widget<DecoratedBox>(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      );
      expect(
        (imageSelection.decoration as BoxDecoration).border,
        Border.all(color: AppColors.accent, width: 2),
      );

      final imageSelectionTarget = find.byKey(
        ValueKey('note-image-selection-target-${asset.id.value}'),
      );
      final imageTapArea = tester
          .getRect(imageSelectionTarget)
          .intersect(
            Rect.fromLTRB(
              visibleEditorRect.left,
              visibleEditorRect.top,
              visibleEditorRect.right,
              visibleEditorRect.bottom - 112,
            ),
          );
      await tester.tapAt(imageTapArea.center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );

      final restoredImageTapArea = tester
          .getRect(imageSelectionTarget)
          .intersect(visibleEditorRect);
      await tester.tapAt(restoredImageTapArea.center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(ValueKey('view-original-note-image-${asset.id.value}')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('copy-note-image-${asset.id.value}')),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(ValueKey('edit-note-image-${asset.id.value}')),
          matching: find.text('操作'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
          matching: find.text('编辑'),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('edit-note-image-${asset.id.value}')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('details-note-image-${asset.id.value}')),
      );
      await tester.pump();
      expect(viewOriginalCalls, 1);
      expect(copyCalls, 1);
      expect(editCalls, 1);
      expect(detailsCalls, 1);

      await tester.tap(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(controller.snapshot().assets, isEmpty);
      expect(controller.snapshot().document.project().plainText, '图片之前\n图片之后');
    },
  );

  testWidgets('unselected audio menu opens on the first pointer sequence', (
    tester,
  ) async {
    final asset = _audioAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
    );
    final focusNode = FocusNode();
    final recognized = <NoteAsset>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _EditorTestApp(
        child: NoteQuillEditor(
          controller: controller,
          focusNode: focusNode,
          onTranscribeAudio: recognized.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();
    final menu = find.byKey(ValueKey('note-audio-actions-${asset.id.value}'));
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsNothing,
    );
    final gesture = await tester.startGesture(tester.getCenter(menu));
    // A real touch spans frames: pointer-down must not replace the button
    // before its recognizer receives pointer-up.
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('修改标题'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
    expect(focusNode.hasFocus, isFalse);
    await tester.tap(find.text('语音识别'));
    await tester.pumpAndSettle();
    expect(recognized.single.id, asset.id);
  });

  testWidgets('renders and controls an inline recording card', (tester) async {
    final asset = _audioAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
    );
    final playback = _FakeAudioPlaybackDriver();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: NoteQuillEditor(
          controller: controller,
          focusNode: focusNode,
          audioPlayback: playback,
          resolveAssetPath: (_) => '/managed/recording.m4a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('note-asset-${asset.id.value}')),
      findsOneWidget,
    );
    expect(find.text('产品讨论'), findsOneWidget);
    expect(find.text('01:32'), findsOneWidget);
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsNothing,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(ValueKey('play-note-audio-${asset.id.value}')));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(playback.activeAssetId, asset.id.value);
    expect(playback.lastPath, '/managed/recording.m4a');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    final audioSelection = tester.widget<DecoratedBox>(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
    );
    expect(
      (audioSelection.decoration as BoxDecoration).border,
      Border.all(color: AppColors.accent, width: 2),
    );

    final audioSelectionTarget = find.byKey(
      ValueKey('note-audio-selection-target-${asset.id.value}'),
    );
    var audioTargetRect = tester.getRect(audioSelectionTarget);
    await tester.tapAt(
      Offset(audioTargetRect.center.dx, audioTargetRect.top + 4),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsNothing,
    );

    audioTargetRect = tester.getRect(audioSelectionTarget);
    await tester.tapAt(
      Offset(audioTargetRect.center.dx, audioTargetRect.top + 4),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('note-audio-actions-${asset.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key('attachment-title-count')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('cancel-attachment-title'))).width,
      tester.getSize(find.byKey(const Key('save-attachment-title'))).width,
    );
    controller.updateAsset(
      controller.asset(asset.id)!.copyWith(transcript: '同时完成的转写'),
    );
    await tester.enterText(
      find.byKey(const Key('audio-attachment-title')),
      '周会录音',
    );
    await tester.tap(find.byKey(const Key('save-attachment-title')));
    await tester.pumpAndSettle();

    expect(controller.assets.single.displayTitle, '周会录音');
    expect(controller.assets.single.transcript, '同时完成的转写');

    await tester.tap(
      find.byKey(ValueKey('note-audio-actions-${asset.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-attachment-title')));
    await tester.pumpAndSettle();

    expect(controller.assets.single.displayTitle, 'recording.m4a');
  });

  testWidgets('renders and opens a dedicated video card', (tester) async {
    final video = _videoAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(video.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [video],
    );
    NoteAsset? opened;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: NoteQuillEditor(
          controller: controller,
          onOpenAsset: (asset) => opened = asset,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('现场记录.mp4'), findsOneWidget);
    expect(find.text('02:05 · 4.0 KB'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('play-note-video-${video.id.value}')));
    await tester.pump();
    expect(opened, same(video));
  });

  Map<String, (NoteEmbed, List<NoteAsset>)> cardFixtures() {
    final image = _imageAsset();
    final audio = _audioAsset();
    final video = _videoAsset();
    final now = DateTime.utc(2026, 11, 5);
    final file = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.file,
      storageKey: 'notes/files/document.pdf',
      originalName: '资料.pdf',
      byteLength: 10,
      mimeType: 'application/pdf',
      createdAt: now,
      updatedAt: now,
    );
    return {
      'image': (NoteEmbed.attachment(image.id), [image]),
      'audio': (NoteEmbed.attachment(audio.id), [audio]),
      'video': (NoteEmbed.attachment(video.id), [video]),
      'file': (NoteEmbed.attachment(file.id), [file]),
      'references': (
        NoteEmbed.fileReferences([
          NoteFileReference(
            fileId: NoteAttachmentId.generate().value,
            name: '资料.zip',
            size: 10,
          ),
        ]),
        [],
      ),
      'table': (
        NoteEmbed.table(
          NoteTable(
            rows: const [
              ['项目', '状态'],
              ['计划', '完成'],
            ],
          ),
        ),
        [],
      ),
      'divider': (const NoteEmbed.divider(), []),
    };
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final name in [
      'image',
      'audio',
      'video',
      'file',
      'references',
      'table',
      'divider',
    ]) {
      testWidgets(
        '${platform.name} $name card never paints a caret and editing selection uses the next paragraph',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final fixture = cardFixtures()[name]!;
          final original = NoteDocument.fromDelta(
            Delta()
              ..insert(fixture.$1.toDeltaData())
              ..insert('\n正文\n'),
          );
          final controller = NoteEditorController(
            document: original,
            assets: fixture.$2,
          );
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            _EditorTestApp(
              child: NoteQuillEditor(
                controller: controller,
                focusNode: focus,
                resolveImage: (_) => MemoryImage(_onePixelPng),
              ),
            ),
          );
          await tester.pumpAndSettle();
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(controller.quillController.selection.extentOffset, 2);
          final raw = tester.state<quill.QuillRawEditorState>(
            find.byType(quill.QuillRawEditor),
          );
          final cardLine =
              raw.renderEditor.childAtPosition(const TextPosition(offset: 0))
                  as RenderEditableTextLine;
          for (final offset in [0, 1]) {
            controller.quillController.updateSelection(
              TextSelection.collapsed(offset: offset),
              quill.ChangeSource.local,
            );
            await tester.pump();
            expect(controller.quillController.selection.extentOffset, 2);
            final caret = raw.renderEditor.localToGlobal(
              raw.renderEditor
                  .getLocalRectForCaret(
                    controller.quillController.selection.extent,
                  )
                  .topLeft,
            );
            expect(
              caret.dy,
              greaterThanOrEqualTo(
                cardLine.localToGlobal(Offset(0, cardLine.size.height)).dy,
              ),
            );
            expect(cardLine.containsCursor(), false);
          }
          cardLine.cursorCont.setFloatingCursorTextPosition(
            const TextPosition(offset: 0),
          );
          expect(cardLine.containsCursor(), false);
          cardLine.cursorCont.setFloatingCursorTextPosition(null);
          final range = TextSelection(
            baseOffset: 0,
            extentOffset: controller.quillController.document.length - 1,
          );
          controller.quillController.updateSelection(
            range,
            quill.ChangeSource.local,
          );
          await tester.pump();
          expect(controller.quillController.selection, range);
          focus.unfocus();
          controller.quillController.updateSelection(
            const TextSelection.collapsed(offset: 0),
            quill.ChangeSource.local,
          );
          await tester.pump();
          expect(
            cardLine.containsCursor(),
            false,
            reason:
                'Even an uncorrected stored caret must never be painted on a block',
          );
          expect(controller.snapshot().document, original);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      '${platform.name} consecutive cards create a real editing line and retain undo redo',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final fixtures = cardFixtures();
        final first = fixtures['references']!.$1;
        final last = fixtures['video']!;
        final original = NoteDocument.fromDelta(
          Delta()
            ..insert(first.toDeltaData())
            ..insert('\n')
            ..insert(last.$1.toDeltaData())
            ..insert('\n'),
        );
        final controller = NoteEditorController(
          document: original,
          assets: last.$2,
        );
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _EditorTestApp(
            child: NoteQuillEditor(controller: controller, focusNode: focus),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.snapshot().document, original);
        focus.requestFocus();
        await tester.pumpAndSettle();
        final edited = controller.snapshot().document;
        expect(controller.quillController.selection.extentOffset, 2);
        expect(
          controller.isBlockEmbedAtOffset(
            controller.quillController.selection.extentOffset,
          ),
          false,
        );
        controller.quillController.undo();
        await tester.pumpAndSettle();
        expect(controller.snapshot().document, original);
        expect(controller.quillController.hasRedo, true);
        controller.quillController.redo();
        await tester.pumpAndSettle();
        expect(controller.snapshot().document, edited);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name} keyboard navigation skips block lines in both directions',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final embed = cardFixtures()['references']!.$1;
        final original = NoteDocument.fromDelta(
          Delta()
            ..insert('前\n')
            ..insert(embed.toDeltaData())
            ..insert('\n后\n'),
        );
        final controller = NoteEditorController(
          document: original,
          assets: const [],
        );
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _EditorTestApp(
            child: NoteQuillEditor(controller: controller, focusNode: focus),
          ),
        );
        await tester.pumpAndSettle();
        focus.requestFocus();
        await tester.pumpAndSettle();
        controller.quillController.updateSelection(
          const TextSelection.collapsed(offset: 1),
          quill.ChangeSource.local,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(controller.quillController.selection.extentOffset, 4);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(controller.quillController.selection.extentOffset, 1);
        expect(controller.snapshot().document, original);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('caret stays below the final card with the production font', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = await rootBundle.load(
      'assets/fonts/source_han_serif/SourceHanSerifCN-VF.otf',
    );
    await (FontLoader('Roboto')..addFont(Future.value(font))).load();
    await (FontLoader(
      'Source Han Serif CN',
    )..addFont(Future.value(font))).load();
    final fixtures = cardFixtures().values.toList();
    final delta = Delta();
    for (final fixture in fixtures) {
      delta
        ..insert(fixture.$1.toDeltaData())
        ..insert('\n');
    }
    delta.insert('在卡片下一行继续记录\n');
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(delta),
      assets: fixtures.expand((fixture) => fixture.$2),
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _EditorTestApp(
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
        child: NoteQuillEditor(
          controller: controller,
          focusNode: focus,
          resolveImage: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(_onePixelPng),
        tester.element(find.byType(NoteQuillEditor)),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(controller.quillController.selection.extentOffset, 14);
    final raw = tester.state<quill.QuillRawEditorState>(
      find.byType(quill.QuillRawEditor),
    );
    final lastBlock = raw.renderEditor.childAtPosition(
      const TextPosition(offset: 12),
    );
    final caret = raw.renderEditor.localToGlobal(
      raw.renderEditor
          .getLocalRectForCaret(controller.quillController.selection.extent)
          .topLeft,
    );
    expect(
      caret.dy,
      greaterThanOrEqualTo(
        lastBlock.localToGlobal(Offset(0, lastBlock.size.height)).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'typing at any block placeholder inserts below the card and preserves undo redo',
    () {
      for (final fixture in cardFixtures().values) {
        final original = NoteDocument.fromDelta(
          Delta()
            ..insert(fixture.$1.toDeltaData())
            ..insert('\n'),
        );
        final controller = NoteEditorController(
          document: original,
          assets: fixture.$2,
        );
        controller.quillController.replaceText(
          0,
          0,
          '正文',
          const TextSelection.collapsed(offset: 2),
        );
        final edited = controller.snapshot().document;
        expect(
          edited.toDelta().toJson(),
          (Delta()
                ..insert(fixture.$1.toDeltaData())
                ..insert('\n正文\n'))
              .toJson(),
        );
        controller.quillController.undo();
        expect(controller.snapshot().document, original);
        controller.quillController.redo();
        expect(controller.snapshot().document, edited);
        controller.dispose();
      }
    },
  );

  testWidgets(
    'a blank paragraph after reference cards remains editable and read only taps add nothing',
    (tester) async {
      final ref = NoteEmbed.fileReferences([
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '资料.pdf',
          size: 1,
        ),
      ]);
      final original = NoteDocument.fromDelta(
        Delta()
          ..insert(ref.toDeltaData())
          ..insert('\n\n'),
      );
      final controller = NoteEditorController(
        document: original,
        assets: const [],
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      expect(controller.isBlockEmbedAtOffset(2), false);
      expect(controller.appendParagraphAfterLastEmbed(), false);
      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(controller: controller, focusNode: focus),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester
                .getRect(
                  find.byKey(const ValueKey('move-note-file-references-0')),
                )
                .bottomCenter +
            const Offset(0, 32),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, true);
      expect(tester.testTextInput.isVisible, true);
      expect(controller.snapshot().document, original);
      final onlyCard = NoteDocument.fromDelta(
        Delta()
          ..insert(ref.toDeltaData())
          ..insert('\n'),
      );
      final readOnlyController = NoteEditorController(
        document: onlyCard,
        assets: const [],
      );
      addTearDown(readOnlyController.dispose);
      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(
            controller: readOnlyController,
            readOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const Key('note-file-reference-open')),
      );
      await tester.tapAt(rect.bottomCenter + const Offset(0, 32));
      await tester.pumpAndSettle();
      expect(readOnlyController.snapshot().document, onlyCard);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'reference groups move atomically, keep file order and reject stale drags',
    () {
      NoteFileReference ref(String name) => NoteFileReference(
        fileId: NoteAttachmentId.generate().value,
        name: name,
        size: 1,
      );
      final first = NoteEmbed.fileReferences([
        ref('first.pdf'),
        ref('second.zip'),
      ]);
      final second = NoteEmbed.fileReferences([ref('last.txt')]);
      final original = NoteDocument.fromDelta(
        Delta()
          ..insert(first.toDeltaData())
          ..insert('\n正文\n')
          ..insert(second.toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: original,
        assets: const [],
      );
      addTearDown(controller.dispose);
      expect(
        controller.moveBlockEmbed(
          expectedEmbed: first,
          sourceOffset: 0,
          targetOffset: 1,
        ),
        false,
      );
      expect(
        controller.moveBlockEmbed(
          expectedEmbed: second,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        false,
      );
      expect(controller.snapshot().document, original);
      expect(
        controller.moveBlockEmbed(
          expectedEmbed: first,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        true,
      );
      final moved = controller.snapshot().document;
      expect(
        moved.toDelta().toJson(),
        (Delta()
              ..insert('正文\n')
              ..insert(second.toDeltaData())
              ..insert('\n')
              ..insert(first.toDeltaData())
              ..insert('\n'))
            .toJson(),
      );
      expect(controller.snapshot().assets, isEmpty);
      expect(NoteDocument.fromJsonString(moved.toJsonString()), moved);
      controller.quillController.undo();
      expect(controller.snapshot().document, original);
      controller.quillController.redo();
      expect(controller.snapshot().document, moved);
    },
  );

  test(
    'moving a final reference preserves the previous heading and each undo step',
    () {
      final reference = NoteEmbed.fileReferences([
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '资料.pdf',
          size: 1,
        ),
      ]);
      final original = NoteDocument.fromDelta(
        Delta()
          ..insert('标题')
          ..insert('\n', {'header': 2})
          ..insert(reference.toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: original,
        assets: const [],
      );
      addTearDown(controller.dispose);
      expect(
        controller.moveBlockEmbed(
          expectedEmbed: reference,
          sourceOffset: 3,
          targetOffset: 0,
        ),
        true,
      );
      final moved = controller.snapshot().document;
      expect(
        moved.toDelta().toJson(),
        (Delta()
              ..insert(reference.toDeltaData())
              ..insert('\n标题')
              ..insert('\n', {'header': 2}))
            .toJson(),
      );
      controller.quillController.undo();
      expect(controller.snapshot().document, original);
      controller.quillController.redo();
      expect(controller.snapshot().document, moved);
      expect(
        controller.moveBlockEmbed(
          expectedEmbed: reference,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        true,
      );
      expect(controller.snapshot().document, original);
      controller.quillController.undo();
      expect(controller.snapshot().document, moved);
    },
  );

  testWidgets(
    'reference cards drag above and below other cards, cancel outside and stay read only',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      NoteEmbed group(String name) => NoteEmbed.fileReferences([
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: name,
          size: 1,
        ),
      ]);
      final first = group('first.pdf');
      final second = group('second.zip');
      final original = NoteDocument.fromDelta(
        Delta()
          ..insert(first.toDeltaData())
          ..insert('\n中间正文\n')
          ..insert(second.toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: original,
        assets: const [],
      );
      addTearDown(controller.dispose);
      List<String> names() => controller
          .snapshot()
          .document
          .toDelta()
          .operations
          .where((op) => op.data is Map)
          .map((op) => NoteEmbed.parse(op.data).fileReferences.first.name)
          .toList();
      await tester.pumpWidget(
        _EditorTestApp(child: NoteQuillEditor(controller: controller)),
      );
      await tester.pumpAndSettle();
      final firstHandle = find.byKey(
        const ValueKey('move-note-file-references-0'),
      );
      final secondCard = find.text('second.zip');
      final gesture = await tester.startGesture(tester.getCenter(firstHandle));
      await tester.pump(const Duration(milliseconds: 420));
      await gesture.moveTo(
        tester.getRect(secondCard).bottomCenter + const Offset(0, 12),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.byKey(const Key('note-asset-drop-indicator')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(names(), ['second.zip', 'first.pdf']);
      expect(find.byKey(const Key('note-file-reference-list')), findsNothing);
      final moved = controller.snapshot().document;
      final movingFirst = await tester.startGesture(
        tester.getCenter(find.text('first.pdf')),
      );
      await tester.pump(const Duration(milliseconds: 420));
      await movingFirst.moveTo(const Offset(-40, -40));
      await tester.pump(const Duration(milliseconds: 120));
      await movingFirst.up();
      await tester.pumpAndSettle();
      expect(controller.snapshot().document, moved);
      final movingUp = await tester.startGesture(
        tester.getCenter(find.text('first.pdf')),
      );
      await tester.pump(const Duration(milliseconds: 420));
      await movingUp.moveTo(
        tester.getRect(find.text('second.zip')).topCenter - const Offset(0, 16),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await movingUp.up();
      await tester.pumpAndSettle();
      expect(names(), ['first.pdf', 'second.zip']);
      controller.quillController.undo();
      await tester.pumpAndSettle();
      expect(controller.snapshot().document, moved);
      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(controller: controller, readOnly: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('move-note-file-references-0')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long press drag reorders image and recording blocks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final image = _imageAsset();
    final audio = _audioAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(image.id).toDeltaData())
          ..insert('\n中间正文\n')
          ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [image, audio],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: NoteQuillEditor(
          controller: controller,
          resolveImage: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageHandle = find.byKey(
      ValueKey('move-note-asset-${image.id.value}'),
    );
    final audioCard = find.byKey(ValueKey('note-asset-${audio.id.value}'));
    final gesture = await tester.startGesture(tester.getCenter(imageHandle));
    await tester.pump(const Duration(milliseconds: 420));
    await gesture.moveTo(
      tester.getRect(audioCard).bottomCenter - const Offset(0, 2),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('note-asset-drop-indicator')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      audio.id,
      image.id,
    ]);
    controller.quillController.undo();
    await tester.pumpAndSettle();
    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      image.id,
      audio.id,
    ]);

    final audioHandle = find.byKey(
      ValueKey('move-note-asset-${audio.id.value}'),
    );
    final imageCard = find.byKey(ValueKey('note-asset-${image.id.value}'));
    final audioGesture = await tester.startGesture(
      tester.getCenter(audioHandle),
    );
    await tester.pump(const Duration(milliseconds: 420));
    await audioGesture.moveTo(
      tester.getRect(imageCard).topCenter + const Offset(0, 2),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await audioGesture.up();
    await tester.pumpAndSettle();

    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      audio.id,
      image.id,
    ]);
  });

  testWidgets('accepts multiline text through the native input connection', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(child: NoteQuillEditor(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.byType(quill.QuillRawEditor));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '第一行\n第二行\n',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();

    expect(controller.snapshot().document.project().plainText, '第一行\n第二行');
  });

  testWidgets(
    'converts Android IME Markdown paste before raw text reaches the document',
    (tester) async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(child: NoteQuillEditor(controller: controller)),
      );
      await tester.pump();
      await tester.tap(find.byType(quill.QuillRawEditor));
      await tester.pump();
      const pasted = '# 系统粘贴\n\n☐ 待处理\n☑ 已完成\n';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: pasted,
          selection: TextSelection.collapsed(offset: pasted.length - 1),
        ),
      );
      await tester.pump();

      expect(
        controller.snapshot().document.project().plainText,
        '系统粘贴\n待处理\n已完成',
      );
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '系统粘贴'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '待处理'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
        {'insert': '已完成'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
      ]);

      controller.quillController.undo();
      expect(controller.snapshot().document.project().isVisuallyEmpty, isTrue);
    },
  );

  testWidgets(
    'renders pasted Markdown table and reveals block actions only after tap',
    (tester) async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(
          child: Center(
            child: SizedBox(
              width: 342,
              height: 700,
              child: NoteQuillEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(quill.QuillRawEditor));
      await tester.pump();
      const pasted = '''
| 项目 | 状态 |
| :--- | ---: |
| Quill | 完成 |

---
''';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: pasted,
          selection: TextSelection.collapsed(offset: pasted.length - 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('项目'), findsOneWidget);
      expect(find.text('状态'), findsOneWidget);
      expect(find.text('Quill'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-note-table')), findsNothing);
      expect(find.byKey(const ValueKey('remove-note-divider')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('note-table-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-note-table')), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-note-table')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-divider-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-note-divider')), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-note-table')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'edits table cells and adds rows and columns from its action bar',
    (tester) async {
      final table = NoteTable(
        rows: const [
          ['项目', '状态'],
          ['Quill', '完成'],
        ],
        alignments: const [NoteTableAlignment.start, NoteTableAlignment.end],
      );
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.table(table).toDeltaData())
            ..insert('\n'),
        ),
        assets: const [],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(child: NoteQuillEditor(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-table-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-note-table')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-table-editor')), findsOneWidget);
      final existingCell = find.descendant(
        of: find.byKey(const ValueKey('note-table-cell-1-0')),
        matching: find.byType(TextField),
      );
      await tester.enterText(existingCell, 'Flutter Quill');
      await tester.tap(find.byKey(const Key('note-table-add-row')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('note-table-add-column')));
      await tester.pump();
      final addedCell = find.descendant(
        of: find.byKey(const ValueKey('note-table-cell-2-2')),
        matching: find.byType(TextField),
      );
      await tester.enterText(addedCell, '新增内容');
      await tester.ensureVisible(find.byKey(const Key('note-table-save')));
      await tester.tap(find.byKey(const Key('note-table-save')));
      await tester.pumpAndSettle();

      final saved = controller.tableAtOffset(0)!;
      expect(saved.columnCount, 3);
      expect(saved.rows.length, 3);
      expect(saved.rows[1][0], 'Flutter Quill');
      expect(saved.rows[2][2], '新增内容');
      expect(find.text('Flutter Quill'), findsOneWidget);
    },
  );

  testWidgets('provides a single-row rich text toolbar', (tester) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    var doneCalls = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: NoteQuillToolbar(
            controller: controller,
            onOpenAssistant: () {},
            onInsertImage: () {},
            onInsertVideo: () {},
            onRecordAudio: () {},
            onDone: () => doneCalls++,
            doneLabel: '完成',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = tester.widget<Row>(
      find.byKey(const Key('quill-toolbar-actions')),
    );
    expect(actions.children.map((child) => child.key).toList(), const [
      Key('quill-open-inline-assistant'),
      Key('quill-insert-image'),
      Key('quill-insert-video'),
      Key('quill-record-audio'),
      Key('quill-toolbar-undo'),
      Key('quill-toolbar-redo'),
      Key('quill-toolbar-bold'),
      Key('quill-toolbar-checklist'),
      Key('quill-toolbar-bullets'),
      Key('quill-toolbar-numbered-list'),
      Key('quill-toolbar-indent-increase'),
      Key('quill-toolbar-indent-decrease'),
      Key('quill-toolbar-quote'),
      Key('quill-toolbar-italic'),
      Key('quill-toolbar-underline'),
      Key('quill-toolbar-heading'),
      Key('quill-toolbar-link'),
      Key('quill-toolbar-divider'),
      Key('quill-toolbar-clear-format'),
    ]);
    expect(find.byType(quill.QuillSimpleToolbar), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(AppIcon), findsWidgets);
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.byIcon(Icons.code), findsNothing);
    expect(find.byIcon(Icons.format_strikethrough), findsNothing);
    expect(find.byIcon(Icons.format_indent_increase), findsOneWidget);
    expect(find.byIcon(Icons.format_indent_decrease), findsOneWidget);

    final assistantButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-open-inline-assistant')),
        matching: find.byType(IconButton),
      ),
    );
    final imageButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-insert-image')),
        matching: find.byType(IconButton),
      ),
    );
    final recordingButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-record-audio')),
        matching: find.byType(IconButton),
      ),
    );
    expect(assistantButton.style, isNull);
    expect(imageButton.style, isNull);
    expect(recordingButton.style, isNull);
    final doneButton = find.byKey(const Key('quill-toolbar-done'));
    final scrollView = find.byKey(const Key('quill-toolbar-scroll-view'));
    expect(doneButton, findsOneWidget);
    expect(find.descendant(of: scrollView, matching: doneButton), findsNothing);
    expect(
      find.descendant(of: doneButton, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(tester.getSize(doneButton).width, lessThan(60));
    final doneButtonRect = tester.getRect(doneButton);
    await tester.drag(scrollView, const Offset(-300, 0));
    await tester.pump();
    expect(tester.getRect(doneButton), doneButtonRect);
    await tester.tap(doneButton);
    expect(doneCalls, 1);
    expect(tester.getSize(find.byType(NoteQuillToolbar)).height, lessThan(90));
  });

  testWidgets('link toolbar uses a keyboard-safe bottom sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = NoteEditorController(
      document: NoteDocument.fromPlainText('了解更多'),
      assets: const [],
    );
    addTearDown(controller.dispose);
    final quillController = controller.quillController;
    quillController.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      quill.ChangeSource.local,
    );

    await tester.pumpWidget(
      _EditorTestApp(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: NoteQuillToolbar(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final linkButton = find.byKey(const Key('quill-toolbar-link'));
    await tester.ensureVisible(linkButton);
    await tester.tap(linkButton);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('note-link-text-field')), findsOneWidget);
    expect(find.byKey(const Key('note-link-address-field')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(
      find.byKey(const Key('note-link-address-field')),
      'https://example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-note-link')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      quillController.document
          .toDelta()
          .operations
          .where((operation) => operation.data == '了解更多')
          .single
          .attributes?['link'],
      'https://example.com',
    );

    quillController.updateSelection(
      const TextSelection.collapsed(offset: 1),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.tap(linkButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-note-link')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-note-link')));
    await tester.pumpAndSettle();
    expect(
      quillController.document.toDelta().operations.any(
        (operation) => operation.attributes?.containsKey('link') ?? false,
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar nests mixed lists and outdents a selection with undo', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('父项')
          ..insert('\n', {'list': 'unchecked'})
          ..insert('子项')
          ..insert('\n', {'list': 'unchecked'})
          ..insert('测试')
          ..insert('\n', {'list': 'unchecked'})
          ..insert('详情')
          ..insert('\n', {'list': 'bullet'})
          ..insert('111')
          ..insert('\n', {'list': 'bullet'})
          ..insert('后续')
          ..insert('\n', {'list': 'ordered'}),
      ),
      assets: const [],
    );
    addTearDown(controller.dispose);
    final quillController = controller.quillController;
    final original = controller.snapshot().document;
    await tester.pumpWidget(
      _EditorTestApp(
        child: Column(
          children: [
            Expanded(child: NoteQuillEditor(controller: controller)),
            NoteQuillToolbar(controller: controller),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapAction(String action) async {
      final button = find.descendant(
        of: find.byKey(Key('quill-toolbar-$action')),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    List<int> levels() => quillController.document
        .toDelta()
        .operations
        .where((op) => op.data == '\n')
        .map((op) => op.attributes?['indent'] as int? ?? 0)
        .toList();

    const children = TextSelection(baseOffset: 3, extentOffset: 15);
    quillController.updateSelection(children, quill.ChangeSource.local);
    await tapAction('indent-increase');
    expect(levels(), [0, 1, 1, 1, 1, 0]);
    expect(quillController.selection, children);
    await tapAction('undo');
    expect(
      controller.snapshot().document.toDelta().toJson(),
      original.toDelta().toJson(),
    );
    await tapAction('redo');
    expect(levels(), [0, 1, 1, 1, 1, 0]);

    quillController.updateSelection(
      const TextSelection(baseOffset: 9, extentOffset: 15),
      quill.ChangeSource.local,
    );
    await tapAction('indent-increase');
    expect(levels(), [0, 1, 1, 2, 2, 0]);
    final nested = controller.snapshot().document;
    // Separate user actions from Quill's 400ms typing-history merge window.
    quillController.document.history.lastRecorded = 0;
    // A reverse selection starting/ending inside text must affect only its lines.
    quillController.updateSelection(
      const TextSelection(baseOffset: 14, extentOffset: 4),
      quill.ChangeSource.local,
    );
    await tapAction('indent-decrease');
    expect(levels(), [0, 0, 0, 1, 1, 0]);
    await tapAction('undo');
    expect(
      controller.snapshot().document.toDelta().toJson(),
      nested.toDelta().toJson(),
    );
    await tapAction('redo');
    expect(levels(), [0, 0, 0, 1, 1, 0]);
    expect(
      controller.snapshot().document.project().plainText,
      original.project().plainText,
    );
    expect(
      quillController.document
          .toDelta()
          .operations
          .where((op) => op.data == '\n')
          .map((op) => op.attributes?['list']),
      ['unchecked', 'unchecked', 'unchecked', 'bullet', 'bullet', 'ordered'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'outline toolbar preserves formatting, history and heading actions',
    (tester) async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('示例文字'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final quillController = controller.quillController;
      quillController.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        quill.ChangeSource.local,
      );
      await tester.pumpWidget(
        _EditorTestApp(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: NoteQuillToolbar(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder button(String name) => find.descendant(
        of: find.byKey(Key('quill-toolbar-$name')),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button('undo')).onPressed, isNull);
      expect(tester.widget<IconButton>(button('redo')).onPressed, isNull);
      await tester.tap(button('bold'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(button('bold')).isSelected, isTrue);
      expect(
        quillController.getSelectionStyle().attributes['bold']?.value,
        isTrue,
      );

      await tester.tap(button('undo'));
      await tester.pumpAndSettle();
      expect(quillController.getSelectionStyle().attributes['bold'], isNull);
      await tester.tap(button('redo'));
      await tester.pumpAndSettle();
      expect(
        quillController.getSelectionStyle().attributes['bold']?.value,
        isTrue,
      );

      await tester.tap(button('checklist'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(button('checklist')).isSelected, isTrue);
      expect(
        quillController.getSelectionStyle().attributes['list']?.value,
        'unchecked',
      );

      final heading = find.descendant(
        of: find.byKey(const Key('quill-toolbar-heading')),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(heading);
      await tester.tap(heading);
      await tester.pumpAndSettle();
      final labels = quill.FlutterQuillLocalizations.of(
        tester.element(find.byType(NoteQuillToolbar)),
      )!;
      await tester.tap(find.widgetWithText(MenuItemButton, labels.heading1));
      await tester.pumpAndSettle();
      expect(
        quillController.getSelectionStyle().attributes['header']?.value,
        1,
      );

      await tester.ensureVisible(button('clear-format'));
      await tester.tap(button('clear-format'));
      await tester.pumpAndSettle();
      expect(quillController.getSelectionStyle().attributes['bold'], isNull);
      expect(quillController.getSelectionStyle().attributes['header'], isNull);
      expect(find.byType(Icon), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ui.Image> _createTestImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF587086),
  );
  return recorder.endRecording().toImage(width, height);
}

final class _SynchronousTestImageProvider extends ImageProvider<int> {
  const _SynchronousTestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<int> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<int>(identityHashCode(this));

  @override
  ImageStreamCompleter loadImage(int key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
      );
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

NoteAsset _imageAsset([String id = '3d2be3d5-00c8-4f5c-8e69-e90085dc2873']) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse(id),
    kind: NoteAssetKind.image,
    storageKey: 'notes/images/$id.png',
    originalName: '原图.png',
    byteLength: _onePixelPng.length,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _audioAsset() {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse('94ee8ed8-4637-40e1-8c91-ff6df6593605'),
    kind: NoteAssetKind.audio,
    storageKey: 'notes/audio/94ee8ed8.m4a',
    originalName: 'recording.m4a',
    displayName: '产品讨论',
    byteLength: 4096,
    mimeType: 'audio/mp4',
    durationMs: 92340,
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _videoAsset() {
  final now = DateTime.utc(2026, 7, 29, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse('88cd8ed8-4637-40e1-8c91-ff6df6593605'),
    kind: NoteAssetKind.video,
    storageKey: 'notes/video/88cd8ed8.mp4',
    originalName: '现场记录.mp4',
    byteLength: 4096,
    mimeType: 'video/mp4',
    durationMs: 125000,
    createdAt: now,
    updatedAt: now,
  );
}

final class _FakeAudioPlaybackDriver extends ChangeNotifier
    implements NoteAudioPlaybackDriver {
  String? lastPath;

  @override
  String? activeAssetId;

  @override
  Duration duration = Duration.zero;

  @override
  String? errorMessage;

  @override
  Duration position = Duration.zero;

  @override
  NoteAudioPlaybackStatus status = NoteAudioPlaybackStatus.idle;

  @override
  Future<void> seek({
    required String assetId,
    required Duration position,
  }) async {
    if (activeAssetId != assetId) return;
    this.position = position;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    activeAssetId = null;
    status = NoteAudioPlaybackStatus.idle;
    notifyListeners();
  }

  @override
  Future<void> toggle({
    required String assetId,
    required String filePath,
  }) async {
    activeAssetId = assetId;
    lastPath = filePath;
    duration = const Duration(milliseconds: 92340);
    status = status == NoteAudioPlaybackStatus.playing
        ? NoteAudioPlaybackStatus.paused
        : NoteAudioPlaybackStatus.playing;
    notifyListeners();
  }
}

final class _EditorTestApp extends StatelessWidget {
  const _EditorTestApp({required this.child, this.theme});

  final Widget child;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: theme,
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox.expand(child: child)),
  );
}

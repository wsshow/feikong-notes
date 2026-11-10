import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fknotes/app.dart';
import 'package:fknotes/debug/app_diagnostics.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/pages/note_share_composer_page.dart';
import 'package:fknotes/services/note_audio_playback_service.dart';
import 'package:fknotes/services/note_audio_recording_service.dart';
import 'package:fknotes/services/note_read_aloud_service.dart';
import 'package:fknotes/services/note_watermark_service.dart';
import 'package:fknotes/widgets/app_icon.dart';
import 'package:fknotes/widgets/note_recording_bar.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late _MemoryNoteWriter writer;

  setUp(() => writer = _MemoryNoteWriter());

  testWidgets('new notes focus the body before the title', (tester) async {
    await tester.pumpWidget(
      _TestApp(child: NoteQuillEditorPage(writerLoader: () async => writer)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    final title = tester.widget<TextField>(
      find.byKey(const Key('quill-note-title')),
    );
    final editor = tester.widget<NoteQuillEditor>(
      find.byKey(const Key('quill-note-body')),
    );
    expect(title.focusNode!.hasFocus, isFalse);
    expect(editor.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
    'references multiple arbitrary files as one card and autosaves the group',
    (tester) async {
      final references = [
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '方案.docx',
          size: 100,
        ),
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '素材.custom',
          size: 200,
        ),
      ];
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            writerLoader: () async => writer,
            pickFileReferences: () async => references,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('quill-insert-file-references')));
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(writer.notes, hasLength(1));
      expect(writer.notes.single.assets, isEmpty);
      final embed = NoteEmbed.parse(
        writer.notes.single.document.toDelta().operations.first.data,
      );
      expect(
        embed.fileReferences.map((file) => file.fileId),
        references.map((file) => file.fileId),
      );
      expect(find.byKey(const Key('note-file-reference-open')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unfocused reference additions append in order and active caret inserts locally',
    (tester) async {
      NoteFileReference ref(String name) => NoteFileReference(
        fileId: NoteAttachmentId.generate().value,
        name: name,
        size: 10,
      );
      final refs = [
        ref('first.pdf'),
        ref('second.zip'),
        ref('third.bin'),
        ref('at-caret.txt'),
      ];
      final note = Note.newDraft().copyWith(
        revision: 1,
        document: NoteDocument.fromDelta(
          Delta()
            ..insert('已有正文\n')
            ..insert(NoteEmbed.fileReferences([refs.first]).toDeltaData())
            ..insert('\n'),
        ),
      );
      writer.notes.add(note);
      var pickCount = 0;
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: note,
            writerLoader: () async => writer,
            pickFileReferences: () async => [refs[++pickCount]],
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final editor = tester.widget<NoteQuillEditor>(
        find.byKey(const Key('quill-note-body')),
      );
      List<String> names() => editor.controller
          .snapshot()
          .document
          .toDelta()
          .operations
          .where((op) => op.data is Map)
          .map((op) => NoteEmbed.parse(op.data).fileReferences.first.name)
          .toList();
      expect(editor.focusNode!.hasFocus, false);
      for (var index = 1; index <= 2; index++) {
        // A stale caret at the start must not move the newly added card above the old ones.
        editor.controller.quillController.updateSelection(
          const TextSelection.collapsed(offset: 0),
          quill.ChangeSource.local,
        );
        await tester.tap(find.byKey(const Key('quill-insert-file-references')));
        await _pumpFor(tester, const Duration(milliseconds: 900));
        expect(names(), refs.take(index + 1).map((ref) => ref.name).toList());
      }
      editor.focusNode!.requestFocus();
      editor.controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 0),
        quill.ChangeSource.local,
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(editor.focusNode!.hasFocus, true);
      await tester.tap(find.byKey(const Key('quill-insert-file-references')));
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(names(), [refs.last.name, ...refs.take(3).map((ref) => ref.name)]);
      expect(
        writer.notes.single.document,
        editor.controller.snapshot().document,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a note containing only reference cards accepts text when tapping below them',
    (tester) async {
      final reference = NoteEmbed.fileReferences([
        NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '资料.pdf',
          size: 10,
        ),
      ]);
      final note = Note.newDraft().copyWith(
        revision: 1,
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(reference.toDeltaData())
            ..insert('\n'),
        ),
      );
      writer.notes.add(note);
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: note,
            writerLoader: () async => writer,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final editor = tester.widget<NoteQuillEditor>(
        find.byKey(const Key('quill-note-body')),
      );
      expect(editor.focusNode!.hasFocus, false);
      expect(editor.controller.endsWithBlockEmbed, true);
      await tester.tapAt(
        tester
                .getRect(
                  find.byKey(const ValueKey('move-note-file-references-0')),
                )
                .bottomCenter +
            const Offset(0, 32),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(editor.focusNode!.hasFocus, true);
      expect(tester.testTextInput.isVisible, true);
      expect(editor.controller.endsWithBlockEmbed, false);
      final text = editor.controller.quillController.document.toPlainText();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${text.substring(0, text.length - 1)}写在引用下面的内容\n',
          selection: TextSelection.collapsed(
            offset: text.length - 1 + '写在引用下面的内容'.length,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(
        writer.notes.single.document.toDelta().toJson(),
        (Delta()
              ..insert(reference.toDeltaData())
              ..insert('\n写在引用下面的内容\n'))
            .toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing notes do not take focus on open', (tester) async {
    final note = Note.newDraft().copyWith(
      title: '已有笔记',
      document: NoteDocument.fromPlainText('已有正文'),
      revision: 1,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: note,
          writerLoader: () async => writer,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    final title = tester.widget<TextField>(
      find.byKey(const Key('quill-note-title')),
    );
    final editor = tester.widget<NoteQuillEditor>(
      find.byKey(const Key('quill-note-body')),
    );
    expect(title.focusNode!.hasFocus, isFalse);
    expect(editor.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'outline shows unsaved headings and jumps without editing or opening the keyboard',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(390, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final body = List.filled(45, '正文段落\n').join();
        final target = '开篇\n'.length + body.length;
        final note = Note.newDraft().copyWith(
          document: NoteDocument.fromDelta(
            Delta()
              ..insert('开篇')
              ..insert('\n', {'header': 1})
              ..insert(body)
              ..insert('旧小节')
              ..insert('\n', {'header': 3})
              ..insert('末尾正文\n'),
          ),
        );
        await tester.pumpWidget(
          _TestApp(
            child: NoteQuillEditorPage(
              initialNote: note,
              writerLoader: () async => writer,
              autosaveDelay: const Duration(minutes: 1),
            ),
          ),
        );
        await _pumpFor(tester, const Duration(milliseconds: 200));
        final editor = tester.widget<NoteQuillEditor>(
          find.byKey(const Key('quill-note-body')),
        );
        final controller = editor.controller.quillController;
        controller.replaceText(
          target,
          3,
          '最新小节',
          const TextSelection.collapsed(offset: 0),
        );
        await tester.pump();
        final before = controller.document.toDelta().toJson();
        expect(find.byKey(const Key('quill-read-aloud')), findsNothing);
        expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
        await tester.tap(find.byKey(const Key('quill-note-outline')));
        await tester.pumpAndSettle();
        final sheet = find.byKey(const Key('note-outline-sheet'));
        final latestHeading = find.descendant(
          of: sheet,
          matching: find.text('最新小节'),
        );
        final openingHeading = find.descendant(
          of: sheet,
          matching: find.text('开篇'),
        );
        expect(sheet, findsOneWidget);
        expect(latestHeading, findsOneWidget);
        expect(
          find.descendant(of: sheet, matching: find.text('旧小节')),
          findsNothing,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('H3')),
          findsNothing,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('H1')),
          findsNothing,
        );
        expect(
          tester.getRect(latestHeading).left,
          greaterThan(tester.getRect(openingHeading).left),
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('标题 3: 最新小节'))
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(find.byKey(ValueKey('note-outline-entry-$target')));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(controller.selection.extentOffset, target);
        expect(editor.scrollController!.offset, greaterThan(0));
        final render = tester
            .state<quill.QuillRawEditorState>(find.byType(quill.QuillRawEditor))
            .renderEditor;
        final caret = render.getLocalRectForCaret(TextPosition(offset: target));
        expect(
          tester
              .getRect(find.byKey(const Key('quill-note-body')))
              .contains(render.localToGlobal(caret.center)),
          isTrue,
        );
        expect(tester.testTextInput.isVisible, isFalse);
        expect(editor.focusNode!.hasFocus, isFalse);
        expect(controller.document.toDelta().toJson(), before);
        expect(writer.notes, isEmpty);
        controller.undo();
        await tester.pump();
        expect(
          controller.document.toDelta().toJson(),
          note.document.toDelta().toJson(),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'empty outline explains headings and dismisses without changing selection',
    (tester) async {
      final note = Note.newDraft().copyWith(
        document: NoteDocument.fromPlainText('普通正文'),
      );
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: note,
            writerLoader: () async => writer,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));
      final controller = tester
          .widget<NoteQuillEditor>(find.byKey(const Key('quill-note-body')))
          .controller
          .quillController;
      const selection = TextSelection(baseOffset: 1, extentOffset: 3);
      controller.updateSelection(selection, quill.ChangeSource.local);
      await tester.tap(find.byKey(const Key('quill-note-outline')));
      await tester.pumpAndSettle();
      expect(find.text('暂无标题'), findsOneWidget);
      expect(find.textContaining('标题 1–6'), findsOneWidget);
      await tester.tap(find.byKey(const Key('note-outline-close')));
      await tester.pumpAndSettle();
      expect(controller.selection, selection);
      expect(
        controller.document.toDelta().toJson(),
        note.document.toDelta().toJson(),
      );
      expect(writer.notes, isEmpty);
      await tester.tap(find.byKey(const Key('quill-note-outline')));
      await tester.pumpAndSettle();
      await Navigator.of(
        tester.element(find.byKey(const Key('note-outline-sheet'))),
      ).maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-outline-sheet')), findsNothing);
      expect(find.byType(NoteQuillEditorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'outline scrolls long headings on a short large-text screen in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final delta = Delta();
        for (var i = 1; i <= 20; i++) {
          delta
            ..insert('章节 $i 这是需要换行的长标题 Long heading')
            ..insert('\n', {'header': (i - 1) % 6 + 1});
        }
        final note = Note.newDraft().copyWith(
          document: NoteDocument.fromDelta(delta),
        );
        await tester.pumpWidget(
          _TestApp(
            locale: locale,
            textScale: 2,
            theme: buildAppTheme(AppThemeStyle.paper, Brightness.dark),
            child: NoteQuillEditorPage(
              initialNote: note,
              writerLoader: () async => writer,
            ),
          ),
        );
        await _pumpFor(tester, const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const Key('quill-note-outline')));
        await tester.pumpAndSettle();
        final list = find.byKey(const Key('note-outline-list'));
        await tester.scrollUntilVisible(
          find.text('章节 20 这是需要换行的长标题 Long heading'),
          200,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('note-outline-close')));
        await tester.pumpAndSettle();
        expect(find.byType(NoteQuillEditorPage), findsOneWidget);
      },
    );
  }

  testWidgets(
    'system back dismisses the more menu without closing the editor',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(child: NoteQuillEditorPage(writerLoader: () async => writer)),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('quill-editor-more')));
      await tester.pumpAndSettle();
      expect(find.text('分享为图片'), findsOneWidget);

      await Navigator.of(
        tester.element(find.byType(NoteQuillEditorPage)),
      ).maybePop();
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(NoteQuillEditorPage), findsOneWidget);
      expect(find.byKey(const Key('quill-editor-more')), findsOneWidget);
      expect(find.text('分享为图片'), findsNothing);
      expect(
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('quill-editor-more')));
      await tester.pumpAndSettle();
      expect(find.text('分享为图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor content fills the page without an outer card frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteQuillEditorPage(writerLoader: () async => writer)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    final pageRect = tester.getRect(find.byType(Scaffold));
    final surface = find.byKey(const Key('quill-editor-surface'));
    final surfaceRect = tester.getRect(surface);
    expect(surfaceRect.left, pageRect.left);
    expect(surfaceRect.right, pageRect.right);
    final editorSurface = tester.widget<Container>(surface);
    expect(editorSurface.color, AppColors.paperPrimary);
    expect(editorSurface.decoration, isNull);
  });

  testWidgets('editorial editor uses its journal title and paper surface', (
    tester,
  ) async {
    final theme = buildAppTheme(
      AppThemeStyle.editorialJournal,
      Brightness.light,
    );
    await tester.pumpWidget(
      _TestApp(
        theme: theme,
        child: NoteQuillEditorPage(writerLoader: () async => writer),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    final components = AppComponentTheme.forStyle(
      AppThemeStyle.editorialJournal,
    );
    final title = tester.widget<TextField>(
      find.byKey(const Key('quill-note-title')),
    );
    expect(title.style?.fontFamily, components.displayFontFamily);
    final editorSurface = tester.widget<Container>(
      find.byKey(const Key('quill-editor-surface')),
    );
    expect(editorSurface.color, isNull);
    final decoration = editorSurface.decoration as BoxDecoration;
    expect(decoration.color, AppPalette.editorialJournalLight.surface);
    expect(
      decoration.image?.image,
      const AssetImage(EditorialJournalTokens.paperTextureAsset),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('title metadata is one compact line with 48dp actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 27, 10, 41);
    final note = Note.newDraft(now: now).copyWith(
      title: '测试提醒',
      document: NoteDocument.fromPlainText('这是提醒测试'),
      tags: ['xx'],
      reminderAt: now.add(const Duration(minutes: 1)),
      revision: 1,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: note,
          writerLoader: () async => writer,
          now: () => now,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));
    final row = find.byKey(const Key('quill-editor-metadata'));
    final time = find.byKey(const Key('quill-note-updated-time'));
    final count = find.byKey(const Key('quill-note-character-count'));
    final reminder = find.byKey(const Key('editor-note-reminder'));
    final tag = find.byKey(const ValueKey('quill-note-tag-xx'));
    expect(find.text('8月27日 10:41'), findsOneWidget);
    expect(find.text('6 字'), findsOneWidget);
    expect(find.text('1分钟后'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(tester.getSize(row).height, 48);
    for (final item in [time, count, reminder, tag]) {
      expect(
        (tester.getCenter(item).dy - tester.getCenter(row).dy).abs(),
        lessThan(1),
      );
    }
    expect(tester.getSize(find.byKey(const Key('quill-edit-tags'))).height, 48);
    expect(tester.getSize(reminder).height, 48);
    expect(
      tester.getTopLeft(row).dy,
      tester.getBottomLeft(find.byKey(const Key('quill-note-title'))).dy,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('quill-note-body'))).dy,
      tester.getBottomLeft(row).dy,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'body count tracks text and ignores title, whitespace and attachment placeholders',
    (tester) async {
      final imageId = NoteAttachmentId.generate();
      final now = DateTime(2026, 8, 27);
      final note = Note(
        id: NoteId.generate(),
        title: '不统计标题',
        revision: 1,
        document: NoteDocument.fromDelta(
          Delta()
            ..insert('这 是\n👨‍👩‍👧‍👦 e\u0301\n')
            ..insert(NoteEmbed.attachment(imageId).toDeltaData())
            ..insert('\n'),
        ),
        assets: [
          NoteAsset(
            id: imageId,
            kind: NoteAssetKind.image,
            storageKey: 'notes/images/count.png',
            originalName: '图片不计入字数.png',
            byteLength: _onePixelPng.length,
            mimeType: 'image/png',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      writer.notes.add(note);
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: note,
            writerLoader: () async => writer,
            resolveImage: (_) => MemoryImage(_onePixelPng),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(find.text('4 字'), findsOneWidget);
      final controller = tester
          .widget<NoteQuillEditor>(find.byKey(const Key('quill-note-body')))
          .controller;
      controller.quillController.replaceText(
        0,
        0,
        '新增',
        const TextSelection.collapsed(offset: 2),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(find.text('6 字'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('quill-note-title')),
        '改标题仍是六字',
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(find.text('6 字'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'long metadata stays one row and scrolls on a small large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 8, 27, 10, 41);
      await tester.pumpWidget(
        _TestApp(
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: NoteQuillEditorPage(
              initialNote: Note.newDraft(now: now).copyWith(
                title: '长信息',
                tags: ['一个很长很长的标签名称', '第二个标签', '第三个标签'],
                reminderAt: now.subtract(const Duration(days: 400)),
                revision: 1,
              ),
              writerLoader: () async => writer,
              now: () => now,
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final row = find.byKey(const Key('quill-editor-metadata'));
      expect(tester.getSize(row).height, 48);
      final scrollable = find.descendant(
        of: row,
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );
      await tester.drag(row, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('+1'), findsNothing);
      expect(find.text(' +1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('debounces a valid Delta snapshot into a new note', (
    tester,
  ) async {
    final initial = Note(
      id: NoteId.generate(),
      title: '',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('第一行', {'bold': true})
          ..insert('\n第二行\n'),
      ),
      createdAt: DateTime.utc(2026, 7, 23, 15),
      updatedAt: DateTime.utc(2026, 7, 23, 15),
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 100),
          now: () => DateTime.utc(2026, 7, 23, 15, 1),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.enterText(
      find.byKey(const Key('quill-note-title')),
      '原生 Delta 笔记',
    );
    await tester.pump(const Duration(milliseconds: 99));
    expect(writer.notes, isEmpty);

    await tester.pump(const Duration(milliseconds: 2));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    final saved = writer.notes.single;
    expect(saved.title, '原生 Delta 笔记');
    expect(saved.contentProjection.plainText, '第一行\n第二行');
    expect(saved.document.toDelta().toJson(), [
      {
        'insert': '第一行',
        'attributes': {'bold': true},
      },
      {'insert': '\n第二行\n'},
    ]);
    expect(find.text('已自动保存到本机'), findsOneWidget);
  });

  testWidgets('nested mixed lists survive autosave and reopening', (
    tester,
  ) async {
    final initial = Note.newDraft().copyWith(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('父项')
          ..insert('\n', {'list': 'unchecked'})
          ..insert('子项')
          ..insert('\n', {'list': 'unchecked', 'indent': 1})
          ..insert('详情')
          ..insert('\n', {'list': 'bullet', 'indent': 1}),
      ),
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 100),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    final editor = tester.widget<NoteQuillEditor>(
      find.byKey(const Key('quill-note-body')),
    );
    editor.controller.quillController.updateSelection(
      const TextSelection.collapsed(offset: 6),
      quill.ChangeSource.local,
    );
    final increase = find.descendant(
      of: find.byKey(const Key('quill-toolbar-indent-increase')),
      matching: find.byType(IconButton),
    );
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-todo-checkbox')).at(1));
    await _pumpFor(tester, const Duration(milliseconds: 400));

    final expected =
        (Delta()
              ..insert('父项')
              ..insert('\n', {'list': 'unchecked'})
              ..insert('子项')
              ..insert('\n', {'list': 'checked', 'indent': 1})
              ..insert('详情')
              ..insert('\n', {'list': 'bullet', 'indent': 2}))
            .toJson();
    final saved = writer.notes.single;
    expect(saved.document.toDelta().toJson(), expected);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 100));
    final reloaded = saved.copyWith(
      document: NoteDocument.fromJsonString(saved.document.toJsonString()),
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: reloaded,
          writerLoader: () async => writer,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    final reopened = tester.widget<NoteQuillEditor>(
      find.byKey(const Key('quill-note-body')),
    );
    expect(
      reopened.controller.snapshot().document.toDelta().toJson(),
      expected,
    );
    expect(find.byKey(const Key('note-todo-checkbox')), findsNWidgets(2));
    expect(find.byType(quill.QuillBulletPoint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back navigation flushes changes before the debounce window', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(minutes: 1),
          now: () => DateTime.utc(2026, 7, 23, 16),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('quill-note-title')), '退出前保存');
    await tester.tap(find.byKey(const Key('quill-editor-back')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes.single.title, '退出前保存');
  });

  testWidgets('done action saves immediately and returns to the opener', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(minutes: 1),
          now: () => DateTime.utc(2026, 7, 23, 16),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('quill-note-title')), '完成后定位');
    await tester.tap(find.byKey(const Key('quill-toolbar-done')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes.single.title, '完成后定位');
  });

  testWidgets('serializes a newer edit behind an in-flight create', (
    tester,
  ) async {
    writer.createGate = Completer<void>();
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    await tester.enterText(find.byKey(const Key('quill-note-title')), '第一版');
    await _pumpFor(tester, const Duration(milliseconds: 60));
    expect(writer.createCalls, 1);

    await tester.enterText(find.byKey(const Key('quill-note-title')), '第二版');
    await _pumpFor(tester, const Duration(milliseconds: 60));
    expect(writer.updateCalls, 0);

    writer.createGate!.complete();
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(writer.createCalls, 1);
    expect(writer.updateCalls, 1);
    expect(writer.notes.single.title, '第二版');
    expect(writer.notes.single.revision, 2);
  });

  testWidgets('records the root cause when automatic saving fails', (
    tester,
  ) async {
    writer.createError = StateError('NOT NULL constraint failed: notes.status');
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('quill-note-title')), '迁移失败诊断');
    await _pumpFor(tester, const Duration(milliseconds: 200));

    final record = AppDiagnostics.instance
        .snapshot(categories: {AppLogCategory.editor})
        .lastWhere((item) => item.event == 'note_autosave_failed');
    expect(record.level, AppLogLevel.error);
    expect(record.error, contains('notes.status'));
    expect(record.data['revision'], 0);
  });

  testWidgets('does not persist an untouched empty draft', (tester) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('quill-editor-back')));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(writer.notes, isEmpty);
  });

  testWidgets('imports a gallery image into the Delta before autosaving', (
    tester,
  ) async {
    final source = PickedNoteImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      originalName: '选择的图片.png',
    );
    final now = DateTime.utc(2026, 7, 23, 17);
    NoteAsset? importedAsset;
    var pickerCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          pickImage: (sourceType) async {
            pickerCalls++;
            expect(sourceType, ImageSource.gallery);
            return source;
          },
          importImage: (bytes, {required originalName}) async {
            expect(bytes, [1, 2, 3]);
            importedAsset = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/managed.png',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/png',
              createdAt: now,
              updatedAt: now,
            );
            return importedAsset!;
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byIcon(Icons.image_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('quill-pick-gallery-image')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(pickerCalls, 1);
    expect(importedAsset, isNotNull);
    expect(
      find.byKey(ValueKey('note-image-${importedAsset!.id.value}')),
      findsOneWidget,
    );
    expect(writer.createCalls, 1);
    final saved = writer.notes.single;
    expect(saved.assets, hasLength(1));
    expect(saved.assets.single.displayTitle, '选择的图片.png');
    expect(saved.assets.single.storageKey, startsWith('notes/images/'));
    expect(saved.document.project().referencedAttachmentIds, [
      saved.assets.single.id,
    ]);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    final image = find.byKey(ValueKey('note-image-${importedAsset!.id.value}'));
    await tester.ensureVisible(image);
    await tester.tap(image);
    await _pumpFor(tester, const Duration(milliseconds: 350));
    await tester.tap(
      find.byKey(ValueKey('edit-note-image-${importedAsset!.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('image-attachment-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('image-attachment-title')),
      '重命名图片',
    );
    await tester.tap(find.byKey(const Key('save-attachment-title')));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(writer.notes.single.assets.single.displayTitle, '重命名图片');
  });

  testWidgets('watermark camera locates and burns the photo before import', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 7, 29, 14, 30);
    final location = NoteWatermarkLocation(
      latitude: 31.230416,
      longitude: 121.473701,
      accuracy: 7,
      placeName: '上海市 · 黄浦区 · 人民广场',
      capturedAt: capturedAt,
    );
    var locationCalls = 0;
    var watermarkCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          locateForWatermark: () async {
            locationCalls++;
            return location;
          },
          pickImage: (source) async {
            expect(source, ImageSource.camera);
            return PickedNoteImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              originalName: 'camera.jpg',
            );
          },
          watermarkImage: (bytes, selectedLocation) async {
            watermarkCalls++;
            expect(bytes, [1, 2, 3]);
            expect(selectedLocation, same(location));
            return Uint8List.fromList([9, 8, 7, 6]);
          },
          importImage: (bytes, {required originalName}) async {
            expect(bytes, [9, 8, 7, 6]);
            expect(originalName, startsWith('watermark-'));
            return NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/watermark.jpg',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/jpeg',
              createdAt: capturedAt,
              updatedAt: capturedAt,
            );
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-image')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    final gallerySize = tester.getSize(
      find.byKey(const Key('quill-pick-gallery-image')),
    );
    expect(
      tester.getSize(find.byKey(const Key('quill-take-photo'))),
      gallerySize,
    );
    expect(
      tester.getSize(find.byKey(const Key('quill-take-watermarked-photo'))),
      gallerySize,
    );
    await tester.tap(find.byKey(const Key('quill-take-watermarked-photo')));
    await _pumpFor(tester, const Duration(milliseconds: 400));

    expect(locationCalls, 1);
    expect(find.text('上海市 · 黄浦区 · 人民广场'), findsOneWidget);
    expect(watermarkCalls, 0);

    await tester.tap(find.byKey(const Key('watermark-location-confirm')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(watermarkCalls, 1);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.image);
    expect(
      writer.notes.single.assets.single.originalName,
      startsWith('watermark-'),
    );
  });

  testWidgets('watermark camera accepts a manually entered location', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 7, 29, 15);
    NoteWatermarkLocation? selectedLocation;
    var locationCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          now: () => capturedAt,
          locateForWatermark: () async {
            locationCalls++;
            throw const NoteWatermarkLocationException(
              NoteWatermarkLocationFailure.serviceDisabled,
            );
          },
          pickImage: (_) async => PickedNoteImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            originalName: 'camera.jpg',
          ),
          watermarkImage: (bytes, location) async {
            selectedLocation = location;
            return Uint8List.fromList([9, 8, 7]);
          },
          importImage: (bytes, {required originalName}) async => NoteAsset(
            id: NoteAttachmentId.generate(),
            kind: NoteAssetKind.image,
            storageKey: 'notes/images/manual-watermark.jpg',
            originalName: originalName,
            byteLength: bytes.length,
            mimeType: 'image/jpeg',
            createdAt: capturedAt,
            updatedAt: capturedAt,
          ),
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-image')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('quill-take-watermarked-photo')));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.text('请先开启系统定位服务，再使用水印相机'), findsOneWidget);
    await tester.tap(find.byKey(const Key('watermark-use-manual-location')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('watermark-manual-location-field')),
      '  公司会议室  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('watermark-location-confirm')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(locationCalls, 1);
    expect(selectedLocation?.normalizedPlaceName, '公司会议室');
    expect(selectedLocation?.hasCoordinates, isFalse);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.image);
  });

  testWidgets('imports a selected video as a native note card', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'fknotes_video_widget_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/现场记录.mp4')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final now = DateTime.utc(2026, 7, 29, 15);
    NoteAsset? imported;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          pickVideo: (sourceType) async {
            expect(sourceType, ImageSource.gallery);
            return PickedNoteVideo(
              file: source,
              originalName: '现场记录.mp4',
              durationMs: 125000,
            );
          },
          importVideo: (file, {required originalName, durationMs}) async {
            expect(file.path, source.path);
            expect(originalName, '现场记录.mp4');
            expect(durationMs, 125000);
            imported = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.video,
              storageKey: 'notes/video/managed.mp4',
              originalName: originalName,
              byteLength: file.lengthSync(),
              mimeType: 'video/mp4',
              durationMs: durationMs,
              createdAt: now,
              updatedAt: now,
            );
            return imported!;
          },
          resolveAssetPath: (_) => source.path,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-video')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('quill-pick-gallery-video')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(imported, isNotNull);
    expect(
      find.byKey(ValueKey('note-asset-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('play-note-video-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(find.text('02:05 · 4 B'), findsOneWidget);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.video);
    expect(writer.notes.single.document.project().referencedAttachmentIds, [
      imported!.id,
    ]);
  });

  testWidgets('imports an externally dropped image at the visible drop point', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final now = DateTime.utc(2026, 7, 23, 17, 30);
    NoteAsset? importedAsset;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          importImage: (bytes, {required originalName}) async {
            expect(bytes, _onePixelPng);
            expect(originalName, '外部拖入.png');
            importedAsset = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/dropped.png',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/png',
              createdAt: now,
              updatedAt: now,
            );
            return importedAsset!;
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    final region = find.byKey(const Key('note-external-image-drop-region'));
    final globalPosition = tester.getCenter(
      find.byKey(const Key('quill-note-body')),
    );
    final dropTarget = tester.widget<DropTarget>(region);
    dropTarget.onDragEntered!(
      DropEventDetails(
        localPosition: const Offset(40, 80),
        globalPosition: globalPosition,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('note-external-image-drop-overlay')),
      findsOneWidget,
    );

    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            _onePixelPng,
            name: '外部拖入.png',
            path: '外部拖入.png',
            mimeType: 'image/png',
          ),
          DropItemFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: '说明.txt',
            path: '说明.txt',
            mimeType: 'text/plain',
          ),
        ],
        localPosition: const Offset(40, 80),
        globalPosition: globalPosition,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 800));
    debugDefaultTargetPlatformOverride = null;

    expect(
      find.byKey(const Key('note-external-image-drop-overlay')),
      findsNothing,
    );
    expect(importedAsset, isNotNull);
    expect(
      find.byKey(ValueKey('note-image-${importedAsset!.id.value}')),
      findsOneWidget,
    );
    expect(writer.notes.single.assets.single.originalName, '外部拖入.png');
    expect(find.text('部分文件不是支持的图片或超过 20 MB'), findsOneWidget);
  });

  testWidgets('recording bar follows the active bottom dock presentation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget buildBar(AppThemeStyle style) => _TestApp(
      theme: buildAppTheme(style, Brightness.light),
      child: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            NoteRecordingBar(
              preparing: false,
              saving: false,
              paused: false,
              elapsed: const Duration(seconds: 8),
              amplitudes: const [.1, .4, .8, .3],
              onCancel: () {},
              onPauseOrResume: () {},
              onFinish: () {},
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(buildBar(AppThemeStyle.editorialJournal));
    await tester.pumpAndSettle();

    final floatingDock = find.byKey(const Key('app-floating-navigation-dock'));
    expect(find.byKey(const Key('note-recording-bar')), findsOneWidget);
    expect(floatingDock, findsOneWidget);
    expect(tester.getSize(floatingDock).width, lessThan(390));
    expect(tester.getBottomRight(floatingDock).dy, lessThan(720));

    await tester.pumpWidget(buildBar(AppThemeStyle.paper));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-recording-bar')), findsOneWidget);
    expect(floatingDock, findsNothing);
  });

  testWidgets('records, pauses and inserts a managed audio card', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync(
      'fknotes_recording_widget_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final recordingPath = '${temp.path}/recording.m4a';
    final recorder = _FakeAudioRecordingDriver(recordingPath);
    final playback = _FakeAudioPlaybackDriver();
    final now = DateTime.utc(2026, 7, 23, 17, 30);
    NoteAsset? imported;

    await tester.pumpWidget(
      _TestApp(
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          audioRecordingDriver: recorder,
          audioPlaybackDriver: playback,
          resolveAssetPath: (_) => '/managed/recording.m4a',
          importAudio:
              (
                source, {
                required originalName,
                required displayName,
                required durationMs,
              }) async {
                expect(source.existsSync(), isTrue);
                expect(originalName, startsWith('recording-'));
                expect(displayName, startsWith('语音笔记 '));
                imported = NoteAsset(
                  id: NoteAttachmentId.generate(),
                  kind: NoteAssetKind.audio,
                  storageKey: 'notes/audio/managed.m4a',
                  originalName: originalName,
                  displayName: displayName,
                  byteLength: source.lengthSync(),
                  mimeType: 'audio/mp4',
                  durationMs: durationMs,
                  createdAt: now,
                  updatedAt: now,
                );
                return imported!;
              },
          now: () => now,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-record-audio')));
    await _pumpFor(tester, const Duration(milliseconds: 100));
    expect(recorder.startCalls, 1);
    expect(find.byType(NoteRecordingBar), findsOneWidget);
    expect(find.byKey(const Key('note-recording-waveform')), findsOneWidget);
    expect(find.byKey(const Key('quill-record-audio')), findsNothing);
    expect(
      tester
          .widget<NoteQuillEditor>(find.byKey(const Key('quill-note-body')))
          .bottomContentPadding,
      greaterThan(0),
    );
    final editorSurface = tester.getRect(
      find.byKey(const Key('quill-editor-surface')),
    );
    final floatingDock = tester.getRect(
      find.byKey(const Key('app-floating-navigation-dock')),
    );
    expect(editorSurface.bottom, greaterThan(floatingDock.bottom));

    recorder.emitAmplitude(.85);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pause-resume-note-recording')));
    await tester.pump();
    expect(recorder.pauseCalls, 1);
    expect(find.text('已暂停'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pause-resume-note-recording')));
    await tester.pump();
    expect(recorder.resumeCalls, 1);

    await tester.tap(find.byKey(const Key('finish-note-recording')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(recorder.stopCalls, 1);
    expect(recorder.stopCompleted, isTrue);
    expect(imported, isNotNull);
    expect(
      find.byKey(ValueKey('note-asset-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(find.text(imported!.displayTitle), findsOneWidget);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.audio);
    expect(writer.notes.single.document.project().referencedAttachmentIds, [
      imported!.id,
    ]);
    expect(File(recordingPath).existsSync(), isFalse);
  });

  testWidgets('reads the current Delta text without media extraction noise', (
    tester,
  ) async {
    final imageId = NoteAttachmentId.generate();
    final now = DateTime.utc(2026, 7, 23, 18);
    final image = NoteAsset(
      id: imageId,
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/read-aloud.png',
      originalName: '检查单.png',
      byteLength: 12,
      mimeType: 'image/png',
      ocrText: '不应被朗读的 OCR 文字',
      createdAt: now,
      updatedAt: now,
    );
    final note = Note(
      id: NoteId.generate(),
      title: '未保存前的标题',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('第一段\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n')
          ..insert(const NoteEmbed.divider().toDeltaData())
          ..insert('\n')
          ..insert('第二段\n'),
      ),
      assets: [image],
      createdAt: now,
      updatedAt: now,
    );
    final readAloud = _FakeReadAloudDriver();

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: note,
          writerLoader: () async => writer,
          readAloud: readAloud,
          readAloudAvailabilityChecker: () async => true,
          resolveImage: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('quill-note-title')),
      '当前 Delta 标题',
    );

    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await tester.pump();
    await tester.tap(find.widgetWithText(MenuItemButton, '朗读笔记'));
    await _pumpFor(tester, const Duration(milliseconds: 200));

    expect(readAloud.spoken, ['当前 Delta 标题\n\n第一段\n第二段']);
    expect(readAloud.spoken.single, isNot(contains('检查单')));
    expect(readAloud.spoken.single, isNot(contains('OCR')));
    expect(readAloud.spoken.single, isNot(contains('——')));
    expect(writer.notes, isEmpty);
  });

  testWidgets(
    'read-aloud status and stop stay in floating controls rather than the menu',
    (tester) async {
      final driver = _FakeReadAloudDriver()
        ..speakStatus = ReadAloudStatus.generating;
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: Note.newDraft().copyWith(
              document: NoteDocument.fromPlainText('朗读内容'),
            ),
            writerLoader: () async => writer,
            readAloud: driver,
            readAloudAvailabilityChecker: () async => true,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('quill-editor-more')));
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, '朗读笔记'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      final bar = find.byKey(const Key('note-read-aloud-bar'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('正在准备朗读…')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('quill-editor-more')));
      await tester.pump();
      expect(
        tester
            .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '朗读笔记'))
            .onPressed,
        isNull,
      );
      expect(find.widgetWithText(MenuItemButton, '停止朗读'), findsNothing);
      await Navigator.of(
        tester.element(find.byType(NoteQuillEditorPage)),
      ).maybePop();
      driver.updateStatus(ReadAloudStatus.playing);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: bar, matching: find.text('正在朗读')),
        findsOneWidget,
      );
      final barRect = tester.getRect(bar);
      expect(barRect.width, lessThanOrEqualTo(280));
      expect(
        barRect.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('quill-note-body'))).bottom,
        ),
      );
      expect(
        barRect.bottom,
        lessThan(tester.getRect(find.byType(NoteQuillToolbar)).top),
      );
      await tester.tap(find.byKey(const Key('note-read-aloud-stop')));
      await tester.pumpAndSettle();
      expect(driver.stopCalls, 1);
      expect(driver.status, ReadAloudStatus.idle);
      expect(bar, findsNothing);
      await tester.tap(find.byKey(const Key('quill-editor-more')));
      await tester.pump();
      expect(
        tester
            .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '朗读笔记'))
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('quill-note-outline')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stopping read-aloud preparation cancels a late model check', (
    tester,
  ) async {
    final available = Completer<bool>();
    final driver = _FakeReadAloudDriver();
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: Note.newDraft().copyWith(
            document: NoteDocument.fromPlainText('取消后不能开始播报'),
          ),
          writerLoader: () async => writer,
          readAloud: driver,
          readAloudAvailabilityChecker: () => available.future,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await tester.pump();
    await tester.tap(find.widgetWithText(MenuItemButton, '朗读笔记'));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('正在准备朗读…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-read-aloud-stop')));
    await tester.pump();
    expect(find.byKey(const Key('note-read-aloud-bar')), findsNothing);
    available.complete(true);
    await tester.pumpAndSettle();
    expect(driver.spoken, isEmpty);
    expect(driver.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'floating read-aloud controls fit large text above the keyboard in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final driver = _FakeReadAloudDriver()..status = ReadAloudStatus.playing;
        await tester.pumpWidget(
          _TestApp(
            locale: locale,
            textScale: 2,
            child: NoteQuillEditorPage(
              writerLoader: () async => writer,
              readAloud: driver,
            ),
          ),
        );
        await _pumpFor(tester, const Duration(milliseconds: 200));
        final bar = find.byKey(const Key('note-read-aloud-bar'));
        final bounds = tester.getRect(bar);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(bounds.bottom, lessThanOrEqualTo(420));
        expect(
          find.byKey(const Key('note-read-aloud-stop')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        driver.updateStatus(ReadAloudStatus.idle);
        await tester.pumpAndSettle();
        expect(
          bar,
          findsNothing,
          reason: 'completion also dismisses the controls',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final source in ['body', 'title']) {
      testWidgets(
        '${platform.name} $source keyboard transfers to AI and back without hide calls',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.physicalSize = const Size(430, 932);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final note = Note.newDraft().copyWith(
            revision: 1,
            title: '焦点交接',
            document: NoteDocument.fromPlainText('保持原来的选区和正文'),
          );
          writer.notes.add(note);
          await tester.pumpWidget(
            _TestApp(
              child: NoteQuillEditorPage(
                initialNote: note,
                writerLoader: () async => writer,
                inlineAssistantDriver: _FakeInlineAssistantDriver(),
              ),
            ),
          );
          await _pumpFor(tester, const Duration(milliseconds: 100));
          final editor = tester.widget<NoteQuillEditor>(
            find.byKey(const Key('quill-note-body')),
          );
          final title = tester.widget<TextField>(
            find.byKey(const Key('quill-note-title')),
          );
          (source == 'body' ? editor.focusNode : title.focusNode)!
              .requestFocus();
          await _pumpFor(tester, const Duration(milliseconds: 100));
          final selection = const TextSelection(baseOffset: 1, extentOffset: 4);
          editor.controller.quillController.updateSelection(
            selection,
            quill.ChangeSource.local,
          );
          await tester.pump();
          expect(tester.testTextInput.isVisible, true);
          for (var count = 0; count < 3; count++) {
            tester.testTextInput.log.clear();
            await tester.tap(
              find.byKey(const Key('quill-open-inline-assistant')),
            );
            for (var frame = 0; frame < 12; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              expect(tester.testTextInput.isVisible, true);
              expect(
                tester.testTextInput.log.where(
                  (call) => call.method == 'TextInput.hide',
                ),
                isEmpty,
              );
            }
            final input = tester.widget<TextField>(
              find.byKey(const Key('quill-inline-assistant-input')),
            );
            expect(input.focusNode!.hasFocus, true);
            expect(editor.controller.quillController.selection, selection);
            expect(
              tester
                  .getRect(find.byKey(const Key('quill-inline-assistant')))
                  .bottom,
              lessThanOrEqualTo(632),
            );
            if (count == 0) {
              tester.testTextInput.log.clear();
              await tester.tap(
                find.byKey(const Key('inline-assistant-target')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('更新标题与标签'));
              await tester.pumpAndSettle();
              expect(input.focusNode!.hasFocus, true);
              expect(
                tester.testTextInput.log.where(
                  (call) => call.method == 'TextInput.hide',
                ),
                isEmpty,
              );
            }
            await tester.enterText(
              find.byKey(const Key('quill-inline-assistant-input')),
              '继续整理',
            );
            await tester.pump();
            tester.testTextInput.log.clear();
            await tester.tap(find.byKey(const Key('close-inline-assistant')));
            for (var frame = 0; frame < 12; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              expect(tester.testTextInput.isVisible, true);
              expect(
                tester.testTextInput.log.where(
                  (call) => call.method == 'TextInput.hide',
                ),
                isEmpty,
              );
            }
            expect(editor.focusNode!.hasFocus, true);
            expect(editor.controller.quillController.selection, selection);
            expect(editor.controller.snapshot().document, note.document);
          }
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets(
    'opening AI with the keyboard closed focuses its prompt immediately',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: Note.newDraft().copyWith(revision: 1),
            writerLoader: () async => writer,
            inlineAssistantDriver: _FakeInlineAssistantDriver(),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(tester.testTextInput.isVisible, false);
      await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('quill-inline-assistant-input')),
            )
            .focusNode!
            .hasFocus,
        true,
      );
      expect(tester.testTextInput.isVisible, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing local model keeps the inline composer idle while checking',
    (tester) async {
      final availability = Completer<bool>();
      final driver = _FakeInlineAssistantDriver();
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            writerLoader: () async => writer,
            inlineAssistantDriver: driver,
            languageModelAvailabilityChecker: () => availability.future,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));

      expect(find.byKey(const Key('quill-local-assistant')), findsNothing);
      expect(
        find.byKey(const Key('quill-open-inline-assistant')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await tester.enterText(
        find.byKey(const Key('quill-inline-assistant-input')),
        '写一段开场白',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-inline-assistant')));
      await tester.pump();

      expect(find.text('正在准备本地模型…'), findsNothing);
      expect(
        find.byKey(const Key('quill-inline-assistant-input')),
        findsOneWidget,
      );
      expect(driver.loadCalls, 0);

      availability.complete(false);
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.text('正在准备本地模型…'), findsNothing);
      expect(driver.loadCalls, 0);
    },
  );

  testWidgets(
    'bottom AI composer streams into the caret and undoes atomically',
    (tester) async {
      final now = DateTime.utc(2026, 7, 23, 19, 30);
      final driver = _FakeInlineAssistantDriver();
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: Note(
              id: NoteId.generate(),
              title: '行程',
              document: NoteDocument.fromPlainText('已有想法'),
              createdAt: now,
              updatedAt: now,
            ),
            writerLoader: () async => writer,
            inlineAssistantDriver: driver,
            autosaveDelay: const Duration(milliseconds: 50),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.byKey(const Key('quill-inline-assistant')), findsOneWidget);
      expect(find.text('续写当前内容'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('quill-inline-assistant-input')),
        '整理一份两项清单',
      );
      await tester.pump();
      final submit = find.byKey(const Key('submit-inline-assistant'));
      final sendIcon = tester.widget<AppIcon>(
        find.descendant(of: submit, matching: find.byType(AppIcon)),
      );
      expect(sendIcon.color, tester.element(submit).appColors.onAccent);
      await tester.tap(find.byKey(const Key('submit-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 700));

      expect(driver.requests, hasLength(1));
      expect(
        driver.requests.single.messages.last.content,
        contains('整理一份两项清单'),
      );
      expect(driver.requests.single.messages.last.content, contains('已有想法'));
      expect(find.text('笔记内容已更新'), findsOneWidget);
      expect(writer.notes.single.contentProjection.plainText, '第一项\n第二项\n已有想法');

      await tester.tap(find.text('撤销'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(writer.notes.single.contentProjection.plainText, '已有想法');
    },
  );

  testWidgets('bottom AI composer can replace the current paragraph', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 19, 30);
    final driver = _FakeInlineAssistantDriver();
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: Note(
            id: NoteId.generate(),
            title: '整理',
            document: NoteDocument.fromPlainText('保留开头\n需要整理\n保留结尾'),
            createdAt: now,
            updatedAt: now,
          ),
          writerLoader: () async => writer,
          inlineAssistantDriver: driver,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    final editor = tester.widget<NoteQuillEditor>(
      find.byKey(const Key('quill-note-body')),
    );
    editor.controller.quillController.updateSelection(
      const TextSelection.collapsed(offset: 7),
      quill.ChangeSource.local,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('inline-assistant-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改当前段落').last);
    await tester.pumpAndSettle();
    expect(find.text('修改当前段落'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('quill-inline-assistant-input')),
      '整理成两项清单',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('submit-inline-assistant')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('submit-inline-assistant')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(driver.requests, hasLength(1));
    expect(driver.requests.single.messages.last.content, contains('当前段落'));
    expect(driver.requests.single.messages.last.content, contains('修改后的完整内容'));
    expect(
      writer.notes.single.contentProjection.plainText,
      '保留开头\n第一项\n第二项\n保留结尾',
    );
  });

  testWidgets('bottom AI composer updates title and tags with one undo', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 19, 30);
    final driver = _FakeInlineAssistantDriver(
      outputChunks: const ['{"title":"春日檐角","tags":["#春天",', '"露珠","春天"]}'],
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: Note(
            id: NoteId.generate(),
            title: '旧标题',
            tags: const ['旧标签'],
            document: NoteDocument.fromPlainText('春天的露珠落在檐角。'),
            createdAt: now,
            updatedAt: now,
          ),
          writerLoader: () async => writer,
          inlineAssistantDriver: driver,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('生成标题和标签'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('quill-inline-assistant-input')),
      '根据正文生成标题和标签',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-inline-assistant')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(driver.requests, hasLength(1));
    expect(driver.requests.single.messages.first.content, contains('JSON'));
    expect(driver.requests.single.messages.last.content, contains('旧标签'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('quill-note-title')))
          .controller
          ?.text,
      '春日檐角',
    );
    expect(find.byKey(const ValueKey('quill-note-tag-春天')), findsOneWidget);
    expect(find.byKey(const ValueKey('quill-note-tag-露珠')), findsOneWidget);
    expect(find.byKey(const ValueKey('quill-note-tag-旧标签')), findsNothing);
    expect(find.text('笔记信息已更新'), findsOneWidget);
    expect(writer.notes.single.title, '春日檐角');
    expect(writer.notes.single.tags, ['春天', '露珠']);
    expect(writer.notes.single.contentProjection.plainText, '春天的露珠落在檐角。');

    await tester.tap(find.text('撤销'));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('quill-note-title')))
          .controller
          ?.text,
      '旧标题',
    );
    expect(find.byKey(const ValueKey('quill-note-tag-旧标签')), findsOneWidget);
    expect(find.byKey(const ValueKey('quill-note-tag-春天')), findsNothing);
    expect(writer.notes.single.title, '旧标题');
    expect(writer.notes.single.tags, ['旧标签']);
  });

  testWidgets('shares the current rich Delta snapshot without Markdown', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 20);
    final initial = Note(
      id: NoteId.generate(),
      title: '分享测试',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('加粗', {'bold': true})
          ..insert('与正文\n'),
      ),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await _pumpFor(tester, const Duration(milliseconds: 150));
    await tester.tap(find.text('分享为图片'));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    final composer = tester.widget<NoteShareComposerPage>(
      find.byType(NoteShareComposerPage),
    );
    expect(composer.draft.title, '分享测试');
    expect(composer.draft.blocks.single.text, '加粗与正文');
    expect(composer.draft.blocks.single.text, isNot(contains('**')));
    expect(composer.draft.blocks.single.styles.single.style.bold, isTrue);
  });

  testWidgets('edits tags as canonical note metadata', (tester) async {
    final now = DateTime.utc(2026, 7, 23, 21);
    final initial = Note(
      id: NoteId.generate(),
      title: '标签测试',
      document: NoteDocument.fromPlainText('正文'),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    expect(find.byKey(const Key('quill-edit-tags')), findsNothing);
    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note-tags-field')),
      '工作, 灵感, 工作',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-note-tags')));
    await tester.tap(find.byKey(const Key('save-note-tags')));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    expect(writer.notes.single.tags, ['工作', '灵感']);
    expect(find.byKey(const ValueKey('quill-note-tag-工作')), findsOneWidget);
    expect(find.byKey(const ValueKey('quill-note-tag-灵感')), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);

    await tester.tap(find.byKey(const Key('quill-edit-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-tags-field')), '灵感');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-note-tags')));
    await tester.tap(find.byKey(const Key('save-note-tags')));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(writer.notes.single.tags, ['灵感']);
    expect(find.byKey(const ValueKey('quill-note-tag-工作')), findsNothing);
  });

  testWidgets('permanently deletes a persisted note after confirmation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 22);
    final persisted = Note(
      id: NoteId.generate(),
      title: '待删除笔记',
      document: NoteDocument.fromPlainText('即将永久删除'),
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    writer.notes.add(persisted);
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          initialNote: persisted,
          writerLoader: () async => writer,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await _pumpFor(tester, const Duration(milliseconds: 120));
    await tester.tap(find.text('永久删除'));
    await _pumpFor(tester, const Duration(milliseconds: 150));
    expect(find.text('永久删除？'), findsOneWidget);
    await tester.tap(find.text('永久删除').last);
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes, isEmpty);
    expect(writer.deletedNotes.single.id, persisted.id);
  });
}

final class _FakeAudioRecordingDriver implements NoteAudioRecordingDriver {
  _FakeAudioRecordingDriver(this.outputPath);

  final String outputPath;
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast();
  var startCalls = 0;
  var pauseCalls = 0;
  var resumeCalls = 0;
  var stopCalls = 0;
  var stopCompleted = false;
  var cancelCalls = 0;

  @override
  Stream<double> get amplitudes => _amplitudes.stream;

  void emitAmplitude(double value) => _amplitudes.add(value);

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<RecordedNoteAudio> stop() async {
    stopCalls++;
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(2048, 5));
    stopCompleted = true;
    return RecordedNoteAudio(path: outputPath);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final file = File(outputPath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> dispose() async {
    await _amplitudes.close();
  }
}

final class _FakeAudioPlaybackDriver extends ChangeNotifier
    implements NoteAudioPlaybackDriver {
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
  }) async {}

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
    status = NoteAudioPlaybackStatus.playing;
    notifyListeners();
  }
}

final class _FakeReadAloudDriver extends ChangeNotifier
    implements NoteReadAloudDriver {
  final List<String> spoken = [];
  var stopCalls = 0;
  ReadAloudStatus speakStatus = ReadAloudStatus.playing;

  void updateStatus(ReadAloudStatus value) {
    status = value;
    notifyListeners();
  }

  @override
  ReadAloudStatus status = ReadAloudStatus.idle;

  @override
  String? errorMessage;

  @override
  bool get isActive =>
      status != ReadAloudStatus.idle && status != ReadAloudStatus.failed;

  @override
  Future<void> speak(String rawText) async {
    spoken.add(rawText);
    status = speakStatus;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    status = ReadAloudStatus.idle;
    notifyListeners();
  }
}

final class _MemoryNoteWriter implements NoteEditorWriter {
  final List<Note> notes = [];
  final List<Note> deletedNotes = [];
  Completer<void>? createGate;
  Object? createError;
  var createCalls = 0;
  var updateCalls = 0;

  @override
  Future<Note> create(Note note) async {
    createCalls++;
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    final persisted = note.copyWith(revision: 1);
    notes.add(persisted);
    return persisted;
  }

  @override
  Future<Note> update(Note note) async {
    updateCalls++;
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    if (index < 0) throw StateError('Note was not created.');
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    deletedNotes.add(note);
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

final class _FakeInlineAssistantDriver implements NoteInlineAssistantDriver {
  _FakeInlineAssistantDriver({this.outputChunks = const ['- 第一项', '\n- 第二项']});

  final List<String> outputChunks;
  final List<LocalLlmGenerationRequest> requests = [];
  var loadCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> load() async {
    loadCalls++;
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    requests.add(request);
    for (final chunk in outputChunks) {
      yield LocalLlmTextDelta(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    yield const LocalLlmGenerationCompleted(
      reason: LocalLlmFinishReason.completed,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 50);
  final frames = (duration.inMilliseconds / frame.inMilliseconds).ceil();
  for (var index = 0; index < frames; index++) {
    await tester.pump(frame);
  }
}

final class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.locale = const Locale('zh'),
    this.textScale,
    this.theme,
  });

  final Widget child;
  final Locale locale;
  final double? textScale;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: locale,
    theme: theme,
    builder: textScale == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale!)),
            child: child!,
          ),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: child,
  );
}

final class _RouteTestApp extends StatelessWidget {
  const _RouteTestApp({required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open-quill-editor'),
            onPressed: () => Navigator.push<Object?>(
              context,
              MaterialPageRoute(builder: (_) => page),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
}

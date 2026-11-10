import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(platform.name, () {
      testWidgets(
        'long press and continuous selection do not show the keyboard',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(
            tester,
            'alpha bravo charlie\nsecond line',
          );
          tester.testTextInput.log.clear();
          final gesture = await tester.startGesture(
            _characterPoint(editor.raw, 8, .25),
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
          expect(editor.focus.hasFocus, isTrue);
          expect(editor.controller.quillController.getPlainText(), 'bravo');
          expect(tester.testTextInput.isVisible, isFalse);
          for (final offset in [2, 14, 22, 8]) {
            await gesture.moveTo(_characterPoint(editor.raw, offset, .25));
            await tester.pump(const Duration(milliseconds: 50));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(editor.raw.selectionOverlay?.toolbar, isNotNull);
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          expect(tester.testTextInput.isVisible, isFalse);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'selection handles preserve a dismissed keyboard until an editing tap',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(
            tester,
            'alpha bravo charlie\nsecond line',
          );
          await tester.tapAt(_characterPoint(editor.raw, 2, .25));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          editor.raw.handleKeyboardVisibilityChanged(true);
          tester.testTextInput.log.clear();
          await tester.longPressAt(_characterPoint(editor.raw, 8, .25));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          tester.testTextInput.hide();
          editor.raw.handleKeyboardVisibilityChanged(false);
          tester.testTextInput.log.clear();
          final gesture = await tester.startGesture(
            tester.getCenter(_handle(editor.raw, start: false)),
          );
          for (var i = 0; i < 5; i++) {
            await gesture.moveBy(const Offset(16, 0));
            await tester.pump(const Duration(milliseconds: 50));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isFalse);
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          expect(
            editor.controller.quillController.selection.end,
            greaterThan(11),
          );
          editor.raw.hideToolbar();
          await tester.pumpAndSettle();
          await tester.tapAt(_characterPoint(editor.raw, 2, .25));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          expect(
            editor.controller.quillController.selection.isCollapsed,
            isTrue,
          );
          final value = editor.controller.quillController.plainTextEditingValue;
          final offset = value.selection.extentOffset;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: value.text.replaceRange(offset, offset, '输入'),
              selection: TextSelection.collapsed(offset: offset + 2),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            editor.controller.quillController.document.toPlainText(),
            contains('输入'),
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'select all and copy keep selection focus without opening the keyboard',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(tester, 'alpha bravo charlie');
          await tester.longPressAt(_characterPoint(editor.raw, 8, .25));
          await tester.pumpAndSettle();
          tester.testTextInput.log.clear();
          editor.raw.selectAll(SelectionChangedCause.toolbar);
          await tester.pumpAndSettle();
          expect(
            editor.controller.quillController.getPlainText(),
            'alpha bravo charlie',
          );
          editor.raw.copySelection(SelectionChangedCause.toolbar);
          await tester.pumpAndSettle();
          expect(
            editor.controller.quillController.selection.isCollapsed,
            isTrue,
          );
          expect(tester.testTextInput.isVisible, isFalse);
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'long press reattaches a closed input client without showing a keyboard',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(tester, 'alpha bravo charlie');
          await tester.tapAt(_characterPoint(editor.raw, 2, .25));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          tester.testTextInput.hide();
          editor.raw.handleKeyboardVisibilityChanged(false);
          tester.testTextInput.closeConnection();
          await tester.pump();
          expect(editor.raw.hasConnection, isFalse);
          tester.testTextInput.log.clear();
          await tester.longPressAt(_characterPoint(editor.raw, 8, .25));
          await tester.pumpAndSettle();
          expect(editor.raw.hasConnection, isTrue);
          expect(editor.controller.quillController.getPlainText(), 'bravo');
          expect(tester.testTextInput.isVisible, isFalse);
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'read-only text selection gets focus without a native input client',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(
            tester,
            'alpha bravo charlie',
            readOnly: true,
          );
          tester.testTextInput.log.clear();
          await tester.longPressAt(_characterPoint(editor.raw, 8, .25));
          await tester.pumpAndSettle();
          expect(editor.focus.hasFocus, isTrue);
          expect(editor.raw.hasConnection, isFalse);
          expect(editor.raw.selectionOverlay?.toolbar, isNotNull);
          expect(editor.controller.quillController.getPlainText(), 'bravo');
          expect(
            tester.testTextInput.log.where(
              (call) => call.method == 'TextInput.show',
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'long press selects the touched word including its last half',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(tester, 'hello 世界\n\nnext paragraph');
          for (final offset in [1, 4, 6, 7]) {
            await tester.longPressAt(_characterPoint(editor.raw, offset, .8));
            await tester.pumpAndSettle();
            final selection = editor.controller.quillController.selection;
            expect(selection.isCollapsed, isFalse, reason: 'character $offset');
            expect(selection.start, lessThanOrEqualTo(offset));
            expect(selection.end, greaterThan(offset));
            expect(
              editor.controller.quillController.getPlainText().trim(),
              isNotEmpty,
            );
            editor.raw.hideToolbar();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'long press drag retains the entire anchor word in both directions',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(
            tester,
            'alpha bravo charlie\nsecond line',
          );
          final gesture = await tester.startGesture(
            _characterPoint(editor.raw, 8, .25),
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(editor.controller.quillController.getPlainText(), 'bravo');
          await gesture.moveTo(_characterPoint(editor.raw, 2, .25));
          await tester.pump();
          expect(
            editor.controller.quillController.getPlainText(),
            'alpha bravo',
          );
          await gesture.moveTo(_characterPoint(editor.raw, 14, .25));
          await tester.pump();
          expect(
            editor.controller.quillController.getPlainText(),
            'bravo charlie',
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      for (final reverse in [false, true]) {
        testWidgets(
          'both handles drag from their text anchor (reverse=$reverse)',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            final editor = await _mount(
              tester,
              'alpha bravo charlie\nsecond paragraph here\nthird paragraph',
            );
            editor.focus.requestFocus();
            editor.controller.quillController.updateSelection(
              TextSelection(
                baseOffset: reverse ? 11 : 6,
                extentOffset: reverse ? 6 : 11,
              ),
              quill.ChangeSource.local,
            );
            await tester.pumpAndSettle();
            editor.raw.showToolbar();
            await tester.pumpAndSettle();
            final overlay = editor.raw.selectionOverlay!;
            for (final start in [false, true]) {
              final handle = find.descendant(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is CompositedTransformFollower &&
                      w.link ==
                          (start
                              ? overlay.startHandleLayerLink
                              : overlay.endHandleLayerLink),
                ),
                matching: find.byWidgetPredicate(
                  (w) => w is GestureDetector && w.onPanUpdate != null,
                ),
              );
              expect(handle, findsOneWidget);
              final anchorOffset = start ? 6 : 11;
              final targetOffset = start ? 1 : 17;
              final from = _caretPoint(editor.raw, anchorOffset);
              final to = _caretPoint(editor.raw, targetOffset);
              await tester.dragFrom(tester.getCenter(handle), to - from);
              await tester.pumpAndSettle();
              final selection = editor.controller.quillController.selection;
              expect(start ? selection.start : selection.end, targetOffset);
              expect(start ? selection.end : selection.start, start ? 17 : 6);
            }
            expect(tester.takeException(), isNull);
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }

      testWidgets(
        'handle edge scrolling is gradual, bounded and stops on cancel',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final text = List.generate(
            60,
            (i) => 'line $i alpha bravo charlie',
          ).join('\n');
          final editor = await _mount(tester, text);
          editor.focus.requestFocus();
          editor.controller.quillController.updateSelection(
            const TextSelection(baseOffset: 5, extentOffset: 7),
            quill.ChangeSource.local,
          );
          await tester.pumpAndSettle();
          editor.raw.showToolbar();
          await tester.pumpAndSettle();
          final handle = _handle(editor.raw, start: false);
          final finger = tester.getCenter(handle);
          final caret = _caretPoint(editor.raw, 7);
          final viewport = tester.getRect(find.byType(NoteQuillEditor));
          final gesture = await tester.startGesture(finger);
          await gesture.moveTo(
            finger + Offset(0, viewport.bottom - 30 - caret.dy),
          );
          await tester.pump();
          final initialEnd = editor.controller.quillController.selection.end;
          final start = editor.scroll.offset;
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          final slowDistance = editor.scroll.offset - start;
          expect(slowDistance, greaterThan(0));
          expect(slowDistance, lessThan(12));
          await gesture.moveTo(
            finger + Offset(0, viewport.bottom + 120 - caret.dy),
          );
          await tester.pump();
          final fastStart = editor.scroll.offset;
          for (var i = 0; i < 20; i++) {
            final previous = editor.scroll.offset;
            await tester.pump(const Duration(milliseconds: 16));
            expect(editor.scroll.offset - previous, inInclusiveRange(0, 3.1));
          }
          expect(editor.scroll.offset - fastStart, greaterThan(slowDistance));
          expect(editor.scroll.offset - fastStart, lessThanOrEqualTo(60));
          expect(editor.controller.quillController.selection.start, 5);
          expect(
            editor.controller.quillController.selection.end,
            greaterThan(initialEnd),
          );
          final beforeDelayedFrame = editor.scroll.offset;
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            editor.scroll.offset - beforeDelayedFrame,
            lessThanOrEqualTo(6.1),
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
          final stopped = editor.scroll.offset;
          await tester.pump(const Duration(seconds: 1));
          expect(editor.scroll.offset, stopped);
          expect(
            editor.controller.quillController.document.toPlainText(),
            '$text\n',
          );
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('handle at a soft wrap stays on its painted line', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        final editor = await _mount(tester, List.filled(100, 'a').join());
        final y = _caretPoint(editor.raw, 0).dy;
        final wrap = List.generate(
          100,
          (i) => i,
        ).firstWhere((i) => _caretPoint(editor.raw, i).dy > y + 1);
        editor.focus.requestFocus();
        editor.controller.quillController.updateSelection(
          TextSelection(baseOffset: 0, extentOffset: wrap),
          quill.ChangeSource.local,
        );
        await tester.pumpAndSettle();
        editor.raw.showToolbar();
        await tester.pumpAndSettle();
        final endpoint = editor.raw.renderEditor
            .getEndpointsForSelection(
              editor.controller.quillController.selection,
            )
            .last;
        final lineHeight = editor.raw.renderEditor.preferredLineHeight(
          TextPosition(offset: wrap - 1),
        );
        final anchor = editor.raw.renderEditor.localToGlobal(
          endpoint.point - Offset(0, lineHeight / 2),
        );
        await tester.dragFrom(
          tester.getCenter(_handle(editor.raw, start: false)),
          _caretPoint(editor.raw, wrap - 3) - anchor,
        );
        await tester.pumpAndSettle();
        expect(editor.controller.quillController.selection.end, wrap - 3);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets(
        'emoji and combining characters are selected as whole glyphs',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final editor = await _mount(tester, '😀 👍🏽 e\u0301 你好');
          for (final range in [
            (0, 2, '😀'),
            (3, 7, '👍🏽'),
            (8, 10, 'e\u0301'),
          ]) {
            final a = _caretPoint(editor.raw, range.$1);
            final b = _caretPoint(editor.raw, range.$2);
            await tester.longPressAt(Offset(a.dx + (b.dx - a.dx) * .8, a.dy));
            await tester.pumpAndSettle();
            expect(editor.controller.quillController.getPlainText(), range.$3);
            editor.raw.hideToolbar();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'word hit testing follows lists and horizontally scrolled code',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final code = '${List.filled(20, 'prefix').join(' ')} target';
          final document = NoteDocument.fromDelta(
            Delta()
              ..insert('列表末尾')
              ..insert('\n', {'list': 'bullet', 'indent': 1})
              ..insert(code)
              ..insert('\n', {'code-block': true}),
          );
          final editor = await _mount(tester, '', document: document);
          await tester.longPressAt(_characterPoint(editor.raw, 3, .8));
          await tester.pumpAndSettle();
          expect(
            editor.controller.quillController.selection.start,
            lessThanOrEqualTo(3),
          );
          expect(editor.controller.quillController.selection.end, 4);
          editor.raw.hideToolbar();
          await tester.pumpAndSettle();
          final horizontal = tester
              .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('quill-code-block-scroll')),
              )
              .controller!;
          horizontal.jumpTo(horizontal.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await tester.longPressAt(
            _characterPoint(editor.raw, 5 + code.length - 1, .8),
          );
          await tester.pumpAndSettle();
          expect(editor.controller.quillController.getPlainText(), 'target');
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'upward handle scrolling retains the other endpoint and stops on release',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final text = List.generate(
            80,
            (i) => 'line $i alpha bravo charlie',
          ).join('\n');
          final editor = await _mount(tester, text);
          editor.focus.requestFocus();
          await tester.pumpAndSettle();
          editor.scroll.jumpTo(700);
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(NoteQuillEditor));
          final offset = editor.raw.renderEditor
              .getPositionForOffset(viewport.center)
              .offset;
          await tester.longPressAt(_characterPoint(editor.raw, offset, .25));
          await tester.pumpAndSettle();
          final original = editor.controller.quillController.selection;
          final finger = tester.getCenter(_handle(editor.raw, start: true));
          final caret = _caretPoint(editor.raw, original.start);
          final gesture = await tester.startGesture(finger);
          await gesture.moveTo(
            finger + Offset(0, viewport.top - 80 - caret.dy),
          );
          await tester.pump();
          final start = editor.scroll.offset;
          final initialSelection =
              editor.controller.quillController.selection.start;
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(start - editor.scroll.offset, inInclusiveRange(60, 90));
          expect(
            editor.controller.quillController.selection.start,
            lessThan(initialSelection),
          );
          expect(editor.controller.quillController.selection.end, original.end);
          await gesture.up();
          final stopped = editor.scroll.offset;
          await tester.pumpAndSettle();
          expect(editor.scroll.offset, stopped);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('unmount during a selection drag cancels pending work', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        final editor = await _mount(
          tester,
          List.filled(80, 'alpha bravo\n').join(),
        );
        final gesture = await tester.startGesture(
          _characterPoint(editor.raw, 2, .25),
        );
        await tester.pump(const Duration(milliseconds: 600));
        final viewport = tester.getRect(find.byType(NoteQuillEditor));
        await gesture.moveTo(viewport.bottomCenter);
        await tester.pumpWidget(const SizedBox());
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets(
        'long press auto scroll keeps its document anchor and stops in the body',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final text = List.generate(
            60,
            (i) => 'line $i alpha bravo charlie',
          ).join('\n');
          final editor = await _mount(tester, text);
          final gesture = await tester.startGesture(
            _characterPoint(editor.raw, 9, .25),
          );
          await tester.pump(const Duration(milliseconds: 600));
          final anchor = editor.controller.quillController.selection.start;
          final viewport = tester.getRect(find.byType(NoteQuillEditor));
          await gesture.moveTo(
            Offset(viewport.center.dx, viewport.bottom + 100),
          );
          await tester.pump();
          final firstEnd = editor.controller.quillController.selection.end;
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(editor.scroll.offset, inInclusiveRange(60, 90));
          expect(editor.controller.quillController.selection.start, anchor);
          expect(
            editor.controller.quillController.selection.end,
            greaterThan(firstEnd),
          );
          await gesture.moveTo(viewport.center);
          await tester.pump();
          final stopped = editor.scroll.offset;
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.scroll.offset, stopped);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(editor.scroll.offset, stopped);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('blank lines keep a valid caret', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final editor = await _mount(tester, 'first\n\nlast');
        await tester.longPressAt(_caretPoint(editor.raw, 6));
        await tester.pumpAndSettle();
        expect(
          editor.controller.quillController.selection,
          const TextSelection.collapsed(offset: 6),
        );
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}

Finder _handle(quill.QuillRawEditorState raw, {required bool start}) {
  final overlay = raw.selectionOverlay!;
  return find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w is CompositedTransformFollower &&
          w.link ==
              (start
                  ? overlay.startHandleLayerLink
                  : overlay.endHandleLayerLink),
    ),
    matching: find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onPanUpdate != null,
    ),
  );
}

Offset _caretPoint(quill.QuillRawEditorState raw, int offset) {
  final rect = raw.renderEditor.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  return raw.renderEditor.localToGlobal(Offset(rect.left, rect.center.dy));
}

Offset _characterPoint(
  quill.QuillRawEditorState raw,
  int offset,
  double fraction,
) {
  final from = _caretPoint(raw, offset);
  final to = _caretPoint(raw, offset + 1);
  return Offset(from.dx + (to.dx - from.dx) * fraction, from.dy);
}

Future<
  ({
    NoteEditorController controller,
    quill.QuillRawEditorState raw,
    FocusNode focus,
    ScrollController scroll,
  })
>
_mount(
  WidgetTester tester,
  String text, {
  NoteDocument? document,
  bool readOnly = false,
}) async {
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final controller = NoteEditorController(
    document: document ?? NoteDocument.fromPlainText(text),
    assets: const [],
  );
  final focus = FocusNode();
  final scroll = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        quill.FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 400,
            child: NoteQuillEditor(
              controller: controller,
              readOnly: readOnly,
              focusNode: focus,
              scrollController: scroll,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final raw = tester.state<quill.QuillRawEditorState>(
    find.byType(quill.QuillRawEditor),
  );
  raw.handleKeyboardVisibilityChanged(false);
  return (controller: controller, focus: focus, scroll: scroll, raw: raw);
}

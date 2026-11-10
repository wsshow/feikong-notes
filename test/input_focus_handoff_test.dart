import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/app_overlay.dart';
import 'package:fknotes/widgets/note_attachment_title_sheet.dart';
import 'package:fknotes/widgets/note_link_editor_sheet.dart';
import 'package:fknotes/widgets/note_tags_editor_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final form in ['tags', 'link', 'attachment']) {
      testWidgets(
        '${platform.name} $form input sheet retains keyboard across open and close',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final navigator = GlobalKey<NavigatorState>();
          final focus = FocusNode();
          final source = TextEditingController(text: '保留原输入');
          addTearDown(focus.dispose);
          addTearDown(source.dispose);
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildAppTheme(
                AppThemeStyle.editorialJournal,
                Brightness.light,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextField(
                        controller: source,
                        focusNode: focus,
                        autofocus: true,
                      ),
                      TextButton(
                        onPressed: () {
                          switch (form) {
                            case 'tags':
                              AppOverlay.inputSheet<List<String>>(
                                context: context,
                                builder: (_) => const NoteTagsEditorSheet(
                                  initialTags: ['工作'],
                                ),
                              );
                            case 'link':
                              showNoteLinkEditorSheet(
                                context,
                                initialText: '了解详情',
                                initialLink: null,
                              );
                            case 'attachment':
                              showNoteAttachmentTitleSheet(
                                context,
                                initialValue: '原文件',
                                fieldKey: const Key('rename-file'),
                              );
                          }
                        },
                        child: const Text('打开输入弹窗'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, true);
          tester.testTextInput.log.clear();
          await tester.tap(find.text('打开输入弹窗'));
          for (var frame = 0; frame < 24; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.testTextInput.isVisible, true);
            expect(
              tester.testTextInput.log.where(
                (call) => call.method == 'TextInput.hide',
              ),
              isEmpty,
            );
          }
          final fieldKey = switch (form) {
            'tags' => const Key('note-tags-field'),
            'link' => const Key('note-link-address-field'),
            _ => const Key('rename-file'),
          };
          final input = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(fieldKey),
              matching: find.byType(EditableText),
            ),
          );
          expect(input.focusNode.hasFocus, true);
          tester.testTextInput.log.clear();
          navigator.currentState!.pop();
          for (var frame = 0; frame < 24; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.testTextInput.isVisible, true);
            expect(
              tester.testTextInput.log.where(
                (call) => call.method == 'TextInput.hide',
              ),
              isEmpty,
            );
          }
          expect(focus.hasFocus, true);
          expect(source.text, '保留原输入');
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}

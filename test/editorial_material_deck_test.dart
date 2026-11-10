import 'dart:io';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/providers/editorial_material_controller.dart';
import 'package:fknotes/services/editorial_material_preferences.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/editorial_material_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends EditorialMaterialPreferences {
  EditorialMaterialLayout selected = EditorialMaterialLayout.recent;
  @override
  Future<EditorialMaterialLayout> load() async => selected;
  @override
  Future<void> save(EditorialMaterialLayout layout) async {
    selected = layout;
  }
}

void main() {
  late EditorialMaterialController controller;
  late _Preferences preferences;
  late Directory root;
  final now = DateTime.utc(2026, 11, 4);
  LibraryFile file(
    String number,
    String name, {
    bool favorite = false,
    String? linkedNoteId,
  }) => LibraryFile(
    id: '00000000-0000-4000-8000-00000000000$number',
    name: name,
    storageName: '00000000-0000-4000-8000-00000000000$number.txt',
    size: 1024,
    favorite: favorite,
    createdAt: now,
    modifiedAt: now,
    linkedNoteId: linkedNoteId,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('editorial-material-widget');
    preferences = _Preferences();
    controller = EditorialMaterialController(
      store: FileLibraryStore(rootPath: root.path),
      preferences: preferences,
    )..loading = false;
  });
  tearDown(() async {
    controller.dispose();
    await root.delete(recursive: true);
  });

  Widget app({
    double scale = 1,
    String language = 'zh',
    bool reduced = false,
    ValueChanged<LibraryFile>? onWrite,
    ValueChanged<LibraryFile>? onOpen,
    void Function(LibraryFileKind?, bool)? onLibrary,
    VoidCallback? onChoose,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale(language),
    theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: EditorialMaterialDeck(
          controller: controller,
          onOpenFile: onOpen ?? (_) {},
          onWriteNote: onWrite ?? (_) {},
          onOpenLibrary: onLibrary ?? (_, _) {},
          onChooseFavorites: onChoose ?? () {},
        ),
      ),
    ),
  );

  Finder getStack() => find.byKey(const Key('editorial-material-stack'));
  Finder topFace() => find.byKey(const Key('material-card-top'));
  Finder topText(String text) =>
      find.descendant(of: topFace(), matching: find.text(text));
  double topX(WidgetTester tester) =>
      tester.widget<Transform>(topFace()).transform.storage[12];
  Future<void> swipe(WidgetTester tester, {bool previous = false}) async {
    final width = tester.getSize(getStack()).width;
    await tester.drag(getStack(), Offset(width * (previous ? .85 : -.85), 0));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'top sheet follows the finger while the next stays underneath; a reverse drag interrupts the spring',
    (tester) async {
      controller.files = [file('1', 'notes.pdf')];
      var writes = 0;
      await tester.pumpWidget(app(onWrite: (_) => writes++));
      final width = tester.getSize(getStack()).width;
      final drag = await tester.startGesture(tester.getCenter(getStack()));
      await drag.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveBy(Offset(-width * .4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(topX(tester), closeTo(-width * .4, 24));
      final following = topX(tester);
      await drag.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(topX(tester), closeTo(following - 30, 1));
      final underneath = tester.widget<Transform>(
        find.byKey(const Key('material-card-underneath')),
      );
      expect(underneath.transform.storage[12], 0);
      expect(controller.layout, EditorialMaterialLayout.recent);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 60));
      final before = topX(tester);
      final reverse = await tester.startGesture(tester.getCenter(getStack()));
      await tester.pump(const Duration(milliseconds: 16));
      expect(topX(tester), closeTo(before, 1));
      await reverse.moveBy(const Offset(20, 0));
      await tester.pump();
      final caught = topX(tester);
      expect(caught, closeTo(before + 20, 1));
      await reverse.moveBy(Offset(-caught, 0));
      await tester.pump(const Duration(milliseconds: 150));
      await reverse.up();
      await tester.pumpAndSettle();
      expect(topX(tester), closeTo(0, .001));
      expect(controller.layout, EditorialMaterialLayout.recent);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'swipes remove exactly one sheet in either direction and cycle the deck',
    (tester) async {
      await tester.pumpWidget(app());
      for (var i = 1; i <= 5; i++) {
        await swipe(tester);
        expect(controller.layout.index, i % 5);
        expect(preferences.selected.index, i % 5);
        expect(topX(tester), 0);
      }
      await swipe(tester, previous: true);
      expect(controller.layout, EditorialMaterialLayout.categories);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all five layouts handle narrow screens, large text, data and empty states',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final note = Note.newDraft().copyWith(title: 'A related note');
      for (final populated in [true, false]) {
        controller.files = populated
            ? [
                file(
                  '1',
                  'a-long-file-name-for-a-document.pdf',
                  favorite: true,
                  linkedNoteId: note.id.value,
                ),
                file('2', 'photo.png', favorite: true),
              ]
            : [];
        controller.linkedNotes = populated
            ? {controller.files.first.id: note}
            : {};
        for (final language in ['zh', 'en']) {
          for (final scale in [1.0, 2.0]) {
            await tester.pumpWidget(
              app(scale: scale, reduced: true, language: language),
            );
            await tester.pumpAndSettle();
            for (var index = 0; index < 5; index++) {
              expect(
                find.descendant(
                  of: topFace(),
                  matching: find.byKey(
                    ValueKey(
                      'editorial-material-${EditorialMaterialLayout.values[index].name}',
                    ),
                  ),
                ),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'layout $index, text $scale, files $populated, $language',
              );
              await swipe(tester);
            }
          }
        }
      }
    },
  );

  testWidgets(
    'file preview, writing, favorites and category actions route independently',
    (tester) async {
      final source = file('1', 'notes.pdf', favorite: true);
      controller.files = [source];
      LibraryFile? opened, written;
      LibraryFileKind? category;
      var chose = false;
      await tester.pumpWidget(
        app(
          reduced: true,
          onOpen: (value) => opened = value,
          onWrite: (value) => written = value,
          onLibrary: (kind, _) => category = kind,
          onChoose: () => chose = true,
        ),
      );
      await tester.tap(topText('预览资料'));
      await tester.pump();
      expect(opened, source);
      await tester.tap(topText('记一笔'));
      await tester.pump();
      expect(written, source);
      await swipe(tester);
      await tester.tap(topText('挑选资料  +'));
      expect(chose, true);
      for (var i = 0; i < 3; i++) {
        await swipe(tester);
      }
      await tester.tap(topText('PDF'));
      expect(category, LibraryFileKind.pdf);
      expect(preferences.selected, EditorialMaterialLayout.categories);
    },
  );

  testWidgets(
    'reduced motion keeps drag translation, drops rotation, and keyboard switches immediately',
    (tester) async {
      await tester.pumpWidget(app(reduced: true));
      await tester.pumpAndSettle();
      Focus.of(tester.element(getStack())).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.layout, EditorialMaterialLayout.favorites);
      expect(topX(tester), 0);
      final drag = await tester.startGesture(tester.getCenter(getStack()));
      await drag.moveBy(const Offset(-20, 0));
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(topX(tester), lessThan(0));
      expect(
        tester
            .widget<Transform>(find.byKey(const Key('material-card-rotation')))
            .transform
            .storage[1],
        0,
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      expect(find.byKey(const Key('material-deck-next')), findsNothing);
      expect(find.text('2 / 5'), findsNothing);
    },
  );
}

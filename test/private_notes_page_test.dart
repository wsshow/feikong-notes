import 'dart:async';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/pages/private_notes_page.dart';
import 'package:fknotes/pages/note_calendar_page.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/app_overlay.dart';
import 'package:fknotes/pages/quill_home_page.dart';
import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/providers/private_notes_controller.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/widgets/privacy_pull_to_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _success = DeviceAuthenticationResult(
  DeviceAuthenticationStatus.authenticated,
  '',
);
const _canceled = DeviceAuthenticationResult(
  DeviceAuthenticationStatus.canceled,
  '',
  messageId: DeviceAuthenticationMessage.canceled,
);

void main() {
  late _Store store;
  late _Authenticator auth;
  late NoteLibraryController publicLibrary;
  late NoteLibraryController privateLibrary;
  late AppLockController appLock;

  setUp(() {
    store = _Store([
      Note.newDraft().copyWith(title: '公开记录'),
      Note.newDraft(isPrivate: true).copyWith(title: '秘密记录'),
    ]);
    auth = _Authenticator();
    publicLibrary = NoteLibraryController(storeLoader: () async => store);
    privateLibrary = NoteLibraryController(
      privateSpace: true,
      storeLoader: () async => store,
    );
    appLock = AppLockController(observeLifecycle: false);
    addTearDown(publicLibrary.dispose);
    addTearDown(privateLibrary.dispose);
    addTearDown(appLock.dispose);
  });

  Widget home({NoteLibraryEditorBuilder? editorBuilder}) => _App(
    appLock: appLock,
    child: QuillHomePage(
      controller: publicLibrary,
      privateControllerFactory: () => privateLibrary,
      privateAuthenticator: auth,
      dataSizeLoader: () async => 0,
      editorBuilder:
          editorBuilder ??
          (editorContext, note) => Scaffold(
            body: TextButton(
              key: const Key('close-editor'),
              onPressed: () => Navigator.of(editorContext).pop(),
              child: Text('编辑 ${note?.title}'),
            ),
          ),
    ),
  );

  testWidgets(
    'disabled app lock still requires a fresh authentication on every visit',
    (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(appLock.enabled, isFalse);
      expect(find.text('秘密记录'), findsNothing);
      await _pull(tester);
      expect(auth.calls, 1);
      expect(find.byType(PrivateNotesPage), findsOneWidget);
      expect(find.text('秘密记录'), findsOneWidget);
      expect(find.text('公开记录'), findsNothing);
      expect(
        find.byKey(const Key('delta-library-open-calendar')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('退出隐私空间'));
      await tester.pumpAndSettle();
      expect(find.text('公开记录'), findsOneWidget);
      expect(find.text('秘密记录'), findsNothing);
      await _pull(tester);
      expect(auth.calls, 2);
      expect(find.text('秘密记录'), findsOneWidget);
    },
  );

  testWidgets('pending and canceled authentication never load private data', (
    tester,
  ) async {
    final pending = Completer<DeviceAuthenticationResult>();
    auth.pending = pending;
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    final reads = store.reads;
    await _pull(tester);
    expect(auth.calls, 1);
    expect(find.byType(PrivateNotesPage), findsNothing);
    expect(privateLibrary.notes, isEmpty);
    expect(store.reads, reads);
    pending.complete(_canceled);
    await tester.pumpAndSettle();
    expect(find.byType(PrivateNotesPage), findsNothing);
    expect(find.text('认证已取消'), findsOneWidget);
    expect(find.text('秘密记录'), findsNothing);
  });

  testWidgets(
    'empty home supports pull but focused search and selection do not',
    (tester) async {
      store.notes.clear();
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delta-library-search')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PrivacyPullToOpen>(find.byType(PrivacyPullToOpen))
            .enabled,
        isFalse,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _pull(tester);
      expect(auth.calls, 1);
      expect(find.text('还没有隐私笔记'), findsOneWidget);
    },
  );

  testWidgets(
    'moving notes in authenticates and moving out refreshes the public library',
    (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      await tester.longPress(find.text('公开记录'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PrivacyPullToOpen>(find.byType(PrivacyPullToOpen))
            .enabled,
        isFalse,
      );
      auth.result = _canceled;
      await tester.tap(find.byKey(const Key('delta-library-privacy-selected')));
      await tester.pumpAndSettle();
      expect(store.notes.first.isPrivate, isFalse);
      auth.result = _success;
      await tester.tap(find.byKey(const Key('delta-library-privacy-selected')));
      await tester.pumpAndSettle();
      expect(auth.calls, 2);
      expect(store.notes.first.isPrivate, isTrue);
      expect(find.text('公开记录'), findsNothing);
      await _pull(tester);
      expect(auth.calls, 3);
      await tester.longPress(find.text('公开记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delta-library-privacy-selected')));
      await tester.pumpAndSettle();
      expect(store.notes.first.isPrivate, isFalse);
      expect(find.text('公开记录'), findsNothing);
      await tester.tap(find.byTooltip('退出隐私空间'));
      await tester.pumpAndSettle();
      expect(find.text('公开记录'), findsOneWidget);
      expect(find.text('秘密记录'), findsNothing);
    },
  );

  testWidgets('private creation passes a private draft to the normal editor', (
    tester,
  ) async {
    Note? draft;
    await tester.pumpWidget(
      home(
        editorBuilder: (_, note) {
          draft = note;
          return const Scaffold(body: Text('新建私密编辑页'));
        },
      ),
    );
    await tester.pumpAndSettle();
    await _pull(tester);
    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    await tester.pumpAndSettle();
    expect(draft?.isPrivate, isTrue);
    expect(draft?.revision, 0);
    expect(find.text('新建私密编辑页'), findsOneWidget);
  });

  for (final style in [AppThemeStyle.paper, AppThemeStyle.editorialJournal]) {
    testWidgets(
      'private calendar and AI remain inside the protected $style workspace',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final session = PrivateNotesController(
          authenticator: auth,
          observeLifecycle: false,
        );
        addTearDown(session.dispose);
        await session.unlock(
          prompt: const DeviceAuthenticationPrompt(reason: 'test'),
        );
        await tester.pumpWidget(
          _App(
            appLock: appLock,
            style: style,
            child: PrivateNotesPage(
              session: session,
              controller: privateLibrary,
              assistantBuilder: (context, openNote) => Scaffold(
                appBar: AppBar(),
                body: TextButton(
                  onPressed: () => AppOverlay.dialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(content: Text('私密对话弹窗')),
                  ),
                  child: const Text('私密对话入口'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('quill-home-assistant')), findsOneWidget);
        if (style == AppThemeStyle.editorialJournal) {
          expect(
            find.byKey(const Key('app-floating-navigation-live-blur')),
            findsNothing,
          );
          expect(
            tester
                .widget<Material>(
                  find.byKey(const Key('app-floating-navigation-dock')),
                )
                .color,
            Color.alphaBlend(
              AppPalette.editorialJournalLight.surface.withValues(alpha: .92),
              AppPalette.editorialJournalLight.canvas,
            ),
          );
        }
        await tester.tap(find.byKey(const Key('delta-library-open-calendar')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NoteCalendarPage>(find.byType(NoteCalendarPage))
              .controller,
          same(privateLibrary),
        );
        if (style == AppThemeStyle.editorialJournal) {
          expect(
            find.byKey(const Key('app-floating-navigation-live-blur')),
            findsNothing,
          );
          expect(
            tester
                .widget<Material>(
                  find.byKey(const Key('app-floating-navigation-dock')),
                )
                .color,
            Color.alphaBlend(
              AppPalette.editorialJournalLight.surface.withValues(alpha: .92),
              AppPalette.editorialJournalLight.canvas,
            ),
          );
        }
        await tester.tap(find.byKey(const Key('calendar-view-day')));
        await tester.pumpAndSettle();
        expect(find.text('秘密记录'), findsOneWidget);
        expect(find.text('公开记录'), findsNothing);
        await tester.tap(find.byKey(const Key('calendar-back-home')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quill-home-assistant')));
        await tester.pumpAndSettle();
        expect(find.text('私密对话入口'), findsOneWidget);
        await tester.tap(find.text('私密对话入口'));
        await tester.pumpAndSettle();
        expect(find.text('私密对话弹窗'), findsOneWidget);
        session.lock();
        await tester.pumpAndSettle();
        expect(find.text('私密对话弹窗'), findsNothing);
        expect(find.text('私密对话入口'), findsNothing);
        expect(find.byKey(const Key('private-notes-locked')), findsOneWidget);
        expect(auth.calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'background shields nested editors and requires reauthentication to restore them',
    (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      await _pull(tester);
      await tester.tap(find.text('秘密记录'));
      await tester.pumpAndSettle();
      expect(find.text('编辑 秘密记录'), findsOneWidget);
      final page = tester.widget<PrivateNotesPage>(
        find.byType(PrivateNotesPage),
      );
      page.session.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('编辑 秘密记录'), findsNothing);
      expect(find.byKey(const Key('private-notes-locked')), findsOneWidget);
      page.session.didChangeAppLifecycleState(AppLifecycleState.paused);
      page.session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('private-notes-locked')), findsOneWidget);
      auth.result = _canceled;
      await tester.tap(find.byKey(const Key('private-notes-unlock')));
      await tester.pumpAndSettle();
      expect(find.text('编辑 秘密记录'), findsNothing);
      auth.result = _success;
      await tester.tap(find.byKey(const Key('private-notes-unlock')));
      await tester.pumpAndSettle();
      expect(auth.calls, 3);
      expect(find.text('编辑 秘密记录'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-editor')));
      await tester.pumpAndSettle();
      expect(find.text('秘密记录'), findsOneWidget);
    },
  );

  testWidgets('an initially locked route has no private navigator or data', (
    tester,
  ) async {
    final session = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _App(
        appLock: appLock,
        child: PrivateNotesPage(session: session, controller: privateLibrary),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.reads, 0);
    expect(find.byType(NoteLibraryPage), findsNothing);
    expect(find.byKey(const Key('private-notes-locked')), findsOneWidget);
  });

  testWidgets('empty private space scrolls on small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    store.notes.clear();
    final session = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(session.dispose);
    await session.unlock(
      prompt: const DeviceAuthenticationPrompt(reason: 'test'),
    );
    await tester.pumpWidget(
      _App(
        appLock: appLock,
        child: PrivateNotesPage(session: session, controller: privateLibrary),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有隐私笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pull(WidgetTester tester) async {
  final area = tester.getRect(find.byType(PrivacyPullToOpen));
  await tester.dragFrom(
    area.topLeft + const Offset(60, 30),
    const Offset(0, PrivacyPullToOpen.triggerDistance + 50),
  );
  await tester.pumpAndSettle();
}

final class _Authenticator implements DeviceAuthenticator {
  int calls = 0;
  DeviceAuthenticationResult result = _success;
  Completer<DeviceAuthenticationResult>? pending;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<DeviceAuthenticationResult> authenticate({
    required DeviceAuthenticationPrompt prompt,
  }) async {
    calls++;
    return pending == null ? result : await pending!.future;
  }
}

final class _Store implements NoteLibraryStore {
  _Store(this.notes);
  final List<Note> notes;
  int reads = 0;
  @override
  Future<List<Note>> list() async {
    reads++;
    return List.of(notes);
  }

  @override
  Future<List<Note>> search(String query) async =>
      notes.where((n) => n.searchText.contains(query)).toList();
  @override
  Future<Note> update(Note note) async {
    final persisted = note.copyWith(revision: note.revision + 1);
    notes[notes.indexWhere((n) => n.id == note.id)] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async =>
      notes.removeWhere((n) => n.id == note.id);
}

final class _App extends StatelessWidget {
  const _App({required this.child, required this.appLock, this.style});
  final AppThemeStyle? style;
  final Widget child;
  final AppLockController appLock;
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AppLocaleController(observePlatform: false),
      ),
      ChangeNotifierProvider.value(value: appLock),
    ],
    child: MaterialApp(
      theme: style == null ? null : buildAppTheme(style!, Brightness.light),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

import 'dart:async';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/pages/private_notes_page.dart';
import 'package:fknotes/pages/quill_home_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
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
);

void main() {
  late Note publicNote, privateNote;
  late _Auth auth;
  late _Store publicStore, privateStore;
  late NoteLibraryController publicLibrary, privateLibrary;
  late AppLockController lock;
  late ValueNotifier<NoteId?> requests;
  var loads = 0;

  Future<void> setup(WidgetTester tester, {bool locked = false}) async {
    auth = _Auth();
    publicNote = Note.newDraft().copyWith(title: '提醒目标', revision: 1);
    privateNote = Note.newDraft(
      isPrivate: true,
    ).copyWith(title: '机密内容', revision: 1);
    publicStore = _Store([publicNote]);
    privateStore = _Store([privateNote]);
    publicLibrary = NoteLibraryController(storeLoader: () async => publicStore);
    privateLibrary = NoteLibraryController(
      privateSpace: true,
      storeLoader: () async => privateStore,
    );
    lock = AppLockController(
      observeLifecycle: false,
      preferencesStore: _Preferences(locked),
      authenticator: _Auth(),
    );
    await lock.initialize();
    loads = 0;
    requests = ValueNotifier(null);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      publicLibrary.dispose();
      privateLibrary.dispose();
      requests.dispose();
      lock.dispose();
    });
  }

  Widget home() => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: lock),
      ChangeNotifierProvider(
        create: (_) => AppLocaleController(observePlatform: false),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: QuillHomePage(
        controller: publicLibrary,
        privateControllerFactory: () => privateLibrary,
        privateAuthenticator: auth,
        reminderRequests: requests,
        noteLoader: (id) async {
          loads++;
          return id == publicNote.id ? publicNote : null;
        },
        privateNoteChecker: (id) async =>
            privateStore.notes.any((note) => note.id == id),
        dataSizeLoader: () async => 0,
        editorBuilder: (context, note) => Scaffold(
          body: Text('打开笔记：${note!.title}', key: const Key('reminder-editor')),
        ),
      ),
    ),
  );

  testWidgets(
    'cold-start notification waits for app unlock before loading its note',
    (tester) async {
      await setup(tester, locked: true);
      requests.value = publicNote.id;
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(loads, 0);
      expect(find.byKey(const Key('reminder-editor')), findsNothing);
      await lock.unlock();
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('打开笔记：提醒目标'), findsOneWidget);
      expect(requests.value, isNull);
    },
  );

  testWidgets(
    'private notification authenticates before reading private content and keeps its shield',
    (tester) async {
      await setup(tester);
      auth.pending = Completer<DeviceAuthenticationResult>();
      requests.value = privateNote.id;
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(auth.calls, 1);
      expect(privateStore.reads, 0);
      expect(find.text('机密内容'), findsNothing);
      auth.pending!.complete(_success);
      await tester.pumpAndSettle();
      expect(find.byType(PrivateNotesPage), findsOneWidget);
      expect(find.text('打开笔记：机密内容'), findsOneWidget);
      final second = Note.newDraft(
        isPrivate: true,
      ).copyWith(title: '第二条隐私提醒', revision: 1);
      privateStore.notes.add(second);
      requests.value = second.id;
      await tester.pumpAndSettle();
      expect(find.text('打开笔记：第二条隐私提醒'), findsOneWidget);
      expect(auth.calls, 1);
      final session = tester
          .widget<PrivateNotesPage>(find.byType(PrivateNotesPage))
          .session;
      session.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('打开笔记：机密内容'), findsNothing);
      expect(find.text('打开笔记：第二条隐私提醒'), findsNothing);
      expect(find.byKey(const Key('private-notes-locked')), findsOneWidget);
    },
  );

  testWidgets(
    'canceled private authentication does not read or open the note',
    (tester) async {
      await setup(tester);
      auth.result = _canceled;
      requests.value = privateNote.id;
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(auth.calls, 1);
      expect(privateStore.reads, 0);
      expect(find.byKey(const Key('reminder-editor')), findsNothing);
      expect(requests.value, isNull);
    },
  );

  testWidgets(
    'a deleted target never opens an editor or private authentication',
    (tester) async {
      await setup(tester);
      requests.value = NoteId.generate();
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(auth.calls, 0);
      expect(find.byKey(const Key('reminder-editor')), findsNothing);
      expect(requests.value, isNull);
    },
  );
}

class _Store implements NoteLibraryStore {
  _Store(this.notes);
  final List<Note> notes;
  int reads = 0;
  @override
  Future<List<Note>> list() async {
    reads++;
    return notes;
  }

  @override
  Future<List<Note>> search(String query) async => notes;
  @override
  Future<Note> update(Note note) async => note;
  @override
  Future<void> deletePermanently(Note note) async {}
}

class _Auth implements DeviceAuthenticator {
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
    return pending == null ? result : pending!.future;
  }
}

class _Preferences implements AppLockPreferencesStore {
  _Preferences(this.enabled);
  final bool enabled;
  @override
  Future<AppLockPreferences> load() async =>
      AppLockPreferences(enabled: enabled);
  @override
  Future<void> save(AppLockPreferences value) async {}
}

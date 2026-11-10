import 'dart:async';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/services/incoming_share_service.dart';
import 'package:fknotes/widgets/incoming_share_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final now = DateTime.utc(2026, 8, 27, 8);
  late _Inbox service;
  late AppLockController lock;
  late List<Note> opened;
  late int imports;
  late Completer<Note>? pendingImport;
  late Completer<void>? pendingEditor;
  late bool failImport;
  var textScale = 1.0;

  Future<void> setup(WidgetTester tester, {bool locked = false}) async {
    opened = [];
    imports = 0;
    failImport = false;
    textScale = 1.0;
    pendingImport = null;
    pendingEditor = null;
    service = _Inbox();
    lock = AppLockController(
      observeLifecycle: false,
      preferencesStore: _Preferences(locked),
      authenticator: _Auth(),
    );
    await lock.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      lock.dispose();
    });
  }

  IncomingShare payload(String text) => IncomingShare(
    id: NoteId.generate(),
    directory: '/inbox',
    createdAt: now,
    text: text,
  );

  Widget app() => ChangeNotifierProvider.value(
    value: lock,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: IncomingShareCoordinator(
        service: service,
        importer: (share) async {
          imports++;
          if (failImport) throw StateError('disk full');
          return pendingImport?.future ??
              Future.value(
                Note.newDraft().copyWith(title: share.text, revision: 1),
              );
        },
        onOpenNote: (note) async {
          opened.add(note);
          await pendingEditor?.future;
        },
        child: const Scaffold(body: Text('当前笔记')),
      ),
    ),
  );

  testWidgets('cold share waits for unlock and explicit save confirmation', (
    tester,
  ) async {
    await setup(tester, locked: true);
    service.add(payload('外部分享'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('保存分享内容'), findsNothing);
    expect(imports, 0);
    await lock.unlock();
    await tester.pumpAndSettle();
    expect(find.text('保存分享内容'), findsOneWidget);
    expect(imports, 0);
    await tester.tap(find.text('保存为新笔记'));
    await tester.pumpAndSettle();
    expect(imports, 1);
    expect(opened.single.title, '外部分享');
    expect(service.pending, isNull);
  });

  testWidgets(
    'cancel drops only the current share, leaving the next one available',
    (tester) async {
      await setup(tester);
      service.add(payload('first'));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      service.add(payload('second'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(imports, 0);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    },
  );

  testWidgets('failure retains content and retry saves exactly once', (
    tester,
  ) async {
    await setup(tester);
    service.add(payload('retry'));
    failImport = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存为新笔记'));
    await tester.pumpAndSettle();
    expect(service.pending, isNotNull);
    expect(opened, isEmpty);
    failImport = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(service.pending, isNull);
  });

  testWidgets(
    'warm share waits while the previous shared note is being edited',
    (tester) async {
      await setup(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      pendingEditor = Completer<void>();
      service.add(payload('first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存为新笔记'));
      await tester.pumpAndSettle();
      service.add(payload('next'));
      await tester.pumpAndSettle();
      expect(find.text('保存分享内容'), findsNothing);
      expect(imports, 1);
      pendingEditor!.complete();
      await tester.pumpAndSettle();
      expect(find.text('next'), findsOneWidget);
      expect(imports, 1);
    },
  );

  testWidgets('unlock is checked again before opening a completed import', (
    tester,
  ) async {
    await setup(tester, locked: true);
    await lock.unlock();
    service.add(payload('later'));
    pendingImport = Completer<Note>();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存为新笔记'));
    await tester.pump();
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    pendingImport!.complete(
      Note.newDraft().copyWith(title: 'later', revision: 1),
    );
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await lock.unlock();
    await tester.pumpAndSettle();
    expect(opened.single.title, 'later');
  });

  testWidgets('confirmation remains usable with large text on a small screen', (
    tester,
  ) async {
    await setup(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    textScale = 2;
    service.add(payload('分享内容和链接 ' * 100));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.pending, isNull);
    expect(imports, 0);
  });
}

class _Inbox extends IncomingShareService {
  _Inbox() : super(supported: false);
  final queue = <IncomingShare>[];
  @override
  IncomingShare? get pending => queue.firstOrNull;
  void add(IncomingShare share) {
    queue.add(share);
    notifyListeners();
  }

  @override
  Future<void> refresh() async => notifyListeners();
  @override
  Future<void> finish(NoteId id) async {
    queue.removeWhere((share) => share.id == id);
    notifyListeners();
  }
}

class _Preferences implements AppLockPreferencesStore {
  _Preferences(this.enabled);
  final bool enabled;
  @override
  Future<AppLockPreferences> load() async =>
      AppLockPreferences(enabled: enabled);
  @override
  Future<void> save(AppLockPreferences preferences) async {}
}

class _Auth implements DeviceAuthenticator {
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<DeviceAuthenticationResult> authenticate({
    required DeviceAuthenticationPrompt prompt,
  }) async => const DeviceAuthenticationResult(
    DeviceAuthenticationStatus.authenticated,
    '',
  );
}

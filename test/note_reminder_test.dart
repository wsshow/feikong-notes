import 'dart:async';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/services/note_reminder_service.dart';
import 'package:fknotes/widgets/note_reminder_indicator.dart';
import 'package:fknotes/widgets/note_reminder_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 27, 14, 26);
  late _Writer writer;
  late _Reminders reminders;
  setUp(() {
    writer = _Writer();
    reminders = _Reminders();
  });

  Future<void> editor(
    WidgetTester tester, {
    Note? note,
    DateTime Function()? clock,
  }) async {
    if (note != null) writer.note = note;
    await tester.pumpWidget(
      _app(
        NoteQuillEditorPage(
          initialNote: note,
          writerLoader: () async => writer,
          reminders: reminders,
          now: clock ?? () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(writer.note?.reminderAt == null ? '设置提醒' : '修改提醒'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteReminderSheet), findsOneWidget);
  }

  testWidgets('sets, edits and removes a reminder on a new empty draft', (
    tester,
  ) async {
    await editor(tester);
    await openPicker(tester);
    final at = now.add(const Duration(minutes: 1));
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(at);
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, at.toUtc());
    expect(writer.note?.revision, 1);
    expect(reminders.scheduled, [writer.note!.id]);
    expect(find.text('1分钟后'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('quill-note-title')), '带提醒的笔记');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, at.toUtc());
    await tester.tap(find.byKey(const Key('editor-note-reminder')));
    await tester.pumpAndSettle();
    final later = now.add(const Duration(days: 1));
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(later);
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, later.toUtc());

    await openPicker(tester);
    await tester.tap(find.byKey(const Key('remove-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, isNull);
    expect(find.byKey(const Key('editor-note-reminder')), findsNothing);
  });

  for (final access in [
    NoteReminderAccess.notificationsDisabled,
    NoteReminderAccess.exactAlarmDisabled,
    NoteReminderAccess.unsupported,
  ]) {
    testWidgets('does not persist a reminder when access is $access', (
      tester,
    ) async {
      reminders.access = access;
      await editor(tester);
      await openPicker(tester);
      await tester.tap(find.byKey(const Key('confirm-note-reminder')));
      await tester.pumpAndSettle();
      expect(writer.note, isNull);
      expect(reminders.scheduled, isEmpty);
      expect(find.text('提醒已设置'), findsNothing);
    });
  }

  testWidgets('failed scheduling restores the previous reminder', (
    tester,
  ) async {
    reminders.succeeds = false;
    final previous = now.add(const Duration(hours: 1)).toUtc();
    await editor(
      tester,
      note: Note.newDraft().copyWith(
        title: '旧提醒',
        revision: 1,
        reminderAt: previous,
      ),
    );
    await openPicker(tester);
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(now.add(const Duration(days: 1)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, previous);
    expect(find.text('未能启用系统提醒，请重新设置'), findsOneWidget);
    expect(find.text('提醒已设置'), findsNothing);
  });

  testWidgets('iOS capacity error rolls back and explains the limit', (
    tester,
  ) async {
    reminders.capacityReached = true;
    await editor(tester);
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note?.reminderAt, isNull);
    expect(find.text('待提醒数量已达上限，请先移除一个提醒后重试。'), findsOneWidget);
  });

  testWidgets('a failed database write never schedules a notification', (
    tester,
  ) async {
    writer.fail = true;
    await editor(tester);
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    expect(writer.note, isNull);
    expect(reminders.scheduled, isEmpty);
  });

  testWidgets('autosave during a reminder write preserves metadata and text', (
    tester,
  ) async {
    final gate = Completer<void>();
    await editor(
      tester,
      note: Note.newDraft().copyWith(title: '原内容', revision: 1),
    );
    writer.updateGate = gate;
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byKey(const Key('quill-note-title')), '继续输入');
    await tester.pump(const Duration(seconds: 1));
    expect(writer.updateCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(writer.note?.title, '继续输入');
    expect(
      writer.note?.reminderAt,
      now.add(const Duration(minutes: 5)).toUtc(),
    );
    expect(writer.note?.revision, 3);
  });

  testWidgets('rechecks time after the system permission flow', (tester) async {
    var clock = now;
    reminders.pendingAccess = Completer<NoteReminderAccess>();
    await editor(tester, clock: () => clock);
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('confirm-note-reminder')));
    await tester.pumpAndSettle();
    clock = now.add(const Duration(hours: 1));
    reminders.pendingAccess!.complete(NoteReminderAccess.ready);
    await tester.pumpAndSettle();
    expect(writer.note, isNull);
    expect(find.text('请选择未来的提醒时间'), findsOneWidget);
  });

  testWidgets(
    'rejects past times and cancel does not change existing reminder',
    (tester) async {
      final at = now.add(const Duration(days: 1)).toUtc();
      await editor(
        tester,
        note: Note.newDraft().copyWith(
          title: '保留',
          revision: 1,
          reminderAt: at,
        ),
      );
      await openPicker(tester);
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(now.subtract(const Duration(minutes: 1)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-note-reminder')));
      await tester.pumpAndSettle();
      expect(find.text('请选择未来的提醒时间'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(writer.note?.reminderAt, at);
      expect(reminders.scheduled, isEmpty);
    },
  );

  testWidgets('picker fits a small screen with large text', (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: NoteReminderSheet(now: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('confirm-note-reminder')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an elapsed reminder shows only time and retains its full tooltip',
    (tester) async {
      await editor(
        tester,
        note: Note.newDraft().copyWith(
          title: '提醒记录',
          revision: 1,
          reminderAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      expect(find.text('14:25'), findsOneWidget);
      expect(find.textContaining('提醒时间：'), findsNothing);
      final reminder = find.byKey(const Key('editor-note-reminder'));
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: reminder, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, '2026年8月27日 14:25');
      expect(find.text('提醒时间已过'), findsNothing);
      expect(
        writer.note?.reminderAt,
        now.subtract(const Duration(minutes: 1)).toUtc(),
      );
    },
  );

  testWidgets(
    'a visible countdown switches to the exact historical time at its deadline',
    (tester) async {
      var clock = now;
      final at = now.add(const Duration(seconds: 20));
      await tester.pumpWidget(
        _app(NoteReminderIndicator(at: at, now: () => clock)),
      );
      expect(find.text('即将提醒'), findsOneWidget);
      clock = at;
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('14:26'), findsOneWidget);
      expect(find.textContaining('提醒时间：'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('relative labels include date/year and do not claim delivery', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      noteReminderLabel(now.add(const Duration(minutes: 1)), now, zh),
      '1分钟后',
    );
    expect(noteReminderLabel(now, now, zh), '14:26');
    expect(
      noteReminderLabel(now.add(const Duration(days: 1)), now, zh),
      '明天 14:26',
    );
    expect(
      noteReminderLabel(DateTime(2027, 1, 2, 10), now, zh),
      contains('2027'),
    );
    expect(
      noteReminderLabel(now.add(const Duration(minutes: 3)), now, en),
      'In 3 min',
    );
  });

  test(
    'past reminders use zero-padded local time across dates and locales',
    () {
      for (final locale in ['zh', 'en']) {
        final l10n = lookupAppLocalizations(Locale(locale));
        for (final at in [
          DateTime(2026, 8, 27, 9, 5),
          DateTime(2026, 8, 26, 9, 5),
          DateTime(2025, 1, 1, 9, 5),
        ]) {
          expect(noteReminderLabel(at.toUtc(), now, l10n), '09:05');
        }
      }
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

class _Writer implements NoteEditorWriter {
  Note? note;
  bool fail = false;
  Completer<void>? updateGate;
  var updateCalls = 0;
  @override
  Future<Note> create(Note value) async {
    if (fail) throw StateError('storage unavailable');
    return note = value.copyWith(revision: 1);
  }

  @override
  Future<Note> update(Note value) async {
    updateCalls++;
    await updateGate?.future;
    if (fail) throw StateError('storage unavailable');
    return note = value.copyWith(revision: value.revision + 1);
  }

  @override
  Future<void> deletePermanently(Note value) async {
    note = null;
  }
}

class _Reminders implements NoteReminderDriver {
  NoteReminderAccess access = NoteReminderAccess.ready;
  bool succeeds = true;
  bool capacityReached = false;
  Completer<NoteReminderAccess>? pendingAccess;
  final scheduled = <NoteId>[];
  @override
  Future<NoteReminderAccess> requestAccess() async =>
      pendingAccess == null ? access : pendingAccess!.future;
  @override
  Future<bool> schedule(NoteId id) async {
    scheduled.add(id);
    if (capacityReached) throw PlatformException(code: 'reminder_limit');
    return succeeds;
  }
}

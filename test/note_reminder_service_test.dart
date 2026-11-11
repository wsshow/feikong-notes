import 'package:fknotes/models/note.dart';
import 'package:fknotes/services/note_reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/note_reminders');
  late NoteReminderService service;
  late List<MethodCall> calls;
  String? pending;
  var fail = false;
  var access = 'ready';

  setUp(() {
    pending = null;
    fail = false;
    access = 'ready';
    calls = [];
    service = NoteReminderService(channel: channel, supported: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'takePendingNote') {
            final id = pending;
            pending = null;
            return id;
          }
          if (call.method == 'requestAccess') return access;
          if (call.method == 'syncNote') {
            if (fail) throw PlatformException(code: 'denied');
            return true;
          }
          return null;
        });
  });
  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'restores a cold-start notification and passes only IDs to scheduler',
    () async {
      final id = NoteId.generate();
      pending = id.value;
      await service.initialize('/internal/fknotes.db');
      expect(service.pendingNote.value, id);
      expect(await service.schedule(id), isTrue);
      expect(calls.last.arguments, {'id': id.value});
      expect(await service.requestAccess(), NoteReminderAccess.ready);
      access = 'exactAlarmDisabled';
      expect(
        await service.requestAccess(),
        NoteReminderAccess.exactAlarmDisabled,
      );
      await service.suspendForRestore();
      expect(calls.last.method, 'suspend');
    },
  );

  test('rejects malformed notification IDs', () async {
    pending = '../../private';
    await service.initialize('/internal/fknotes.db');
    expect(service.pendingNote.value, isNull);
  });

  test(
    'native scheduling failure cannot turn a committed save into a failed write',
    () async {
      await service.initialize('/internal/fknotes.db');
      fail = true;
      await service.noteChanged(NoteId.generate());
      await expectLater(
        service.schedule(NoteId.generate()),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'foreground resume reconciles reminders without requesting permission',
    () async {
      await service.initialize('/internal/fknotes.db');
      calls.clear();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), ['synchronize', 'takePendingNote']);
    },
  );

  test('iOS uses the native reminder bridge by default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ios = NoteReminderService(channel: channel);
    try {
      await ios.initialize('/internal/fknotes.db');
      expect(await ios.requestAccess(), NoteReminderAccess.ready);
      expect(await ios.schedule(NoteId.generate()), isTrue);
    } finally {
      ios.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('unsupported hosts neither initialize nor schedule', () async {
    final unsupported = NoteReminderService(channel: channel, supported: false);
    await unsupported.initialize('/internal/fknotes.db');
    expect(await unsupported.requestAccess(), NoteReminderAccess.unsupported);
    expect(await unsupported.schedule(NoteId.generate()), isFalse);
    expect(calls, isEmpty);
    unsupported.dispose();
  });
}

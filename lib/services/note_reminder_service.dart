import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/note.dart';

enum NoteReminderAccess {
  ready,
  notificationsDisabled,
  exactAlarmDisabled,
  unsupported,
}

abstract interface class NoteReminderDriver {
  Future<NoteReminderAccess> requestAccess();
  Future<bool> schedule(NoteId id);
}

/// Native schedulers own reminders; no running Flutter engine is needed.
/// Only IDs cross the bridge. iOS notifications never contain note content.
final class NoteReminderService
    with WidgetsBindingObserver
    implements NoteReminderDriver {
  NoteReminderService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('fknotes/note_reminders'),
      _supported =
          supported ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS));

  static final instance = NoteReminderService();
  final MethodChannel _channel;
  final bool _supported;
  final pendingNote = ValueNotifier<NoteId?>(null);
  bool _initialized = false;
  bool _observing = false;

  Future<void> initialize(String databasePath) async {
    if (!_supported) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'reminderOpened') await _takePendingNote();
      });
      await _channel.invokeMethod<void>('initialize', {
        'databasePath': databasePath,
      });
      _initialized = true;
      if (!_observing) {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
      await _takePendingNote();
    } on MissingPluginException {
      // Other Flutter hosts do not implement Android reminders.
    } on PlatformException {
      // Existing notes must remain usable if the OS cannot schedule alarms.
    }
  }

  Future<void> _takePendingNote() async {
    final value = await _channel.invokeMethod<String>('takePendingNote');
    if (value == null) return;
    try {
      pendingNote.value = NoteId.parse(value);
    } on FormatException {
      // Never route malformed external intent payloads.
    }
  }

  @override
  Future<NoteReminderAccess> requestAccess() async {
    if (!_supported) return NoteReminderAccess.unsupported;
    try {
      final value = await _channel.invokeMethod<String>('requestAccess');
      return NoteReminderAccess.values.firstWhere(
        (status) => status.name == value,
        orElse: () => NoteReminderAccess.unsupported,
      );
    } on MissingPluginException {
      return NoteReminderAccess.unsupported;
    }
  }

  @override
  Future<bool> schedule(NoteId id) async {
    if (!_supported || !_initialized) return false;
    return await _channel.invokeMethod<bool>('syncNote', {'id': id.value}) ??
        false;
  }

  /// Repository hook: a committed save must not be reported as a failed write
  /// if Android rejects scheduling. The explicit reminder UI checks separately.
  Future<void> noteChanged(NoteId id) async {
    try {
      await schedule(id);
    } on PlatformException catch (_) {
      debugPrint('Note reminder could not be synchronized.');
    } on MissingPluginException catch (_) {
      // Desktop/test hosts have no Android scheduler.
    }
  }

  Future<void> synchronize() async {
    if (!_initialized) return;
    try {
      await _channel.invokeMethod<void>('synchronize');
      await _takePendingNote();
    } on PlatformException catch (_) {
      debugPrint('Note reminders could not be synchronized.');
    } on MissingPluginException catch (_) {
      // Optional native integration.
    }
  }

  /// Suspend delivery while a restore swaps the authoritative database.
  Future<void> suspendForRestore() async {
    if (!_initialized) return;
    await _channel.invokeMethod<void>('suspend');
  }

  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    _initialized = false;
    _channel.setMethodCallHandler(null);
    pendingNote.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) synchronize();
  }
}

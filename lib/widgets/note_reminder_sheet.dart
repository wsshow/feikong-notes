import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';

final class NoteReminderSelection {
  const NoteReminderSelection(this.at);
  final DateTime? at;
}

final class NoteReminderSheet extends StatefulWidget {
  const NoteReminderSheet({this.initialTime, this.now, super.key});
  final DateTime? initialTime;
  final DateTime Function()? now;

  @override
  State<NoteReminderSheet> createState() => _NoteReminderSheetState();
}

final class _NoteReminderSheetState extends State<NoteReminderSheet> {
  late final DateTime _minimumDay;
  late DateTime _selected;
  String? _error;
  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toLocal();

  @override
  void initState() {
    super.initState();
    final now = _now;
    _minimumDay = DateTime(now.year, now.month, now.day);
    final initial = widget.initialTime?.toLocal();
    final candidate = initial != null && initial.isAfter(now)
        ? initial
        : now.add(const Duration(minutes: 5));
    _selected = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
      candidate.hour,
      candidate.minute,
    );
  }

  void _confirm() {
    if (!_selected.isAfter(_now)) {
      setState(() => _error = context.l10n.reminderChooseFuture);
      return;
    }
    Navigator.pop(context, NoteReminderSelection(_selected.toUtc()));
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.reminderDateTime,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat.yMMMd(locale).add_Hm().format(_selected),
              key: const Key('reminder-selected-time'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(context).brightness,
                  primaryColor: context.appColors.accent,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 19,
                    ),
                  ),
                ),
                child: SizedBox(
                  height: 200,
                  child: CupertinoDatePicker(
                    key: const Key('note-reminder-picker'),
                    mode: CupertinoDatePickerMode.dateAndTime,
                    initialDateTime: _selected,
                    minimumDate: _minimumDay,
                    use24hFormat: true,
                    itemExtent: 42,
                    onDateTimeChanged: (value) => setState(() {
                      _selected = value;
                      _error = null;
                    }),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.appColors.danger),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('confirm-note-reminder'),
                    onPressed: _confirm,
                    child: Text(context.l10n.reminderConfirm),
                  ),
                ),
              ],
            ),
            if (widget.initialTime != null)
              TextButton(
                key: const Key('remove-note-reminder'),
                onPressed: () =>
                    Navigator.pop(context, const NoteReminderSelection(null)),
                child: Text(
                  context.l10n.removeNoteReminder,
                  style: TextStyle(color: context.appColors.muted),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? context.l10n.iosReminderPermissionHint
                  : context.l10n.reminderPermissionHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.appColors.subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

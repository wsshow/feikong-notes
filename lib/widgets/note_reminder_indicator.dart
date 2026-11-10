import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

String noteReminderLabel(DateTime at, DateTime now, AppLocalizations l10n) {
  final remaining = at.difference(now);
  if (remaining <= Duration.zero) {
    // Keep the metadata row compact; the tooltip and semantics retain the date.
    return DateFormat.Hm(l10n.localeName).format(at.toLocal());
  }
  if (remaining.inSeconds < 60) return l10n.reminderSoon;
  if (remaining.inMinutes < 60) {
    return l10n.reminderInMinutes((remaining.inSeconds / 60).ceil());
  }
  final local = at.toLocal();
  final today = now.toLocal();
  final time = DateFormat.Hm(l10n.localeName).format(local);
  final day = DateTime(local.year, local.month, local.day);
  final currentDay = DateTime(today.year, today.month, today.day);
  if (day == currentDay) return l10n.reminderToday(time);
  if (day == DateTime(today.year, today.month, today.day + 1)) {
    return l10n.reminderTomorrow(time);
  }
  return (local.year == today.year
          ? DateFormat.Md(l10n.localeName)
          : DateFormat.yMd(l10n.localeName))
      .add_Hm()
      .format(local);
}

/// Relative text is refreshed even while an editor/list stays open.
final class NoteReminderIndicator extends StatefulWidget {
  const NoteReminderIndicator({
    required this.at,
    this.onTap,
    this.now,
    this.textColor,
    super.key,
  });
  final DateTime at;
  final VoidCallback? onTap;
  final DateTime Function()? now;
  final Color? textColor;

  @override
  State<NoteReminderIndicator> createState() => _NoteReminderIndicatorState();
}

final class _NoteReminderIndicatorState extends State<NoteReminderIndicator>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleTick();
  }

  void _scheduleTick() {
    _timer?.cancel();
    final remaining = widget.at.difference(
      widget.now?.call() ?? DateTime.now(),
    );
    if (remaining <= Duration.zero) return;
    final delay = remaining < const Duration(seconds: 30)
        ? remaining
        : const Duration(seconds: 30);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void didUpdateWidget(NoteReminderIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleTick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = noteReminderLabel(
      widget.at,
      widget.now?.call() ?? DateTime.now(),
      context.l10n,
    );
    final absolute = DateFormat.yMMMd(
      context.l10n.localeName,
    ).add_Hm().format(widget.at.toLocal());
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          Icons.alarm_outlined,
          size: 15,
          color: context.appColors.subtle,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: widget.textColor ?? context.appColors.muted,
            ),
          ),
        ),
      ],
    );
    return Tooltip(
      message: absolute,
      child: widget.onTap == null
          ? content
          : Semantics(
              label: '${context.l10n.editNoteReminder} · $absolute',
              button: true,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: content,
                ),
              ),
            ),
    );
  }
}

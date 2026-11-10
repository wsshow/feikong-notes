import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import 'app_icon.dart';

enum AppFeedbackTone { info, success, error }

/// Presents app-wide feedback without covering the page's working area.
///
/// Messages that belong to a field or control should be rendered beside that
/// control instead. [action] is reserved for short, reversible operations and
/// is the only feedback that uses a bottom snackbar.
class AppFeedback {
  AppFeedback._();

  static final Expando<_FeedbackSession> _sessions =
      Expando<_FeedbackSession>();

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackTone tone = AppFeedbackTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final prepared = _prepare(context, message);
    if (prepared == null) return;
    final (:messenger, session: _) = prepared;
    final colors = _FeedbackColors.forTone(context, tone);

    final actions = <Widget>[
      if (actionLabel != null && onAction != null)
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            onAction();
          },
          child: Text(actionLabel),
        ),
      _BannerDismissAction(
        duration:
            duration ??
            (tone == AppFeedbackTone.error
                ? const Duration(seconds: 8)
                : const Duration(milliseconds: 2600)),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onDismiss: messenger.hideCurrentMaterialBanner,
        color: colors.foreground,
      ),
    ];

    messenger.showMaterialBanner(
      MaterialBanner(
        key: const Key('app-feedback'),
        elevation: 0,
        backgroundColor: colors.background,
        dividerColor: colors.border,
        leading: AppIcon(colors.icon, size: 20, color: colors.foreground),
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 12),
        leadingPadding: const EdgeInsetsDirectional.only(end: 12),
        content: Text(
          message,
          style: TextStyle(
            color: colors.foreground,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        actions: actions,
      ),
    );
  }

  static void dismiss(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..removeCurrentMaterialBanner()
      ..removeCurrentSnackBar();
  }

  static void success(BuildContext context, String message) =>
      show(context, message, tone: AppFeedbackTone.success);

  static void error(BuildContext context, String message) =>
      show(context, message, tone: AppFeedbackTone.error);

  /// Shows a brief bottom message for an operation the user can undo.
  static void action(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final prepared = _prepare(context, message);
    if (prepared == null) return;
    final (:messenger, session: _) = prepared;
    final colors = _FeedbackColors.forTone(context, AppFeedbackTone.info);
    messenger.showSnackBar(
      SnackBar(
        key: const Key('app-feedback-action'),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        dismissDirection: DismissDirection.horizontal,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 5),
        backgroundColor: colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.appRadii.large),
          side: BorderSide(color: colors.border),
        ),
        content: Text(message, style: TextStyle(color: colors.foreground)),
        action: SnackBarAction(
          label: actionLabel,
          textColor: colors.foreground,
          onPressed: onAction,
        ),
      ),
    );
  }

  static ({ScaffoldMessengerState messenger, _FeedbackSession session})?
  _prepare(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final normalized = message.trim();
    if (messenger == null || normalized.isEmpty) return null;

    final session = _sessions[messenger] ??= _FeedbackSession();
    final now = DateTime.now();
    if (session.message == normalized &&
        now.difference(session.shownAt) < const Duration(milliseconds: 800)) {
      return null;
    }
    session.message = normalized;
    session.shownAt = now;
    messenger
      ..removeCurrentMaterialBanner()
      ..removeCurrentSnackBar();
    return (messenger: messenger, session: session);
  }
}

class _FeedbackSession {
  String message = '';
  DateTime shownAt = DateTime.fromMillisecondsSinceEpoch(0);
}

class _BannerDismissAction extends StatefulWidget {
  final Duration duration;
  final String tooltip;
  final VoidCallback onDismiss;
  final Color color;

  const _BannerDismissAction({
    required this.duration,
    required this.tooltip,
    required this.onDismiss,
    required this.color,
  });

  @override
  State<_BannerDismissAction> createState() => _BannerDismissActionState();
}

class _BannerDismissActionState extends State<_BannerDismissAction> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.tooltip,
    onPressed: widget.onDismiss,
    color: widget.color,
    iconSize: 20,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: const AppIcon(Icons.close),
  );
}

class _FeedbackColors {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _FeedbackColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });

  static _FeedbackColors forTone(BuildContext context, AppFeedbackTone tone) =>
      switch (tone) {
        AppFeedbackTone.info => _FeedbackColors(
          background: context.appColors.surface,
          foreground: context.appColors.ink,
          border: context.appColors.line,
          icon: Icons.info_outline_rounded,
        ),
        AppFeedbackTone.success => _FeedbackColors(
          background: context.appColors.successSoft,
          foreground: context.appColors.success,
          border: context.appColors.line,
          icon: Icons.check_circle_outline_rounded,
        ),
        AppFeedbackTone.error => _FeedbackColors(
          background: context.appColors.dangerSoft,
          foreground: context.appColors.danger,
          border: context.appColors.danger,
          icon: Icons.error_outline_rounded,
        ),
      };
}

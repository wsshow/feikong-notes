import 'package:flutter/widgets.dart';

import '../providers/private_notes_controller.dart';

/// All private destinations and overlays inherit the same visit authorization.
class PrivateNotesScope extends InheritedWidget {
  const PrivateNotesScope({
    required this.session,
    required super.child,
    super.key,
  });

  final PrivateNotesController session;

  static PrivateNotesController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PrivateNotesScope>()?.session;

  @override
  bool updateShouldNotify(PrivateNotesScope oldWidget) =>
      session != oldWidget.session;
}

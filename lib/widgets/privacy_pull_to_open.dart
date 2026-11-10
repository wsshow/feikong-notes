import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

/// Deliberate pull from the top; ballistic overscroll and ordinary list
/// scrolling cannot open the private space. The callback runs only on release.
final class PrivacyPullToOpen extends StatefulWidget {
  const PrivacyPullToOpen({
    required this.child,
    required this.onOpen,
    this.enabled = true,
    super.key,
  });

  static const triggerDistance = 320.0;
  final Widget child;
  final Future<void> Function() onOpen;
  final bool enabled;

  @override
  State<PrivacyPullToOpen> createState() => _PrivacyPullToOpenState();
}

final class _PrivacyPullToOpenState extends State<PrivacyPullToOpen> {
  double _distance = 0;
  bool _draggingFromTop = false;
  bool _opening = false;

  @override
  void didUpdateWidget(covariant PrivacyPullToOpen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _distance = 0;
      _draggingFromTop = false;
    }
  }

  Future<void> _open() async {
    if (_opening || !widget.enabled) return;
    setState(() {
      _opening = true;
      _distance = 0;
    });
    try {
      await widget.onOpen();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (!widget.enabled || _opening) return false;
    if (notification is ScrollStartNotification) {
      _draggingFromTop =
          notification.dragDetails != null &&
          notification.metrics.extentBefore == 0;
      if (_distance != 0) setState(() => _distance = 0);
    } else if (_draggingFromTop &&
        notification is OverscrollNotification &&
        notification.dragDetails != null) {
      final wasReady = _distance >= PrivacyPullToOpen.triggerDistance;
      setState(
        () => _distance = (_distance - notification.overscroll).clamp(
          0,
          PrivacyPullToOpen.triggerDistance + 48,
        ),
      );
      if (!wasReady && _distance >= PrivacyPullToOpen.triggerDistance) {
        unawaited(HapticFeedback.lightImpact());
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.extentBefore > 0) {
      _draggingFromTop = false;
      if (_distance != 0) setState(() => _distance = 0);
    } else if (notification is ScrollEndNotification) {
      final open =
          _draggingFromTop && _distance >= PrivacyPullToOpen.triggerDistance;
      _draggingFromTop = false;
      setState(() => _distance = 0);
      if (open) unawaited(_open());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the natural pull space, but reveal its purpose only at the threshold.
    final ready = _distance >= PrivacyPullToOpen.triggerDistance;
    final offset = _opening ? 64.0 : math.min(_distance * .55, 144.0);
    return Semantics(
      customSemanticsActions: widget.enabled
          ? {
              CustomSemanticsAction(label: context.l10n.openPrivateNotes): () =>
                  unawaited(_open()),
            }
          : null,
      child: Listener(
        onPointerCancel: (_) {
          _draggingFromTop = false;
          if (_distance != 0) setState(() => _distance = 0);
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ClipRect(
            child: Stack(
              children: [
                if (_opening || ready)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: offset,
                    child: Row(
                      key: const Key('privacy-pull-hint'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: context.appColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _opening
                                ? context.l10n.authenticationInProgress
                                : context.l10n.releaseForPrivateNotes,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.appColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Transform.translate(
                  offset: Offset(0, offset),
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

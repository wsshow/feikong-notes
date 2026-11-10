import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// Keeps Material's keyboard, focus and tap semantics while styling the single
/// primary action. Transform feedback never changes the surrounding layout.
class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_updatePressed);
  }

  void _updatePressed() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updatePressed();
      });
    } else if (mounted) {
      setState(() => _pressed = pressed);
    }
  }

  @override
  void dispose() {
    _states.removeListener(_updatePressed);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final components = context.appComponents;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pressed = _pressed;
    final enabled = widget.onPressed != null;
    return AnimatedScale(
      scale: pressed && !reduceMotion ? .98 : 1,
      duration: reduceMotion ? Duration.zero : AppMotion.press,
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.appRadii.button),
          boxShadow: enabled && components.primaryButtonShadowOpacity > 0
              ? colors.floatingShadows
              : null,
        ),
        child: FilledButton.icon(
          clipBehavior: Clip.antiAlias,
          statesController: _states,
          onPressed: widget.onPressed,
          icon: widget.icon,
          label: widget.label,
          style:
              FilledButton.styleFrom(
                foregroundColor: colors.onStrong,
                backgroundColor: colors.primaryFill,
                disabledForegroundColor: colors.subtle,
                disabledBackgroundColor: colors.surfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.appRadii.button),
                ),
              ).copyWith(
                animationDuration: reduceMotion
                    ? Duration.zero
                    : AppMotion.press,
                backgroundBuilder: (context, states, child) => Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      context.appRadii.button,
                    ),
                    color: enabled
                        ? (pressed ? colors.accentPressed : colors.primaryFill)
                        : colors.surfaceMuted,
                    gradient: enabled ? colors.primaryGradient : null,
                  ),
                  child: ColoredBox(
                    color:
                        pressed &&
                            enabled &&
                            components.primaryPressedOverlayUsesForeground
                        ? colors.accentPressed.withValues(alpha: .35)
                        : Colors.transparent,
                    child: child,
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

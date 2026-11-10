import 'package:flutter/material.dart';
import 'private_notes_scope.dart';

/// Theme-aware entrance for application-owned modal surfaces.
///
/// Keeping route creation here ensures every feature inherits the active
/// dialog and sheet themes, honors reduced motion, and can gain a new theme's
/// presentation behavior without editing each call site.
abstract final class AppOverlay {
  /// An input form hands focus directly to its autofocus field. Letting the
  /// route focus its empty scope first would close and reopen an existing IME.
  /// The builder must autofocus a field or request its input FocusNode.
  static Future<T?> inputSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) => bottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    requestFocus: false,
    builder: builder,
  );

  static Future<T?> dialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    bool useSafeArea = true,
    bool useRootNavigator = true,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
    TraversalEdgeBehavior? traversalEdgeBehavior,
    bool fullscreenDialog = false,
    bool? requestFocus,
    AnimationStyle? animationStyle,
  }) => showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator:
        useRootNavigator && PrivateNotesScope.maybeOf(context) == null,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: _animationStyle(context, animationStyle),
  );

  static Future<T?> bottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    String? barrierLabel,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    Color? barrierColor,
    bool isScrollControlled = false,
    double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
    bool useRootNavigator = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool? showDragHandle,
    bool useSafeArea = false,
    RouteSettings? routeSettings,
    AnimationController? transitionAnimationController,
    Offset? anchorPoint,
    AnimationStyle? sheetAnimationStyle,
    bool? requestFocus,
  }) => showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator:
        useRootNavigator && PrivateNotesScope.maybeOf(context) == null,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: _animationStyle(context, sheetAnimationStyle),
    requestFocus: requestFocus,
  );

  static AnimationStyle? _animationStyle(
    BuildContext context,
    AnimationStyle? requested,
  ) => MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : requested;
}

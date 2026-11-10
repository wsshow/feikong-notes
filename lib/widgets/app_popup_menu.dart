import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import 'app_icon.dart';

class AppMenuAction<T> {
  final T value;
  final IconData? icon;
  final String label;
  final bool enabled;
  final bool selected;
  final bool destructive;

  const AppMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
  });
}

/// A lightweight action menu with a consistent floating surface.
///
/// Positioning uses the panel's actual laid-out size, leaving room around the
/// trigger, screen edges and keyboard. Long menus scroll within that space.
class AppAnchoredMenuButton<T> extends StatefulWidget {
  final String tooltip;
  final List<AppMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final Widget? icon;
  final Widget? child;
  final BorderRadius borderRadius;

  const AppAnchoredMenuButton({
    super.key,
    required this.tooltip,
    required this.actions,
    required this.onSelected,
    this.enabled = true,
    this.icon,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) : assert(icon == null || child == null);

  @override
  State<AppAnchoredMenuButton<T>> createState() =>
      _AppAnchoredMenuButtonState<T>();
}

class _AppAnchoredMenuButtonState<T> extends State<AppAnchoredMenuButton<T>> {
  final _controller = MenuController();
  final _scrollController = ScrollController(keepScrollOffset: false);
  LocalHistoryEntry? _historyEntry;
  bool _disposing = false;
  bool _keyboardOpened = false;

  @override
  void didUpdateWidget(covariant AppAnchoredMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.enabled || widget.actions.isEmpty) && _controller.isOpen) {
      _controller.close();
    }
  }

  void _toggle() {
    if (!widget.enabled || widget.actions.isEmpty) return;
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _keyboardOpened =
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
      _controller.open();
    }
  }

  void _didOpen() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    _historyEntry = LocalHistoryEntry(
      impliesAppBarDismissal: false,
      onRemove: () {
        _historyEntry = null;
        if (!_disposing && mounted && _controller.isOpen) _controller.close();
      },
    );
    route.addLocalHistoryEntry(_historyEntry!);
  }

  void _didClose() {
    final entry = _historyEntry;
    _historyEntry = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _disposing = true;
    _didClose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: _controller,
    useRootOverlay: true,
    consumeOutsideTaps: true,
    onOpen: _didOpen,
    onClose: _didClose,
    overlayBuilder: _buildOverlay,
    builder: (context, controller, _) => _buildTrigger(),
  );

  Widget _buildOverlay(BuildContext context, RawMenuOverlayInfo info) {
    return BlockSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ModalBarrier(
              color: context.appColors.shadow.withValues(alpha: .06),
              onDismiss: _controller.close,
              semanticsLabel: MaterialLocalizations.of(
                context,
              ).modalBarrierDismissLabel,
            ),
          ),
          CustomSingleChildLayout(
            delegate: _AppMenuLayout(
              anchor: info.anchorRect,
              media: MediaQuery.of(context),
              textDirection: Directionality.of(context),
            ),
            child: TapRegion(
              groupId: info.tapRegionGroupId,
              consumeOutsideTaps: true,
              onTapOutside: (_) => _controller.close(),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: widget.tooltip,
                child: FocusScope(
                  child: FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(),
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            NextFocusIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            PreviousFocusIntent(),
                        SingleActivator(LogicalKeyboardKey.escape):
                            DismissIntent(),
                      },
                      child: Actions(
                        actions: {
                          DismissIntent: CallbackAction<DismissIntent>(
                            onInvoke: (_) {
                              _controller.close();
                              return null;
                            },
                          ),
                        },
                        child: _buildPanel(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final firstEnabled = widget.actions.indexWhere((action) => action.enabled);
    return IntrinsicWidth(
      child: Material(
        color: context.appColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppMenuTokens.elevation,
        shadowColor: context.appColors.shadow.withValues(alpha: .16),
        shape: AppMenuTokens.shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: AppMenuTokens.padding,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false, scrollbars: false),
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < widget.actions.length; index++)
                      _item(
                        widget.actions[index],
                        autofocus: _keyboardOpened && index == firstEnabled,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrigger() {
    final enabled = widget.enabled && widget.actions.isNotEmpty;
    if (widget.icon != null) {
      return IconButton(
        tooltip: widget.tooltip,
        onPressed: enabled ? _toggle : null,
        icon: widget.icon!,
      );
    }
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? _toggle : null,
          borderRadius: widget.borderRadius,
          child: widget.child ?? const SizedBox(width: 48, height: 48),
        ),
      ),
    );
  }

  Widget _item(AppMenuAction<T> action, {required bool autofocus}) {
    final color = action.destructive
        ? context.appColors.danger
        : context.appColors.ink;
    return Semantics(
      selected: action.selected,
      child: MenuItemButton(
        semanticsLabel: action.label,
        overflowAxis: Axis.vertical,
        autofocus: autofocus,
        onPressed: action.enabled
            ? () {
                _controller.close();
                widget.onSelected(action.value);
              }
            : null,
        leadingIcon: action.icon == null
            ? null
            : AppIcon(action.icon, size: 20),
        trailingIcon: action.selected
            ? const AppIcon(Icons.check_rounded, size: 18)
            : null,
        style: MenuItemButton.styleFrom(
          foregroundColor: color,
          iconColor: action.destructive || action.selected
              ? color
              : context.appColors.muted,
          disabledForegroundColor: context.appColors.subtle,
          disabledIconColor: context.appColors.subtle,
          backgroundColor: action.selected
              ? context.appColors.surfaceMuted
              : null,
          minimumSize: const Size(0, AppMenuTokens.itemHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.appRadii.medium),
          ),
          visualDensity: VisualDensity.standard,
          textStyle: AppMenuTokens.textStyle,
        ),
        child: Text(action.label),
      ),
    );
  }
}

class _AppMenuLayout extends SingleChildLayoutDelegate {
  const _AppMenuLayout({
    required this.anchor,
    required this.media,
    required this.textDirection,
  });

  final Rect anchor;
  final MediaQueryData media;
  final TextDirection textDirection;

  Rect _safeBounds(Size size) => Rect.fromLTRB(
    math.max(media.padding.left, media.viewInsets.left) +
        AppMenuTokens.edgeInset,
    math.max(media.padding.top, media.viewInsets.top) + AppMenuTokens.edgeInset,
    size.width -
        math.max(media.padding.right, media.viewInsets.right) -
        AppMenuTokens.edgeInset,
    size.height -
        math.max(media.padding.bottom, media.viewInsets.bottom) -
        AppMenuTokens.edgeInset,
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _safeBounds(constraints.biggest);
    final width = math.max(0.0, math.min(AppMenuTokens.maxWidth, bounds.width));
    final above = anchor.top - AppMenuTokens.anchorGap - bounds.top;
    final below = bounds.bottom - anchor.bottom - AppMenuTokens.anchorGap;
    return BoxConstraints(
      minWidth: math.min(AppMenuTokens.minWidth, width),
      maxWidth: width,
      maxHeight: math.max(0.0, math.min(bounds.height, math.max(above, below))),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _safeBounds(size);
    final left = textDirection == TextDirection.ltr
        ? anchor.left
        : anchor.right - childSize.width;
    final below = anchor.bottom + AppMenuTokens.anchorGap;
    final top = below + childSize.height <= bounds.bottom
        ? below
        : anchor.top - AppMenuTokens.anchorGap - childSize.height;
    return Offset(
      left.clamp(
        bounds.left,
        math.max(bounds.left, bounds.right - childSize.width),
      ),
      top.clamp(
        bounds.top,
        math.max(bounds.top, bounds.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_AppMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      media != oldDelegate.media ||
      textDirection != oldDelegate.textDirection;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_icon.dart';

/// A compact copy action that confirms success in place instead of opening a
/// global message over unrelated content.
class AppCopyButton extends StatefulWidget {
  final String text;
  final String copyTooltip;
  final String copiedTooltip;
  final double dimension;
  final double iconSize;
  final Color? color;

  const AppCopyButton({
    super.key,
    required this.text,
    required this.copyTooltip,
    required this.copiedTooltip,
    this.dimension = 34,
    this.iconSize = 17,
    this.color,
  });

  @override
  State<AppCopyButton> createState() => _AppCopyButtonState();
}

class _AppCopyButtonState extends State<AppCopyButton> {
  Timer? _reset;
  bool _copied = false;

  @override
  void didUpdateWidget(covariant AppCopyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _clear();
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _clear() {
    _reset?.cancel();
    _reset = null;
    if (_copied && mounted) setState(() => _copied = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.dimension,
    child: IconButton(
      tooltip: _copied ? widget.copiedTooltip : widget.copyTooltip,
      onPressed: widget.text.isEmpty ? null : _copy,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: Size.square(widget.dimension),
        maximumSize: Size.square(widget.dimension),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: AppIcon(
          _copied ? Icons.check_rounded : Icons.content_copy_rounded,
          key: ValueKey(_copied),
          size: widget.iconSize,
          color: widget.color,
        ),
      ),
    ),
  );
}

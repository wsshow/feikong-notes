import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A per-operation lease. iOS foreground work must release resources before
/// suspension; transient inactive states (permission sheets) do not interrupt it.
final class IosForegroundWork with WidgetsBindingObserver {
  IosForegroundWork({required this.onSuspend, bool? enabled})
    : _enabled =
          enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (!_enabled) return;
    final binding = WidgetsBinding.instance;
    interrupted = shouldSuspend(binding.lifecycleState);
    binding.addObserver(this);
  }

  final VoidCallback onSuspend;
  final bool _enabled;
  bool interrupted = false;
  bool _disposed = false;

  static bool shouldSuspend(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || _disposed || interrupted || !shouldSuspend(state)) return;
    interrupted = true;
    onSuspend();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_enabled) WidgetsBinding.instance.removeObserver(this);
  }
}

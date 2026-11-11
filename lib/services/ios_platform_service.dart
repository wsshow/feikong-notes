import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native data policy and app-switcher shield. The shield is released only
/// after Flutter has painted its resumed frame (including authentication gates).
final class IosPlatformService with WidgetsBindingObserver {
  IosPlatformService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('fknotes/ios_platform'),
      _supported =
          supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  static final instance = IosPlatformService();
  final MethodChannel _channel;
  final bool _supported;
  bool _observing = false;

  Future<void> initialize() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('configureStorage');
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_supported || !_observing || state != AppLifecycleState.resumed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_observing ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      unawaited(_channel.invokeMethod<void>('privacyReady'));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }
}

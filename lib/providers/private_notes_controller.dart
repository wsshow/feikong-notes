import 'package:flutter/widgets.dart';

import '../services/device_authentication_service.dart';

/// A short-lived, independent authorization for one private-space visit.
/// App-lock preferences and previous app unlocks never authorize this session.
final class PrivateNotesController extends ChangeNotifier
    with WidgetsBindingObserver {
  PrivateNotesController({
    DeviceAuthenticator? authenticator,
    bool observeLifecycle = true,
  }) : _authenticator = authenticator ?? SystemDeviceAuthenticator.instance,
       _observesLifecycle = observeLifecycle {
    if (_observesLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final DeviceAuthenticator _authenticator;
  final bool _observesLifecycle;
  bool _locked = true;
  bool _obscured = false;
  bool _authenticating = false;
  bool _disposed = false;
  int _generation = 0;
  DeviceAuthenticationResult? _lastResult;
  PrivateNotesController? _authorizationSource;
  int? _sourceGeneration;

  bool get locked => _locked;
  bool get obscured => _obscured;
  bool get protected => _locked || _obscured;
  int get authorizationGeneration => _generation;
  bool get authenticating => _authenticating;
  DeviceAuthenticationResult? get lastResult => _lastResult;
  bool get hasWorkspaceAuthorization =>
      !protected &&
      _authorizationSource != null &&
      !_authorizationSource!.protected;

  /// Reuses an already authenticated workspace visit, without another prompt.
  /// The derived grant expires as soon as that visit locks or is disposed.
  void followSession(PrivateNotesController source) {
    if (identical(source, this) || identical(source, _authorizationSource)) {
      return;
    }
    _authorizationSource?.removeListener(_followAuthorization);
    _authorizationSource = source;
    _sourceGeneration = null;
    source.addListener(_followAuthorization);
    _followAuthorization();
  }

  void _followAuthorization() {
    final source = _authorizationSource;
    if (_disposed || source == null) return;
    if (_sourceGeneration == source.authorizationGeneration &&
        _locked == source.locked &&
        _obscured == source.obscured) {
      return;
    }
    _sourceGeneration = source.authorizationGeneration;
    _generation++;
    _locked = source.locked;
    _obscured = source.obscured;
    notifyListeners();
  }

  Future<DeviceAuthenticationResult> unlock({
    required DeviceAuthenticationPrompt prompt,
  }) async {
    if (_disposed || _authenticating) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '',
      );
    }
    final generation = ++_generation;
    _authenticating = true;
    _lastResult = null;
    notifyListeners();
    DeviceAuthenticationResult result;
    try {
      result = await _authenticator.isSupported()
          ? await _authenticator.authenticate(prompt: prompt)
          : const DeviceAuthenticationResult(
              DeviceAuthenticationStatus.unavailable,
              '',
              messageId: DeviceAuthenticationMessage.credentialsRequired,
            );
    } catch (_) {
      result = const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.failed,
        '',
        messageId: DeviceAuthenticationMessage.temporarilyUnavailable,
      );
    }
    if (_disposed) {
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '',
      );
    }
    _authenticating = false;
    if (generation != _generation) {
      notifyListeners();
      return const DeviceAuthenticationResult(
        DeviceAuthenticationStatus.canceled,
        '',
      );
    }
    _lastResult = result;
    _locked = !result.authenticated;
    notifyListeners();
    return result;
  }

  void lock() {
    if (_disposed) return;
    _generation++;
    _locked = true;
    _lastResult = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _obscured = false;
      case AppLifecycleState.inactive:
        _obscured = true;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _obscured = true;
        // Android device-credential UI can itself pause the activity. Keep
        // its result valid, but never uncover content until the app resumes.
        if (!_authenticating) {
          _generation++;
          _locked = true;
        }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authorizationSource?.removeListener(_followAuthorization);
    _authorizationSource = null;
    lock();
    _disposed = true;
    _generation++;
    if (_observesLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

import 'dart:async';

import 'package:fknotes/providers/private_notes_controller.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _prompt = DeviceAuthenticationPrompt(reason: '解锁隐私笔记');
const _success = DeviceAuthenticationResult(
  DeviceAuthenticationStatus.authenticated,
  '',
);

void main() {
  test('AI shares the visit grant and loses it on lock or disposal', () async {
    final auth = _Authenticator();
    final visit = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    final agent = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(agent.dispose);
    await visit.unlock(prompt: _prompt);
    agent.followSession(visit);
    expect(agent.protected, isFalse);
    expect(auth.calls, 1);
    final generation = agent.authorizationGeneration;
    agent.followSession(visit);
    expect(agent.authorizationGeneration, generation);
    visit.lock();
    expect(agent.protected, isTrue);
    expect(agent.authorizationGeneration, greaterThan(generation));
    await visit.unlock(prompt: _prompt);
    expect(agent.protected, isFalse);
    visit.dispose();
    expect(agent.protected, isTrue);
  });
  test(
    'each visit authenticates independently of application preferences',
    () async {
      final auth = _Authenticator();
      for (var visit = 0; visit < 2; visit++) {
        final session = PrivateNotesController(
          authenticator: auth,
          observeLifecycle: false,
        );
        expect(session.protected, isTrue);
        expect((await session.unlock(prompt: _prompt)).authenticated, isTrue);
        expect(session.protected, isFalse);
        session.dispose();
      }
      expect(auth.calls, 2);
    },
  );

  test('cancellation, failure and missing credentials fail closed', () async {
    final auth = _Authenticator();
    final session = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(session.dispose);
    for (final status in DeviceAuthenticationStatus.values) {
      if (status == DeviceAuthenticationStatus.authenticated) continue;
      auth.result = DeviceAuthenticationResult(status, '');
      await session.unlock(prompt: _prompt);
      expect(session.protected, isTrue);
    }
    auth.supported = false;
    final calls = auth.calls;
    final result = await session.unlock(prompt: _prompt);
    expect(result.messageId, DeviceAuthenticationMessage.credentialsRequired);
    expect(auth.calls, calls);
    expect(session.protected, isTrue);
  });

  test('an exception cannot unlock the space', () async {
    final auth = _Authenticator()..throwError = true;
    final session = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(session.dispose);
    final result = await session.unlock(prompt: _prompt);
    expect(result.authenticated, isFalse);
    expect(session.protected, isTrue);
    expect(session.authenticating, isFalse);
  });

  test('background locks immediately and resume never auto-unlocks', () async {
    final auth = _Authenticator();
    final session = PrivateNotesController(
      authenticator: auth,
      observeLifecycle: false,
    );
    addTearDown(session.dispose);
    await session.unlock(prompt: _prompt);
    session.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(session.obscured, isTrue);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    session.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(session.obscured, isFalse);
    expect(session.locked, isTrue);
    expect(auth.calls, 1);
    await session.unlock(prompt: _prompt);
    expect(session.protected, isFalse);
    expect(auth.calls, 2);
  });

  test(
    'system credential activity may pause without invalidating its result',
    () async {
      final pending = Completer<DeviceAuthenticationResult>();
      final auth = _Authenticator()..pending = pending;
      final session = PrivateNotesController(
        authenticator: auth,
        observeLifecycle: false,
      );
      addTearDown(session.dispose);
      final request = session.unlock(prompt: _prompt);
      await Future<void>.delayed(Duration.zero);
      expect(session.authenticating, isTrue);
      session.didChangeAppLifecycleState(AppLifecycleState.inactive);
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      pending.complete(_success);
      await request;
      expect(session.protected, isTrue);
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(session.protected, isFalse);
    },
  );

  test(
    'concurrent attempts share no permission and stale success is discarded',
    () async {
      final pending = Completer<DeviceAuthenticationResult>();
      final auth = _Authenticator()..pending = pending;
      final session = PrivateNotesController(
        authenticator: auth,
        observeLifecycle: false,
      );
      addTearDown(session.dispose);
      final request = session.unlock(prompt: _prompt);
      final duplicate = await session.unlock(prompt: _prompt);
      expect(duplicate.authenticated, isFalse);
      expect(auth.calls, 1);
      session.lock();
      pending.complete(_success);
      expect((await request).authenticated, isFalse);
      expect(session.protected, isTrue);
    },
  );

  test(
    'a completed request after disposal cannot authorize another route',
    () async {
      final pending = Completer<DeviceAuthenticationResult>();
      final session = PrivateNotesController(
        authenticator: _Authenticator()..pending = pending,
        observeLifecycle: false,
      );
      final request = session.unlock(prompt: _prompt);
      await Future<void>.delayed(Duration.zero);
      session.dispose();
      pending.complete(_success);
      expect((await request).authenticated, isFalse);
    },
  );
}

final class _Authenticator implements DeviceAuthenticator {
  bool supported = true;
  bool throwError = false;
  int calls = 0;
  DeviceAuthenticationResult result = _success;
  Completer<DeviceAuthenticationResult>? pending;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required DeviceAuthenticationPrompt prompt,
  }) async {
    calls++;
    if (throwError) throw StateError('authentication unavailable');
    return pending == null ? result : await pending!.future;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_lock_controller.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/device_authentication_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLockController>();
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.appLock)),
      body: PaperShell(
        child: Material(
          color: Colors.transparent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Text(
                l.systemAuthenticationDescription,
                style: TextStyle(color: context.appColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              InsetSettingsSection(
                title: l.systemAuthentication,
                children: [
                  InsetSettingsSwitchRow(
                    rowKey: const Key('app-lock-enabled-switch'),
                    value: controller.enabled,
                    onChanged: _busy ? null : _setEnabled,
                    title: l.enableAppLock,
                    subtitle: controller.enabled
                        ? l.appLockEnabledDescription
                        : l.appLockDisabledDescription,
                  ),
                ],
              ),
              if (controller.enabled) ...[
                const SizedBox(height: 22),
                InsetSettingsSection(
                  title: l.autoLockAfterLeaving,
                  children: [
                    for (final timeout in AppLockTimeout.values)
                      InsetSettingsRow(
                        title: _timeoutLabel(l, timeout),
                        selected: controller.timeout == timeout,
                        enabled: !_busy,
                        showDisclosure: false,
                        onTap: () => _setTimeout(timeout),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                InsetSettingsSection(
                  children: [
                    InsetSettingsRow(
                      rowKey: const Key('app-lock-lock-now-button'),
                      title: l.lockNow,
                      enabled: !_busy,
                      showDisclosure: false,
                      onTap: controller.lockNow,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  l.appLockLimitDescription,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setEnabled(bool enabled) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final result = await context.read<AppLockController>().setEnabled(
      enabled,
      prompt: DeviceAuthenticationPrompt(
        appName: l10n.appBrandName,
        reason: enabled
            ? l10n.authenticateToEnableAppLock
            : l10n.authenticateToDisableAppLock,
        cancelButton: l10n.cancel,
        fallbackTitle: l10n.useDevicePassword,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.authenticated) {
      AppFeedback.error(context, _localizeLockResult(context.l10n, result));
    }
  }

  Future<void> _setTimeout(AppLockTimeout timeout) async {
    setState(() => _busy = true);
    final message = await context.read<AppLockController>().setTimeout(timeout);
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      AppFeedback.error(context, context.l10n.autoLockSaveFailed);
    }
  }
}

String _timeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) =>
    switch (timeout) {
      AppLockTimeout.immediately => l10n.lockImmediately,
      AppLockTimeout.oneMinute => l10n.lockAfterOneMinute,
      AppLockTimeout.fiveMinutes => l10n.lockAfterFiveMinutes,
      AppLockTimeout.fifteenMinutes => l10n.lockAfterFifteenMinutes,
    };

String _localizeLockResult(
  AppLocalizations l10n,
  DeviceAuthenticationResult result,
) => switch (result.messageId) {
  DeviceAuthenticationMessage.canceled => l10n.authenticationCanceled,
  DeviceAuthenticationMessage.credentialsRequired =>
    l10n.authenticationCredentialsRequired,
  DeviceAuthenticationMessage.unavailable => l10n.authenticationUnavailable,
  DeviceAuthenticationMessage.lockedOut => l10n.authenticationLockedOut,
  DeviceAuthenticationMessage.inProgress => l10n.authenticationInProgress,
  DeviceAuthenticationMessage.uiUnavailable => l10n.authenticationUiUnavailable,
  DeviceAuthenticationMessage.temporarilyUnavailable =>
    l10n.authenticationTemporarilyUnavailable,
  DeviceAuthenticationMessage.appLockSaveFailed => l10n.appLockSaveFailed,
  DeviceAuthenticationMessage.autoLockSaveFailed => l10n.autoLockSaveFailed,
  DeviceAuthenticationMessage.failed => l10n.authenticationFailedRetry,
  DeviceAuthenticationMessage.none => switch (result.status) {
    DeviceAuthenticationStatus.canceled => l10n.authenticationCanceled,
    DeviceAuthenticationStatus.unavailable => l10n.authenticationUnavailable,
    DeviceAuthenticationStatus.lockedOut => l10n.authenticationLockedOut,
    DeviceAuthenticationStatus.failed => l10n.authenticationFailedRetry,
    DeviceAuthenticationStatus.authenticated => '',
  },
};

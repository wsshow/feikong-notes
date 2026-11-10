import '../l10n/generated/app_localizations.dart';
import '../services/device_authentication_service.dart';

DeviceAuthenticationPrompt privateNotesPrompt(
  AppLocalizations l10n, {
  bool exporting = false,
}) => DeviceAuthenticationPrompt(
  appName: l10n.appBrandName,
  reason: exporting
      ? l10n.authenticatePrivateBackup
      : l10n.authenticatePrivateNotes,
  cancelButton: l10n.cancel,
  fallbackTitle: l10n.useDevicePassword,
);

String privateNotesAuthMessage(
  AppLocalizations l10n,
  DeviceAuthenticationResult result,
) => switch (result.messageId) {
  DeviceAuthenticationMessage.credentialsRequired =>
    l10n.authenticationCredentialsRequired,
  DeviceAuthenticationMessage.unavailable => l10n.authenticationUnavailable,
  DeviceAuthenticationMessage.lockedOut => l10n.authenticationLockedOut,
  DeviceAuthenticationMessage.inProgress => l10n.authenticationInProgress,
  DeviceAuthenticationMessage.uiUnavailable => l10n.authenticationUiUnavailable,
  DeviceAuthenticationMessage.temporarilyUnavailable =>
    l10n.authenticationTemporarilyUnavailable,
  _ => switch (result.status) {
    DeviceAuthenticationStatus.canceled => l10n.authenticationCanceled,
    DeviceAuthenticationStatus.authenticated => '',
    DeviceAuthenticationStatus.unavailable => l10n.authenticationUnavailable,
    DeviceAuthenticationStatus.lockedOut => l10n.authenticationLockedOut,
    DeviceAuthenticationStatus.failed => l10n.authenticationFailedRetry,
  },
};

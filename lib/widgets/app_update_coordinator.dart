import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../services/app_update_service.dart';
import '../providers/app_update_controller.dart';
import 'app_feedback.dart';
import 'fk_markdown_view.dart';
import 'app_icon.dart';

const _automaticCheckInterval = Duration(hours: 6);
Future<AppUpdateCheck>? _activeUpdateCheck;
var _updateSheetVisible = false;

enum AppUpdateCheckResult { unsupported, latest, updateAvailable, failed }

/// Runs the Android update check and presents an update when a newer build is
/// available. Interactive checks also report the up-to-date and error states.
Future<AppUpdateCheckResult> checkForAppUpdate(
  BuildContext context, {
  bool interactive = true,
}) async {
  final service = AppUpdateService.instance;
  if (!service.supported) return AppUpdateCheckResult.unsupported;
  final controller = AppUpdateController.instance;
  PendingAppUpdate? pending;
  if (!controller.hasDownload) {
    try {
      pending = await service.restorePendingUpdate();
    } catch (_) {
      // An unavailable system record does not prevent a fresh update check.
    }
  }
  if (!context.mounted) return AppUpdateCheckResult.failed;
  if (interactive) {
    AppFeedback.show(
      context,
      context.l10n.checkingForUpdates,
      duration: const Duration(seconds: 10),
    );
  }

  final activeCheck = _activeUpdateCheck ??= service.check();
  late final AppUpdateCheck check;
  try {
    check = await activeCheck;
  } catch (_) {
    if (!controller.hasDownload && pending != null) {
      controller.restore(pending);
    }
    if (context.mounted && controller.hasDownload) {
      await _showUpdateSheet(
        context,
        controller.manifest!,
        controller.artifact!,
      );
      return AppUpdateCheckResult.updateAvailable;
    }
    if (interactive && context.mounted) {
      AppFeedback.error(context, context.l10n.updateCheckFailed);
    }
    return AppUpdateCheckResult.failed;
  } finally {
    if (identical(_activeUpdateCheck, activeCheck)) {
      _activeUpdateCheck = null;
    }
  }

  if (!context.mounted) return AppUpdateCheckResult.failed;
  final savedManifest = controller.manifest ?? pending?.manifest;
  if (check.updateAvailable &&
      savedManifest != null &&
      check.manifest.versionCode > savedManifest.versionCode) {
    try {
      await controller.supersede(check.manifest, check.artifact);
      pending = null;
    } catch (_) {
      // Keep surfacing the saved transfer if Android could not replace it.
    }
  } else if (!controller.hasDownload && pending != null) {
    controller.restore(pending);
  }
  if (!context.mounted) return AppUpdateCheckResult.failed;
  if (controller.hasDownload) {
    await _showUpdateSheet(context, controller.manifest!, controller.artifact!);
    return AppUpdateCheckResult.updateAvailable;
  }
  if (!check.updateAvailable) {
    if (interactive) {
      AppFeedback.success(context, context.l10n.latestVersionInstalled);
    }
    return AppUpdateCheckResult.latest;
  }

  final manifest = check.manifest;
  if (!interactive &&
      !manifest.mandatory &&
      await service.isSnoozed(manifest.versionCode)) {
    return AppUpdateCheckResult.updateAvailable;
  }
  if (!context.mounted || _updateSheetVisible) {
    return AppUpdateCheckResult.updateAvailable;
  }

  try {
    await _showUpdateSheet(context, manifest, check.artifact);
    return AppUpdateCheckResult.updateAvailable;
  } catch (_) {
    if (interactive && context.mounted) {
      AppFeedback.error(context, context.l10n.updateCheckFailed);
    }
    return AppUpdateCheckResult.failed;
  }
}

Future<void> _showUpdateSheet(
  BuildContext context,
  AppUpdateManifest manifest,
  AppUpdateArtifact artifact,
) async {
  if (!context.mounted || _updateSheetVisible) return;
  _updateSheetVisible = true;
  try {
    final notes = AppUpdateService.instance.fetchReleaseNotes(manifest);
    await AppOverlay.bottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: context.appColors.scrim,
      builder: (_) => AppUpdateSheet(
        manifest: manifest,
        artifact: artifact,
        releaseNotes: notes,
      ),
    );
  } finally {
    _updateSheetVisible = false;
  }
}

/// Automatically checks shortly after launch and after a long background gap.
class AppUpdateCoordinator extends StatefulWidget {
  final Widget child;

  const AppUpdateCoordinator({super.key, required this.child});

  @override
  State<AppUpdateCoordinator> createState() => _AppUpdateCoordinatorState();
}

class _AppUpdateCoordinatorState extends State<AppUpdateCoordinator>
    with WidgetsBindingObserver {
  Timer? _initialCheck;
  DateTime? _lastCheckAt;
  final _controller = AppUpdateController.instance;
  bool _restoring = false;
  String? _lastNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_announceState);
    if (AppUpdateService.instance.supported) {
      AppUpdateService.instance.openRequests.addListener(_openRequested);
      _initialCheck = Timer(const Duration(milliseconds: 1200), () async {
        await _restoreAndOpen();
        _check();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_resume());
  }

  Future<void> _resume() async {
    await _controller.resume();
    await _restoreAndOpen();
    final lastCheckAt = _lastCheckAt;
    if (lastCheckAt == null ||
        DateTime.now().difference(lastCheckAt) >= _automaticCheckInterval) {
      _check();
    }
  }

  void _openRequested() => unawaited(_restoreAndOpen());

  Future<void> _restoreAndOpen() async {
    if (_restoring || !mounted || !AppUpdateService.instance.supported) return;
    _restoring = true;
    try {
      if (!_controller.hasDownload) {
        final pending = await AppUpdateService.instance.restorePendingUpdate();
        if (pending != null) _controller.restore(pending);
      }
      final requested = await AppUpdateService.instance.consumeUpdateLaunch();
      if (requested && mounted) {
        _lastCheckAt = DateTime.now();
        await checkForAppUpdate(context, interactive: false);
      }
      _announceState();
    } catch (_) {
      // A malformed or unavailable system record must not block opening notes.
    } finally {
      _restoring = false;
    }
  }

  void _announceState() {
    if (_controller.isBusy) {
      _lastNotice = null;
      return;
    }
    if (!mounted ||
        _updateSheetVisible ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        (_controller.phase != AppUpdatePhase.ready &&
            _controller.phase != AppUpdatePhase.error)) {
      return;
    }
    final key =
        '${_controller.manifest?.versionCode}:${_controller.phase.name}';
    if (_lastNotice == key) return;
    _lastNotice = key;
    AppFeedback.show(
      context,
      _controller.phase == AppUpdatePhase.ready
          ? context.l10n.updateReadyToInstall
          : context.l10n.updateFailed,
      duration: const Duration(seconds: 10),
      actionLabel: context.l10n.viewUpdate,
      onAction: () => unawaited(
        _showUpdateSheet(context, _controller.manifest!, _controller.artifact!),
      ),
    );
  }

  void _check() {
    if (!mounted || !AppUpdateService.instance.supported) return;
    final lastCheckAt = _lastCheckAt;
    if (lastCheckAt != null &&
        DateTime.now().difference(lastCheckAt) < _automaticCheckInterval) {
      return;
    }
    _initialCheck?.cancel();
    _initialCheck = null;
    _lastCheckAt = DateTime.now();
    unawaited(checkForAppUpdate(context, interactive: false));
  }

  @override
  void dispose() {
    _initialCheck?.cancel();
    _controller.removeListener(_announceState);
    if (AppUpdateService.instance.supported) {
      AppUpdateService.instance.openRequests.removeListener(_openRequested);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppUpdateSheet extends StatefulWidget {
  final AppUpdateManifest manifest;
  final AppUpdateArtifact artifact;
  final Future<String> releaseNotes;
  final AppUpdateClient? service;

  const AppUpdateSheet({
    super.key,
    required this.manifest,
    required this.artifact,
    required this.releaseNotes,
    this.service,
  });

  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<AppUpdateSheet>
    with WidgetsBindingObserver {
  AppUpdateClient get _service => widget.service ?? AppUpdateService.instance;
  late final AppUpdateController _controller;
  AppUpdatePhase get _phase => _controller.phase;
  int get _downloadedBytes => _controller.downloadedBytes;
  String? get _errorCode => _controller.errorCode;
  bool get _busy => _controller.isBusy;
  bool get _canClose =>
      !widget.manifest.mandatory && _phase != AppUpdatePhase.installing;

  @override
  void initState() {
    super.initState();
    _controller = widget.service == null
        ? AppUpdateController.instance
        : AppUpdateController(service: _service);
    _controller.select(widget.manifest, widget.artifact);
    _controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller.resume());
  }

  Future<void> _beginUpdate() => _controller.download();
  Future<void> _launchInstaller() => _controller.install();
  Future<void> _openPermissionSettings() =>
      _controller.openPermissionSettings();

  void _close() {
    if (!_canClose) return;
    final background = _busy;
    if (_phase == AppUpdatePhase.available) {
      unawaited(_service.snooze(widget.manifest.versionCode));
    }
    Navigator.pop(context);
    if (background) {
      AppFeedback.show(context, context.l10n.updateDownloadingInBackground);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.service != null) _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final manifest = widget.manifest;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final releaseDate = DateFormat.yMMMd(locale).format(manifest.releaseDate);
    final sheetHeight = (MediaQuery.sizeOf(context).height * .86)
        .clamp(420.0, 760.0)
        .toDouble();
    return PopScope(
      canPop: _canClose,
      child: SizedBox(
        height: sheetHeight,
        child: Material(
          key: const Key('app-update-sheet'),
          color: context.appColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.extraLarge),
            ),
            side: BorderSide(color: context.appColors.line),
          ),
          // Paint the surface behind the system navigation area while keeping
          // the sheet's content clear of the bottom inset.
          child: SafeArea(
            top: false,
            child: _UpdateSheetLayout(
              header: Padding(
                key: const Key('app-update-header'),
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: context.appColors.accentSoft,
                            borderRadius: BorderRadius.circular(
                              AppRadius.large,
                            ),
                          ),
                          child: AppIcon(
                            Icons.system_update_alt_rounded,
                            color: context.appColors.accent,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      l10n.updateAvailableTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  if (manifest.mandatory) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.appColors.warningSoft,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.pill,
                                        ),
                                      ),
                                      child: Text(
                                        l10n.mandatoryUpdate,
                                        style: TextStyle(
                                          color: context.appColors.warning,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.updateAvailableDescription(
                                  manifest.version,
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: context.appColors.muted),
                              ),
                            ],
                          ),
                        ),
                        if (_canClose)
                          IconButton(
                            tooltip: _busy
                                ? l10n.downloadInBackground
                                : l10n.cancel,
                            onPressed: _close,
                            icon: const AppIcon(Icons.close_rounded, size: 22),
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _UpdateChip('v${manifest.version}'),
                        _UpdateChip(releaseDate),
                        _UpdateChip(_formatBytes(widget.artifact.size)),
                      ],
                    ),
                  ],
                ),
              ),
              notes: SingleChildScrollView(
                key: const Key('app-update-release-notes-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.releaseNotes,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<String>(
                      future: widget.releaseNotes,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator(),
                          );
                        }
                        final notes = snapshot.data?.trim();
                        if (snapshot.hasError ||
                            notes == null ||
                            notes.isEmpty) {
                          return Text(
                            l10n.releaseNotesUnavailable,
                            style: TextStyle(color: context.appColors.muted),
                          );
                        }
                        return FkMarkdownView(data: notes, compact: true);
                      },
                    ),
                  ],
                ),
              ),
              footer: _buildFooter(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return ColoredBox(
      key: const Key('app-update-footer'),
      color: context.appColors.surface,
      child: ConstrainedBox(
        // Keep the notes viewport steady when actions become download progress,
        // but allow the footer to grow for larger text and installation errors.
        constraints: const BoxConstraints(minHeight: 96),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy)
                _UpdateTransferProgress(
                  phase: _phase,
                  downloadedBytes: _downloadedBytes,
                  totalBytes: widget.artifact.size,
                )
              else ...[
                if (_phase != AppUpdatePhase.available) ...[
                  _UpdateStatus(phase: _phase, errorCode: _errorCode),
                  const SizedBox(height: 10),
                ],
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 10,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: _actions(l10n),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n) => switch (_phase) {
    AppUpdatePhase.available => [
      if (!widget.manifest.mandatory)
        TextButton(onPressed: _close, child: Text(l10n.remindMeLater)),
      FilledButton.icon(
        onPressed: _beginUpdate,
        icon: const AppIcon(Icons.download_rounded, size: 19),
        label: Text(l10n.updateNow),
      ),
    ],
    AppUpdatePhase.downloading ||
    AppUpdatePhase.verifying ||
    AppUpdatePhase.installing => const [],
    AppUpdatePhase.permission => [
      if (!widget.manifest.mandatory)
        TextButton(onPressed: _close, child: Text(l10n.remindMeLater)),
      FilledButton(
        onPressed: _openPermissionSettings,
        child: Text(l10n.openInstallSettings),
      ),
    ],
    AppUpdatePhase.error => [
      if (!widget.manifest.mandatory)
        TextButton(onPressed: _close, child: Text(l10n.remindMeLater)),
      FilledButton(onPressed: _beginUpdate, child: Text(l10n.retry)),
    ],
    AppUpdatePhase.ready => [
      if (!widget.manifest.mandatory)
        TextButton(onPressed: _close, child: Text(l10n.cancel)),
      FilledButton(
        onPressed: _launchInstaller,
        child: Text(l10n.installUpdateNow),
      ),
    ],
  };
}

class _UpdateSheetLayout extends StatelessWidget {
  final Widget header;
  final Widget notes;
  final Widget footer;

  const _UpdateSheetLayout({
    required this.header,
    required this.notes,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        // Oversized text must not push the actions outside the sheet. These
        // sections only scroll when necessary, leaving room for release notes.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .4),
          child: SingleChildScrollView(primary: false, child: header),
        ),
        const Divider(height: 1),
        Expanded(child: notes),
        const Divider(key: Key('app-update-footer-divider'), height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .45),
          child: SingleChildScrollView(primary: false, child: footer),
        ),
      ],
    ),
  );
}

class _UpdateChip extends StatelessWidget {
  final String label;

  const _UpdateChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: context.appColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: context.appColors.line),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class _UpdateTransferProgress extends StatelessWidget {
  final AppUpdatePhase phase;
  final int downloadedBytes;
  final int totalBytes;

  const _UpdateTransferProgress({
    required this.phase,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final downloading = phase == AppUpdatePhase.downloading;
    final progress = totalBytes <= 0
        ? 0.0
        : (downloadedBytes / totalBytes).clamp(0.0, 1.0);
    final label = switch (phase) {
      AppUpdatePhase.downloading => l10n.downloadingUpdate,
      AppUpdatePhase.verifying => l10n.verifyingUpdate,
      AppUpdatePhase.installing => l10n.openingInstaller,
      _ => '',
    };
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: context.appColors.ink,
      fontWeight: FontWeight.w700,
    );
    final percent = (progress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: titleStyle)),
            if (downloading) ...[
              const SizedBox(width: 12),
              Text('$percent%', style: titleStyle),
            ],
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          key: const Key('app-update-download-progress'),
          value: downloading ? progress : null,
          minHeight: 4,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: context.appColors.ink,
          backgroundColor: context.appColors.line,
          semanticsLabel: label,
        ),
        const SizedBox(height: 8),
        Text(
          downloading
              ? '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}'
              : _formatBytes(totalBytes),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appColors.muted),
        ),
      ],
    );
  }
}

class _UpdateStatus extends StatelessWidget {
  final AppUpdatePhase phase;
  final String? errorCode;

  const _UpdateStatus({required this.phase, required this.errorCode});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (phase) {
      AppUpdatePhase.permission => l10n.installPermissionRequired,
      AppUpdatePhase.ready => l10n.updateReadyToInstall,
      AppUpdatePhase.error => l10n.updateFailed,
      _ => null,
    };
    if (title == null) return const SizedBox.shrink();
    final warning = phase == AppUpdatePhase.permission;
    final failed = phase == AppUpdatePhase.error;
    final foreground = failed
        ? context.appColors.danger
        : warning
        ? context.appColors.warning
        : context.appColors.ink;
    final icon = failed
        ? Icons.error_outline_rounded
        : warning
        ? Icons.security_outlined
        : phase == AppUpdatePhase.ready
        ? Icons.check_circle_outline_rounded
        : Icons.downloading_rounded;
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIcon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (phase == AppUpdatePhase.permission) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.installPermissionDescription,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (phase == AppUpdatePhase.error) ...[
                  const SizedBox(height: 4),
                  Text(
                    _failureMessage(l10n, errorCode),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _failureMessage(AppLocalizations l10n, String? code) {
  if (code == 'UPDATE_SIZE_MISMATCH') return l10n.updateSizeMismatch;
  if (code == 'UPDATE_CHECKSUM_MISMATCH') {
    return l10n.updateChecksumMismatch;
  }
  if (code == 'PACKAGE_MISMATCH' || code == 'SIGNATURE_MISMATCH') {
    return l10n.updatePackageInvalid;
  }
  if (code == 'VERSION_MISMATCH') return l10n.updateVersionInvalid;
  if (code == 'INSTALLER_UNAVAILABLE') return l10n.updateInstallerUnavailable;
  if (code == 'INSTALL_PERMISSION_SETTINGS_FAILED') {
    return l10n.updatePermissionSettingsFailed;
  }
  if (code == 'UPDATE_DOWNLOAD_TIMEOUT') return l10n.updateDownloadTimedOut;
  if (code != null &&
      (code.startsWith('UPDATE_DOWNLOAD_') ||
          code.startsWith('UPDATE_DOWNLOAD_HTTP_'))) {
    return l10n.updateDownloadFailed;
  }
  if (code == 'UPDATE_INSTALL_FAILED') return l10n.updateInstallFailed;
  return l10n.updateVerificationFailed;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

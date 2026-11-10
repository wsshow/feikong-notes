import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/app_update_service.dart';

enum AppUpdatePhase {
  available,
  downloading,
  verifying,
  permission,
  installing,
  ready,
  error,
}

/// Owns an update independently of the sheet. Android owns the actual transfer.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({required this.service});

  static final instance = AppUpdateController(
    service: AppUpdateService.instance,
  );
  final AppUpdateClient service;
  AppUpdateManifest? manifest;
  AppUpdateArtifact? artifact;
  AppUpdatePhase phase = AppUpdatePhase.available;
  int downloadedBytes = 0;
  String? errorCode;
  File? _file;
  bool _disposed = false;
  bool _installRequested = false;
  bool _permissionSettingsOpened = false;
  int _downloadGeneration = 0;

  bool get hasDownload => manifest != null && phase != AppUpdatePhase.available;
  bool get isBusy => switch (phase) {
    AppUpdatePhase.downloading ||
    AppUpdatePhase.verifying ||
    AppUpdatePhase.installing => true,
    _ => false,
  };

  void select(AppUpdateManifest release, AppUpdateArtifact package) {
    if (manifest?.versionCode == release.versionCode &&
        artifact?.sha256 == package.sha256) {
      return;
    }
    if (isBusy) throw StateError('An update is already running');
    manifest = release;
    artifact = package;
    phase = AppUpdatePhase.available;
    downloadedBytes = 0;
    errorCode = null;
    _file = null;
  }

  void restore(PendingAppUpdate pending) {
    if (hasDownload) return;
    select(pending.manifest, pending.artifact);
    if (pending.failed) {
      errorCode = pending.errorCode ?? 'UPDATE_DOWNLOAD_FAILED';
      _setPhase(AppUpdatePhase.error);
    } else {
      unawaited(download(restoring: true));
    }
  }

  /// Cancels a saved older transfer and selects a newer release.
  Future<void> supersede(
    AppUpdateManifest release,
    AppUpdateArtifact package,
  ) async {
    if (manifest?.versionCode == release.versionCode &&
        artifact?.sha256 == package.sha256) {
      return;
    }
    _downloadGeneration++;
    try {
      await service.clearPendingUpdate();
    } catch (error) {
      _fail(error);
      rethrow;
    }
    manifest = release;
    artifact = package;
    phase = AppUpdatePhase.available;
    downloadedBytes = 0;
    errorCode = null;
    _file = null;
    _installRequested = false;
    _permissionSettingsOpened = false;
    _notify();
  }

  Future<void> download({bool restoring = false}) async {
    if (isBusy || manifest == null || artifact == null) return;
    final generation = ++_downloadGeneration;
    final restart = phase == AppUpdatePhase.error;
    _file = null;
    downloadedBytes = 0;
    errorCode = null;
    _setPhase(AppUpdatePhase.downloading);
    try {
      final file = await service.download(
        manifest!,
        artifact: artifact!,
        restart: restart,
        requestNotifications: !restoring,
        onProgress: (bytes, _) {
          if (generation != _downloadGeneration) return;
          downloadedBytes = bytes;
          _notify();
        },
      );
      if (generation != _downloadGeneration) return;
      _setPhase(AppUpdatePhase.verifying);
      await service.verify(manifest!, artifact!, file);
      if (generation != _downloadGeneration) return;
      _file = file;
      // Installation is always an explicit action, even if the app is visible.
      // Finishing a background transfer must not interrupt note editing.
      _setPhase(AppUpdatePhase.ready);
    } catch (error) {
      if (generation == _downloadGeneration) _fail(error);
    }
  }

  Future<void> install() async {
    if (_file == null || _installRequested) return;
    _installRequested = true;
    try {
      if (!await service.canInstallUpdates()) {
        _setPhase(AppUpdatePhase.permission);
        return;
      }
      errorCode = null;
      _setPhase(AppUpdatePhase.installing);
      await service.install(manifest!, artifact!, _file!);
      _setPhase(AppUpdatePhase.ready);
    } on PlatformException catch (error) {
      if (error.code == 'INSTALL_PERMISSION_REQUIRED') {
        _setPhase(AppUpdatePhase.permission);
      } else {
        _fail(error);
      }
    } catch (error) {
      _fail(error);
    } finally {
      _installRequested = false;
    }
  }

  Future<void> openPermissionSettings() async {
    try {
      _permissionSettingsOpened = true;
      await service.openInstallPermissionSettings();
    } catch (error) {
      _permissionSettingsOpened = false;
      _fail(error);
    }
  }

  Future<void> resume() async {
    if (phase == AppUpdatePhase.permission && _permissionSettingsOpened) {
      _permissionSettingsOpened = false;
      await install();
    }
  }

  void _fail(Object error) {
    errorCode = switch (error) {
      AppUpdateException value => value.code,
      PlatformException value => value.code,
      _ => 'UPDATE_FAILED',
    };
    _setPhase(AppUpdatePhase.error);
  }

  void _setPhase(AppUpdatePhase next) {
    phase = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

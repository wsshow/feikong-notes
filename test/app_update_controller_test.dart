import 'dart:async';
import 'dart:io';

import 'package:fknotes/providers/app_update_controller.dart';
import 'package:fknotes/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _UpdateClient service;
  late AppUpdateController controller;
  setUp(() {
    service = _UpdateClient();
    controller = AppUpdateController(service: service)
      ..select(_manifest, _artifact);
  });
  tearDown(() => controller.dispose());

  test(
    'download survives UI detachment and installs only on request',
    () async {
      void listener() {}
      controller.addListener(listener);
      final download = controller.download();
      controller.removeListener(listener);
      service.finishDownload();
      await download;

      expect(controller.phase, AppUpdatePhase.ready);
      expect(service.installs, 0);
      await controller.install();
      expect(service.installs, 1);
    },
  );

  test(
    'verification failure blocks install and retry replaces the bad transfer',
    () async {
      service.verificationError = const AppUpdateException(
        'SIGNATURE_MISMATCH',
      );
      final first = controller.download();
      service.finishDownload();
      await first;
      expect(controller.phase, AppUpdatePhase.error);
      await controller.install();
      expect(service.installs, 0);

      service.verificationError = null;
      final retry = controller.download();
      expect(service.restart, isTrue);
      service.finishDownload();
      await retry;
      expect(controller.phase, AppUpdatePhase.ready);
    },
  );

  test(
    'restored downloads reuse the system transfer without permission prompts',
    () async {
      controller.restore(
        PendingAppUpdate(manifest: _manifest, artifact: _artifact),
      );
      expect(controller.phase, AppUpdatePhase.downloading);
      expect(service.restart, isFalse);
      expect(service.requestNotifications, isFalse);
      service.finishDownload();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, AppUpdatePhase.ready);
      expect(service.installs, 0);
    },
  );

  test('restored failures do not silently restart downloads', () async {
    controller.restore(
      PendingAppUpdate(
        manifest: _manifest,
        artifact: _artifact,
        failed: true,
        errorCode: 'UPDATE_DOWNLOAD_NETWORK',
      ),
    );
    expect(controller.phase, AppUpdatePhase.error);
    expect(service.downloads, 0);
  });

  test('a newer release supersedes a restored older download', () async {
    controller.restore(
      PendingAppUpdate(manifest: _manifest, artifact: _artifact),
    );
    expect(controller.phase, AppUpdatePhase.downloading);

    await controller.supersede(_newerManifest, _newerArtifact);
    await Future<void>.delayed(Duration.zero);

    expect(service.clears, 1);
    expect(controller.manifest?.versionCode, 2041);
    expect(controller.artifact?.sha256, _newerArtifact.sha256);
    expect(controller.phase, AppUpdatePhase.available);
    expect(controller.errorCode, isNull);
  });
}

final _artifact = AppUpdateArtifact(
  id: 'android-universal',
  abi: null,
  url: Uri.https('example.com', '/update.apk'),
  size: 100,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);
final _manifest = AppUpdateManifest(
  version: '2.0.0',
  versionCode: 2040,
  releaseDate: DateTime(2026, 8, 28),
  mandatory: false,
  changelog: Uri.https('example.com', '/notes.md'),
  artifacts: {'android-universal': _artifact},
);
final _newerArtifact = AppUpdateArtifact(
  id: 'android-universal',
  abi: null,
  url: Uri.https('example.com', '/newer.apk'),
  size: 120,
  sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);
final _newerManifest = AppUpdateManifest(
  version: '2.0.1',
  versionCode: 2041,
  releaseDate: DateTime(2026, 8, 29),
  mandatory: false,
  changelog: Uri.https('example.com', '/newer-notes.md'),
  artifacts: {'android-universal': _newerArtifact},
);

class _UpdateClient implements AppUpdateClient {
  Completer<File>? _download;
  int downloads = 0;
  int installs = 0;
  int clears = 0;
  bool? restart;
  bool? requestNotifications;
  Object? verificationError;

  void finishDownload() => _download!.complete(File('/tmp/update.apk'));

  @override
  Future<File> download(
    AppUpdateManifest manifest, {
    required AppUpdateArtifact artifact,
    required AppUpdateDownloadProgress onProgress,
    bool restart = false,
    bool requestNotifications = true,
  }) {
    downloads++;
    this.restart = restart;
    this.requestNotifications = requestNotifications;
    _download = Completer<File>();
    onProgress(25, 100);
    return _download!.future;
  }

  @override
  Future<void> verify(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) async {
    if (verificationError != null) throw verificationError!;
  }

  @override
  Future<bool> canInstallUpdates() async => true;

  @override
  Future<void> install(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) async {
    installs++;
  }

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<void> clearPendingUpdate() async {
    clears++;
    final download = _download;
    if (download != null && !download.isCompleted) {
      download.completeError(
        const AppUpdateException('UPDATE_DOWNLOAD_MISSING'),
      );
    }
  }

  @override
  Future<void> snooze(int versionCode) async {}
}

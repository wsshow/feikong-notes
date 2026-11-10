import 'dart:convert';

import 'package:fknotes/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pending download restores the selected artifact and verification metadata',
    () {
      final manifest = AppUpdateManifest.fromJson(_manifest());
      final pending = PendingAppUpdate.fromSnapshot({
        'manifest': jsonEncode(manifest.toJson()),
        'artifactId': 'android-arm64-v8a',
        'status': 'paused',
      });
      expect(pending.manifest.versionCode, manifest.versionCode);
      expect(pending.artifact.id, 'android-arm64-v8a');
      expect(pending.artifact.sha256, _validSha256);
      expect(pending.artifact.size, 100000);
    },
  );
  group('AppUpdateManifest', () {
    test('parses a valid Android update manifest', () {
      final manifest = AppUpdateManifest.fromJson(_manifest());

      expect(manifest.version, '1.2.3');
      expect(manifest.versionCode, 2040);
      expect(manifest.releaseDate, DateTime(2026, 8, 25));
      expect(manifest.mandatory, isFalse);
      expect(
        manifest.androidArtifact.url.toString(),
        'https://downloads.example.com/fknotes/1.2.3/fknotes-1.2.3.apk',
      );
      expect(manifest.androidArtifact.size, 123456);
      expect(manifest.androidArtifact.sha256, _validSha256);
    });

    test('selects the best APK for the device ABI and falls back safely', () {
      final manifest = AppUpdateManifest.fromJson(_manifest());

      final arm64 = manifest.selectArtifact(const ['arm64-v8a', 'armeabi-v7a']);
      expect(arm64.id, 'android-arm64-v8a');
      expect(arm64.abi, 'arm64-v8a');

      expect(
        manifest.selectArtifact(const ['riscv64']).id,
        'android-universal',
      );
    });

    test('rejects another app feed', () {
      final value = _manifest()..['app'] = 'another-app';

      expect(
        () => AppUpdateManifest.fromJson(value),
        throwsA(_updateError('INVALID_UPDATE_MANIFEST')),
      );
    });

    test('rejects insecure artifact and changelog URLs', () {
      final insecureArtifact = _manifest();
      final artifacts = insecureArtifact['artifacts']! as Map<String, Object?>;
      final android = artifacts['android-universal']! as Map<String, Object?>;
      android['url'] = 'http://downloads.example.com/fknotes.apk';

      expect(
        () => AppUpdateManifest.fromJson(insecureArtifact),
        throwsA(_updateError('INVALID_ARTIFACT_URL')),
      );

      final insecureNotes = _manifest()
        ..['changelog'] = 'http://downloads.example.com/notes.md';
      expect(
        () => AppUpdateManifest.fromJson(insecureNotes),
        throwsA(_updateError('INVALID_CHANGELOG_URL')),
      );
    });

    test('rejects invalid dates, sizes and checksums', () {
      final invalidDate = _manifest()..['releaseDate'] = '2026-02-30';
      expect(
        () => AppUpdateManifest.fromJson(invalidDate),
        throwsA(_updateError('INVALID_UPDATE_MANIFEST')),
      );

      final invalidArtifact = _manifest();
      final artifacts = invalidArtifact['artifacts']! as Map<String, Object?>;
      final android = artifacts['android-universal']! as Map<String, Object?>;
      android
        ..['size'] = 0
        ..['sha256'] = 'not-a-checksum';
      expect(
        () => AppUpdateManifest.fromJson(invalidArtifact),
        throwsA(_updateError('INVALID_UPDATE_MANIFEST')),
      );
    });
  });

  test('compares the manifest build number with the installed build', () {
    final manifest = AppUpdateManifest.fromJson(_manifest());
    final artifact = manifest.selectArtifact(const ['arm64-v8a']);

    expect(
      AppUpdateCheck(
        currentVersion: '1.2.2',
        currentVersionCode: 2039,
        manifest: manifest,
        artifact: artifact,
      ).updateAvailable,
      isTrue,
    );
    expect(
      AppUpdateCheck(
        currentVersion: '1.2.3',
        currentVersionCode: 2040,
        manifest: manifest,
        artifact: artifact,
      ).updateAvailable,
      isFalse,
    );
  });
}

Map<String, Object?> _manifest() => {
  'app': 'fknotes',
  'version': '1.2.3',
  'versionCode': 2040,
  'releaseDate': '2026-08-25',
  'mandatory': false,
  'changelog': 'https://downloads.example.com/fknotes/1.2.3/notes.md',
  'artifacts': <String, Object?>{
    'android-universal': <String, Object?>{
      'url': 'https://downloads.example.com/fknotes/1.2.3/fknotes-1.2.3.apk',
      'size': 123456,
      'sha256': _validSha256,
    },
    'android-arm64-v8a': <String, Object?>{
      'url':
          'https://downloads.example.com/fknotes/1.2.3/fknotes-1.2.3-arm64-v8a.apk',
      'size': 100000,
      'sha256': _validSha256,
    },
  },
};

const _validSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Matcher _updateError(String code) =>
    isA<AppUpdateException>().having((error) => error.code, 'code', code);

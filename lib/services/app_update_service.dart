import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _manifestUrl = String.fromEnvironment('FKNOTES_UPDATE_MANIFEST_URL');
const _feedId = 'fknotes';
const _androidPackageName = 'com.fknotes.app';

typedef AppUpdateDownloadProgress =
    void Function(int downloadedBytes, int totalBytes);

abstract interface class AppUpdateClient {
  Future<File> download(
    AppUpdateManifest manifest, {
    required AppUpdateArtifact artifact,
    required AppUpdateDownloadProgress onProgress,
    bool restart = false,
    bool requestNotifications = true,
  });

  Future<void> verify(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  );

  Future<bool> canInstallUpdates();

  Future<void> install(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  );

  Future<void> openInstallPermissionSettings();

  Future<void> clearPendingUpdate();

  Future<void> snooze(int versionCode);
}

final class AppUpdateService implements AppUpdateClient {
  AppUpdateService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openUpdate') openRequests.value++;
    });
  }

  static final instance = AppUpdateService._();
  static const _channel = MethodChannel('fknotes/app_update');
  static const _connectTimeout = Duration(seconds: 10);
  static const _readTimeout = Duration(seconds: 60);
  static const _maximumManifestBytes = 256 * 1024;
  static const _maximumReleaseNotesBytes = 512 * 1024;
  static const _optionalUpdateSnooze = Duration(hours: 24);
  final openRequests = ValueNotifier<int>(0);

  bool get supported =>
      !kIsWeb && Platform.isAndroid && _manifestUrl.isNotEmpty;

  Future<AppUpdateCheck> check() async {
    if (!supported) throw const AppUpdateException('UPDATE_UNSUPPORTED');
    final values = await Future.wait<Object>([
      PackageInfo.fromPlatform(),
      fetchManifest(),
      getSupportedAbis(),
    ]);
    final packageInfo = values[0] as PackageInfo;
    final manifest = values[1] as AppUpdateManifest;
    final supportedAbis = values[2] as List<String>;
    final currentVersionCode = int.tryParse(packageInfo.buildNumber.trim());
    if (currentVersionCode == null || currentVersionCode < 1) {
      throw const AppUpdateException('INVALID_CURRENT_VERSION');
    }
    return AppUpdateCheck(
      currentVersion: packageInfo.version.trim(),
      currentVersionCode: currentVersionCode,
      manifest: manifest,
      artifact: manifest.selectArtifact(supportedAbis),
    );
  }

  Future<List<String>> getSupportedAbis() async {
    final values = await _channel.invokeListMethod<String>('getSupportedAbis');
    return values?.where((value) => value.trim().isNotEmpty).toList() ??
        const [];
  }

  Future<AppUpdateManifest> fetchManifest() async {
    final configuredUri = _httpsUri(_manifestUrl, 'INVALID_MANIFEST_URL');
    final requestUri = configuredUri.replace(
      queryParameters: {
        ...configuredUri.queryParameters,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final text = await _getText(
      requestUri,
      maximumBytes: _maximumManifestBytes,
      accept: 'application/json',
      failurePrefix: 'UPDATE_MANIFEST',
    );
    try {
      return AppUpdateManifest.fromJson(jsonDecode(text));
    } on AppUpdateException {
      rethrow;
    } catch (_) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
  }

  Future<String> fetchReleaseNotes(AppUpdateManifest manifest) async {
    final text = await _getText(
      manifest.changelog,
      maximumBytes: _maximumReleaseNotesBytes,
      accept: 'text/markdown, text/plain;q=0.9',
      failurePrefix: 'UPDATE_CHANGELOG',
    );
    return text.trim();
  }

  Future<bool> isSnoozed(int versionCode) async {
    try {
      final file = await _snoozeFile();
      if (!await file.exists()) return false;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['versionCode'] != versionCode) return false;
      final dismissedAtText = value['dismissedAt'];
      if (dismissedAtText is! String) return false;
      final dismissedAt = DateTime.tryParse(dismissedAtText);
      return dismissedAt != null &&
          DateTime.now().difference(dismissedAt) < _optionalUpdateSnooze;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> snooze(int versionCode) async {
    try {
      final file = await _snoozeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode({'versionCode': versionCode, 'dismissedAt': DateTime.now().toIso8601String()})}\n',
        flush: true,
      );
    } catch (_) {
      // Failing to remember a dismissal must never block closing the dialog.
    }
  }

  @override
  Future<File> download(
    AppUpdateManifest manifest, {
    required AppUpdateArtifact artifact,
    required AppUpdateDownloadProgress onProgress,
    bool restart = false,
    bool requestNotifications = true,
  }) async {
    if (requestNotifications && supported) {
      try {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } on PlatformException {
        // Notification access is optional; the task remains available in-app.
      }
    }
    final id = await _channel.invokeMethod<int>('startUpdateDownload', {
      'url': artifact.url.toString(),
      'sha256': artifact.sha256,
      'size': artifact.size,
      'versionCode': manifest.versionCode,
      'manifest': jsonEncode(manifest.toJson()),
      'artifactId': artifact.id,
      'restart': restart,
    });
    if (id == null) throw const AppUpdateException('UPDATE_DOWNLOAD_FAILED');
    while (true) {
      final state = await _channel.invokeMapMethod<String, Object?>(
        'getUpdateDownload',
      );
      if (state == null || state['id'] != id) {
        throw const AppUpdateException('UPDATE_DOWNLOAD_MISSING');
      }
      final bytes = (state['downloadedBytes'] as num?)?.toInt() ?? 0;
      onProgress(bytes.clamp(0, artifact.size), artifact.size);
      if (state['status'] == 'failed') {
        throw AppUpdateException(
          state['errorCode'] as String? ?? 'UPDATE_DOWNLOAD_FAILED',
        );
      }
      if (state['status'] == 'downloaded') {
        if (bytes != artifact.size) {
          throw const AppUpdateException('UPDATE_SIZE_MISMATCH');
        }
        final file = await _channel.invokeMethod<String>(
          'materializeUpdateDownload',
          id,
        );
        if (file == null) throw const AppUpdateException('UPDATE_FILE_MISSING');
        return File(file);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<PendingAppUpdate?> restorePendingUpdate() async {
    if (!supported) return null;
    final state = await _channel.invokeMapMethod<String, Object?>(
      'getUpdateDownload',
    );
    if (state == null) return null;
    try {
      return PendingAppUpdate.fromSnapshot(state);
    } on FormatException {
      await clearPendingUpdate();
      return null;
    } on AppUpdateException {
      await clearPendingUpdate();
      return null;
    }
  }

  @override
  Future<void> clearPendingUpdate() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('clearUpdateDownload');
  }

  Future<bool> consumeUpdateLaunch() async =>
      supported &&
      await _channel.invokeMethod<bool>('consumeUpdateLaunch') == true;

  @override
  Future<bool> canInstallUpdates() async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'canInstallUpdates',
    );
    return response?['allowed'] == true;
  }

  @override
  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<void> verify(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) => _channel.invokeMethod<void>(
    'verifyUpdate',
    _verificationArguments(manifest, artifact, file),
  );

  @override
  Future<void> install(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) => _channel.invokeMethod<void>(
    'installUpdate',
    _verificationArguments(manifest, artifact, file),
  );

  Map<String, Object> _verificationArguments(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) => {
    'path': file.path,
    'sha256': artifact.sha256,
    'size': artifact.size,
    'packageName': _androidPackageName,
    'versionCode': manifest.versionCode,
  };

  Future<String> _getText(
    Uri uri, {
    required int maximumBytes,
    required String accept,
    required String failurePrefix,
  }) async {
    final client = _newHttpClient();
    try {
      final request = await client.getUrl(uri).timeout(_connectTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, accept)
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(_connectTimeout);
      _validateSecureRedirects(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppUpdateException(
          '${failurePrefix}_HTTP_${response.statusCode}',
        );
      }
      if (response.contentLength > maximumBytes) {
        throw AppUpdateException('${failurePrefix}_TOO_LARGE');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_readTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maximumBytes) {
          throw AppUpdateException('${failurePrefix}_TOO_LARGE');
        }
      }
      return utf8.decode(bytes.takeBytes());
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw AppUpdateException('${failurePrefix}_TIMEOUT');
    } on SocketException {
      throw AppUpdateException('${failurePrefix}_NETWORK');
    } on FormatException {
      throw AppUpdateException('${failurePrefix}_INVALID_TEXT');
    } catch (_) {
      throw AppUpdateException('${failurePrefix}_FAILED');
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _newHttpClient() => HttpClient()
    ..connectionTimeout = _connectTimeout
    ..autoUncompress = true;

  void _validateSecureRedirects(HttpClientResponse response) {
    for (final redirect in response.redirects) {
      final scheme = redirect.location.scheme.toLowerCase();
      if (scheme.isNotEmpty && scheme != 'https') {
        throw const AppUpdateException('INSECURE_UPDATE_REDIRECT');
      }
    }
  }

  Future<File> _snoozeFile() async {
    final support = await getApplicationSupportDirectory();
    return File(path.join(support.path, 'app-update-dismissed.json'));
  }
}

final class AppUpdateCheck {
  final String currentVersion;
  final int currentVersionCode;
  final AppUpdateManifest manifest;
  final AppUpdateArtifact artifact;

  const AppUpdateCheck({
    required this.currentVersion,
    required this.currentVersionCode,
    required this.manifest,
    required this.artifact,
  });

  bool get updateAvailable => manifest.versionCode > currentVersionCode;
}

final class AppUpdateManifest {
  final String version;
  final int versionCode;
  final DateTime releaseDate;
  final bool mandatory;
  final Uri changelog;
  final Map<String, AppUpdateArtifact> artifacts;

  const AppUpdateManifest({
    required this.version,
    required this.versionCode,
    required this.releaseDate,
    required this.mandatory,
    required this.changelog,
    required this.artifacts,
  });

  AppUpdateArtifact get androidArtifact => artifacts['android-universal']!;

  Map<String, Object> toJson() => {
    'app': _feedId,
    'version': version,
    'versionCode': versionCode,
    'releaseDate': _dateText(releaseDate),
    'mandatory': mandatory,
    'changelog': changelog.toString(),
    'artifacts': {
      for (final entry in artifacts.entries)
        entry.key: {
          'url': entry.value.url.toString(),
          'size': entry.value.size,
          'sha256': entry.value.sha256,
        },
    },
  };

  AppUpdateArtifact selectArtifact(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      final artifact = artifacts['android-$abi'];
      if (artifact != null) return artifact;
    }
    return androidArtifact;
  }

  factory AppUpdateManifest.fromJson(Object? value) {
    if (value is! Map || value['app'] != _feedId) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    final version = value['version'];
    final versionCode = value['versionCode'];
    final releaseDateText = value['releaseDate'];
    final mandatory = value['mandatory'];
    final changelogText = value['changelog'];
    final artifacts = value['artifacts'];
    final universal = artifacts is Map ? artifacts['android-universal'] : null;
    if (version is! String ||
        version.trim().isEmpty ||
        versionCode is! int ||
        versionCode < 1 ||
        releaseDateText is! String ||
        mandatory is! bool ||
        changelogText is! String ||
        artifacts is! Map ||
        universal is! Map) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(releaseDateText)) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    final releaseDate = DateTime.tryParse(releaseDateText);
    if (releaseDate == null || _dateText(releaseDate) != releaseDateText) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    final parsedArtifacts = <String, AppUpdateArtifact>{};
    for (final entry in artifacts.entries) {
      final key = entry.key;
      final raw = entry.value;
      if (key is! String ||
          !_supportedArtifactKeys.contains(key) ||
          raw is! Map) {
        continue;
      }
      parsedArtifacts[key] = AppUpdateArtifact.fromJson(key, raw);
    }
    if (!parsedArtifacts.containsKey('android-universal')) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    return AppUpdateManifest(
      version: version.trim(),
      versionCode: versionCode,
      releaseDate: releaseDate,
      mandatory: mandatory,
      changelog: _httpsUri(changelogText, 'INVALID_CHANGELOG_URL'),
      artifacts: Map.unmodifiable(parsedArtifacts),
    );
  }
}

final class AppUpdateArtifact {
  final String id;
  final String? abi;
  final Uri url;
  final int size;
  final String sha256;

  const AppUpdateArtifact({
    required this.id,
    required this.abi,
    required this.url,
    required this.size,
    required this.sha256,
  });

  factory AppUpdateArtifact.fromJson(String id, Map value) {
    final artifactUrl = value['url'];
    final size = value['size'];
    final sha256 = value['sha256'];
    if (artifactUrl is! String ||
        size is! int ||
        size < 1 ||
        sha256 is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    return AppUpdateArtifact(
      id: id,
      abi: id == 'android-universal' ? null : id.substring('android-'.length),
      url: _httpsUri(artifactUrl, 'INVALID_ARTIFACT_URL'),
      size: size,
      sha256: sha256.toLowerCase(),
    );
  }
}

final class PendingAppUpdate {
  final AppUpdateManifest manifest;
  final AppUpdateArtifact artifact;
  final bool failed;
  final String? errorCode;

  const PendingAppUpdate({
    required this.manifest,
    required this.artifact,
    this.failed = false,
    this.errorCode,
  });

  factory PendingAppUpdate.fromSnapshot(Map<String, Object?> state) {
    final serialized = state['manifest'];
    if (serialized is! String) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    final manifest = AppUpdateManifest.fromJson(jsonDecode(serialized));
    final artifact = manifest.artifacts[state['artifactId']];
    if (artifact == null) {
      throw const AppUpdateException('INVALID_UPDATE_MANIFEST');
    }
    return PendingAppUpdate(
      manifest: manifest,
      artifact: artifact,
      failed: state['status'] == 'failed',
      errorCode: state['errorCode'] as String?,
    );
  }
}

final class AppUpdateException implements Exception {
  final String code;

  const AppUpdateException(this.code);

  @override
  String toString() => 'AppUpdateException($code)';
}

Uri _httpsUri(String value, String errorCode) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw AppUpdateException(errorCode);
  }
  return uri;
}

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

const _supportedArtifactKeys = {'android-universal', 'android-arm64-v8a'};

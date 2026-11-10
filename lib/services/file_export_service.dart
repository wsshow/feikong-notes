import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saves an explicit copy through the OS document picker on both mobile hosts.
class FileExportService {
  FileExportService({MethodChannel? channel, TargetPlatform? platform})
    : _channel = channel ?? const MethodChannel('fknotes/backup_export'),
      _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final TargetPlatform _platform;

  Future<bool> save({
    required File source,
    required String suggestedName,
    required String mimeType,
    List<XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!await source.exists()) {
      throw const FileSystemException('Export file missing');
    }
    if (_platform == TargetPlatform.android ||
        _platform == TargetPlatform.iOS) {
      return await _channel.invokeMethod<bool>('saveFile', {
            'sourcePath': source.path,
            'suggestedName': suggestedName,
            'mimeType': mimeType,
          }) ??
          false;
    }
    final location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      suggestedName: suggestedName,
    );
    if (location == null) return false;
    await XFile(
      source.path,
      mimeType: mimeType,
      name: suggestedName,
    ).saveTo(location.path);
    return true;
  }
}

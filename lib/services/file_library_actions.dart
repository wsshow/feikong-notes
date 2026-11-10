import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/library_file.dart';
import 'file_library_store.dart';

class FileLibraryActions {
  FileLibraryActions(this.store);
  final FileLibraryStore store;

  static String mimeType(LibraryFile entry) =>
      lookupMimeType(entry.name) ?? 'application/octet-stream';

  Future<File> _namedCopy(LibraryFile entry) async {
    final source = store.fileFor(entry);
    if (!await source.exists()) throw const FileLibraryException('missing');
    final root = Directory(
      p.join((await getTemporaryDirectory()).path, 'file-library-exports'),
    );
    await root.create(recursive: true);
    final expiration = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          (await entity.stat()).modified.isBefore(expiration)) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          /* Best-effort temporary cleanup. */
        }
      }
    }
    final directory = await Directory(
      p.join(root.path, const Uuid().v4()),
    ).create();
    return source.copy(p.join(directory.path, entry.name));
  }

  Future<bool> openExternal(LibraryFile entry) async {
    final file = await _namedCopy(entry);
    final result = await OpenFilex.open(file.path, type: mimeType(entry));
    return result.type == ResultType.done;
  }

  Future<void> share(List<LibraryFile> entries, {Rect? origin}) async {
    final files = <XFile>[];
    for (final entry in entries.where((e) => !e.isFolder)) {
      final file = await _namedCopy(entry);
      files.add(XFile(file.path, name: entry.name, mimeType: mimeType(entry)));
    }
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: files, sharePositionOrigin: origin),
    );
  }

  Future<bool> save(LibraryFile entry) async {
    final source = store.fileFor(entry);
    if (!await source.exists()) throw const FileLibraryException('missing');
    if (Platform.isAndroid) {
      return await const MethodChannel(
            'fknotes/backup_export',
          ).invokeMethod<bool>('saveFile', {
            'sourcePath': source.path,
            'suggestedName': entry.name,
            'mimeType': mimeType(entry),
          }) ??
          false;
    }
    if (Platform.isIOS) {
      await share([entry]);
      return false;
    }
    final destination = await getSaveLocation(suggestedName: entry.name);
    if (destination == null) return false;
    await XFile(source.path).saveTo(destination.path);
    return true;
  }
}

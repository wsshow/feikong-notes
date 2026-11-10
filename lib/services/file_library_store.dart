import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/library_file.dart';
import 'file_storage_service.dart';
import 'file_library_picker.dart';

/// Logical folders keep user names separate from immutable, app-owned blobs.
/// A flushed, atomically replaced index is the commit point for every mutation.
class FileLibraryStore {
  FileLibraryStore({this._rootPath});

  static final instance = FileLibraryStore();
  static const relativeRoot = 'notes/files/library';
  static final _queues = <String, Future<void>>{};
  final String? _rootPath;
  final _uuid = const Uuid();

  String get rootPath =>
      _rootPath ?? FileStorageService.instance.absolutePath(relativeRoot);
  File get _index => File(p.join(rootPath, 'index.json'));
  File fileFor(LibraryFile entry) {
    final name = entry.storageName;
    if (name == null || !_validBlobName(name)) {
      throw const FileLibraryException('invalid');
    }
    return File(p.join(rootPath, 'data', name));
  }

  Future<T> _exclusive<T>(Future<T> Function() work) async {
    final key = p.normalize(rootPath);
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<List<LibraryFile>> load() => _exclusive(() async {
    final entries = await _read();
    final referenced = entries
        .map((e) => e.storageName)
        .whereType<String>()
        .toSet();
    final data = Directory(p.join(rootPath, 'data'));
    if (await data.exists()) {
      await for (final entity in data.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if ((_validBlobName(name) && !referenced.contains(name)) ||
            name.endsWith('.part')) {
          try {
            await entity.delete();
          } on FileSystemException {
            /* Retry cleanup on the next load. */
          }
        }
      }
    }
    return entries;
  });

  Future<List<LibraryFile>> _read() async {
    if (!await _index.exists()) return [];
    final raw = jsonDecode(await _index.readAsString());
    if (raw is! Map || raw['version'] != 1 || raw['entries'] is! List) {
      throw const FileLibraryException('corrupt');
    }
    final entries = (raw['entries'] as List)
        .map((e) => LibraryFile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    validateEntries(entries);
    return entries;
  }

  static bool _validBlobName(String name) =>
      RegExp(r'^[0-9a-f-]{36}(\.[a-z0-9]{1,16})?$').hasMatch(name);

  static String validateName(String name) {
    final value = name.trim();
    if (value.isEmpty ||
        value.length > 240 ||
        value == '.' ||
        value == '..' ||
        RegExp(r'[\x00-\x1f/\\:*?"<>|]').hasMatch(value) ||
        value.endsWith('.')) {
      throw const FileLibraryException('name');
    }
    return value;
  }

  static void validateEntries(List<LibraryFile> entries) {
    final byId = {for (final entry in entries) entry.id: entry};
    final blobs = <String>{};
    final names = <String>{};
    if (byId.length != entries.length) {
      throw const FileLibraryException('corrupt');
    }
    for (final entry in entries) {
      validateName(entry.name);
      if (entry.linkedNoteId != null &&
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(entry.linkedNoteId!)) {
        throw const FileLibraryException('corrupt');
      }
      if (entry.deletedAt == null &&
          !names.add('${entry.parentId ?? ''}/${entry.name.toLowerCase()}')) {
        throw const FileLibraryException('corrupt');
      }
      if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(entry.id) ||
          entry.size < 0 ||
          (entry.isFolder && entry.size != 0)) {
        throw const FileLibraryException('corrupt');
      }
      if (entry.storageName case final name?) {
        if (!_validBlobName(name) || !blobs.add(name)) {
          throw const FileLibraryException('corrupt');
        }
      }
      var current = entry;
      final seen = {entry.id};
      while (current.parentId != null) {
        final parent = byId[current.parentId];
        if (parent == null || !parent.isFolder || !seen.add(parent.id)) {
          throw const FileLibraryException('corrupt');
        }
        current = parent;
      }
    }
  }

  Future<void> _write(List<LibraryFile> entries) async {
    validateEntries(entries);
    await Directory(rootPath).create(recursive: true);
    final temporary = File('${_index.path}.part');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
      }),
      flush: true,
    );
    await temporary.rename(_index.path);
  }

  static bool isInTrash(LibraryFile entry, Map<String, LibraryFile> byId) {
    LibraryFile? current = entry;
    while (current != null) {
      if (current.deletedAt != null) return true;
      current = byId[current.parentId];
    }
    return false;
  }

  static bool isInTrashParent(
    LibraryFile entry,
    Map<String, LibraryFile> byId,
  ) {
    final parent = byId[entry.parentId];
    return parent != null && isInTrash(parent, byId);
  }

  void _checkParent(String? parentId, List<LibraryFile> entries) {
    if (parentId == null) return;
    final byId = {for (final e in entries) e.id: e};
    final parent = byId[parentId];
    if (parent == null || !parent.isFolder || isInTrash(parent, byId)) {
      throw const FileLibraryException('destination');
    }
  }

  String _uniqueName(
    String name,
    String? parentId,
    List<LibraryFile> entries, {
    String? exceptId,
  }) {
    final names = entries
        .where(
          (e) =>
              e.parentId == parentId && e.deletedAt == null && e.id != exceptId,
        )
        .map((e) => e.name.toLowerCase())
        .toSet();
    if (!names.contains(name.toLowerCase())) return name;
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var i = 2;
    while (names.contains('$stem ($i)$ext'.toLowerCase())) {
      i++;
    }
    return '$stem ($i)$ext';
  }

  Future<LibraryFile> createFolder(String name, {String? parentId}) =>
      _exclusive(() async {
        final entries = await _read();
        _checkParent(parentId, entries);
        final safeName = validateName(name);
        if (_uniqueName(safeName, parentId, entries) != safeName) {
          throw const FileLibraryException('exists');
        }
        final now = DateTime.now().toUtc();
        final entry = LibraryFile(
          id: _uuid.v4(),
          name: safeName,
          parentId: parentId,
          createdAt: now,
          modifiedAt: now,
        );
        await _write([...entries, entry]);
        return entry;
      });

  Future<LibraryFile> importFile(
    XFile source, {
    String? parentId,
    void Function(int bytes, int total)? onProgress,
    bool Function()? isCancelled,
  }) => _exclusive(() async {
    final entries = await _read();
    _checkParent(parentId, entries);
    var name = p
        .basename(source.name.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[\x00-\x1f/\\:*?"<>|]'), '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..') name = 'file';
    if (name.endsWith('.')) name = '${name}_';
    if (name.length > 200) {
      name =
          '${name.substring(0, 180)}${p.extension(name).substring(0, p.extension(name).length.clamp(0, 16))}';
    }
    name = _uniqueName(validateName(name), parentId, entries);
    final id = _uuid.v4();
    final ext = p.extension(name).toLowerCase();
    final blob = '$id${RegExp(r'^\.[a-z0-9]{1,16}$').hasMatch(ext) ? ext : ''}';
    final target = File(p.join(rootPath, 'data', blob));
    final temporary = File('${target.path}.part');
    await target.parent.create(recursive: true);
    var bytes = 0;
    final total = await source.length();
    IOSink? sink;
    try {
      if (source is AndroidLibraryFile) {
        bytes = await source.copyTo(
          temporary.path,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } else {
        sink = temporary.openWrite();
        await sink.addStream(
          source.openRead().map((chunk) {
            if (isCancelled?.call() == true) {
              throw const FileLibraryException('cancelled');
            }
            bytes += chunk.length;
            onProgress?.call(bytes, total);
            return chunk;
          }),
        );
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (isCancelled?.call() == true) {
        throw const FileLibraryException('cancelled');
      }
      if (total > 0 && bytes != total) {
        throw const FileLibraryException('incomplete');
      }
      onProgress?.call(bytes, bytes);
      await temporary.rename(target.path);
      final now = DateTime.now().toUtc();
      final entry = LibraryFile(
        id: id,
        name: name,
        parentId: parentId,
        storageName: blob,
        size: bytes,
        createdAt: now,
        modifiedAt: now,
      );
      await _write([...entries, entry]);
      return entry;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        /* Preserve the import error and clean partial files. */
      }
      if (await temporary.exists()) await temporary.delete();
      if (await target.exists()) await target.delete();
      rethrow;
    }
  });

  Future<void> rename(String id, String name) => _exclusive(() async {
    final entries = await _read();
    final entry = entries.firstWhere((e) => e.id == id);
    final byId = {for (final e in entries) e.id: e};
    if (isInTrash(entry, byId)) throw const FileLibraryException('destination');
    final safeName = validateName(name);
    if (_uniqueName(safeName, entry.parentId, entries, exceptId: id) !=
        safeName) {
      throw const FileLibraryException('exists');
    }
    await _write([
      for (final e in entries)
        if (e.id == id)
          e.copyWith(name: safeName, modifiedAt: DateTime.now().toUtc())
        else
          e,
    ]);
  });

  Future<void> setFavorite(Set<String> ids, bool favorite) =>
      _update(ids, (e) => e.copyWith(favorite: favorite));
  Future<void> markOpened(String id) =>
      _update({id}, (e) => e.copyWith(openedAt: DateTime.now().toUtc()));
  Future<void> linkNote(String fileId, String noteId) =>
      _update({fileId}, (e) => e.copyWith(linkedNoteId: noteId));
  Future<void> _update(
    Set<String> ids,
    LibraryFile Function(LibraryFile) change,
  ) => _exclusive(() async {
    final entries = await _read();
    await _write([
      for (final e in entries)
        if (ids.contains(e.id)) change(e) else e,
    ]);
  });

  static Set<String> descendants(Set<String> ids, List<LibraryFile> entries) {
    final result = {...ids};
    final children = <String?, List<String>>{};
    for (final entry in entries) {
      (children[entry.parentId] ??= []).add(entry.id);
    }
    final queue = ids.toList();
    for (var index = 0; index < queue.length; index++) {
      for (final child in children[queue[index]] ?? <String>[]) {
        if (result.add(child)) queue.add(child);
      }
    }
    return result;
  }

  Future<void> transfer(
    Set<String> ids,
    String? parentId, {
    required bool copy,
  }) => _exclusive(() async {
    final entries = await _read();
    _checkParent(parentId, entries);
    final all = descendants(ids, entries);
    if (parentId != null && all.contains(parentId)) {
      throw const FileLibraryException('cycle');
    }
    final byId = {for (final e in entries) e.id: e};
    if (ids.any((id) => byId[id] == null || isInTrash(byId[id]!, byId))) {
      throw const FileLibraryException('destination');
    }
    final roots = entries
        .where((e) => ids.contains(e.id) && !all.contains(e.parentId))
        .toList();
    final now = DateTime.now().toUtc();
    final result = [...entries];
    final created = <File>[];
    try {
      if (copy) {
        final mapping = {for (final id in all) id: _uuid.v4()};
        for (final entry in entries.where((e) => all.contains(e.id))) {
          final id = mapping[entry.id]!;
          String? blob;
          if (!entry.isFolder) {
            blob = '$id${p.extension(entry.storageName!)}';
            final output = File(p.join(rootPath, 'data', blob));
            created.add(output);
            await fileFor(entry).copy(output.path);
          }
          final root = roots.any((e) => e.id == entry.id);
          final destination = root ? parentId : mapping[entry.parentId];
          result.add(
            LibraryFile(
              id: id,
              name: root
                  ? _uniqueName(entry.name, destination, result)
                  : entry.name,
              parentId: destination,
              storageName: blob,
              size: entry.size,
              createdAt: now,
              modifiedAt: now,
              deletedAt: entry.deletedAt,
            ),
          );
        }
      } else {
        for (final entry in roots) {
          if (entry.parentId == parentId) continue;
          final index = result.indexWhere((e) => e.id == entry.id);
          result[index] = entry.copyWith(
            parentId: parentId,
            clearParent: parentId == null,
            name: _uniqueName(entry.name, parentId, result, exceptId: entry.id),
            modifiedAt: now,
          );
        }
      }
      await _write(result);
    } catch (_) {
      for (final file in created) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  });

  Future<void> trash(Set<String> ids) => _exclusive(() async {
    final entries = await _read();
    final byId = {for (final e in entries) e.id: e};
    final all = descendants(ids, entries);
    final now = DateTime.now().toUtc();
    await _write([
      for (final e in entries)
        if (ids.contains(e.id) &&
            !all.contains(e.parentId) &&
            !isInTrash(e, byId))
          e.copyWith(deletedAt: now)
        else
          e,
    ]);
  });

  Future<void> restore(Set<String> ids) => _exclusive(() async {
    final entries = await _read();
    final result = [...entries];
    for (final entry in entries.where(
      (e) => ids.contains(e.id) && e.deletedAt != null,
    )) {
      final byId = {for (final e in result) e.id: e};
      final parent = byId[entry.parentId];
      final destination = parent == null || isInTrash(parent, byId)
          ? null
          : parent.id;
      result[result.indexWhere((e) => e.id == entry.id)] = entry.copyWith(
        parentId: destination,
        clearParent: destination == null,
        restore: true,
        name: _uniqueName(entry.name, destination, result, exceptId: entry.id),
      );
    }
    await _write(result);
  });

  Future<void> deletePermanently(Set<String> ids) => _exclusive(() async {
    final entries = await _read();
    final byId = {for (final e in entries) e.id: e};
    if (ids.any((id) => byId[id] == null || !isInTrash(byId[id]!, byId))) {
      throw const FileLibraryException('trashOnly');
    }
    final all = descendants(ids, entries);
    await _write(entries.where((e) => !all.contains(e.id)).toList());
    for (final entry in entries.where(
      (e) => all.contains(e.id) && !e.isFolder,
    )) {
      try {
        await fileFor(entry).delete();
      } on FileSystemException {
        /* Orphan cleanup can retry on the next maintenance pass. */
      }
    }
  });

  /// Copy a coherent library into the backup staging directory under the same
  /// lock used by imports and mutations, including recycle-bin contents.
  Future<Map<String, File>> backupSnapshot(Directory staging) =>
      _exclusive(() async {
        final entries = await _read();
        if (!await _index.exists()) return {};
        for (final entry in entries.where((e) => !e.isFolder)) {
          if (await fileFor(entry).length() != entry.size) {
            throw const FileLibraryException('corrupt');
          }
        }
        final files = <String, File>{
          '$relativeRoot/index.json': _index,
          for (final e in entries.where((e) => !e.isFolder))
            '$relativeRoot/data/${e.storageName}': fileFor(e),
        };
        final result = <String, File>{};
        for (final entry in files.entries) {
          final output = File(p.join(staging.path, entry.key));
          await output.parent.create(recursive: true);
          result[entry.key] = await entry.value.copy(output.path);
        }
        return result;
      });

  Future<Set<String>> validateBackupFiles() async {
    final entries = await _read();
    if (!await _index.exists()) return {};
    final names = <String>{'$relativeRoot/index.json'};
    for (final entry in entries.where((e) => !e.isFolder)) {
      final file = fileFor(entry);
      if (!await file.exists() || await file.length() != entry.size) {
        throw const FileLibraryException('corrupt');
      }
      names.add('$relativeRoot/data/${entry.storageName}');
    }
    return names;
  }
}

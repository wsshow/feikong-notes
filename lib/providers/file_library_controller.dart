import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../models/library_file.dart';
import '../services/file_library_store.dart';

class FileLibraryController extends ChangeNotifier {
  FileLibraryController({FileLibraryStore? store})
    : store = store ?? FileLibraryStore.instance;
  final FileLibraryStore store;
  List<LibraryFile> _entries = [];
  Map<String, LibraryFile> _byId = {};
  Set<String> _trashedIds = {};
  Map<String, int> _childCounts = {};
  List<LibraryFile> get entries => _entries;
  Map<String, LibraryFile> get byId => _byId;

  void _replaceEntries(List<LibraryFile> entries) {
    _entries = List.unmodifiable(entries);
    _byId = Map.unmodifiable({for (final e in entries) e.id: e});
    _trashedIds = FileLibraryStore.descendants(
      entries.where((e) => e.deletedAt != null).map((e) => e.id).toSet(),
      entries,
    );
    _childCounts = {};
    for (final entry in entries) {
      if (entry.parentId != null && !_trashedIds.contains(entry.id)) {
        _childCounts.update(
          entry.parentId!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  bool loading = true;
  bool busy = false;
  String? error;
  FileLibraryLocation location = FileLibraryLocation.files;
  String? folderId;
  String query = '';
  LibraryFileKind? filter;
  FileLibrarySort sort = FileLibrarySort.modified;
  bool ascending = false;
  bool grid = false;
  String? importName;
  int imported = 0;
  int importTotal = 0;
  int importBytes = 0;
  int importFileBytes = 0;
  bool _cancelImport = false;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool isTrashed(LibraryFile entry) => _trashedIds.contains(entry.id);
  int get fileCount =>
      _entries.where((e) => !e.isFolder && !isTrashed(e)).length;
  int get totalBytes =>
      _entries.where((e) => !e.isFolder).fold(0, (sum, e) => sum + e.size);
  int get trashCount => _entries.where((e) => e.deletedAt != null).length;

  List<LibraryFile> get breadcrumbs {
    final map = byId;
    final result = <LibraryFile>[];
    var current = map[folderId];
    while (current != null) {
      result.insert(0, current);
      current = map[current.parentId];
    }
    return result;
  }

  int sizeOf(LibraryFile entry) {
    if (!entry.isFolder) return entry.size;
    final ids = FileLibraryStore.descendants({entry.id}, _entries);
    return _entries
        .where((e) => !e.isFolder && ids.contains(e.id))
        .fold(0, (sum, e) => sum + e.size);
  }

  int childrenOf(LibraryFile entry) => _childCounts[entry.id] ?? 0;

  List<LibraryFile> get visible {
    final map = byId;
    final search = query.trim().toLowerCase();
    final scope = folderId == null
        ? null
        : FileLibraryStore.descendants({folderId!}, _entries);
    final result = _entries.where((entry) {
      final trashed = _trashedIds.contains(entry.id);
      if (location == FileLibraryLocation.trash) {
        if (entry.deletedAt == null ||
            FileLibraryStore.isInTrashParent(entry, map)) {
          return false;
        }
      } else {
        if (trashed) return false;
        if (location == FileLibraryLocation.favorites && !entry.favorite) {
          return false;
        }
        if (location == FileLibraryLocation.recent &&
            (entry.isFolder || entry.openedAt == null)) {
          return false;
        }
        if (location == FileLibraryLocation.files) {
          if (search.isEmpty && filter == null) {
            if (entry.parentId != folderId) return false;
          } else if (scope != null &&
              (!scope.contains(entry.id) || entry.id == folderId)) {
            return false;
          }
        }
      }
      return (filter == null || entry.kind == filter) &&
          (search.isEmpty || entry.name.toLowerCase().contains(search));
    }).toList();
    result.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      DateTime timestamp(LibraryFile entry) => switch (location) {
        FileLibraryLocation.recent => entry.openedAt ?? entry.modifiedAt,
        FileLibraryLocation.trash => entry.deletedAt ?? entry.modifiedAt,
        _ => entry.modifiedAt,
      };
      final value = switch (sort) {
        FileLibrarySort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        FileLibrarySort.modified => timestamp(a).compareTo(timestamp(b)),
        FileLibrarySort.size => a.size.compareTo(b.size),
        FileLibrarySort.type => a.extension.compareTo(b.extension),
      };
      if (value == 0) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return ascending ? value : -value;
    });
    return result;
  }

  Future<void> load() async {
    try {
      _replaceEntries(await store.load());
      if (folderId != null && !byId.containsKey(folderId)) folderId = null;
      error = null;
    } catch (_) {
      error = 'load';
    }
    loading = false;
    _notify();
  }

  void navigate(FileLibraryLocation value, {String? folder}) {
    if (location != value &&
        (value == FileLibraryLocation.recent ||
            value == FileLibraryLocation.trash)) {
      sort = FileLibrarySort.modified;
      ascending = false;
    }
    location = value;
    folderId = folder;
    query = '';
    filter = null;
    _notify();
  }

  void search(String value) {
    query = value;
    _notify();
  }

  void setFilter(LibraryFileKind? value) {
    filter = value;
    _notify();
  }

  void setSort(FileLibrarySort value) {
    if (sort == value) {
      ascending = !ascending;
    } else {
      sort = value;
      ascending =
          value == FileLibrarySort.name || value == FileLibrarySort.type;
    }
    _notify();
  }

  void toggleGrid() {
    grid = !grid;
    _notify();
  }

  Future<bool> run(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      _replaceEntries(await store.load());
      return true;
    } catch (e) {
      error = e is FileLibraryException ? e.code : 'operation';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importFiles(List<XFile> files) async {
    if (busy || files.isEmpty) return;
    final destination = location == FileLibraryLocation.files ? folderId : null;
    busy = true;
    error = null;
    _cancelImport = false;
    imported = 0;
    importTotal = files.length;
    var failed = false;
    _notify();
    for (final file in files) {
      if (_cancelImport || _disposed) break;
      importName = file.name;
      importBytes = 0;
      importFileBytes = 0;
      _notify();
      var lastUpdate = DateTime.now();
      try {
        final entry = await store.importFile(
          file,
          parentId: destination,
          isCancelled: () => _cancelImport || _disposed,
          onProgress: (bytes, total) {
            importBytes = bytes;
            importFileBytes = total;
            if (DateTime.now().difference(lastUpdate).inMilliseconds > 80) {
              lastUpdate = DateTime.now();
              _notify();
            }
          },
        );
        _replaceEntries([..._entries, entry]);
        imported++;
      } catch (e) {
        if (e is FileLibraryException && e.code == 'cancelled') break;
        failed = true;
      }
    }
    importName = null;
    busy = false;
    if (failed) error = 'import';
    if (imported > 0) navigate(FileLibraryLocation.files, folder: destination);
    _notify();
  }

  void cancelImport() {
    _cancelImport = true;
    _notify();
  }

  Future<void> opened(LibraryFile entry) async {
    try {
      await store.markOpened(entry.id);
      _replaceEntries(await store.load());
      _notify();
    } catch (_) {
      /* Opening content does not depend on recent-history writes. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelImport = true;
    super.dispose();
  }
}

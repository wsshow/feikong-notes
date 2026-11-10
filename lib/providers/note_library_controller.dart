import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../models/note_constellation.dart';
import '../models/note_link.dart';
import '../services/file_storage_service.dart';
import '../services/note_database_service.dart';
import '../services/note_repository.dart';

abstract interface class NoteLibraryStore {
  Future<List<Note>> list();

  Future<List<Note>> search(String query);

  Future<Note> update(Note note);

  Future<void> deletePermanently(Note note);
}

abstract interface class NoteRelationshipStore {
  Future<List<NoteLink>> listLinks();

  Future<void> replaceLinks(NoteId noteId, Iterable<NoteId> otherNoteIds);
}

abstract interface class NoteConstellationStore {
  Future<NoteConstellationSnapshot> loadConstellation();

  Future<void> saveConstellationPosition(NoteId noteId, double x, double y);

  Future<void> saveConstellationOverviewPosition(
    String groupKey,
    NoteId noteId,
    double x,
    double y,
  );

  Future<void> saveConstellationOverviewRegionPosition(
    String groupKey,
    double x,
    double y,
  );

  Future<void> saveConstellationGroup(NoteConstellationGroup group);

  Future<void> deleteConstellationGroup(String groupId);
}

final class RepositoryNoteLibraryStore
    implements NoteLibraryStore, NoteRelationshipStore, NoteConstellationStore {
  RepositoryNoteLibraryStore(
    this.repository, {
    FileStorageService? storage,
    this.privateSpace = false,
  }) : storage = storage ?? FileStorageService.instance;

  final NoteRepository repository;
  final FileStorageService storage;
  final bool privateSpace;

  @override
  Future<List<Note>> list() => repository.list(privateSpace: privateSpace);

  @override
  Future<List<Note>> search(String query) =>
      repository.search(query, privateSpace: privateSpace);

  @override
  Future<Note> update(Note note) => repository.update(note);

  @override
  Future<List<NoteLink>> listLinks() => repository.listLinks();

  @override
  Future<void> replaceLinks(NoteId noteId, Iterable<NoteId> otherNoteIds) =>
      repository.replaceLinks(noteId, otherNoteIds);

  @override
  Future<NoteConstellationSnapshot> loadConstellation() =>
      repository.loadConstellation();

  @override
  Future<void> saveConstellationPosition(NoteId noteId, double x, double y) =>
      repository.saveConstellationPosition(noteId, x, y);

  @override
  Future<void> saveConstellationOverviewPosition(
    String groupKey,
    NoteId noteId,
    double x,
    double y,
  ) => repository.saveConstellationOverviewPosition(groupKey, noteId, x, y);

  @override
  Future<void> saveConstellationOverviewRegionPosition(
    String groupKey,
    double x,
    double y,
  ) => repository.saveConstellationOverviewRegionPosition(groupKey, x, y);

  @override
  Future<void> saveConstellationGroup(NoteConstellationGroup group) =>
      repository.saveConstellationGroup(group);

  @override
  Future<void> deleteConstellationGroup(String groupId) =>
      repository.deleteConstellationGroup(groupId);

  @override
  Future<void> deletePermanently(Note note) async {
    await repository.deletePermanently(note.id);
    for (final asset in note.assets) {
      for (final key in [asset.storageKey, asset.previewStorageKey]) {
        try {
          await storage.deleteFile(key);
        } on FileSystemException {
          // Database deletion is authoritative. A later orphan sweep can
          // retry cleanup if the OS still has a file handle open.
        }
      }
    }
  }
}

typedef NoteLibraryStoreLoader = Future<NoteLibraryStore> Function();

/// State for the clean Delta note library.
///
/// Every async request carries a generation so a slow search can never replace
/// a newer query. Note mutations use repository revisions and refresh on a
/// conflict instead of silently overwriting another editor session.
final class NoteLibraryController extends ChangeNotifier {
  NoteLibraryController({
    NoteLibraryStoreLoader? storeLoader,
    DateTime Function()? now,
    this.privateSpace = false,
  }) : _storeLoader =
           storeLoader ??
           (() async => RepositoryNoteLibraryStore(
             await NoteDatabaseService.instance.repository,
             privateSpace: privateSpace,
           )),
       _now = now ?? DateTime.now;

  final NoteLibraryStoreLoader _storeLoader;
  final bool privateSpace;
  final DateTime Function() _now;
  final Set<NoteId> _busyNoteIds = {};
  List<Note> _notes = const [];
  List<NoteLink> _links = const [];
  Map<NoteId, NoteConstellationPosition> _constellationPositions = const {};
  Map<String, Map<NoteId, NoteConstellationOverviewPosition>>
  _constellationOverviewPositions = const {};
  Map<String, NoteConstellationOverviewRegionPosition>
  _constellationOverviewRegionPositions = const {};
  List<NoteConstellationGroup> _constellationGroups = const [];
  String _query = '';
  Object? _error;
  var _loading = false;
  var _requestGeneration = 0;
  var _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    super.dispose();
  }

  List<Note> get notes => _notes;

  /// Logical content size for this space, not the shared database/backups.
  /// Database overhead and preview caches are deliberately not attributed.
  int get contentSizeBytes {
    var bytes = 0;
    final assets = <String>{};
    for (final note in _notes.where((note) => note.isPrivate == privateSpace)) {
      bytes += utf8
          .encode(
            [note.title, note.document.toJsonString(), ...note.tags].join('\n'),
          )
          .length;
      for (final asset in note.assets) {
        if (!assets.add(asset.storageKey)) continue;
        bytes +=
            asset.byteLength +
            utf8
                .encode('${asset.ocrText ?? ''}\n${asset.transcript ?? ''}')
                .length;
      }
    }
    return bytes;
  }

  List<NoteLink> get links => _links;
  Map<NoteId, NoteConstellationPosition> get constellationPositions =>
      _constellationPositions;
  Map<String, Map<NoteId, NoteConstellationOverviewPosition>>
  get constellationOverviewPositions => _constellationOverviewPositions;
  Map<String, NoteConstellationOverviewRegionPosition>
  get constellationOverviewRegionPositions =>
      _constellationOverviewRegionPositions;
  List<NoteConstellationGroup> get constellationGroups => _constellationGroups;
  String get query => _query;
  Object? get error => _error;
  bool get isLoading => _loading;
  bool get hasError => _error != null;
  bool isBusy(NoteId id) => _busyNoteIds.contains(id);

  Future<void> initialize() => refresh();

  Future<void> search(String value) async {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_query == normalized && !_loading) return;
    _query = normalized;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_requestGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      final loaded = _query.isEmpty
          ? await store.list()
          : await store.search(_query);
      if (generation != _requestGeneration) return;
      _notes = List.unmodifiable(
        loaded.where((note) => note.isPrivate == privateSpace),
      );
    } catch (error) {
      if (generation != _requestGeneration) return;
      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePinned(Note note) =>
      _mutate(note, (value) => value.copyWith(isPinned: !value.isPinned));

  Future<void> setPrivate(
    Iterable<Note> notes, {
    required bool isPrivate,
  }) async {
    final selected = notes.toList(growable: false);
    if (selected.isEmpty || selected.any((note) => isBusy(note.id))) return;
    _busyNoteIds.addAll(selected.map((note) => note.id));
    notifyListeners();
    try {
      final store = await _storeLoader();
      for (final note in selected) {
        if (note.isPrivate == isPrivate) continue;
        await store.update(
          note.copyWith(isPrivate: isPrivate, updatedAt: _now().toUtc()),
        );
      }
    } finally {
      _busyNoteIds.removeAll(selected.map((note) => note.id));
      // Also refresh after a partial failure; never leave a moved note visible.
      await refresh();
    }
  }

  Future<void> setPinned(Iterable<Note> notes, {required bool pinned}) async {
    final selected = notes.toList(growable: false);
    if (selected.isEmpty ||
        selected.any((note) => _busyNoteIds.contains(note.id))) {
      return;
    }
    _busyNoteIds.addAll(selected.map((note) => note.id));
    _error = null;
    notifyListeners();
    try {
      final timestamp = _now().toUtc();
      final store = await _storeLoader();
      for (final note in selected) {
        if (note.isPinned == pinned) continue;
        await store.update(
          note.copyWith(isPinned: pinned, updatedAt: timestamp),
        );
      }
      await refresh();
    } catch (error) {
      await refresh();
      _error = error;
      notifyListeners();
      rethrow;
    } finally {
      _busyNoteIds.removeAll(selected.map((note) => note.id));
      notifyListeners();
    }
  }

  Future<void> _mutate(Note note, Note Function(Note value) change) async {
    if (!_busyNoteIds.add(note.id)) return;
    _error = null;
    notifyListeners();
    try {
      final timestamp = _now().toUtc();
      final store = await _storeLoader();
      await store.update(change(note).copyWith(updatedAt: timestamp));
      await refresh();
    } catch (error) {
      await refresh();
      _error = error;
      notifyListeners();
      rethrow;
    } finally {
      _busyNoteIds.remove(note.id);
      notifyListeners();
    }
  }

  Future<void> deletePermanently(Note note) async {
    if (!_busyNoteIds.add(note.id)) return;
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      await store.deletePermanently(note);
      _notes = List.unmodifiable(
        _notes.where((candidate) => candidate.id != note.id),
      );
      _removeConstellationNotes({note.id});
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _busyNoteIds.remove(note.id);
      notifyListeners();
    }
  }

  Future<void> deletePermanentlyAll(Iterable<Note> notes) async {
    final selected = notes.toList(growable: false);
    if (selected.isEmpty ||
        selected.any((note) => _busyNoteIds.contains(note.id))) {
      return;
    }
    _busyNoteIds.addAll(selected.map((note) => note.id));
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      for (final note in selected) {
        await store.deletePermanently(note);
      }
      final ids = selected.map((note) => note.id).toSet();
      _notes = List.unmodifiable(
        _notes.where((candidate) => !ids.contains(candidate.id)),
      );
      _removeConstellationNotes(ids);
    } catch (error) {
      await refresh();
      _error = error;
      rethrow;
    } finally {
      _busyNoteIds.removeAll(selected.map((note) => note.id));
      notifyListeners();
    }
  }

  Set<NoteId> linkedNoteIds(NoteId noteId) => {
    for (final link in _links)
      if (link.connects(noteId)) link.other(noteId),
  };

  Future<void> replaceLinksFor(
    NoteId noteId,
    Iterable<NoteId> otherNoteIds,
  ) async {
    if (!_busyNoteIds.add(noteId)) return;
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is! NoteRelationshipStore) return;
      final relationshipStore = store as NoteRelationshipStore;
      await relationshipStore.replaceLinks(noteId, otherNoteIds);
      _links = List.unmodifiable(await relationshipStore.listLinks());
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _busyNoteIds.remove(noteId);
      notifyListeners();
    }
  }

  Future<void> saveConstellationPosition(
    NoteId noteId,
    double x,
    double y,
  ) async {
    final position = NoteConstellationPosition(
      noteId: noteId,
      x: x,
      y: y,
      updatedAt: _now(),
    );
    _constellationPositions = Map.unmodifiable({
      ..._constellationPositions,
      noteId: position,
    });
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is NoteConstellationStore) {
        await (store as NoteConstellationStore).saveConstellationPosition(
          noteId,
          position.x,
          position.y,
        );
      }
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveConstellationOverviewPosition(
    String groupKey,
    NoteId noteId,
    double x,
    double y,
  ) async {
    final position = NoteConstellationOverviewPosition(
      groupKey: groupKey,
      noteId: noteId,
      x: x,
      y: y,
      updatedAt: _now(),
    );
    _constellationOverviewPositions = Map.unmodifiable({
      ..._constellationOverviewPositions,
      groupKey: Map<NoteId, NoteConstellationOverviewPosition>.unmodifiable({
        ...(_constellationOverviewPositions[groupKey] ??
            const <NoteId, NoteConstellationOverviewPosition>{}),
        noteId: position,
      }),
    });
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is NoteConstellationStore) {
        await (store as NoteConstellationStore)
            .saveConstellationOverviewPosition(
              groupKey,
              noteId,
              position.x,
              position.y,
            );
      }
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveConstellationOverviewRegionPosition(
    String groupKey,
    double x,
    double y,
  ) async {
    final position = NoteConstellationOverviewRegionPosition(
      groupKey: groupKey,
      x: x,
      y: y,
      updatedAt: _now(),
    );
    _constellationOverviewRegionPositions = Map.unmodifiable({
      ..._constellationOverviewRegionPositions,
      groupKey: position,
    });
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is NoteConstellationStore) {
        await (store as NoteConstellationStore)
            .saveConstellationOverviewRegionPosition(
              groupKey,
              position.x,
              position.y,
            );
      }
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveConstellationGroup(NoteConstellationGroup group) async {
    final existing = _constellationGroups.indexWhere(
      (candidate) => candidate.id == group.id,
    );
    final updated = List<NoteConstellationGroup>.of(_constellationGroups);
    if (existing == -1) {
      updated.insert(0, group);
    } else {
      updated[existing] = group;
    }
    _constellationGroups = List.unmodifiable(updated);
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is NoteConstellationStore) {
        await (store as NoteConstellationStore).saveConstellationGroup(group);
      }
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteConstellationGroup(String groupId) async {
    _constellationGroups = List.unmodifiable(
      _constellationGroups.where((group) => group.id != groupId),
    );
    notifyListeners();
    try {
      final store = await _storeLoader();
      if (store is NoteConstellationStore) {
        await (store as NoteConstellationStore).deleteConstellationGroup(
          groupId,
        );
      }
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  void _removeConstellationNotes(Set<NoteId> noteIds) {
    _constellationPositions = Map.unmodifiable(
      Map.of(_constellationPositions)
        ..removeWhere((noteId, _) => noteIds.contains(noteId)),
    );
    _constellationGroups = List.unmodifiable([
      for (final group in _constellationGroups)
        if (group.noteIds.any(noteIds.contains))
          group.copyWith(
            noteIds: group.noteIds.where((noteId) => !noteIds.contains(noteId)),
            updatedAt: _now(),
          )
        else
          group,
    ]);
  }
}

typedef NoteMutation = Note Function(Note value);

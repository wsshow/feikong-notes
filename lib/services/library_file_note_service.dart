import 'package:flutter_quill/quill_delta.dart';
import 'package:path/path.dart' as p;

import '../models/library_file.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import 'file_library_store.dart';
import 'note_database_service.dart';
import 'note_repository.dart';

/// Library references keep a stable file identity without copying file content.
/// Public entry points never resume a private note.
class LibraryFileNoteService {
  LibraryFileNoteService({
    FileLibraryStore? store,
    Future<NoteRepository> Function()? repositoryLoader,
  }) : store = store ?? FileLibraryStore.instance,
       _repositoryLoader =
           repositoryLoader ?? (() => NoteDatabaseService.instance.repository);

  final FileLibraryStore store;
  final Future<NoteRepository> Function() _repositoryLoader;
  final _pending = <String, Future<Note>>{};

  Future<Note?> linkedNote(LibraryFile file) async {
    final id = file.linkedNoteId;
    if (id == null) return null;
    final note = await (await _repositoryLoader()).get(NoteId.parse(id));
    return note == null || note.isPrivate ? null : note;
  }

  Future<Note> openOrCreate(LibraryFile file) => openOrCreateMany([file]);

  Future<Note> openOrCreateMany(Iterable<LibraryFile> files) {
    final unique = {for (final file in files) file.id: file}.values.toList();
    final ids = unique.map((file) => file.id).toList()..sort();
    final key = ids.join(',');
    return _pending.putIfAbsent(key, () {
      final future = _create(unique);
      return future.whenComplete(() {
        _pending.remove(key);
      });
    });
  }

  Future<List<NoteFileReference>> referencesFor(
    Iterable<LibraryFile> files,
  ) async {
    final entries = await store.load();
    final byId = {for (final entry in entries) entry.id: entry};
    final references = <NoteFileReference>[];
    final seen = <String>{};
    for (final requested in files) {
      if (!seen.add(requested.id)) continue;
      final file = byId[requested.id];
      if (file == null ||
          file.isFolder ||
          FileLibraryStore.isInTrash(file, byId) ||
          !await store.fileFor(file).exists()) {
        throw const FileLibraryException('missing');
      }
      references.add(
        NoteFileReference(fileId: file.id, name: file.name, size: file.size),
      );
    }
    // Apply the same count and payload validation used by persisted documents.
    return NoteEmbed.fileReferences(references).fileReferences;
  }

  Future<Note> _create(List<LibraryFile> requested) async {
    final references = await referencesFor(requested);
    // A single file retains the established "continue writing" behavior.
    // Batch actions create a new group without replacing individual links.
    if (references.length == 1) {
      final current = (await store.load()).firstWhere(
        (file) => file.id == references.single.fileId,
      );
      final existing = await linkedNote(current);
      if (existing != null) return existing;
    }
    final repository = await _repositoryLoader();
    final now = DateTime.now().toUtc();
    final draft = Note(
      id: NoteId.generate(),
      title: p.basenameWithoutExtension(references.first.name),
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.fileReferences(references).toDeltaData())
          ..insert('\n'),
      ),
      createdAt: now,
      updatedAt: now,
    );
    Note saved;
    try {
      saved = await repository.create(draft);
    } catch (_) {
      final committed = await repository.get(draft.id);
      if (committed == null) rethrow;
      saved = committed;
    }
    if (references.length == 1) {
      await store.linkNote(references.single.fileId, saved.id.value);
    }
    return saved;
  }
}

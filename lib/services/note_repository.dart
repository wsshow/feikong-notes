import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/note_constellation.dart';
import '../models/note_document.dart';
import '../models/note_link.dart';

final class NoteWriteConflict implements Exception {
  const NoteWriteConflict(this.noteId);

  final NoteId noteId;

  @override
  String toString() => 'NoteWriteConflict(${noteId.value})';
}

final class NoteAgentConflict implements Exception {
  final String code;
  const NoteAgentConflict(this.code);
}

final class AgentNoteMutation {
  final NoteId id;
  final int expectedRevision;
  final Note? replacement;
  final int? nextRevision;
  const AgentNoteMutation({
    required this.id,
    required this.expectedRevision,
    required this.replacement,
    this.nextRevision,
  });
}

enum NoteQuerySort { updatedDesc, createdDesc, titleAsc, titleDesc }

final class NoteQueryFilter {
  final String query;
  final String title;
  final List<String> tags;
  final bool matchAllTags;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final DateTime? updatedFrom;
  final DateTime? updatedTo;
  final bool? isPinned;
  final bool? hasAttachments;
  final NoteQuerySort sort;

  const NoteQueryFilter({
    this.query = '',
    this.title = '',
    this.tags = const [],
    this.matchAllTags = true,
    this.createdFrom,
    this.createdTo,
    this.updatedFrom,
    this.updatedTo,
    this.isPinned,
    this.hasAttachments,
    this.sort = NoteQuerySort.updatedDesc,
  });
}

final class NoteQueryPage {
  final List<Note> notes;
  final int total;

  const NoteQueryPage(this.notes, this.total);
}

/// Persistence for the Delta-based note model.
///
/// This repository intentionally has no legacy Markdown or integer-ID adapter.
/// Callers either provide a complete valid note graph or the transaction fails.
final class NoteRepository {
  NoteRepository(this._database, {this.onNoteChanged});

  final Database _database;

  /// Runs after a committed write, never inside the SQLite transaction.
  final Future<void> Function(NoteId id)? onNoteChanged;
  final _privacyListeners = <void Function(NoteId, bool)>{};
  void addPrivacyListener(void Function(NoteId, bool) listener) =>
      _privacyListeners.add(listener);
  void removePrivacyListener(void Function(NoteId, bool) listener) =>
      _privacyListeners.remove(listener);
  void _publishPrivacy(Note note) {
    for (final listener in List.of(_privacyListeners)) {
      try {
        listener(note.id, note.isPrivate);
      } catch (_) {
        /* commit is authoritative */
      }
    }
  }

  /// Classification metadata only; no private titles or content are read.
  Future<Set<String>> privateNoteIds() async => {
    for (final row in await _database.query(
      'notes',
      columns: ['id'],
      where: 'is_private = 1',
    ))
      row['id'] as String,
  };
  bool _usesFts = false;

  Future<void> initialize() async {
    await _database.execute('PRAGMA foreign_keys = ON');
    await _createNotesTable(_database, 'notes');
    await _addPrivacyColumn(_database);
    await _addReminderColumn(_database);
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS note_assets (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('image', 'audio', 'video', 'file')),
        storage_key TEXT NOT NULL UNIQUE,
        original_name TEXT NOT NULL,
        display_name TEXT,
        byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
        mime_type TEXT NOT NULL,
        preview_storage_key TEXT UNIQUE,
        duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
        ocr_text TEXT,
        transcript TEXT,
        transcription_engine TEXT,
        transcribed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS note_tags (
        note_id TEXT NOT NULL,
        position INTEGER NOT NULL CHECK(position >= 0),
        value TEXT NOT NULL,
        normalized_value TEXT NOT NULL,
        PRIMARY KEY(note_id, normalized_value),
        UNIQUE(note_id, position),
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await _createNoteLinksTable(_database);
    await _createConstellationTables(_database);
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_updated '
      'ON notes(is_pinned DESC, updated_at DESC)',
    );
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_space_updated '
      'ON notes(is_private, is_pinned DESC, updated_at DESC)',
    );
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_assets_note ON note_assets(note_id)',
    );
    await _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_tags_value '
      'ON note_tags(normalized_value)',
    );
    await _createSearchIndex();
    await _createAgentTables(_database);
  }

  static Future<void> upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await _removeLegacyOrganizationColumns(database);
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _createNoteLinksTable(database);
    }
    if (oldVersion < 4 && newVersion >= 4) {
      await _createConstellationTables(database);
    }
    if (oldVersion < 5 && newVersion >= 5) {
      await _migrateConstellationPositionsToWorld(database);
    }
    if (oldVersion < 6 && newVersion >= 6) {
      await _createConstellationOverviewTable(database);
    }
    if (oldVersion < 7 && newVersion >= 7) {
      await _createConstellationOverviewRegionTable(database);
    }
    if (oldVersion < 8 && newVersion >= 8) {
      await _addPrivacyColumn(database);
    }
    if (oldVersion < 9 && newVersion >= 9) {
      await _addReminderColumn(database);
    }
    if (oldVersion < 10 && newVersion >= 10) {
      await _createAgentTables(database);
    }
  }

  static Future<void> _createAgentTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS agent_library_identity (id INTEGER PRIMARY KEY CHECK(id = 1), epoch TEXT NOT NULL)',
    );
    await db.insert('agent_library_identity', {
      'id': 1,
      'epoch': const Uuid().v4(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS agent_operation_receipts (operation_id TEXT PRIMARY KEY, arguments_digest TEXT NOT NULL, library_epoch TEXT NOT NULL, result_json TEXT NOT NULL, created_at INTEGER NOT NULL)',
    );
  }

  Future<String> get agentEpoch async =>
      (await _database.query(
            'agent_library_identity',
            where: 'id = 1',
          )).single['epoch']!
          as String;

  /// Export strips execution metadata. Restore rotates it even for a backup
  /// produced by another implementation that happened to retain the tables.
  Future<void> clearAgentMetadata({required bool restoring}) async {
    await _database.transaction((tx) async {
      await tx.delete('agent_operation_receipts');
      await tx.delete('agent_library_identity');
      if (restoring) {
        await tx.insert('agent_library_identity', {
          'id': 1,
          'epoch': const Uuid().v4(),
        });
      }
    });
    await _database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    // Deleted metadata must not remain in free pages of an exported database.
    if (!restoring) await _database.execute('VACUUM');
  }

  Future<Map<String, dynamic>?> agentReceipt({
    required String operationId,
    required String argumentsDigest,
    required String epoch,
  }) => _agentReceipt(_database, operationId, argumentsDigest, epoch);

  Future<Map<String, dynamic>?> _agentReceipt(
    DatabaseExecutor db,
    String operationId,
    String digest,
    String epoch,
  ) async {
    final identity = await db.query('agent_library_identity', where: 'id = 1');
    if (identity.singleOrNull?['epoch'] != epoch) {
      throw const NoteAgentConflict('libraryChanged');
    }
    final rows = await db.query(
      'agent_operation_receipts',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    if (rows.isEmpty) return null;
    if (rows.single['arguments_digest'] != digest ||
        rows.single['library_epoch'] != epoch) {
      throw const NoteAgentConflict('operationMismatch');
    }
    return jsonDecode(rows.single['result_json']! as String)
        as Map<String, dynamic>;
  }

  /// A group is all-or-nothing. The durable receipt and revisions commit in
  /// this same transaction; callers may safely recover a lost task-store save.
  Future<Map<String, dynamic>> applyAgentMutations({
    required String operationId,
    required String argumentsDigest,
    required String epoch,
    required List<AgentNoteMutation> mutations,
    required void Function() validateAccess,
  }) async {
    if (mutations.isEmpty ||
        mutations.length > 30 ||
        mutations.map((m) => m.id).toSet().length != mutations.length) {
      throw const NoteAgentConflict('invalidChanges');
    }
    final result = await _database.transaction((tx) async {
      validateAccess();
      final recovered = await _agentReceipt(
        tx,
        operationId,
        argumentsDigest,
        epoch,
      );
      if (recovered != null) return recovered;
      final results = <Map<String, Object?>>[];
      for (final mutation in mutations) {
        validateAccess();
        final existing = await tx.query(
          'notes',
          columns: ['revision'],
          where: 'id = ?',
          whereArgs: [mutation.id.value],
        );
        if ((existing.singleOrNull?['revision'] ?? 0) !=
            mutation.expectedRevision) {
          throw NoteWriteConflict(mutation.id);
        }
        final note = mutation.replacement;
        if (note == null) {
          if (mutation.expectedRevision == 0) {
            throw NoteWriteConflict(mutation.id);
          }
          final links = await tx.query(
            'note_links',
            columns: ['first_note_id'],
            where: 'first_note_id = ? OR second_note_id = ?',
            whereArgs: [mutation.id.value, mutation.id.value],
            limit: 1,
          );
          final memberships = await tx.query(
            'note_constellation_memberships',
            where: 'note_id = ?',
            whereArgs: [mutation.id.value],
            limit: 1,
          );
          if (links.isNotEmpty || memberships.isNotEmpty) {
            throw const NoteAgentConflict('noteRelationshipsChanged');
          }
          await tx.delete(
            'notes',
            where: 'id = ? AND revision = ?',
            whereArgs: [mutation.id.value, mutation.expectedRevision],
          );
          results.add({
            'noteId': mutation.id.value,
            'revision': 0,
            'deleted': true,
          });
          continue;
        }
        if (note.id != mutation.id) {
          throw const NoteAgentConflict('invalidChanges');
        }
        final nextRevision =
            mutation.nextRevision ?? mutation.expectedRevision + 1;
        if (nextRevision <= mutation.expectedRevision) {
          throw const NoteAgentConflict('invalidChanges');
        }
        final persisted = note.copyWith(revision: nextRevision);
        if (mutation.expectedRevision == 0) {
          await tx.insert('notes', _noteMap(persisted, cover: null));
        } else {
          final changed = await tx.update(
            'notes',
            _noteMap(persisted, cover: null),
            where: 'id = ? AND revision = ?',
            whereArgs: [mutation.id.value, mutation.expectedRevision],
          );
          if (changed != 1) throw NoteWriteConflict(mutation.id);
          await tx.delete(
            'note_assets',
            where: 'note_id = ?',
            whereArgs: [mutation.id.value],
          );
          await tx.delete(
            'note_tags',
            where: 'note_id = ?',
            whereArgs: [mutation.id.value],
          );
        }
        await _insertOwnedRows(tx, persisted);
        await _writeCover(tx, persisted);
        results.add({
          'noteId': mutation.id.value,
          'revision': persisted.revision,
          'deleted': false,
        });
      }
      validateAccess();
      final result = <String, dynamic>{
        'operationId': operationId,
        'results': results,
      };
      await tx.insert('agent_operation_receipts', {
        'operation_id': operationId,
        'arguments_digest': argumentsDigest,
        'library_epoch': epoch,
        'result_json': jsonEncode(result),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return result;
    });
    for (final mutation in mutations) {
      if (mutation.replacement != null) _publishPrivacy(mutation.replacement!);
      // Notification failure cannot turn an already-committed edit into a
      // failed transaction. The durable receipt remains authoritative.
      try {
        await onNoteChanged?.call(mutation.id);
      } catch (_) {
        /* rescheduled on next app startup */
      }
    }
    return result;
  }

  static Future<void> _addReminderColumn(DatabaseExecutor database) async {
    final columns = await database.rawQuery('PRAGMA table_info(notes)');
    if (!columns.any((row) => row['name'] == 'reminder_at')) {
      await database.execute(
        'ALTER TABLE notes ADD COLUMN reminder_at INTEGER',
      );
    }
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_reminder ON notes(reminder_at) '
      'WHERE reminder_at IS NOT NULL',
    );
  }

  static Future<void> _addPrivacyColumn(DatabaseExecutor database) async {
    final columns = await database.rawQuery('PRAGMA table_info(notes)');
    if (columns.any((row) => row['name'] == 'is_private')) return;
    await database.execute(
      'ALTER TABLE notes ADD COLUMN is_private INTEGER NOT NULL DEFAULT 0 '
      'CHECK(is_private IN (0, 1))',
    );
  }

  static Future<void> _createNoteLinksTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS note_links (
        first_note_id TEXT NOT NULL,
        second_note_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(first_note_id, second_note_id),
        CHECK(first_note_id < second_note_id),
        FOREIGN KEY(first_note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY(second_note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_links_second '
      'ON note_links(second_note_id)',
    );
  }

  static Future<void> _createConstellationTables(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS note_constellation_nodes (
        note_id TEXT PRIMARY KEY,
        x REAL NOT NULL,
        y REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await _createConstellationOverviewTable(database);
    await _createConstellationOverviewRegionTable(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS note_constellation_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        kind TEXT NOT NULL CHECK(kind IN ('cluster', 'nebula', 'galaxy')),
        color_index INTEGER NOT NULL CHECK(color_index >= 0 AND color_index < 5),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS note_constellation_memberships (
        group_id TEXT NOT NULL,
        note_id TEXT NOT NULL,
        PRIMARY KEY(group_id, note_id),
        FOREIGN KEY(group_id) REFERENCES note_constellation_groups(id)
          ON DELETE CASCADE,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_constellation_membership_note '
      'ON note_constellation_memberships(note_id)',
    );
  }

  static Future<void> _createConstellationOverviewTable(
    DatabaseExecutor database,
  ) => database.execute('''
    CREATE TABLE IF NOT EXISTS note_constellation_overview_nodes (
      group_key TEXT NOT NULL,
      note_id TEXT NOT NULL,
      x REAL NOT NULL,
      y REAL NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY(group_key, note_id),
      FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
    )
  ''');

  static Future<void> _createConstellationOverviewRegionTable(
    DatabaseExecutor database,
  ) => database.execute('''
    CREATE TABLE IF NOT EXISTS note_constellation_overview_regions (
      group_key TEXT PRIMARY KEY,
      x REAL NOT NULL,
      y REAL NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  static Future<void> _migrateConstellationPositionsToWorld(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE note_constellation_nodes_v5 (
        note_id TEXT PRIMARY KEY,
        x REAL NOT NULL,
        y REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      INSERT INTO note_constellation_nodes_v5 (note_id, x, y, updated_at)
      SELECT note_id, (x - 0.5) * 1200, (y - 0.5) * 1200, updated_at
      FROM note_constellation_nodes
    ''');
    await database.execute('DROP TABLE note_constellation_nodes');
    await database.execute(
      'ALTER TABLE note_constellation_nodes_v5 '
      'RENAME TO note_constellation_nodes',
    );
  }

  static Future<void> _createNotesTable(
    DatabaseExecutor database,
    String tableName,
  ) => database.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        document_json TEXT NOT NULL,
        search_text TEXT NOT NULL,
        is_pinned INTEGER NOT NULL CHECK(is_pinned IN (0, 1)),
        is_private INTEGER NOT NULL DEFAULT 0 CHECK(is_private IN (0, 1)),
        reminder_at INTEGER,
        cover_attachment_id TEXT,
        revision INTEGER NOT NULL CHECK(revision > 0),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(cover_attachment_id) REFERENCES note_assets(id)
          ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
      )
    ''');

  static Future<void> _removeLegacyOrganizationColumns(
    Database database,
  ) async {
    final columns = (await database.rawQuery(
      'PRAGMA table_info(notes)',
    )).map((row) => row['name']).whereType<String>().toSet();
    if (!columns.contains('status') &&
        !columns.contains('is_favorite') &&
        !columns.contains('trashed_at')) {
      return;
    }

    const requiredColumns = {
      'id',
      'title',
      'document_json',
      'search_text',
      'is_pinned',
      'cover_attachment_id',
      'revision',
      'created_at',
      'updated_at',
    };
    if (!columns.containsAll(requiredColumns)) {
      throw const FormatException('旧笔记数据库结构不完整，无法安全升级');
    }

    for (final trigger in [
      'notes_search_insert',
      'notes_search_update',
      'notes_search_delete',
    ]) {
      await database.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    for (final table in [
      '_fknotes_v2_assets',
      '_fknotes_v2_tags',
      '_fknotes_v2_covers',
    ]) {
      await database.execute('DROP TABLE IF EXISTS temp.$table');
    }

    await database.execute(
      'CREATE TEMP TABLE _fknotes_v2_assets AS SELECT * FROM note_assets',
    );
    await database.execute(
      'CREATE TEMP TABLE _fknotes_v2_tags AS SELECT * FROM note_tags',
    );
    await database.execute('''
      CREATE TEMP TABLE _fknotes_v2_covers AS
      SELECT id, cover_attachment_id
      FROM notes
      WHERE cover_attachment_id IS NOT NULL
    ''');
    await _createNotesTable(database, '_fknotes_v2_notes');
    await database.execute('''
      INSERT INTO _fknotes_v2_notes (
        id,
        title,
        document_json,
        search_text,
        is_pinned,
        cover_attachment_id,
        revision,
        created_at,
        updated_at
      )
      SELECT
        id,
        title,
        document_json,
        search_text,
        is_pinned,
        NULL,
        revision,
        created_at,
        updated_at
      FROM notes
    ''');

    // Backups live in TEMP tables, so clearing the child rows makes replacing
    // the parent table safe even with foreign keys enabled.
    await database.delete('note_assets');
    await database.delete('note_tags');
    await database.execute('DROP TABLE notes');
    await database.execute('ALTER TABLE _fknotes_v2_notes RENAME TO notes');
    await database.execute('''
      INSERT INTO note_assets (
        id,
        note_id,
        kind,
        storage_key,
        original_name,
        display_name,
        byte_length,
        mime_type,
        preview_storage_key,
        duration_ms,
        ocr_text,
        transcript,
        transcription_engine,
        transcribed_at,
        created_at,
        updated_at
      )
      SELECT
        id,
        note_id,
        kind,
        storage_key,
        original_name,
        display_name,
        byte_length,
        mime_type,
        preview_storage_key,
        duration_ms,
        ocr_text,
        transcript,
        transcription_engine,
        transcribed_at,
        created_at,
        updated_at
      FROM _fknotes_v2_assets
    ''');
    await database.execute('''
      INSERT INTO note_tags (
        note_id,
        position,
        value,
        normalized_value
      )
      SELECT note_id, position, value, normalized_value
      FROM _fknotes_v2_tags
    ''');
    await database.execute('''
      UPDATE notes
      SET cover_attachment_id = (
        SELECT covers.cover_attachment_id
        FROM _fknotes_v2_covers AS covers
        JOIN note_assets AS assets ON assets.id = covers.cover_attachment_id
        WHERE covers.id = notes.id
      )
      WHERE EXISTS (
        SELECT 1
        FROM _fknotes_v2_covers AS covers
        JOIN note_assets AS assets ON assets.id = covers.cover_attachment_id
        WHERE covers.id = notes.id
      )
    ''');

    for (final table in [
      '_fknotes_v2_assets',
      '_fknotes_v2_tags',
      '_fknotes_v2_covers',
    ]) {
      await database.execute('DROP TABLE temp.$table');
    }
  }

  Future<Note> create(Note note) async {
    if (note.revision != 0) {
      throw ArgumentError.value(
        note.revision,
        'revision',
        'Must start at zero',
      );
    }
    final persisted = note.copyWith(revision: 1);
    await _database.transaction((transaction) async {
      await transaction.insert('notes', _noteMap(persisted, cover: null));
      await _insertOwnedRows(transaction, persisted);
      await _writeCover(transaction, persisted);
    });
    _publishPrivacy(persisted);
    await onNoteChanged?.call(persisted.id);
    return persisted;
  }

  Future<Note> update(Note note) async {
    if (note.revision < 1) {
      throw ArgumentError.value(note.revision, 'revision', 'Must be persisted');
    }
    final persisted = note.copyWith(revision: note.revision + 1);
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'notes',
        _noteMap(persisted, cover: null),
        where: 'id = ? AND revision = ?',
        whereArgs: [note.id.value, note.revision],
      );
      if (changed != 1) throw NoteWriteConflict(note.id);
      await transaction.delete(
        'note_assets',
        where: 'note_id = ?',
        whereArgs: [note.id.value],
      );
      await transaction.delete(
        'note_tags',
        where: 'note_id = ?',
        whereArgs: [note.id.value],
      );
      await _insertOwnedRows(transaction, persisted);
      await _writeCover(transaction, persisted);
    });
    _publishPrivacy(persisted);
    await onNoteChanged?.call(persisted.id);
    return persisted;
  }

  /// Public entry points cannot resolve a private note, even by a known ID.
  Future<Note?> get(NoteId id, {bool privateSpace = false}) async {
    final rows = await _database.query(
      'notes',
      where: 'id = ? AND is_private = ?',
      whereArgs: [id.value, privateSpace ? 1 : 0],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _hydrate(rows)).single;
  }

  Future<List<Note>> list({bool privateSpace = false}) async {
    final rows = await _database.query(
      'notes',
      where: 'is_private = ?',
      whereArgs: [privateSpace ? 1 : 0],
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return _hydrate(rows);
  }

  Future<List<Note>> search(String query, {bool privateSpace = false}) async {
    final normalized = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];
    List<Map<String, Object?>> rows;
    // Trigram FTS cannot match one- or two-rune CJK queries. Those are common
    // for note search, so route them through the exact LIKE fallback.
    if (_usesFts && normalized.runes.length >= 3) {
      final phrase = '"${normalized.replaceAll('"', '""')}"';
      try {
        rows = await _database.rawQuery(
          '''
          SELECT notes.*
          FROM note_search_fts
          JOIN notes ON notes.id = note_search_fts.note_id
          WHERE note_search_fts MATCH ? AND notes.is_private = ?
          ORDER BY notes.is_pinned DESC, notes.updated_at DESC
          ''',
          [phrase, privateSpace ? 1 : 0],
        );
      } on DatabaseException {
        rows = await _searchWithLike(normalized, privateSpace: privateSpace);
      }
    } else {
      rows = await _searchWithLike(normalized, privateSpace: privateSpace);
    }
    return _hydrate(rows);
  }

  Future<NoteQueryPage> queryPage(
    NoteQueryFilter filter, {
    bool? privateSpace = false,
    int offset = 0,
    int limit = 10,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Invalid note query page.');
    }
    final query = filter.query.replaceAll(RegExp(r'\s+'), ' ').trim();
    final useFts = _usesFts && query.runes.length >= 3;
    try {
      return await _queryPage(
        filter,
        privateSpace: privateSpace,
        offset: offset,
        limit: limit,
        useFts: useFts,
      );
    } on DatabaseException {
      if (!useFts) rethrow;
      return _queryPage(
        filter,
        privateSpace: privateSpace,
        offset: offset,
        limit: limit,
        useFts: false,
      );
    }
  }

  Future<NoteQueryPage> _queryPage(
    NoteQueryFilter filter, {
    required bool? privateSpace,
    required int offset,
    required int limit,
    required bool useFts,
  }) async {
    final where = <String>[];
    final values = <Object?>[];
    if (privateSpace case final isPrivate?) {
      where.add('notes.is_private = ?');
      values.add(isPrivate ? 1 : 0);
    }
    final query = filter.query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (query.isNotEmpty) {
      if (useFts) {
        where.add('note_search_fts MATCH ?');
        values.add('"${query.replaceAll('"', '""')}"');
      } else {
        where.add("notes.search_text LIKE ? ESCAPE '\\'");
        values.add('%${_escapeLike(query)}%');
      }
    }
    final title = filter.title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isNotEmpty) {
      where.add("notes.title LIKE ? ESCAPE '\\'");
      values.add('%${_escapeLike(title)}%');
    }
    final tags = filter.tags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (filter.matchAllTags) {
      for (final tag in tags) {
        where.add(
          'EXISTS (SELECT 1 FROM note_tags AS tag_filter '
          'WHERE tag_filter.note_id = notes.id '
          'AND tag_filter.normalized_value = ?)',
        );
        values.add(tag);
      }
    } else if (tags.isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM note_tags AS tag_filter '
        'WHERE tag_filter.note_id = notes.id '
        'AND tag_filter.normalized_value IN '
        '(${List.filled(tags.length, '?').join(',')}))',
      );
      values.addAll(tags);
    }
    void dateRange(String column, DateTime? from, DateTime? to) {
      if (from != null) {
        where.add('notes.$column >= ?');
        values.add(from.toUtc().millisecondsSinceEpoch);
      }
      if (to != null) {
        where.add('notes.$column <= ?');
        values.add(to.toUtc().millisecondsSinceEpoch);
      }
    }

    dateRange('created_at', filter.createdFrom, filter.createdTo);
    dateRange('updated_at', filter.updatedFrom, filter.updatedTo);
    if (filter.isPinned case final pinned?) {
      where.add('notes.is_pinned = ?');
      values.add(pinned ? 1 : 0);
    }
    if (filter.hasAttachments case final hasAttachments?) {
      where.add(
        '${hasAttachments ? '' : 'NOT '}EXISTS '
        '(SELECT 1 FROM note_assets AS asset_filter '
        'WHERE asset_filter.note_id = notes.id)',
      );
    }
    final whereSql = where.isEmpty ? '1 = 1' : where.join(' AND ');
    final fromSql = useFts
        ? 'note_search_fts JOIN notes ON notes.id = note_search_fts.note_id'
        : 'notes';
    final countRows = await _database.rawQuery(
      'SELECT COUNT(*) AS total FROM $fromSql WHERE $whereSql',
      values,
    );
    final orderBy = switch (filter.sort) {
      NoteQuerySort.updatedDesc => 'notes.updated_at DESC, notes.id ASC',
      NoteQuerySort.createdDesc => 'notes.created_at DESC, notes.id ASC',
      NoteQuerySort.titleAsc => 'notes.title COLLATE NOCASE ASC, notes.id ASC',
      NoteQuerySort.titleDesc =>
        'notes.title COLLATE NOCASE DESC, notes.id ASC',
    };
    final rows = await _database.rawQuery(
      'SELECT notes.* FROM $fromSql WHERE $whereSql '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...values, limit, offset],
    );
    return NoteQueryPage(
      await _hydrate(rows),
      (countRows.single['total'] as int?) ?? 0,
    );
  }

  Future<bool> hasPrivateNotes() async => (await _database.query(
    'notes',
    columns: ['id'],
    where: 'is_private = 1',
    limit: 1,
  )).isNotEmpty;

  Future<void> deletePermanently(NoteId id) async {
    await _database.delete('notes', where: 'id = ?', whereArgs: [id.value]);
    await onNoteChanged?.call(id);
  }

  /// Checks routing eligibility without reading private titles or documents.
  Future<bool> isPrivateNote(NoteId id) async => (await _database.query(
    'notes',
    columns: ['id'],
    where: 'id = ? AND is_private = 1',
    whereArgs: [id.value],
    limit: 1,
  )).isNotEmpty;

  Future<List<NoteLink>> listLinks() async {
    final rows = await _database.query(
      'note_links',
      orderBy: 'created_at, first_note_id, second_note_id',
    );
    return List.unmodifiable([
      for (final row in rows)
        NoteLink(
          firstNoteId: NoteId.parse(row['first_note_id']! as String),
          secondNoteId: NoteId.parse(row['second_note_id']! as String),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at']! as int,
            isUtc: true,
          ),
        ),
    ]);
  }

  Future<NoteConstellationSnapshot> loadConstellation() async {
    final positionRows = await _database.query('note_constellation_nodes');
    final overviewPositionRows = await _database.query(
      'note_constellation_overview_nodes',
    );
    final overviewRegionRows = await _database.query(
      'note_constellation_overview_regions',
    );
    final groupRows = await _database.query(
      'note_constellation_groups',
      orderBy: 'updated_at DESC, name',
    );
    final membershipRows = await _database.query(
      'note_constellation_memberships',
      orderBy: 'group_id, note_id',
    );
    final memberships = <String, Set<NoteId>>{};
    for (final row in membershipRows) {
      memberships
          .putIfAbsent(row['group_id']! as String, () => {})
          .add(NoteId.parse(row['note_id']! as String));
    }
    final overviewPositions =
        <String, Map<NoteId, NoteConstellationOverviewPosition>>{};
    for (final row in overviewPositionRows) {
      final groupKey = row['group_key']! as String;
      final noteId = NoteId.parse(row['note_id']! as String);
      overviewPositions.putIfAbsent(
        groupKey,
        () => {},
      )[noteId] = NoteConstellationOverviewPosition(
        groupKey: groupKey,
        noteId: noteId,
        x: (row['x']! as num).toDouble(),
        y: (row['y']! as num).toDouble(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
          isUtc: true,
        ),
      );
    }
    return NoteConstellationSnapshot(
      positions: {
        for (final row in positionRows)
          NoteId.parse(row['note_id']! as String): NoteConstellationPosition(
            noteId: NoteId.parse(row['note_id']! as String),
            x: (row['x']! as num).toDouble(),
            y: (row['y']! as num).toDouble(),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at']! as int,
              isUtc: true,
            ),
          ),
      },
      groups: [
        for (final row in groupRows)
          NoteConstellationGroup(
            id: row['id']! as String,
            name: row['name']! as String,
            kind: NoteConstellationGroupKind.values.byName(
              row['kind']! as String,
            ),
            colorIndex: row['color_index']! as int,
            noteIds: memberships[row['id']! as String] ?? const {},
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at']! as int,
              isUtc: true,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at']! as int,
              isUtc: true,
            ),
          ),
      ],
      overviewPositions: overviewPositions,
      overviewRegionPositions: {
        for (final row in overviewRegionRows)
          row['group_key']! as String: NoteConstellationOverviewRegionPosition(
            groupKey: row['group_key']! as String,
            x: (row['x']! as num).toDouble(),
            y: (row['y']! as num).toDouble(),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at']! as int,
              isUtc: true,
            ),
          ),
      },
    );
  }

  Future<void> saveConstellationPosition(
    NoteId noteId,
    double x,
    double y, {
    DateTime? updatedAt,
  }) async {
    final position = NoteConstellationPosition(
      noteId: noteId,
      x: x,
      y: y,
      updatedAt: updatedAt ?? DateTime.now(),
    );
    await _database.insert('note_constellation_nodes', {
      'note_id': noteId.value,
      'x': position.x,
      'y': position.y,
      'updated_at': position.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveConstellationOverviewPosition(
    String groupKey,
    NoteId noteId,
    double x,
    double y, {
    DateTime? updatedAt,
  }) async {
    final position = NoteConstellationOverviewPosition(
      groupKey: groupKey,
      noteId: noteId,
      x: x,
      y: y,
      updatedAt: updatedAt ?? DateTime.now(),
    );
    await _database.insert('note_constellation_overview_nodes', {
      'group_key': position.groupKey,
      'note_id': noteId.value,
      'x': position.x,
      'y': position.y,
      'updated_at': position.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveConstellationOverviewRegionPosition(
    String groupKey,
    double x,
    double y, {
    DateTime? updatedAt,
  }) async {
    final position = NoteConstellationOverviewRegionPosition(
      groupKey: groupKey,
      x: x,
      y: y,
      updatedAt: updatedAt ?? DateTime.now(),
    );
    await _database.insert('note_constellation_overview_regions', {
      'group_key': position.groupKey,
      'x': position.x,
      'y': position.y,
      'updated_at': position.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveConstellationGroup(NoteConstellationGroup group) async {
    await _database.transaction((transaction) async {
      await transaction.insert('note_constellation_groups', {
        'id': group.id,
        'name': group.name,
        'kind': group.kind.name,
        'color_index': group.colorIndex,
        'created_at': group.createdAt.millisecondsSinceEpoch,
        'updated_at': group.updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete(
        'note_constellation_memberships',
        where: 'group_id = ?',
        whereArgs: [group.id],
      );
      for (final noteId in group.noteIds) {
        await transaction.insert('note_constellation_memberships', {
          'group_id': group.id,
          'note_id': noteId.value,
        });
      }
    });
  }

  Future<void> deleteConstellationGroup(String groupId) => _database.delete(
    'note_constellation_groups',
    where: 'id = ?',
    whereArgs: [groupId],
  );

  /// Replaces every relationship touching [noteId] in one transaction.
  Future<void> replaceLinks(
    NoteId noteId,
    Iterable<NoteId> otherNoteIds, {
    DateTime? createdAt,
  }) async {
    final others = otherNoteIds.where((id) => id != noteId).toSet();
    final timestamp = (createdAt ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch;
    await _database.transaction((transaction) async {
      await transaction.delete(
        'note_links',
        where: 'first_note_id = ? OR second_note_id = ?',
        whereArgs: [noteId.value, noteId.value],
      );
      for (final otherId in others) {
        final link = NoteLink.between(
          noteId,
          otherId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            timestamp,
            isUtc: true,
          ),
        );
        await transaction.insert('note_links', {
          'first_note_id': link.firstNoteId.value,
          'second_note_id': link.secondNoteId.value,
          'created_at': timestamp,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> _searchWithLike(
    String query, {
    required bool privateSpace,
  }) => _database.query(
    'notes',
    where: "is_private = ? AND search_text LIKE ? ESCAPE '\\'",
    whereArgs: [privateSpace ? 1 : 0, '%${_escapeLike(query)}%'],
    orderBy: 'is_pinned DESC, updated_at DESC',
  );

  Future<void> _createSearchIndex() async {
    try {
      await _database.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS note_search_fts USING fts5(
          note_id UNINDEXED,
          content,
          tokenize = 'trigram case_sensitive 0'
        )
      ''');
    } on DatabaseException {
      try {
        await _database.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS note_search_fts USING fts5(
            note_id UNINDEXED,
            content,
            tokenize = 'unicode61 remove_diacritics 2'
          )
        ''');
      } on DatabaseException {
        await _database.execute('''
          CREATE TABLE IF NOT EXISTS note_search_fts (
            note_id TEXT PRIMARY KEY,
            content TEXT NOT NULL
          )
        ''');
      }
    }
    final table = await _database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = 'note_search_fts'",
    );
    _usesFts =
        table.singleOrNull?['sql']?.toString().toUpperCase().contains(
          'VIRTUAL TABLE',
        ) ==
        true;
    for (final trigger in [
      'notes_search_insert',
      'notes_search_update',
      'notes_search_delete',
    ]) {
      await _database.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    await _database.execute('''
      CREATE TRIGGER notes_search_insert AFTER INSERT ON notes BEGIN
        INSERT INTO note_search_fts(note_id, content)
        VALUES(NEW.id, NEW.search_text);
      END
    ''');
    await _database.execute('''
      CREATE TRIGGER notes_search_update AFTER UPDATE ON notes BEGIN
        DELETE FROM note_search_fts WHERE note_id = OLD.id;
        INSERT INTO note_search_fts(note_id, content)
        VALUES(NEW.id, NEW.search_text);
      END
    ''');
    await _database.execute('''
      CREATE TRIGGER notes_search_delete AFTER DELETE ON notes BEGIN
        DELETE FROM note_search_fts WHERE note_id = OLD.id;
      END
    ''');
    await _database.delete('note_search_fts');
    await _database.execute('''
      INSERT INTO note_search_fts(note_id, content)
      SELECT id, search_text FROM notes
    ''');
  }

  Future<void> _insertOwnedRows(DatabaseExecutor transaction, Note note) async {
    for (final asset in note.assets) {
      await transaction.insert('note_assets', _assetMap(note.id, asset));
    }
    for (var index = 0; index < note.tags.length; index++) {
      final tag = note.tags[index];
      await transaction.insert('note_tags', {
        'note_id': note.id.value,
        'position': index,
        'value': tag,
        'normalized_value': tag.toLowerCase(),
      });
    }
  }

  Future<void> _writeCover(DatabaseExecutor transaction, Note note) async {
    final cover = note.coverAttachmentId;
    if (cover == null) return;
    await transaction.update(
      'notes',
      {'cover_attachment_id': cover.value},
      where: 'id = ?',
      whereArgs: [note.id.value],
    );
  }

  Future<List<Note>> _hydrate(List<Map<String, Object?>> noteRows) async {
    if (noteRows.isEmpty) return const [];
    final ids = noteRows.map((row) => row['id']! as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final assetRows = await _database.rawQuery(
      'SELECT * FROM note_assets WHERE note_id IN ($placeholders) '
      'ORDER BY created_at, id',
      ids,
    );
    final tagRows = await _database.rawQuery(
      'SELECT * FROM note_tags WHERE note_id IN ($placeholders) '
      'ORDER BY position',
      ids,
    );
    final assetsByNote = <String, List<NoteAsset>>{};
    for (final row in assetRows) {
      assetsByNote
          .putIfAbsent(row['note_id']! as String, () => [])
          .add(_assetFromMap(row));
    }
    final tagsByNote = <String, List<String>>{};
    for (final row in tagRows) {
      tagsByNote
          .putIfAbsent(row['note_id']! as String, () => [])
          .add(row['value']! as String);
    }
    return [
      for (final row in noteRows)
        _noteFromMap(
          row,
          assetsByNote[row['id']] ?? const [],
          tagsByNote[row['id']] ?? const [],
        ),
    ];
  }

  static Map<String, Object?> _noteMap(Note note, {NoteAttachmentId? cover}) =>
      {
        'id': note.id.value,
        'title': note.title,
        'document_json': note.document.toJsonString(),
        'search_text': note.searchText,
        'is_pinned': note.isPinned ? 1 : 0,
        'is_private': note.isPrivate ? 1 : 0,
        'reminder_at': note.reminderAt?.millisecondsSinceEpoch,
        'cover_attachment_id': cover?.value,
        'revision': note.revision,
        'created_at': note.createdAt.millisecondsSinceEpoch,
        'updated_at': note.updatedAt.millisecondsSinceEpoch,
      };

  static Map<String, Object?> _assetMap(NoteId noteId, NoteAsset asset) => {
    'id': asset.id.value,
    'note_id': noteId.value,
    'kind': asset.kind.name,
    'storage_key': asset.storageKey,
    'original_name': asset.originalName,
    'display_name': asset.displayName,
    'byte_length': asset.byteLength,
    'mime_type': asset.mimeType,
    'preview_storage_key': asset.previewStorageKey,
    'duration_ms': asset.durationMs,
    'ocr_text': asset.ocrText,
    'transcript': asset.transcript,
    'transcription_engine': asset.transcriptionEngine,
    'transcribed_at': asset.transcribedAt?.toUtc().millisecondsSinceEpoch,
    'created_at': asset.createdAt.millisecondsSinceEpoch,
    'updated_at': asset.updatedAt.millisecondsSinceEpoch,
  };

  static Note _noteFromMap(
    Map<String, Object?> map,
    List<NoteAsset> assets,
    List<String> tags,
  ) => Note(
    id: NoteId.parse(map['id']! as String),
    title: map['title']! as String,
    document: NoteDocument.fromJsonString(map['document_json']! as String),
    tags: tags,
    isPinned: map['is_pinned'] == 1,
    isPrivate: map['is_private'] == 1,
    reminderAt: map['reminder_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            map['reminder_at']! as int,
            isUtc: true,
          ),
    coverAttachmentId: map['cover_attachment_id'] == null
        ? null
        : NoteAttachmentId.parse(map['cover_attachment_id']! as String),
    assets: assets,
    revision: map['revision']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      map['created_at']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      map['updated_at']! as int,
      isUtc: true,
    ),
  );

  static NoteAsset _assetFromMap(Map<String, Object?> map) => NoteAsset(
    id: NoteAttachmentId.parse(map['id']! as String),
    kind: NoteAssetKind.values.byName(map['kind']! as String),
    storageKey: map['storage_key']! as String,
    originalName: map['original_name']! as String,
    displayName: map['display_name'] as String?,
    byteLength: map['byte_length']! as int,
    mimeType: map['mime_type']! as String,
    previewStorageKey: map['preview_storage_key'] as String?,
    durationMs: map['duration_ms'] as int?,
    ocrText: map['ocr_text'] as String?,
    transcript: map['transcript'] as String?,
    transcriptionEngine: map['transcription_engine'] as String?,
    transcribedAt: map['transcribed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            map['transcribed_at']! as int,
            isUtc: true,
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      map['created_at']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      map['updated_at']! as int,
      isUtc: true,
    ),
  );

  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

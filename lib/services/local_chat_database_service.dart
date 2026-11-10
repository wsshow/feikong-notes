import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/local_chat.dart';
import 'file_storage_service.dart';

/// Isolated persistence for local-assistant conversations.
///
/// This schema starts clean and never opens or migrates tables from the old
/// note database. Note content remains exclusively owned by `fknotes.db`.
final class LocalChatDatabaseService {
  LocalChatDatabaseService({this.databasePath});

  static final LocalChatDatabaseService instance = LocalChatDatabaseService();
  static const String databaseFileName = 'fknotes-chat.db';
  static const int schemaVersion = 3;

  final String? databasePath;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path =
        databasePath ??
        p.join(FileStorageService.instance.baseDir, databaseFileName);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        // journal_mode returns a row and cannot be issued through `execute`
        // on Android's SQLite driver.
        await database.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE chat_personas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            system_prompt TEXT NOT NULL,
            built_in INTEGER NOT NULL CHECK(built_in IN (0, 1)),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE chat_sessions (
            id TEXT PRIMARY KEY,
            is_private INTEGER NOT NULL DEFAULT 0 CHECK(is_private IN (0, 1)),
            title TEXT NOT NULL,
            persona_id TEXT NOT NULL DEFAULT '${LocalChatPersona.defaultId}',
            system_prompt TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(persona_id) REFERENCES chat_personas(id)
              ON DELETE SET DEFAULT
          )
        ''');
        await database.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
            content TEXT NOT NULL,
            attachments_json TEXT NOT NULL,
            note_contexts_json TEXT NOT NULL,
            tool_calls_json TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('complete', 'stopped')),
            created_at TEXT NOT NULL,
            sort_order INTEGER NOT NULL CHECK(sort_order >= 0),
            UNIQUE(session_id, sort_order),
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id)
              ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_chat_sessions_updated '
          'ON chat_sessions(updated_at DESC)',
        );
        await database.execute(
          'CREATE INDEX idx_chat_messages_session '
          'ON chat_messages(session_id, sort_order)',
        );
        await _seedDefaultPersona(database);
      },
      onUpgrade: _upgrade,
    );
  }

  static Future<void> _upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await database.execute(
        'ALTER TABLE chat_sessions ADD COLUMN is_private INTEGER NOT NULL '
        'DEFAULT 0 CHECK(is_private IN (0, 1))',
      );
    }
    if (oldVersion < 2) {
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await database.update(
        'chat_personas',
        {
          'name': '非空笔记助手',
          'description': '记录、查找、整理和完善笔记',
          'system_prompt': LocalChatPersona.defaultSystemPrompt,
          'updated_at': timestamp,
        },
        where: 'id = ?',
        whereArgs: [LocalChatPersona.defaultId],
      );
      await database.update(
        'chat_sessions',
        {'system_prompt': LocalChatPersona.defaultSystemPrompt},
        where: 'persona_id = ?',
        whereArgs: [LocalChatPersona.defaultId],
      );
    }
  }

  static Future<void> _seedDefaultPersona(DatabaseExecutor database) async {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    ).toIso8601String();
    await database.insert('chat_personas', {
      'id': LocalChatPersona.defaultId,
      'name': '非空笔记助手',
      'description': '记录、查找、整理和完善笔记',
      'system_prompt': LocalChatPersona.defaultSystemPrompt,
      'built_in': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> validate() async {
    final db = await database;
    final quickCheck = await db.rawQuery('PRAGMA quick_check');
    if (quickCheck.singleOrNull?.values.singleOrNull != 'ok') {
      throw const FormatException('本地助手数据库完整性检查失败');
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('本地助手数据库关联损坏');
    }
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).whereType<String>().toSet();
    if (!tables.containsAll(const {
      'chat_personas',
      'chat_sessions',
      'chat_messages',
    })) {
      throw const FormatException('本地助手数据库结构不完整');
    }
  }

  /// Produces a transactionally consistent, sidecar-free SQLite snapshot.
  /// `VACUUM INTO` also prevents a writer that is currently committing from
  /// leaving a copied database and WAL at different revisions.
  Future<void> snapshotTo(File target) async {
    if (await target.exists()) await target.delete();
    await target.parent.create(recursive: true);
    final escaped = target.path.replaceAll("'", "''");
    await (await database).execute("VACUUM INTO '$escaped'");
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

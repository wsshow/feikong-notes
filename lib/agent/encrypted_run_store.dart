import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:sqflite/sqflite.dart';

import 'credential_vault.dart';

/// A separate database; only identifiers, status and timestamps are plaintext.
/// AES-GCM authenticates the run ID and CAS revision as well as every payload.
class EncryptedRunStore implements RunStore {
  static const fileName = 'fknotes-agent.db';
  static const keyId = 'fknotes.agent.database.key.v1';
  static Future<void> _keyQueue = Future.value();
  final Database database;
  final SecretKey _key;
  final _cipher = AesGcm.with256bits();
  final _cache = <String, AgentRun>{};
  EncryptedRunStore._(this.database, this._key);

  static Future<EncryptedRunStore> open(
    String path,
    CredentialVault vault, {
    DatabaseFactory? factory,
    bool singleInstance = true,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: singleInstance,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE runs (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, root_id TEXT NOT NULL, revision INTEGER NOT NULL, status TEXT NOT NULL, updated_at INTEGER NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX runs_session ON runs(session_id, updated_at)',
          );
        },
      ),
    );
    try {
      final keyFuture = _keyQueue.then((_) async {
        var value = await vault.read(keyId);
        if (value == null) {
          if ((await db.query('runs', columns: ['id'], limit: 1)).isNotEmpty) {
            throw const HarnessException(
              'taskKeyMissing',
              'Task encryption key is unavailable. Restore access or explicitly clear task history.',
            );
          }
          value = base64Encode(
            await (await AesGcm.with256bits().newSecretKey()).extractBytes(),
          );
          await vault.write(keyId, value);
        }
        final bytes = base64Decode(value);
        if (bytes.length != 32) {
          throw const HarnessException(
            'taskKeyInvalid',
            'Task encryption key is invalid.',
          );
        }
        return SecretKey(bytes);
      });
      _keyQueue = keyFuture.then((_) {}, onError: (Object _, StackTrace _) {});
      return EncryptedRunStore._(db, await keyFuture);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<AgentRun> _decode(Map<String, Object?> row) async {
    try {
      final box = jsonDecode(row['payload']! as String) as Json;
      if (box['version'] != 1) throw const FormatException();
      final bytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(box['cipher'] as String),
          nonce: base64Decode(box['nonce'] as String),
          mac: Mac(base64Decode(box['mac'] as String)),
        ),
        secretKey: _key,
        aad: utf8.encode('${row['id']}:${row['revision']}'),
      );
      final run = AgentRun.fromJson(jsonDecode(utf8.decode(bytes)) as Json);
      if (run.id != row['id'] ||
          run.revision != row['revision'] ||
          run.sessionId != row['session_id'] ||
          run.rootId != row['root_id'] ||
          run.status.name != row['status']) {
        throw const FormatException();
      }
      return run;
    } catch (_) {
      throw const HarnessException(
        'taskCorrupt',
        'Task data could not be authenticated. No actions were resumed.',
      );
    }
  }

  @override
  Future<AgentRun?> get(String id) async {
    final cached = _cache[id];
    if (cached != null) {
      final metadata = await database.query(
        'runs',
        columns: ['id', 'session_id', 'root_id', 'revision', 'status'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (metadata.isEmpty) {
        _cache.remove(id);
        return null;
      }
      final row = metadata.single;
      if (cached.revision == row['revision'] &&
          cached.sessionId == row['session_id'] &&
          cached.rootId == row['root_id'] &&
          cached.status.name == row['status']) {
        return cached.clone();
      }
      _cache.remove(id);
    }
    final rows = await database.query('runs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final run = await _decode(rows.single);
    _cache[id] = run;
    return run.clone();
  }

  @override
  Future<List<AgentRun>> list({String? sessionId}) async {
    final rows = await database.query(
      'runs',
      where: sessionId == null ? null : 'session_id = ?',
      whereArgs: sessionId == null ? null : [sessionId],
      orderBy: 'updated_at DESC',
    );
    final runs = <AgentRun>[];
    for (final row in rows) {
      final id = row['id']! as String;
      final revision = row['revision']! as int;
      var run = _cache[id];
      if (run == null || run.revision != revision) {
        run = await _decode(row);
        _cache[id] = run;
      }
      runs.add(run.clone());
    }
    return runs;
  }

  @override
  Future<void> save(AgentRun run, {required int expectedRevision}) async {
    if (run.revision != expectedRevision + 1) {
      throw const HarnessException('writeConflict', 'Task revision changed.');
    }
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(run.toJson())),
      secretKey: _key,
      aad: utf8.encode('${run.id}:${run.revision}'),
    );
    final row = <String, Object?>{
      'id': run.id,
      'session_id': run.sessionId,
      'root_id': run.rootId,
      'revision': run.revision,
      'status': run.status.name,
      'updated_at': run.updatedAt.millisecondsSinceEpoch,
      'payload': jsonEncode({
        'version': 1,
        'nonce': base64Encode(box.nonce),
        'cipher': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    };
    await database.transaction((tx) async {
      if (expectedRevision == 0) {
        if ((await tx.query(
          'runs',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [run.id],
        )).isNotEmpty) {
          throw const HarnessException('writeConflict', 'Task already exists.');
        }
        await tx.insert('runs', row);
      } else {
        if (await tx.update(
              'runs',
              row,
              where: 'id = ? AND revision = ?',
              whereArgs: [run.id, expectedRevision],
            ) !=
            1) {
          throw const HarnessException(
            'writeConflict',
            'Task changed in another executor.',
          );
        }
      }
    });
    _cache[run.id] = run.clone();
  }

  @override
  Future<void> delete(String id) async {
    final run = await get(id);
    if (run == null) return;
    final runs = await list();
    if (runs.any((r) => (r.id == id || r.rootId == id) && !r.status.terminal)) {
      throw const HarnessException(
        'taskActive',
        'Stop the task before deleting it.',
      );
    }
    await database.delete(
      'runs',
      where: 'id = ? OR root_id = ?',
      whereArgs: [id, id],
    );
    _cache.removeWhere((_, run) => run.id == id || run.rootId == id);
  }

  Future<void> prune({required DateTime before}) async {
    for (final run in await list()) {
      if (run.parentId == null &&
          run.status.terminal &&
          run.updatedAt.isBefore(before)) {
        await delete(run.id);
      }
    }
  }

  Future<void> close() {
    _cache.clear();
    return database.close();
  }
}

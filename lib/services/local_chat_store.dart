import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../debug/app_diagnostics.dart';
import '../models/local_chat.dart';
import 'file_storage_service.dart';
import 'local_chat_database_service.dart';

class LocalChatStore {
  LocalChatStore._();
  static final LocalChatStore instance = LocalChatStore._();

  static const defaultSystemPrompt = LocalChatPersona.defaultSystemPrompt;

  final _uuid = const Uuid();
  Future<void>? _writeQueue;

  Future<void> flushWrites() async => _writeQueue;

  Future<void> _serializeWrite(Future<void> Function() write) {
    final pending = _writeQueue;
    final result = pending == null
        ? Future<void>.sync(write)
        : pending.then((_) => write());
    late final Future<void> tail;
    tail = result.catchError((_) {}).whenComplete(() {
      if (identical(_writeQueue, tail)) _writeQueue = null;
    });
    _writeQueue = tail;
    return result;
  }

  LocalChatSession createSession({
    bool privateSpace = false,
    String personaId = LocalChatPersona.defaultId,
    String? systemPrompt,
  }) {
    final now = DateTime.now();
    return LocalChatSession(
      privateSpace: privateSpace,
      id: _uuid.v4(),
      title: '新对话',
      personaId: personaId,
      systemPrompt: systemPrompt ?? defaultSystemPrompt,
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  LocalChatMessage createMessage({
    required LocalChatRole role,
    required String content,
    List<LocalChatAttachment> attachments = const [],
    List<LocalChatNoteContext> noteContexts = const [],
    List<LocalChatToolCall> toolCalls = const [],
    LocalChatMessageStatus status = LocalChatMessageStatus.complete,
  }) => LocalChatMessage(
    id: _uuid.v4(),
    role: role,
    content: content,
    attachments: List.unmodifiable(attachments),
    noteContexts: List.unmodifiable(noteContexts),
    toolCalls: List.unmodifiable(toolCalls),
    createdAt: DateTime.now(),
    status: status,
  );

  String titleFrom(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '新对话';
    final runes = normalized.runes.toList(growable: false);
    if (runes.length <= 24) return normalized;
    return '${String.fromCharCodes(runes.take(24))}…';
  }

  LocalChatAttachment createImageAttachment({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) => LocalChatAttachment(
    id: _uuid.v4(),
    type: LocalChatAttachmentType.image,
    filePath: filePath,
    fileName: fileName,
    mimeType: mimeType,
    createdAt: DateTime.now(),
  );

  LocalChatPersona createPersona({
    required String name,
    required String description,
    required String systemPrompt,
  }) {
    final now = DateTime.now();
    return LocalChatPersona(
      id: _uuid.v4(),
      name: name.trim(),
      description: description.trim(),
      systemPrompt: systemPrompt.trim(),
      builtIn: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<List<LocalChatPersona>> loadPersonas() async {
    final database = await LocalChatDatabaseService.instance.database;
    final rows = await database.query(
      'chat_personas',
      orderBy: 'built_in DESC, updated_at DESC',
    );
    return rows
        .map(
          (row) => LocalChatPersona(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String,
            systemPrompt: row['system_prompt'] as String,
            builtIn: row['built_in'] == 1,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> savePersona(LocalChatPersona persona) async {
    if (persona.name.trim().isEmpty || persona.systemPrompt.trim().isEmpty) {
      throw const FormatException('角色名称和系统提示词不能为空');
    }
    final database = await LocalChatDatabaseService.instance.database;
    await database.insert('chat_personas', {
      'id': persona.id,
      'name': persona.name.trim(),
      'description': persona.description.trim(),
      'system_prompt': persona.systemPrompt.trim(),
      'built_in': persona.builtIn ? 1 : 0,
      'created_at': persona.createdAt.toIso8601String(),
      'updated_at': persona.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePersona(String id) async {
    if (id == LocalChatPersona.defaultId) {
      throw const FormatException('内置角色不能删除');
    }
    final database = await LocalChatDatabaseService.instance.database;
    await database.transaction((transaction) async {
      await transaction.update(
        'chat_sessions',
        {
          'persona_id': LocalChatPersona.defaultId,
          'system_prompt': defaultSystemPrompt,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'persona_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'chat_personas',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<LocalChatSession>> loadSessions({
    bool? privateSpace = false,
  }) async {
    final database = await LocalChatDatabaseService.instance.database;
    final sessionRows = await database.query(
      'chat_sessions',
      where: privateSpace == null ? null : 'is_private = ?',
      whereArgs: privateSpace == null ? null : [privateSpace ? 1 : 0],
      orderBy: 'updated_at DESC',
    );
    if (sessionRows.isEmpty) return [];
    final messageRows = await database.query(
      'chat_messages',
      where: privateSpace == null
          ? null
          : 'session_id IN (SELECT id FROM chat_sessions WHERE is_private = ?)',
      whereArgs: privateSpace == null ? null : [privateSpace ? 1 : 0],
      orderBy: 'session_id, sort_order',
    );
    final messagesBySession = <String, List<LocalChatMessage>>{};
    for (final row in messageRows) {
      final sessionId = row['session_id'] as String;
      messagesBySession
          .putIfAbsent(sessionId, () => [])
          .add(
            LocalChatMessage(
              id: row['id'] as String,
              role: row['role'] == 'assistant'
                  ? LocalChatRole.assistant
                  : LocalChatRole.user,
              content: row['content'] as String,
              attachments: _decodeAttachments(
                row['attachments_json'] as String? ?? '[]',
              ),
              noteContexts: _decodeNoteContexts(
                row['note_contexts_json'] as String? ?? '[]',
              ),
              toolCalls: _decodeToolCalls(
                row['tool_calls_json'] as String? ?? '[]',
              ),
              createdAt: DateTime.parse(row['created_at'] as String),
              status: row['status'] == 'stopped'
                  ? LocalChatMessageStatus.stopped
                  : LocalChatMessageStatus.complete,
            ),
          );
    }
    final sessions = sessionRows
        .map(
          (row) => LocalChatSession(
            privateSpace: row['is_private'] == 1,
            id: row['id'] as String,
            title: row['title'] as String,
            personaId:
                row['persona_id'] as String? ?? LocalChatPersona.defaultId,
            systemPrompt: row['system_prompt'] as String,
            messages: List.unmodifiable(messagesBySession[row['id']] ?? []),
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList();
    if (kDebugMode) {
      AppDiagnostics.debug(
        AppLogCategory.localAssistant,
        'chat_history_loaded',
        data: {
          'sessionCount': sessions.length,
          'messageCount': messageRows.length,
        },
      );
    }
    return sessions;
  }

  Future<void> saveSession(LocalChatSession session) {
    final result = _serializeWrite(() async {
      final database = await LocalChatDatabaseService.instance.database;
      await database.transaction((transaction) async {
        final existing = await transaction.query(
          'chat_sessions',
          columns: ['is_private'],
          where: 'id = ?',
          whereArgs: [session.id],
        );
        await transaction.insert('chat_sessions', {
          'id': session.id,
          'is_private':
              session.privateSpace || existing.firstOrNull?['is_private'] == 1
              ? 1
              : 0,
          'title': session.title,
          'persona_id': session.personaId,
          'system_prompt': session.systemPrompt,
          'created_at': session.createdAt.toIso8601String(),
          'updated_at': session.updatedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [session.id],
        );
        final batch = transaction.batch();
        for (var index = 0; index < session.messages.length; index++) {
          final message = session.messages[index];
          batch.insert('chat_messages', {
            'id': message.id,
            'session_id': session.id,
            'role': message.role.name,
            'content': message.content,
            'attachments_json': jsonEncode(
              message.attachments
                  .map((attachment) => attachment.toJson())
                  .toList(),
            ),
            'note_contexts_json': jsonEncode(
              message.noteContexts.map((context) => context.toJson()).toList(),
            ),
            'tool_calls_json': jsonEncode(
              message.toolCalls.map((call) => call.toJson()).toList(),
            ),
            'status': message.status.name,
            'created_at': message.createdAt.toIso8601String(),
            'sort_order': index,
          });
        }
        await batch.commit(noResult: true);
      });
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.localAssistant,
          'chat_session_saved',
          data: {
            'sessionId': session.id,
            'personaId': session.personaId,
            'messageCount': session.messages.length,
            'attachmentCount': session.messages.fold<int>(
              0,
              (total, message) => total + message.attachments.length,
            ),
            'characterCount': session.messages.fold<int>(
              0,
              (total, message) => total + message.content.length,
            ),
          },
          traceId: 'chat-${session.id}',
        );
      }
    });
    return result;
  }

  /// Older chats whose source notes became private move with their content.
  Future<void> protectLegacySources(Set<String> privateNoteIds) async {
    final database = await LocalChatDatabaseService.instance.database;
    final rows = await database.query(
      'chat_messages',
      columns: ['session_id', 'note_contexts_json', 'tool_calls_json'],
      where:
          'session_id IN (SELECT id FROM chat_sessions WHERE is_private = 0)',
    );
    await protectSessions({
      for (final row in rows)
        if (_decodeNoteContexts(row['note_contexts_json'] as String).any(
              (note) =>
                  note.isPrivate || privateNoteIds.contains(note.noteId.value),
            ) ||
            _decodeToolCalls(
              row['tool_calls_json'] as String,
            ).any((call) => privateNoteIds.contains(call.noteId?.value)))
          row['session_id'] as String,
    });
  }

  Future<void> protectSessions(Set<String> ids) async {
    if (ids.isEmpty) return;
    final database = await LocalChatDatabaseService.instance.database;
    final batch = database.batch();
    for (final id in ids) {
      batch.update(
        'chat_sessions',
        {'is_private': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  List<LocalChatNoteContext> _decodeNoteContexts(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .map(
            (item) => LocalChatNoteContext.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<LocalChatToolCall> _decodeToolCalls(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .map(
            (item) => LocalChatToolCall.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteSession(String id) {
    final result = _serializeWrite(() async {
      final database = await LocalChatDatabaseService.instance.database;
      final rows = await database.query(
        'chat_messages',
        columns: ['attachments_json'],
        where: 'session_id = ?',
        whereArgs: [id],
      );
      final paths = <String>{
        for (final row in rows)
          for (final attachment in _decodeAttachments(
            row['attachments_json'] as String? ?? '[]',
          ))
            attachment.filePath,
      };
      await database.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
      for (final path in paths) {
        await FileStorageService.instance.deleteFile(path);
      }
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.localAssistant,
          'chat_session_deleted',
          data: {'sessionId': id, 'attachmentCount': paths.length},
          traceId: 'chat-$id',
        );
      }
    });
    return result;
  }

  static List<LocalChatAttachment> _decodeAttachments(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      return decoded
          .map(
            (item) => LocalChatAttachment.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }
}

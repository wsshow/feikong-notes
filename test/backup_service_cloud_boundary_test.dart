import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:fknotes/agent/credential_vault.dart';
import 'package:fknotes/agent/encrypted_run_store.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fknotes/services/local_chat_database_service.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:fknotes/services/note_database_service.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late Directory exports;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await NoteDatabaseService.instance.close();
    await LocalChatDatabaseService.instance.close();
    storage = await Directory.systemTemp.createTemp('fknotes_backup_data');
    exports = await Directory.systemTemp.createTemp('fknotes_backup_export');
    await FileStorageService.instance.init(baseDir: storage.path);
    await NoteDatabaseService.instance.repository;
  });

  tearDown(() async {
    await NoteDatabaseService.instance.close();
    await LocalChatDatabaseService.instance.close();
    await storage.delete(recursive: true);
    await exports.delete(recursive: true);
  });

  test(
    'v4 complete backup round-trips file-library folders, blobs and trash',
    () async {
      final library = FileLibraryStore.instance;
      final folder = await library.createFolder('Documents');
      final source = File(p.join(exports.path, 'original.pptx'));
      await source.writeAsBytes([0, 1, 2, 255]);
      final entry = await library.importFile(
        XFile(source.path),
        parentId: folder.id,
      );
      await library.setFavorite({entry.id}, true);
      await library.trash({folder.id});
      final service = BackupService();
      final artifact = await service.createBackupArtifact(
        outputDirectory: exports,
      );
      await library.deletePermanently({folder.id});
      await library.createFolder('After backup');
      await service.restoreBackupFile(artifact.file);
      final entries = await library.load();
      expect(entries.length, 2);
      expect(
        entries.singleWhere((e) => e.id == folder.id).deletedAt,
        isNotNull,
      );
      final restored = entries.singleWhere((e) => e.id == entry.id);
      expect(restored.parentId, folder.id);
      expect(restored.favorite, true);
      expect(await library.fileFor(restored).readAsBytes(), [0, 1, 2, 255]);
      expect(await source.readAsBytes(), [0, 1, 2, 255]);
    },
  );

  test(
    'exports exclude receipts and raw encryption files; restore changes library epoch',
    () async {
      final repo = await NoteDatabaseService.instance.repository;
      final epoch = await repo.agentEpoch;
      final note = Note.newDraft().copyWith(title: 'kept');
      await repo.applyAgentMutations(
        operationId: 'operation-secret-marker',
        argumentsDigest: 'args',
        epoch: epoch,
        mutations: [
          AgentNoteMutation(
            id: note.id,
            expectedRevision: 0,
            replacement: note,
          ),
        ],
        validateAccess: () {},
      );
      final service = BackupService();
      final artifact = await service.createBackupArtifact(
        outputDirectory: exports,
      );
      final archive = ZipDecoder().decodeBytes(
        await artifact.file.readAsBytes(),
      );
      expect(archive.map((f) => f.name), isNot(contains('fknotes-agent.db')));
      expect(
        archive.map((f) => f.name),
        contains('assistant/agent-history.json'),
      );
      final databaseBytes = archive
          .firstWhere((f) => f.name == NoteDatabaseService.databaseFileName)
          .readBytes()!;
      expect(
        utf8.decode(databaseBytes, allowMalformed: true),
        isNot(contains('operation-secret-marker')),
      );
      final current = await NoteDatabaseService.instance.repository;
      expect(await current.agentEpoch, epoch);
      expect(
        await current.agentReceipt(
          operationId: 'operation-secret-marker',
          argumentsDigest: 'args',
          epoch: epoch,
        ),
        isNotNull,
      );
      await service.restoreBackupFile(artifact.file);
      final restored = await NoteDatabaseService.instance.repository;
      expect(await restored.agentEpoch, isNot(epoch));
      expect((await restored.list()).single.title, 'kept');
      expect(
        await (await NoteDatabaseService.instance.database).query(
          'agent_operation_receipts',
        ),
        isEmpty,
      );
      await expectLater(
        restored.agentReceipt(
          operationId: 'operation-secret-marker',
          argumentsDigest: 'args',
          epoch: epoch,
        ),
        throwsA(isA<NoteAgentConflict>()),
      );
    },
  );

  test(
    'canceled authentication never creates or exports a private backup',
    () async {
      await (await NoteDatabaseService.instance.repository).create(
        Note.newDraft(isPrivate: true).copyWith(title: '私密内容'),
      );
      final auth = _PrivateBackupAuthenticator()..allow = false;
      final service = BackupService(privateAuthenticator: auth);
      await expectLater(
        service.createBackupArtifact(outputDirectory: exports),
        throwsStateError,
      );
      expect(auth.calls, 1);
      expect(await exports.list().toList(), isEmpty);
      expect(
        (await (await NoteDatabaseService.instance.repository).list(
          privateSpace: true,
        )).single.title,
        '私密内容',
      );
    },
  );

  test(
    'private flags survive backup, history and restore and protect later exports',
    () async {
      final note = await (await NoteDatabaseService.instance.repository).create(
        Note.newDraft(isPrivate: true).copyWith(title: '备份里的秘密'),
      );
      final auth = _PrivateBackupAuthenticator();
      final service = BackupService(privateAuthenticator: auth);
      final record = await service.createManagedBackup();
      expect(auth.calls, 1);
      expect(record.containsPrivateNotes, isTrue);
      final historyRecord = (await service.listManagedBackups()).single;
      expect(historyRecord.containsPrivateNotes, isTrue);
      final file = service.managedBackupFile(historyRecord);
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final manifest =
          jsonDecode(
                utf8.decode(
                  archive
                      .firstWhere((e) => e.name == 'fknotes-backup.json')
                      .readBytes()!,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['containsPrivateNotes'], isTrue);

      final repository = await NoteDatabaseService.instance.repository;
      await repository.update(note.copyWith(isPrivate: false));
      auth.allow = false;
      await expectLater(
        service.saveManagedBackupCopy(historyRecord),
        throwsStateError,
      );
      await expectLater(
        service.shareManagedBackup(historyRecord),
        throwsStateError,
      );
      expect(auth.calls, 3);
      await service.restoreBackupFile(file);
      final restored = await NoteDatabaseService.instance.repository;
      expect(await restored.get(note.id), isNull);
      expect(
        (await restored.get(note.id, privateSpace: true))?.title,
        '备份里的秘密',
      );
    },
  );

  test(
    'ordinary backups need no authentication and absent legacy metadata stays compatible',
    () async {
      await (await NoteDatabaseService.instance.repository).create(
        Note.newDraft(),
      );
      final auth = _PrivateBackupAuthenticator()..allow = false;
      final service = BackupService(privateAuthenticator: auth);
      final record = await service.createManagedBackup();
      expect(auth.calls, 0);
      expect(record.containsPrivateNotes, isFalse);
      expect(
        BackupRecord.fromJson(
          record.toJson()..remove('containsPrivateNotes'),
        ).containsPrivateNotes,
        isFalse,
      );
    },
  );

  test(
    'backup contains only the canonical Delta graph and restores it',
    () async {
      Future<void> write(String relative, List<int> bytes) async {
        final file = File(
          p.joinAll([storage.path, ...p.posix.split(relative)]),
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }

      final note = await _createRichNote(write: write);
      await write('notes/images/orphan.png', [9, 9, 9]);
      await write('images/legacy.png', [7]);
      await write('models/llm/model.bin', [6]);
      await write('settings/cloud-sync.json', utf8.encode('device-secret'));
      await write('recovery/draft.json', utf8.encode('temporary-draft'));

      final artifact = await BackupService.instance.createBackupArtifact(
        outputDirectory: exports,
      );
      final input = InputFileStream(artifact.file.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      await input.close();
      final names = archive
          .where((entry) => entry.isFile)
          .map((entry) => entry.name)
          .toSet();

      expect(names, contains(NoteDatabaseService.databaseFileName));
      expect(names, contains('notes/images/editor.png'));
      expect(names, contains('notes/thumbnails/editor-preview.jpg'));
      expect(names, contains('fknotes-backup.json'));
      expect(names, isNot(contains('notes/images/orphan.png')));
      expect(names, isNot(contains('images/legacy.png')));
      expect(names, isNot(contains('models/llm/model.bin')));
      expect(names, isNot(contains('settings/cloud-sync.json')));
      expect(names, isNot(contains('recovery/draft.json')));

      final manifest =
          jsonDecode(
                utf8.decode(
                  archive
                      .firstWhere(
                        (entry) => entry.name == 'fknotes-backup.json',
                      )
                      .readBytes()!,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['kind'], 'fknotes.delta-backup');
      expect(manifest['formatVersion'], 4);
      expect(
        manifest['databaseSchemaVersion'],
        NoteDatabaseService.schemaVersion,
      );
      expect(manifest['documentSchemaVersion'], 1);
      expect(manifest['noteCount'], 1);
      expect(manifest['assetCount'], 1);
      expect(manifest['contentDigest'], artifact.contentDigest);
      expect(artifact.archiveSha256, hasLength(64));

      final repository = await NoteDatabaseService.instance.repository;
      final persisted = (await repository.get(note.id))!;
      await repository.update(
        persisted.copyWith(
          title: '已经覆盖的标题',
          updatedAt: DateTime.utc(2026, 7, 23, 19),
        ),
      );
      await write('notes/images/editor.png', [8, 8, 8, 8]);
      await write(
        'settings/cloud-sync.json',
        utf8.encode('current-device-secret'),
      );

      await BackupService.instance.restoreBackupFile(artifact.file);

      final restoredRepository = await NoteDatabaseService.instance.repository;
      final restored = await restoredRepository.get(note.id);
      expect(restored?.title, '重构数据契约');
      expect(restored?.tags, ['设计', 'Delta']);
      expect(restored?.reminderAt, DateTime.utc(2027, 1, 2, 10, 30));
      expect(
        restored?.document.toDelta().toJson(),
        note.document.toDelta().toJson(),
      );
      expect(restored?.contentProjection.plainText, '探索记录\n【编辑器截图】');
      expect(
        (await restoredRepository.search('探索')).map((item) => item.id),
        contains(note.id),
      );
      expect(
        await File(
          p.join(storage.path, 'notes/images/editor.png'),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(
        await File(
          p.join(storage.path, 'settings/cloud-sync.json'),
        ).readAsString(),
        'current-device-secret',
      );
      expect(
        await File(p.join(storage.path, 'images/legacy.png')).readAsBytes(),
        [7],
      );
    },
  );

  test(
    'ordinary and private AI history restores on another device without portable keys',
    () async {
      final timestamp = DateTime.utc(2026, 9, 4, 8, 30);
      final repository = await NoteDatabaseService.instance.repository;
      final privateNote = await repository.create(
        Note.newDraft(
          isPrivate: true,
        ).copyWith(title: '私密来源', updatedAt: timestamp),
      );
      const publicImage = 'assistant/public-chat.jpg';
      const privateImage = 'assistant/private-chat.jpg';
      await File(
        p.join(storage.path, publicImage),
      ).writeAsBytes([1, 2, 3], flush: true);
      await File(
        p.join(storage.path, privateImage),
      ).writeAsBytes([4, 5, 6], flush: true);
      final localChats = LocalChatStore.instance;
      LocalChatMessage message(
        String id,
        String content, {
        String? image,
        LocalChatNoteContext? context,
      }) => LocalChatMessage(
        id: id,
        role: LocalChatRole.user,
        content: content,
        attachments: image == null
            ? const []
            : [
                LocalChatAttachment(
                  id: 'attachment-$id',
                  type: LocalChatAttachmentType.image,
                  filePath: image,
                  fileName: p.basename(image),
                  mimeType: 'image/jpeg',
                  createdAt: timestamp,
                ),
              ],
        noteContexts: context == null ? const [] : [context],
        createdAt: timestamp,
      );
      await localChats.saveSession(
        LocalChatSession(
          id: 'public-chat',
          title: '普通对话',
          systemPrompt: LocalChatStore.defaultSystemPrompt,
          messages: [message('public-message', '普通设备间对话', image: publicImage)],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await localChats.saveSession(
        LocalChatSession(
          privateSpace: true,
          id: 'private-chat',
          title: '隐私对话',
          systemPrompt: LocalChatStore.defaultSystemPrompt,
          messages: [
            message(
              'private-message',
              '只在隐私空间展示',
              image: privateImage,
              context: LocalChatNoteContext(
                isPrivate: true,
                noteId: privateNote.id,
                title: privateNote.title,
                scope: LocalChatNoteScope.fullNote,
                content: '隐私上下文',
                updatedAt: timestamp,
              ),
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );

      final sourceVault = _MemoryVault();
      final sourceRuns = await EncryptedRunStore.open(
        p.join(storage.path, EncryptedRunStore.fileName),
        sourceVault,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      AgentRun run({required bool private}) => AgentRun(
        id: private ? 'private-run' : 'public-run',
        sessionId: private ? 'private-chat' : 'public-chat',
        profileId: 'remote-model',
        noteStoreEpoch: 'source-device-epoch',
        scope: RunScope(
          online: true,
          readNotes: true,
          allNotes: true,
          privateNotes: private,
          privateGeneration: private ? 7 : null,
          modelBinding: 'remote-binding',
          noteIds: private ? {privateNote.id.value} : const {},
        ),
        limits: const RunLimits(),
        system: 'assistant',
        skillId: 'assistant',
        goal: private ? '整理私密内容' : '整理普通内容',
        createdAt: timestamp,
        updatedAt: timestamp,
        status: RunStatus.completed,
        revision: 1,
        messages: [
          AgentMessage(
            role: MessageRole.user,
            text: private ? '读取私密来源' : '普通问题',
            attachments: [
              ModelAttachment(
                private ? privateImage : publicImage,
                'image/jpeg',
              ),
            ],
            sources: private
                ? [
                    {
                      'noteId': privateNote.id.value,
                      'title': privateNote.title,
                    },
                  ]
                : const [],
          ),
          AgentMessage(
            role: MessageRole.assistant,
            text: private ? '私密回答完整保留' : '普通回答完整保留',
            protocol: const {'providerState': 'must-not-travel'},
          ),
        ],
      );
      await sourceRuns.save(run(private: false), expectedRevision: 0);
      await sourceRuns.save(run(private: true), expectedRevision: 0);
      await sourceRuns.close();
      final sourceTaskKey = await sourceVault.read(EncryptedRunStore.keyId);
      expect(sourceTaskKey, isNotNull);

      final modelConfig = File(
        p.join(storage.path, 'assistant', 'model-profiles.json'),
      );
      await modelConfig.writeAsString('source-device-config', flush: true);
      final auth = _PrivateBackupAuthenticator();
      final artifact = await BackupService(
        privateAuthenticator: auth,
        credentialVault: sourceVault,
      ).createBackupArtifact(outputDirectory: exports);
      expect(auth.calls, 1);
      expect(artifact.containsPrivateNotes, isTrue);

      final archive = ZipDecoder().decodeBytes(
        await artifact.file.readAsBytes(),
      );
      final names = archive.map((entry) => entry.name).toSet();
      expect(names, contains(LocalChatDatabaseService.databaseFileName));
      expect(names, contains('assistant/agent-history.json'));
      expect(names, containsAll([publicImage, privateImage]));
      expect(names, isNot(contains(EncryptedRunStore.fileName)));
      expect(names, isNot(contains('assistant/model-profiles.json')));

      await LocalChatDatabaseService.instance.close();
      for (final databaseName in [
        LocalChatDatabaseService.databaseFileName,
        EncryptedRunStore.fileName,
      ]) {
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          final file = File(p.join(storage.path, '$databaseName$suffix'));
          if (await file.exists()) await file.delete();
        }
      }
      await File(p.join(storage.path, publicImage)).writeAsBytes([9]);
      await File(p.join(storage.path, privateImage)).writeAsBytes([9]);
      await modelConfig.writeAsString('target-device-config', flush: true);

      final targetVault = _MemoryVault();
      await BackupService(
        privateAuthenticator: auth,
        credentialVault: targetVault,
      ).restoreBackupFile(artifact.file);

      final publicSessions = await localChats.loadSessions();
      final privateSessions = await localChats.loadSessions(privateSpace: true);
      expect(publicSessions.single.title, '普通对话');
      expect(publicSessions.single.messages.single.content, '普通设备间对话');
      expect(privateSessions.single.title, '隐私对话');
      expect(privateSessions.single.privateSpace, isTrue);
      expect(privateSessions.single.messages.single.content, '只在隐私空间展示');
      expect(await File(p.join(storage.path, publicImage)).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await File(p.join(storage.path, privateImage)).readAsBytes(), [
        4,
        5,
        6,
      ]);
      expect(await modelConfig.readAsString(), 'target-device-config');

      final restoredRuns = await EncryptedRunStore.open(
        p.join(storage.path, EncryptedRunStore.fileName),
        targetVault,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      final runs = await restoredRuns.list();
      await restoredRuns.close();
      expect(runs, hasLength(2));
      expect(runs.every((item) => item.historyOnly), isTrue);
      expect(runs.every((item) => item.status.terminal), isTrue);
      expect(runs.every((item) => !item.scope.online), isTrue);
      expect(runs.every((item) => !item.scope.readNotes), isTrue);
      expect(
        runs
            .expand((item) => item.messages)
            .every((message) => message.protocol.isEmpty),
        isTrue,
      );
      expect(
        runs.singleWhere((item) => item.id == 'private-run').scope.privateNotes,
        isTrue,
      );
      expect(
        runs.singleWhere((item) => item.id == 'private-run').answer,
        '私密回答完整保留',
      );
      final targetTaskKey = await targetVault.read(EncryptedRunStore.keyId);
      expect(targetTaskKey, isNotNull);
      expect(targetTaskKey, isNot(sourceTaskKey));
      final roundTrip = await BackupService(
        privateAuthenticator: auth,
        credentialVault: targetVault,
      ).createBackupArtifact(outputDirectory: exports);
      expect(roundTrip.contentDigest, artifact.contentDigest);
    },
  );

  test(
    'version 2 note-only backups preserve current device chat history',
    () async {
      final timestamp = DateTime.utc(2026, 9, 4, 10);
      final repository = await NoteDatabaseService.instance.repository;
      final note = await repository.create(
        Note.newDraft().copyWith(title: '旧备份标题', updatedAt: timestamp),
      );
      final session = LocalChatSession(
        id: 'current-chat',
        title: '当前设备对话',
        systemPrompt: LocalChatStore.defaultSystemPrompt,
        messages: [
          LocalChatMessage(
            id: 'message',
            role: LocalChatRole.user,
            content: '不能被旧备份删除',
            createdAt: timestamp,
          ),
        ],
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await LocalChatStore.instance.saveSession(session);
      final current = await BackupService.instance.createBackupArtifact(
        outputDirectory: exports,
      );
      final decoded = ZipDecoder().decodeBytes(
        await current.file.readAsBytes(),
      );
      final originalManifest =
          jsonDecode(
                utf8.decode(
                  decoded
                      .singleWhere(
                        (entry) => entry.name == 'fknotes-backup.json',
                      )
                      .readBytes()!,
                ),
              )
              as Map<String, dynamic>;
      final v2Entries = decoded
          .where(
            (entry) =>
                entry.isFile &&
                (entry.name == NoteDatabaseService.databaseFileName ||
                    entry.name.startsWith('notes/')),
          )
          .toList();
      final files = SplayTreeMap<String, Object?>();
      final originalFiles = originalManifest['files'] as Map;
      for (final entry in v2Entries) {
        files[entry.name] = originalFiles[entry.name];
      }
      originalManifest
        ..['formatVersion'] = 2
        ..remove('chatDatabaseSchemaVersion')
        ..remove('agentHistorySchemaVersion')
        ..remove('chatSessionCount')
        ..remove('chatMessageCount')
        ..remove('agentRunCount')
        ..remove('containsPrivateData')
        ..['files'] = files
        ..['contentDigest'] = sha256
            .convert(utf8.encode(jsonEncode(files)))
            .toString();
      final v2 = File(p.join(exports.path, 'compatible-v2.fknotes.zip'));
      final encoder = ZipFileEncoder()..create(v2.path);
      for (final entry in v2Entries) {
        final bytes = entry.readBytes()!;
        encoder.addArchiveFile(ArchiveFile(entry.name, bytes.length, bytes));
      }
      encoder.addArchiveFile(
        ArchiveFile.string('fknotes-backup.json', jsonEncode(originalManifest)),
      );
      await encoder.close();

      await (await NoteDatabaseService.instance.repository).update(
        note.copyWith(
          title: '当前标题',
          updatedAt: timestamp.add(const Duration(hours: 1)),
        ),
      );
      await BackupService.instance.restoreBackupFile(v2);

      final restoredRepository = await NoteDatabaseService.instance.repository;
      expect((await restoredRepository.get(note.id))?.title, '旧备份标题');
      expect(
        (await LocalChatStore.instance.loadSessions())
            .single
            .messages
            .single
            .content,
        '不能被旧备份删除',
      );
    },
  );

  test(
    'cloud content fingerprint tracks chat and task history changes',
    () async {
      final vault = _MemoryVault();
      final service = BackupService(credentialVault: vault);
      final first = await service.createBackupArtifact(
        outputDirectory: exports,
      );
      final timestamp = DateTime.utc(2026, 9, 4, 11);
      await LocalChatStore.instance.saveSession(
        LocalChatSession(
          id: 'fingerprint-chat',
          title: '需要同步',
          systemPrompt: LocalChatStore.defaultSystemPrompt,
          messages: [
            LocalChatMessage(
              id: 'fingerprint-message',
              role: LocalChatRole.user,
              content: '新增对话也必须触发上传',
              createdAt: timestamp,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      final second = await service.createBackupArtifact(
        outputDirectory: exports,
      );
      expect(second.contentDigest, isNot(first.contentDigest));

      final runStore = await EncryptedRunStore.open(
        p.join(storage.path, EncryptedRunStore.fileName),
        vault,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      await runStore.save(
        AgentRun(
          id: 'fingerprint-run',
          sessionId: 'fingerprint-chat',
          profileId: 'local',
          noteStoreEpoch: 'epoch',
          scope: const RunScope(),
          limits: const RunLimits(),
          system: '',
          skillId: 'assistant',
          goal: '新增任务历史',
          createdAt: timestamp,
          updatedAt: timestamp,
          status: RunStatus.completed,
          revision: 1,
          messages: [
            AgentMessage(role: MessageRole.user, text: '任务问题'),
            AgentMessage(role: MessageRole.assistant, text: '任务回答'),
          ],
        ),
        expectedRevision: 0,
      );
      await runStore.close();
      final third = await service.createBackupArtifact(
        outputDirectory: exports,
      );
      expect(third.contentDigest, isNot(second.contentDigest));
    },
  );

  test('managed backups preserve multiple new-format versions', () async {
    final first = await BackupService.instance.createManagedBackup(
      label: '换机前',
      description: '包含最新项目资料',
    );
    final second = await BackupService.instance.createManagedBackup();

    final records = await BackupService.instance.listManagedBackups();
    expect(records, hasLength(2));
    expect(first.contentDigest, second.contentDigest);
    expect(records.first.fileName, second.fileName);
    expect(records.last.label, '换机前');
    expect(records.last.description, '包含最新项目资料');
    expect(records.last.formatVersion, 4);
    expect(records.last.archiveSha256, hasLength(64));
    expect(records.last.contentDigest, hasLength(64));
    expect(records.last.sizeBytes, greaterThan(0));

    final input = InputFileStream(
      BackupService.instance.managedBackupFile(first).path,
    );
    final archive = ZipDecoder().decodeStream(input, verify: true);
    await input.close();
    final manifest =
        jsonDecode(
              utf8.decode(
                archive
                    .firstWhere((entry) => entry.name == 'fknotes-backup.json')
                    .readBytes()!,
              ),
            )
            as Map<String, dynamic>;
    expect(manifest['label'], '换机前');
    expect(manifest['description'], '包含最新项目资料');

    await BackupService.instance.deleteManagedBackup(first);
    expect(
      (await BackupService.instance.listManagedBackups()).map(
        (record) => record.fileName,
      ),
      [second.fileName],
    );
    expect(
      await BackupService.instance.managedBackupFile(first).exists(),
      isFalse,
    );
  });

  test(
    'strictly rejects a legacy backup without touching live notes',
    () async {
      final repository = await NoteDatabaseService.instance.repository;
      final live = await repository.create(
        Note(
          id: NoteId.generate(),
          title: '当前的新笔记',
          document: NoteDocument.fromPlainText('不会被旧备份覆盖'),
          createdAt: DateTime.utc(2026, 7, 23),
          updatedAt: DateTime.utc(2026, 7, 23),
        ),
      );
      final legacy = File(p.join(exports.path, 'legacy.fknotes.zip'));
      final encoder = ZipFileEncoder()..create(legacy.path);
      encoder.addArchiveFile(
        ArchiveFile.string('fknotes.db', 'legacy-database'),
      );
      encoder.addArchiveFile(
        ArchiveFile.string(
          'fknotes-backup.json',
          jsonEncode({'formatVersion': 1, 'files': <String, Object?>{}}),
        ),
      );
      await encoder.close();

      await expectLater(
        BackupService.instance.restoreBackupFile(legacy),
        throwsA(isA<FormatException>()),
      );
      expect((await repository.get(live.id))?.title, '当前的新笔记');
    },
  );

  test('rejects a tampered asset before replacing the live database', () async {
    Future<void> write(String relative, List<int> bytes) async {
      final file = File(p.joinAll([storage.path, ...p.posix.split(relative)]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    final original = await _createRichNote(write: write);
    final artifact = await BackupService.instance.createBackupArtifact(
      outputDirectory: exports,
    );
    final repository = await NoteDatabaseService.instance.repository;
    final current = (await repository.get(original.id))!;
    await (await NoteDatabaseService.instance.repository).update(
      current.copyWith(
        title: '当前设备上的更新',
        updatedAt: DateTime.utc(2026, 7, 23, 20),
      ),
    );

    final input = InputFileStream(artifact.file.path);
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final tampered = File(p.join(exports.path, 'tampered.fknotes.zip'));
    final encoder = ZipFileEncoder()..create(tampered.path);
    for (final entry in archive.where((item) => item.isFile)) {
      final bytes = entry.readBytes()!;
      final content = entry.name == 'notes/images/editor.png'
          ? <int>[0, 0, 0, 0]
          : bytes;
      encoder.addArchiveFile(ArchiveFile(entry.name, content.length, content));
    }
    await encoder.close();
    await input.close();

    await expectLater(
      BackupService.instance.restoreBackupFile(tampered),
      throwsA(isA<FormatException>()),
    );
    final untouched = await repository.get(original.id);
    expect(untouched?.title, '当前设备上的更新');
    expect(
      await File(p.join(storage.path, 'notes/images/editor.png')).readAsBytes(),
      [1, 2, 3, 4],
    );
  });

  test(
    'recovers a restore transaction interrupted before database swap',
    () async {
      final repository = await NoteDatabaseService.instance.repository;
      final note = await repository.create(
        Note(
          id: NoteId.generate(),
          title: '中断前的数据',
          document: NoteDocument.fromPlainText('必须自动恢复'),
          createdAt: DateTime.utc(2026, 7, 23),
          updatedAt: DateTime.utc(2026, 7, 23),
        ),
      );
      await NoteDatabaseService.instance.close();
      final rollback = Directory(
        p.join(storage.path, '.fknotes-restore-rollback'),
      );
      await rollback.create(recursive: true);
      await File(
        p.join(storage.path, NoteDatabaseService.databaseFileName),
      ).rename(p.join(rollback.path, NoteDatabaseService.databaseFileName));
      await Directory(
        p.join(storage.path, 'notes'),
      ).rename(p.join(rollback.path, 'notes'));
      final staging = Directory(
        p.join(storage.path, '.fknotes-restore-staging'),
      );
      await staging.create(recursive: true);
      await File(p.join(staging.path, 'partial')).writeAsString('incomplete');

      await BackupService.instance.recoverInterruptedRestore();

      final restoredRepository = await NoteDatabaseService.instance.repository;
      expect((await restoredRepository.get(note.id))?.title, '中断前的数据');
      expect(await rollback.exists(), isFalse);
      expect(await staging.exists(), isFalse);
    },
  );

  test(
    'interrupted whole-data restore rolls chat and images back together',
    () async {
      final timestamp = DateTime.utc(2026, 9, 4, 12);
      final note = await (await NoteDatabaseService.instance.repository).create(
        Note.newDraft().copyWith(title: '回滚笔记', updatedAt: timestamp),
      );
      const imagePath = 'assistant/rollback-chat.jpg';
      await File(p.join(storage.path, imagePath)).writeAsBytes([7, 8, 9]);
      await LocalChatStore.instance.saveSession(
        LocalChatSession(
          id: 'rollback-chat',
          title: '回滚对话',
          systemPrompt: LocalChatStore.defaultSystemPrompt,
          messages: [
            LocalChatMessage(
              id: 'rollback-message',
              role: LocalChatRole.user,
              content: '聊天和图片必须一起回来',
              attachments: [
                LocalChatAttachment(
                  id: 'rollback-image',
                  type: LocalChatAttachmentType.image,
                  filePath: imagePath,
                  fileName: 'rollback-chat.jpg',
                  mimeType: 'image/jpeg',
                  createdAt: timestamp,
                ),
              ],
              createdAt: timestamp,
            ),
          ],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await NoteDatabaseService.instance.close();
      await LocalChatDatabaseService.instance.close();
      final rollback = Directory(
        p.join(storage.path, '.fknotes-restore-rollback'),
      );
      await rollback.create(recursive: true);
      await Directory(
        p.join(storage.path, 'notes'),
      ).rename(p.join(rollback.path, 'notes'));
      for (final databaseName in [
        NoteDatabaseService.databaseFileName,
        LocalChatDatabaseService.databaseFileName,
      ]) {
        await File(
          p.join(storage.path, databaseName),
        ).rename(p.join(rollback.path, databaseName));
      }
      await Directory(p.join(rollback.path, 'assistant')).create();
      await File(
        p.join(storage.path, imagePath),
      ).rename(p.join(rollback.path, imagePath));
      await File(p.join(rollback.path, 'restore-scope.json')).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'includeAssistantData': true,
          'phase': 'movingNew',
        }),
      );
      final staging = Directory(
        p.join(storage.path, '.fknotes-restore-staging'),
      );
      await staging.create();
      await File(p.join(staging.path, 'partial')).writeAsString('incomplete');

      await BackupService.instance.recoverInterruptedRestore();

      expect(
        (await (await NoteDatabaseService.instance.repository).get(
          note.id,
        ))?.title,
        '回滚笔记',
      );
      expect(
        (await LocalChatStore.instance.loadSessions())
            .single
            .messages
            .single
            .content,
        '聊天和图片必须一起回来',
      );
      expect(await File(p.join(storage.path, imagePath)).readAsBytes(), [
        7,
        8,
        9,
      ]);
      expect(await rollback.exists(), isFalse);
      expect(await staging.exists(), isFalse);
    },
  );
}

Future<Note> _createRichNote({
  required Future<void> Function(String relative, List<int> bytes) write,
}) async {
  const storageKey = 'notes/images/editor.png';
  const previewKey = 'notes/thumbnails/editor-preview.jpg';
  await write(storageKey, [1, 2, 3, 4]);
  await write(previewKey, [5, 6]);
  final attachmentId = NoteAttachmentId.generate();
  final document = NoteDocument.fromDelta(
    Delta()
      ..insert('探索', {'bold': true})
      ..insert('记录\n')
      ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
      ..insert('\n'),
  );
  final timestamp = DateTime.utc(2026, 7, 23, 18);
  final note = Note(
    id: NoteId.generate(),
    title: '重构数据契约',
    reminderAt: DateTime.utc(2027, 1, 2, 10, 30),
    document: document,
    tags: const ['设计', 'Delta'],
    assets: [
      NoteAsset(
        id: attachmentId,
        kind: NoteAssetKind.image,
        storageKey: storageKey,
        originalName: 'editor.png',
        displayName: '编辑器截图',
        byteLength: 4,
        mimeType: 'image/png',
        previewStorageKey: previewKey,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ],
    coverAttachmentId: attachmentId,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  return (await NoteDatabaseService.instance.repository).create(note);
}

final class _PrivateBackupAuthenticator implements DeviceAuthenticator {
  bool allow = true;
  int calls = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required DeviceAuthenticationPrompt prompt,
  }) async {
    calls++;
    return DeviceAuthenticationResult(
      allow
          ? DeviceAuthenticationStatus.authenticated
          : DeviceAuthenticationStatus.canceled,
      '',
    );
  }
}

final class _MemoryVault implements CredentialVault {
  final values = <String, String>{};

  @override
  Future<void> delete(String id) async => values.remove(id);

  @override
  Future<String?> read(String id) async => values[id];

  @override
  Future<void> write(String id, String value) async => values[id] = value;
}

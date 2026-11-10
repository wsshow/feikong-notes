import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import '../models/note_document.dart';
import '../models/local_chat.dart';
import '../agent/agent_service.dart';
import '../agent/credential_vault.dart';
import '../agent/encrypted_run_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_locale_controller.dart';
import '../widgets/private_notes_auth.dart';
import 'device_authentication_service.dart';
import 'file_storage_service.dart';
import 'file_library_store.dart';
import 'note_database_service.dart';
import 'local_chat_database_service.dart';
import 'local_chat_store.dart';
import 'note_reminder_service.dart';

/// Backup boundary for the clean Delta application.
///
/// A backup contains the canonical note graph plus portable assistant history.
/// Device credentials, model files, application settings, caches and broad
/// storage directories remain outside this boundary.
final class BackupService {
  BackupService({
    DeviceAuthenticator? privateAuthenticator,
    CredentialVault? credentialVault,
  }) : _credentialVault = credentialVault ?? const SystemCredentialVault(),
       _privateAuthenticator =
           privateAuthenticator ?? SystemDeviceAuthenticator.instance;

  static final BackupService instance = BackupService();
  final DeviceAuthenticator _privateAuthenticator;
  final CredentialVault _credentialVault;

  Future<void> _authorizePrivateNotes() async {
    final locale =
        AppLocaleController.instance.locale ??
        WidgetsBinding.instance.platformDispatcher.locale;
    final l10n = lookupAppLocalizations(
      Locale(locale.languageCode == 'zh' ? 'zh' : 'en'),
    );
    final result = await _privateAuthenticator.isSupported()
        ? await _privateAuthenticator.authenticate(
            prompt: privateNotesPrompt(l10n, exporting: true),
          )
        : const DeviceAuthenticationResult(
            DeviceAuthenticationStatus.unavailable,
            '',
            messageId: DeviceAuthenticationMessage.credentialsRequired,
          );
    if (!result.authenticated) {
      throw StateError(privateNotesAuthMessage(l10n, result));
    }
  }

  static const _manifestName = 'fknotes-backup.json';
  static const _agentHistoryName = 'assistant/agent-history.json';
  static const _agentHistoryKind = 'fknotes.agent-history';
  static const _agentHistoryFormatVersion = 1;
  static const _historyIndexName = 'index.json';
  static const _backupKind = 'fknotes.delta-backup';
  static const _backupFormatVersion = 4;
  static const _historyFormatVersion = 2;
  static const _supportedBackupFormatVersions = {2, 3, 4};
  static const _maxArchiveFiles = 50000;
  static const _maxExpandedBytes = 8 * 1024 * 1024 * 1024;
  static const _stagingName = '.fknotes-restore-staging';
  static const _rollbackName = '.fknotes-restore-rollback';
  static const _restoreScopeName = 'restore-scope.json';
  static const _noteAssetDirectories = {
    'images',
    'thumbnails',
    'audio',
    'video',
    'files',
  };
  static const _databaseSidecars = {
    '${NoteDatabaseService.databaseFileName}-journal',
    '${NoteDatabaseService.databaseFileName}-shm',
    '${NoteDatabaseService.databaseFileName}-wal',
  };
  static const _assistantDatabaseNames = {
    LocalChatDatabaseService.databaseFileName,
    EncryptedRunStore.fileName,
  };
  static const _assistantImageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

  final _storage = FileStorageService.instance;
  static const _exportChannel = MethodChannel('fknotes/backup_export');
  var _operationInProgress = false;

  Directory get backupDirectory =>
      Directory(p.join(_storage.baseDir, 'backups'));

  File get _historyIndex =>
      File(p.join(backupDirectory.path, _historyIndexName));

  Future<bool> exportBackup({Rect? sharePositionOrigin}) async {
    final record = await createManagedBackup();
    return shareManagedBackup(record, sharePositionOrigin: sharePositionOrigin);
  }

  /// Resolves a restore transaction interrupted by process termination.
  ///
  /// This must run after file storage initialization and before any feature
  /// opens the note database.
  Future<void> recoverInterruptedRestore() => _exclusive(() async {
    final root = Directory(_storage.baseDir);
    final staging = Directory(p.join(root.path, _stagingName));
    final rollback = Directory(p.join(root.path, _rollbackName));
    if (!await rollback.exists()) {
      if (await staging.exists()) await staging.delete(recursive: true);
      return;
    }

    final restoreScope = await _readRestoreScope(rollback);
    final includeAssistantData = restoreScope.includeAssistantData;
    final liveDatabase = NoteDatabaseService.instance;
    var liveIsValid = false;
    final liveDatabaseFile = File(
      p.join(root.path, NoteDatabaseService.databaseFileName),
    );
    if (await liveDatabaseFile.exists()) {
      try {
        await _validateRestoredData(
          root,
          includeAssistantData: includeAssistantData,
        );
        liveIsValid = true;
      } catch (_) {
        await liveDatabase.close();
      }
    }

    if (liveIsValid) {
      await rollback.delete(recursive: true);
    } else {
      await liveDatabase.close();
      if (includeAssistantData) {
        await AgentService.currentInstance?.releaseHistoryForRestore();
        await LocalChatDatabaseService.instance.close();
      }
      if (restoreScope.phase == 'movingOld') {
        await _moveManagedData(
          root,
          rollback,
          includeAssistantData: includeAssistantData,
        );
      }
      final rollbackDatabaseFile = File(
        p.join(rollback.path, NoteDatabaseService.databaseFileName),
      );
      if (!await rollbackDatabaseFile.exists()) {
        throw const FormatException('未完成的恢复事务缺少回滚数据库');
      }
      final rollbackDatabase = NoteDatabaseService(
        databasePath: rollbackDatabaseFile.path,
      );
      try {
        await rollbackDatabase.validate(assetRoot: rollback.path);
      } finally {
        await rollbackDatabase.close();
      }
      await _deleteManagedData(
        root,
        includeAssistantData: includeAssistantData,
      );
      await _moveManagedData(
        rollback,
        root,
        includeAssistantData: includeAssistantData,
      );
      await _storage.init(baseDir: root.path);
      await _validateRestoredData(
        root,
        includeAssistantData: includeAssistantData,
      );
      if (await rollback.exists()) await rollback.delete(recursive: true);
    }
    if (await staging.exists()) await staging.delete(recursive: true);
  });

  Future<BackupRecord> createManagedBackup({
    String? label,
    String? description,
  }) async {
    await backupDirectory.create(recursive: true);
    final artifact = await createBackupArtifact(
      outputDirectory: backupDirectory,
      cleanTemporaryArtifacts: false,
      label: label,
      description: description,
    );
    final normalizedLabel = label?.trim();
    final record = BackupRecord(
      fileName: p.basename(artifact.file.path),
      label: normalizedLabel == null || normalizedLabel.isEmpty
          ? _defaultLabel(artifact.createdAt.toLocal())
          : normalizedLabel,
      description: description?.trim() ?? '',
      contentDigest: artifact.contentDigest,
      archiveSha256: artifact.archiveSha256,
      sizeBytes: artifact.sizeBytes,
      createdAt: artifact.createdAt,
      formatVersion: _backupFormatVersion,
      containsPrivateNotes: artifact.containsPrivateNotes,
    );
    final records = await listManagedBackups();
    await _writeHistory([record, ...records]);
    return record;
  }

  Future<List<BackupRecord>> listManagedBackups() async {
    await backupDirectory.create(recursive: true);
    if (!await _historyIndex.exists()) return const [];
    try {
      final decoded = jsonDecode(await _historyIndex.readAsString());
      if (decoded is! Map ||
          decoded['formatVersion'] != _historyFormatVersion ||
          decoded['records'] is! List) {
        return const [];
      }
      final records = <BackupRecord>[];
      for (final raw in decoded['records'] as List) {
        if (raw is! Map) continue;
        final record = BackupRecord.fromJson(Map<String, Object?>.from(raw));
        if (!_supportedBackupFormatVersions.contains(record.formatVersion) ||
            !_isSafeBackupFileName(record.fileName)) {
          continue;
        }
        if (await managedBackupFile(record).exists()) records.add(record);
      }
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(records);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> deleteManagedBackup(BackupRecord record) async {
    final file = managedBackupFile(record);
    if (await file.exists()) await file.delete();
    final records = await listManagedBackups();
    await _writeHistory(
      records.where((item) => item.fileName != record.fileName).toList(),
    );
  }

  File managedBackupFile(BackupRecord record) {
    if (!_isSafeBackupFileName(record.fileName)) {
      throw const FormatException('备份文件名不安全');
    }
    return File(p.join(backupDirectory.path, record.fileName));
  }

  Future<bool> shareManagedBackup(
    BackupRecord record, {
    Rect? sharePositionOrigin,
  }) async {
    if (record.containsPrivateNotes) await _authorizePrivateNotes();
    final file = managedBackupFile(record);
    if (!await file.exists()) throw const FormatException('备份文件不存在');
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: 'application/zip', name: record.fileName),
        ],
        title: '保存非空笔记备份',
        subject: '非空笔记完整备份',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  Future<bool> saveManagedBackupCopy(BackupRecord record) async {
    if (record.containsPrivateNotes) await _authorizePrivateNotes();
    final source = managedBackupFile(record);
    if (!await source.exists()) throw const FormatException('备份文件不存在');
    if (!kIsWeb && Platform.isAndroid) {
      return await _exportChannel.invokeMethod<bool>('saveFile', {
            'sourcePath': source.path,
            'suggestedName': record.fileName,
            'mimeType': 'application/zip',
          }) ??
          false;
    }
    const type = XTypeGroup(
      label: 'FKNotes Backup',
      extensions: ['zip'],
      mimeTypes: ['application/zip'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: const [type],
      suggestedName: record.fileName,
    );
    if (location == null) return false;
    await XFile(
      source.path,
      mimeType: 'application/zip',
      name: record.fileName,
    ).saveTo(location.path);
    return true;
  }

  Future<BackupArtifact> createBackupArtifact({
    Directory? outputDirectory,
    bool cleanTemporaryArtifacts = true,
    String? label,
    String? description,
  }) => _exclusive(() async {
    final now = DateTime.now();
    final outputName =
        'fknotes_${now.year}${_two(now.month)}${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}_'
        '${now.microsecondsSinceEpoch}.fknotes.zip';
    final liveDatabase = NoteDatabaseService.instance;
    await liveDatabase.repository;
    final database = await liveDatabase.database;
    await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await liveDatabase.close();
    await LocalChatStore.instance.flushWrites();

    Directory? snapshotDirectory;
    try {
      final liveDatabasePath = p.join(
        _storage.baseDir,
        NoteDatabaseService.databaseFileName,
      );
      snapshotDirectory = await Directory.systemTemp.createTemp(
        'fknotes_backup_snapshot_',
      );
      final databasePath = p.join(
        snapshotDirectory.path,
        NoteDatabaseService.databaseFileName,
      );
      final chatDatabasePath = p.join(
        snapshotDirectory.path,
        LocalChatDatabaseService.databaseFileName,
      );
      final agentHistoryPath = p.joinAll([
        snapshotDirectory.path,
        ...p.posix.split(_agentHistoryName),
      ]);
      // Freeze every content graph before authentication. Later live edits
      // must not enter an already-authorized archive.
      await File(liveDatabasePath).copy(databasePath);
      await LocalChatDatabaseService.instance.snapshotTo(
        File(chatDatabasePath),
      );
      final snapshotDatabase = NoteDatabaseService(databasePath: databasePath);
      late final _BackupGraph noteGraph;
      try {
        await (await snapshotDatabase.repository).clearAgentMetadata(
          restoring: false,
        );
        await snapshotDatabase.validate(assetRoot: _storage.baseDir);
        noteGraph = await _readBackupGraph(snapshotDatabase);
      } finally {
        await snapshotDatabase.close();
      }
      final snapshotChatDatabase = LocalChatDatabaseService(
        databasePath: chatDatabasePath,
      );
      late final _ChatBackupGraph chatGraph;
      try {
        await snapshotChatDatabase.validate();
        chatGraph = await _readChatBackupGraph(
          snapshotChatDatabase,
          privateNoteIds: noteGraph.privateNoteIds,
          assetRoot: _storage.baseDir,
        );
      } finally {
        await snapshotChatDatabase.close();
      }
      final agentHistory = await _readPortableAgentHistory(
        privateNoteIds: noteGraph.privateNoteIds,
      );
      final agentHistoryFile = File(agentHistoryPath);
      await agentHistoryFile.parent.create(recursive: true);
      await agentHistoryFile.writeAsString(
        jsonEncode(agentHistory.json),
        flush: true,
      );
      final containsPrivateData =
          noteGraph.containsPrivateNotes ||
          chatGraph.containsPrivateData ||
          agentHistory.containsPrivateData;

      // Covers both local backups and the cloud-sync adapter. Do not create
      // or upload an unprotected copy when system authentication is canceled.
      if (containsPrivateData) await _authorizePrivateNotes();

      final exportDirectory =
          outputDirectory ??
          Directory(
            p.join((await getTemporaryDirectory()).path, 'fknotes_exports'),
          );
      await exportDirectory.create(recursive: true);
      if (cleanTemporaryArtifacts) {
        await _cleanupOldArtifacts(exportDirectory, now);
      }
      final output = File(p.join(exportDirectory.path, outputName));
      final files = <String, File>{
        NoteDatabaseService.databaseFileName: File(databasePath),
        LocalChatDatabaseService.databaseFileName: File(chatDatabasePath),
        _agentHistoryName: agentHistoryFile,
        for (final key in noteGraph.assetKeys)
          key: File(_storage.absolutePath(key)),
        for (final key in {...chatGraph.assetKeys, ...agentHistory.assetKeys})
          key: File(_storage.absolutePath(key)),
        ...await FileLibraryStore(
          rootPath: p.join(_storage.baseDir, FileLibraryStore.relativeRoot),
        ).backupSnapshot(snapshotDirectory),
      };
      final sortedNames = files.keys.toList()..sort();
      final manifestFiles = SplayTreeMap<String, Object?>();
      for (final name in sortedNames) {
        final file = files[name]!;
        manifestFiles[name] = {
          'size': await file.length(),
          'sha256': (await sha256.bind(file.openRead()).first).toString(),
        };
      }
      final archiveDigest = _manifestFilesDigest(manifestFiles);
      final semanticFiles = SplayTreeMap<String, Object?>.of(manifestFiles)
        ..[NoteDatabaseService.databaseFileName] = {
          'contentDigest': noteGraph.contentDigest,
        }
        ..[LocalChatDatabaseService.databaseFileName] = {
          'contentDigest': chatGraph.contentDigest,
        };
      final contentDigest = _manifestFilesDigest(semanticFiles);
      final encoder = ZipFileEncoder()..create(output.path);
      var encoderOpen = true;
      try {
        for (final name in sortedNames) {
          await encoder.addFile(files[name]!, name);
        }
        encoder.addArchiveFile(
          ArchiveFile.string(
            _manifestName,
            jsonEncode({
              'kind': _backupKind,
              'formatVersion': _backupFormatVersion,
              'databaseSchemaVersion': NoteDatabaseService.schemaVersion,
              'chatDatabaseSchemaVersion':
                  LocalChatDatabaseService.schemaVersion,
              'agentHistorySchemaVersion': AgentRun.schemaVersion,
              'documentSchemaVersion': NoteDocument.schemaVersion,
              'createdAt': now.toUtc().toIso8601String(),
              if (label?.trim().isNotEmpty == true) 'label': label!.trim(),
              if (description?.trim().isNotEmpty == true)
                'description': description!.trim(),
              'noteCount': noteGraph.noteCount,
              'assetCount': noteGraph.assetCount,
              'chatSessionCount': chatGraph.sessionCount,
              'chatMessageCount': chatGraph.messageCount,
              'agentRunCount': agentHistory.runCount,
              // Keep the legacy key so backup-history clients continue to
              // require authentication for any private workspace content.
              'containsPrivateNotes': containsPrivateData,
              'containsPrivateData': containsPrivateData,
              'contentDigest': contentDigest,
              'archiveDigest': archiveDigest,
              'files': manifestFiles,
            }),
          ),
        );
        await encoder.close();
        encoderOpen = false;
      } catch (_) {
        if (await output.exists()) await output.delete();
        rethrow;
      } finally {
        if (encoderOpen) {
          try {
            await encoder.close();
          } catch (_) {
            // Preserve the original snapshot error.
          }
        }
      }
      return BackupArtifact(
        file: output,
        contentDigest: contentDigest,
        archiveSha256: (await sha256.bind(output.openRead()).first).toString(),
        sizeBytes: await output.length(),
        createdAt: now.toUtc(),
        containsPrivateNotes: containsPrivateData,
      );
    } finally {
      try {
        if (snapshotDirectory != null) {
          await snapshotDirectory.delete(recursive: true);
        }
      } finally {
        await liveDatabase.repository;
      }
    }
  });

  Future<bool> restoreBackup() async {
    final selected = await chooseBackupFile();
    if (selected == null) return false;
    await restoreBackupFile(selected);
    return true;
  }

  Future<File?> chooseBackupFile() async {
    const group = XTypeGroup(label: 'FK Notes Backup', extensions: ['zip']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    return selected == null ? null : File(selected.path);
  }

  Future<void> restoreBackupFile(File backup) => _exclusive(() async {
    if (!await backup.exists()) throw const FormatException('备份文件不存在');
    final input = InputFileStream(backup.path);
    final root = Directory(_storage.baseDir);
    final staging = Directory(p.join(root.path, _stagingName));
    final rollback = Directory(p.join(root.path, _rollbackName));
    var swapStarted = false;
    var movingOldData = false;
    var restoreCompleted = false;
    var remindersSuspended = false;
    var restoresAssistantData = false;
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input, verify: true);
      } catch (_) {
        throw const FormatException('备份压缩包损坏');
      }
      final entries = archive.where((entry) => entry.isFile).toList();
      final expandedBytes = entries.fold<int>(
        0,
        (total, entry) => total + entry.size,
      );
      if (entries.length > _maxArchiveFiles ||
          expandedBytes > _maxExpandedBytes) {
        throw const FormatException('备份文件数量或容量异常');
      }
      final names = entries.map((entry) => _safeName(entry.name)).toList();
      if (names.toSet().length != names.length) {
        throw const FormatException('备份中包含重复路径');
      }
      final manifestIndexes = <int>[
        for (var index = 0; index < names.length; index++)
          if (names[index] == _manifestName) index,
      ];
      if (manifestIndexes.length != 1) {
        throw const FormatException('这不是新版非空笔记备份');
      }
      final manifestIndex = manifestIndexes.single;
      final manifest = _decodeManifest(entries[manifestIndex]);
      final backupFormatVersion = manifest['formatVersion']! as int;
      restoresAssistantData = backupFormatVersion >= 3;
      final files = <ArchiveFile>[];
      final fileNames = <String>[];
      for (var index = 0; index < entries.length; index++) {
        if (index == manifestIndex) continue;
        final name = names[index];
        if (!_isAllowedArchivePath(name, backupFormatVersion)) {
          throw FormatException('备份包含新数据边界之外的内容：$name');
        }
        files.add(entries[index]);
        fileNames.add(name);
      }
      if (!fileNames.contains(NoteDatabaseService.databaseFileName)) {
        throw const FormatException('备份缺少笔记数据库');
      }
      if (restoresAssistantData &&
          (!fileNames.contains(LocalChatDatabaseService.databaseFileName) ||
              !fileNames.contains(_agentHistoryName))) {
        throw const FormatException('备份缺少助手对话历史');
      }

      await _resetInternalDirectory(staging);
      for (var index = 0; index < files.length; index++) {
        final output = File(
          p.joinAll([staging.path, ...p.posix.split(fileNames[index])]),
        );
        await output.parent.create(recursive: true);
        final stream = OutputFileStream(output.path);
        try {
          files[index].writeContent(stream);
        } finally {
          stream.closeSync();
        }
      }
      await _validateManifest(manifest, staging, fileNames);

      final stagedDatabase = NoteDatabaseService(
        databasePath: p.join(
          staging.path,
          NoteDatabaseService.databaseFileName,
        ),
      );
      late final _BackupGraph stagedGraph;
      try {
        await stagedDatabase.validate(assetRoot: staging.path);
        stagedGraph = await _readBackupGraph(stagedDatabase);
        await (await stagedDatabase.repository).clearAgentMetadata(
          restoring: true,
        );
      } finally {
        await stagedDatabase.close();
      }
      final expectedNames = <String>{
        NoteDatabaseService.databaseFileName,
        ...stagedGraph.assetKeys,
        if (backupFormatVersion >= 4)
          ...await FileLibraryStore(
            rootPath: p.join(staging.path, FileLibraryStore.relativeRoot),
          ).validateBackupFiles(),
      };
      _ChatBackupGraph? stagedChatGraph;
      _PortableAgentHistory? stagedAgentHistory;
      if (restoresAssistantData) {
        final stagedChatDatabase = LocalChatDatabaseService(
          databasePath: p.join(
            staging.path,
            LocalChatDatabaseService.databaseFileName,
          ),
        );
        try {
          await stagedChatDatabase.validate();
          stagedChatGraph = await _readChatBackupGraph(
            stagedChatDatabase,
            privateNoteIds: stagedGraph.privateNoteIds,
            assetRoot: staging.path,
          );
        } finally {
          await stagedChatDatabase.close();
        }
        stagedAgentHistory = await _decodePortableAgentHistory(
          File(p.joinAll([staging.path, ...p.posix.split(_agentHistoryName)])),
          assetRoot: staging.path,
        );
        expectedNames.addAll({
          LocalChatDatabaseService.databaseFileName,
          _agentHistoryName,
          ...stagedChatGraph.assetKeys,
          ...stagedAgentHistory.assetKeys,
        });
      }
      if (!expectedNames.containsAll(fileNames) ||
          !fileNames.toSet().containsAll(expectedNames)) {
        throw const FormatException('备份附件与数据库引用不一致');
      }
      if (manifest['noteCount'] != stagedGraph.noteCount ||
          manifest['assetCount'] != stagedGraph.assetCount ||
          restoresAssistantData &&
              (manifest['chatSessionCount'] != stagedChatGraph!.sessionCount ||
                  manifest['chatMessageCount'] !=
                      stagedChatGraph.messageCount ||
                  manifest['agentRunCount'] != stagedAgentHistory!.runCount)) {
        throw const FormatException('备份数据计数校验失败');
      }
      if (restoresAssistantData) {
        await _materializeAgentHistory(staging, stagedAgentHistory!.runs);
        await File(
          p.joinAll([staging.path, ...p.posix.split(_agentHistoryName)]),
        ).delete();
      }

      final liveDatabase = NoteDatabaseService.instance;
      await _resetInternalDirectory(rollback);
      await _writeRestoreScope(
        rollback,
        includeAssistantData: restoresAssistantData,
        phase: 'movingOld',
      );
      await NoteReminderService.instance.suspendForRestore();
      remindersSuspended = true;
      await liveDatabase.close();
      if (restoresAssistantData) {
        await LocalChatStore.instance.flushWrites();
        await AgentService.currentInstance?.releaseHistoryForRestore();
        await LocalChatDatabaseService.instance.close();
      }
      movingOldData = true;
      swapStarted = true;
      await _moveManagedData(
        root,
        rollback,
        includeAssistantData: restoresAssistantData,
      );
      movingOldData = false;
      await _writeRestoreScope(
        rollback,
        includeAssistantData: restoresAssistantData,
        phase: 'movingNew',
      );
      await _moveManagedData(
        staging,
        root,
        includeAssistantData: restoresAssistantData,
      );
      await _storage.init(baseDir: root.path);
      await _validateRestoredData(
        root,
        includeAssistantData: restoresAssistantData,
      );
      await liveDatabase.repository;
      restoreCompleted = true;
      try {
        await rollback.delete(recursive: true);
      } on FileSystemException {
        // The restored graph is valid; stale rollback data is cleaned later.
      }
    } catch (error, stackTrace) {
      if (swapStarted) {
        try {
          final liveDatabase = NoteDatabaseService.instance;
          await liveDatabase.close();
          if (restoresAssistantData) {
            await AgentService.currentInstance?.releaseHistoryForRestore();
            await LocalChatDatabaseService.instance.close();
          }
          if (movingOldData) {
            await _moveManagedData(
              root,
              rollback,
              includeAssistantData: restoresAssistantData,
            );
            movingOldData = false;
          }
          await _deleteManagedData(
            root,
            includeAssistantData: restoresAssistantData,
          );
          await _moveManagedData(
            rollback,
            root,
            includeAssistantData: restoresAssistantData,
          );
          await _storage.init(baseDir: root.path);
          await _validateRestoredData(
            root,
            includeAssistantData: restoresAssistantData,
          );
          await liveDatabase.repository;
          swapStarted = false;
        } catch (rollbackError) {
          throw StateError('恢复失败且自动回滚未完成：$rollbackError');
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await input.close();
      if (remindersSuspended && (!swapStarted || restoreCompleted)) {
        // Also resume after a failure before the first file was moved.
        await NoteReminderService.instance.initialize(
          p.join(root.path, NoteDatabaseService.databaseFileName),
        );
      }
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // A decoder may release a file handle shortly after this operation.
        }
      }
      if ((restoreCompleted || !swapStarted) && await rollback.exists()) {
        try {
          await rollback.delete(recursive: true);
        } on FileSystemException {
          // Never let cleanup hide the restore result.
        }
      }
    }
  });

  Map<String, Object?> _decodeManifest(ArchiveFile entry) {
    if (entry.size > 1024 * 1024) {
      throw const FormatException('备份清单异常');
    }
    final bytes = entry.readBytes();
    if (bytes == null) throw const FormatException('备份清单不完整');
    final decoded = jsonDecode(utf8.decode(bytes));
    final databaseSchemaVersion = decoded is Map
        ? decoded['databaseSchemaVersion']
        : null;
    final formatVersion = decoded is Map ? decoded['formatVersion'] : null;
    if (decoded is! Map ||
        decoded['kind'] != _backupKind ||
        formatVersion is! int ||
        !_supportedBackupFormatVersions.contains(formatVersion) ||
        databaseSchemaVersion is! int ||
        databaseSchemaVersion < 1 ||
        databaseSchemaVersion > NoteDatabaseService.schemaVersion ||
        decoded['documentSchemaVersion'] != NoteDocument.schemaVersion ||
        DateTime.tryParse(decoded['createdAt']?.toString() ?? '') == null ||
        decoded['noteCount'] is! int ||
        decoded['assetCount'] is! int ||
        decoded['contentDigest'] is! String ||
        decoded['files'] is! Map) {
      throw const FormatException('不支持的备份格式或数据版本');
    }
    if (formatVersion >= 3) {
      final chatSchemaVersion = decoded['chatDatabaseSchemaVersion'];
      if (chatSchemaVersion is! int ||
          chatSchemaVersion < 1 ||
          chatSchemaVersion > LocalChatDatabaseService.schemaVersion ||
          decoded['agentHistorySchemaVersion'] != AgentRun.schemaVersion ||
          decoded['chatSessionCount'] is! int ||
          decoded['chatMessageCount'] is! int ||
          decoded['agentRunCount'] is! int) {
        throw const FormatException('不支持的助手历史数据版本');
      }
      if (decoded['archiveDigest'] is! String) {
        throw const FormatException('备份完整性校验信息缺失');
      }
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<void> _validateManifest(
    Map<String, Object?> manifest,
    Directory root,
    List<String> fileNames,
  ) async {
    final rawFiles = manifest['files'];
    if (rawFiles is! Map ||
        rawFiles.length != fileNames.length ||
        !rawFiles.keys.toSet().containsAll(fileNames)) {
      throw const FormatException('备份清单与文件不匹配');
    }
    final normalizedFiles = SplayTreeMap<String, Object?>();
    for (final relative in fileNames) {
      final metadata = rawFiles[relative];
      if (metadata is! Map) throw const FormatException('备份清单损坏');
      final expectedSize = metadata['size'];
      final expectedDigest = metadata['sha256'];
      if (expectedSize is! int || expectedDigest is! String) {
        throw const FormatException('备份清单损坏');
      }
      final file = File(p.joinAll([root.path, ...p.posix.split(relative)]));
      if (!await file.exists() ||
          await file.length() != expectedSize ||
          (await sha256.bind(file.openRead()).first).toString() !=
              expectedDigest) {
        throw FormatException('备份文件校验失败：$relative');
      }
      normalizedFiles[relative] = {
        'size': expectedSize,
        'sha256': expectedDigest,
      };
    }
    final formatVersion = manifest['formatVersion']! as int;
    final expectedDigest = formatVersion >= 3
        ? manifest['archiveDigest']
        : manifest['contentDigest'];
    if (_manifestFilesDigest(normalizedFiles) != expectedDigest) {
      throw const FormatException('备份内容摘要校验失败');
    }
  }

  Future<_PortableAgentHistory> _decodePortableAgentHistory(
    File file, {
    required String assetRoot,
  }) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['kind'] != _agentHistoryKind ||
        decoded['formatVersion'] != _agentHistoryFormatVersion ||
        decoded['runSchemaVersion'] != AgentRun.schemaVersion ||
        decoded['runs'] is! List) {
      throw const FormatException('助手任务历史格式不受支持');
    }
    final rawRuns = decoded['runs']! as List;
    if (rawRuns.length > 100000) {
      throw const FormatException('助手任务历史数量异常');
    }
    final ids = <String>{};
    final assetKeys = <String>{};
    final runs = <AgentRun>[];
    var containsPrivateData = false;
    try {
      for (final raw in rawRuns) {
        final run = AgentRun.fromJson(Map<String, dynamic>.from(raw as Map));
        if (!ids.add(run.id) ||
            !run.historyOnly ||
            !run.status.terminal ||
            run.conversationQueuePending ||
            run.scope.online ||
            run.scope.networkTools ||
            run.scope.readNotes ||
            run.scope.writeNotes ||
            run.scope.externalWrites ||
            run.scope.allNotes ||
            run.scope.privateGeneration != null ||
            run.scope.modelBinding != null ||
            run.scope.networkBindings.isNotEmpty ||
            run.scope.noteIds.isNotEmpty ||
            run.providerToolCallKeys.isNotEmpty ||
            run.noteStoreEpoch != 'restored-history' ||
            run.steering.isNotEmpty ||
            run.messages.any((message) => message.protocol.isNotEmpty) ||
            run.pending.any(
              (pending) =>
                  pending.approvalId != null ||
                  pending.approvedDigest != null ||
                  pending.approvalMode != null ||
                  pending.approvalExpires != null ||
                  !{
                    PendingPhase.completed,
                    PendingPhase.rejected,
                  }.contains(pending.phase),
            )) {
          throw const FormatException();
        }
        containsPrivateData =
            containsPrivateData ||
            run.scope.privateNotes ||
            run.requiresPrivateAccess;
        for (final attachment in [
          ...run.messages.expand((message) => message.attachments),
          ...run.steering.expand((input) => input.attachments),
        ]) {
          final key = attachment.reference;
          if (!_isCanonicalAssistantAssetPath(key) ||
              !await File(
                p.joinAll([assetRoot, ...p.posix.split(key)]),
              ).exists()) {
            throw const FormatException();
          }
          assetKeys.add(key);
        }
        runs.add(run);
      }
    } catch (_) {
      throw const FormatException('助手任务历史损坏');
    }
    final sortedKeys = assetKeys.toList()..sort();
    return _PortableAgentHistory(
      json: Map<String, dynamic>.from(decoded),
      runs: List.unmodifiable(runs),
      runCount: runs.length,
      assetKeys: List.unmodifiable(sortedKeys),
      containsPrivateData: containsPrivateData,
    );
  }

  Future<void> _materializeAgentHistory(
    Directory root,
    List<AgentRun> runs,
  ) async {
    final path = p.join(root.path, EncryptedRunStore.fileName);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    if (runs.isEmpty) return;
    final store = await EncryptedRunStore.open(
      path,
      _credentialVault,
      singleInstance: false,
    );
    try {
      for (final source in runs) {
        final run = source.clone()..revision = 1;
        await store.save(run, expectedRevision: 0);
      }
      if ((await store.list()).length != runs.length) {
        throw const FormatException('助手任务历史写入不完整');
      }
    } finally {
      await store.close();
    }
  }

  Future<void> _validateRestoredData(
    Directory root, {
    required bool includeAssistantData,
  }) async {
    final noteDatabase = NoteDatabaseService(
      databasePath: p.join(root.path, NoteDatabaseService.databaseFileName),
    );
    late final _BackupGraph noteGraph;
    try {
      await noteDatabase.validate(assetRoot: root.path);
      noteGraph = await _readBackupGraph(noteDatabase);
    } finally {
      await noteDatabase.close();
    }
    if (!includeAssistantData) return;
    final chatDatabaseFile = File(
      p.join(root.path, LocalChatDatabaseService.databaseFileName),
    );
    if (!await chatDatabaseFile.exists()) {
      throw const FormatException('恢复后的助手对话数据库缺失');
    }
    final chatDatabase = LocalChatDatabaseService(
      databasePath: chatDatabaseFile.path,
    );
    try {
      await chatDatabase.validate();
      await _readChatBackupGraph(
        chatDatabase,
        privateNoteIds: noteGraph.privateNoteIds,
        assetRoot: root.path,
      );
    } finally {
      await chatDatabase.close();
    }
    final agentDatabaseFile = File(
      p.join(root.path, EncryptedRunStore.fileName),
    );
    if (await agentDatabaseFile.exists()) {
      final store = await EncryptedRunStore.open(
        agentDatabaseFile.path,
        _credentialVault,
        singleInstance: false,
      );
      try {
        await store.list();
      } finally {
        await store.close();
      }
    }
  }

  Future<_BackupGraph> _readBackupGraph(NoteDatabaseService service) async {
    final database = await service.database;
    final noteCount =
        (await database.rawQuery(
              'SELECT COUNT(*) AS count FROM notes',
            )).single['count']!
            as int;
    final rows = await database.query(
      'note_assets',
      columns: ['storage_key', 'preview_storage_key'],
    );
    final keys = <String>{};
    for (final row in rows) {
      for (final value in [row['storage_key'], row['preview_storage_key']]) {
        if (value == null) continue;
        final key = value as String;
        if (!_isCanonicalNoteAssetPath(key)) {
          throw FormatException('笔记附件不属于新数据空间：$key');
        }
        keys.add(key);
      }
    }
    final sortedKeys = keys.toList()..sort();
    final privateNoteIds = (await database.query(
      'notes',
      columns: ['id'],
      where: 'is_private = 1',
    )).map((row) => row['id']! as String).toSet();
    const logicalTables = [
      'notes',
      'note_assets',
      'note_tags',
      'note_links',
      'note_constellation_nodes',
      'note_constellation_overview_nodes',
      'note_constellation_overview_regions',
      'note_constellation_groups',
      'note_constellation_memberships',
    ];
    final logicalData = <String, Object?>{};
    for (final table in logicalTables) {
      final rows = (await database.query(table)).toList();
      rows.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
      logicalData[table] = rows;
    }
    return _BackupGraph(
      noteCount: noteCount,
      assetCount: rows.length,
      assetKeys: List.unmodifiable(sortedKeys),
      containsPrivateNotes: privateNoteIds.isNotEmpty,
      privateNoteIds: Set.unmodifiable(privateNoteIds),
      contentDigest: contentDigest(logicalData),
    );
  }

  Future<_ChatBackupGraph> _readChatBackupGraph(
    LocalChatDatabaseService service, {
    required Set<String> privateNoteIds,
    required String assetRoot,
  }) async {
    final database = await service.database;
    final sessions = await database.query('chat_sessions', orderBy: 'id');
    final privateSessionIds = <String>{
      for (final row in sessions)
        if (row['is_private'] == 1) row['id']! as String,
    };
    final messages = await database.query(
      'chat_messages',
      orderBy: 'session_id, sort_order',
    );
    final personas = await database.query('chat_personas', orderBy: 'id');
    final assetKeys = <String>{};
    var containsPrivateData = privateSessionIds.isNotEmpty;
    for (final row in messages) {
      final attachments = _decodeChatList(
        row['attachments_json'] as String? ?? '[]',
        LocalChatAttachment.fromJson,
      );
      for (final attachment in attachments) {
        final key = attachment.filePath;
        if (!_isCanonicalAssistantAssetPath(key)) {
          throw FormatException('聊天附件不属于受管数据空间：$key');
        }
        if (!await File(
          p.joinAll([assetRoot, ...p.posix.split(key)]),
        ).exists()) {
          throw FormatException('聊天附件不存在：$key');
        }
        assetKeys.add(key);
      }
      final contexts = _decodeChatList(
        row['note_contexts_json'] as String? ?? '[]',
        LocalChatNoteContext.fromJson,
      );
      final calls = _decodeChatList(
        row['tool_calls_json'] as String? ?? '[]',
        LocalChatToolCall.fromJson,
      );
      containsPrivateData =
          containsPrivateData ||
          contexts.any(
            (context) =>
                context.isPrivate ||
                privateNoteIds.contains(context.noteId.value),
          ) ||
          calls.any((call) => privateNoteIds.contains(call.noteId?.value));
    }
    final sortedKeys = assetKeys.toList()..sort();
    return _ChatBackupGraph(
      sessionCount: sessions.length,
      messageCount: messages.length,
      assetKeys: List.unmodifiable(sortedKeys),
      containsPrivateData: containsPrivateData,
      contentDigest: contentDigest({
        'personas': personas,
        'sessions': sessions,
        'messages': messages,
      }),
    );
  }

  List<T> _decodeChatList<T>(
    String encoded,
    T Function(Map<String, Object?>) decode,
  ) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List) throw const FormatException();
      return value
          .map((item) => decode(Map<String, Object?>.from(item as Map)))
          .toList(growable: false);
    } catch (_) {
      throw const FormatException('聊天历史数据损坏');
    }
  }

  Future<_PortableAgentHistory> _readPortableAgentHistory({
    required Set<String> privateNoteIds,
  }) async {
    final databaseFile = File(
      p.join(_storage.baseDir, EncryptedRunStore.fileName),
    );
    final runs = <AgentRun>[];
    if (await databaseFile.exists()) {
      final store = await EncryptedRunStore.open(
        databaseFile.path,
        _credentialVault,
        singleInstance: false,
      );
      try {
        runs.addAll(await store.list());
      } finally {
        await store.close();
      }
    }
    runs.sort((a, b) => a.id.compareTo(b.id));
    final portableRuns = <Json>[];
    final portableObjects = <AgentRun>[];
    final assetKeys = <String>{};
    var containsPrivateData = false;
    for (final run in runs) {
      final private = _runContainsPrivateData(run, privateNoteIds);
      containsPrivateData = containsPrivateData || private;
      final json = jsonCopy(run.toJson());
      final messages = json['messages']! as List;
      for (final queued in run.steering) {
        messages.add(queued.toMessage().toJson());
      }
      for (final message in messages) {
        (message as Json)['protocol'] = <String, dynamic>{};
      }
      json['steering'] = <Object>[];
      for (final pending in json['pending']! as List) {
        final value = pending as Json;
        value['approvalId'] = null;
        value['approvedDigest'] = null;
        value['approvalMode'] = null;
        value['approvalExpires'] = null;
        if (value['phase'] != PendingPhase.completed.name &&
            value['phase'] != PendingPhase.rejected.name) {
          value['phase'] = PendingPhase.rejected.name;
        }
      }
      json['noteStoreEpoch'] = 'restored-history';
      json['scope'] = RunScope(privateNotes: private).toJson();
      json['requiresPrivateAccess'] = private;
      json['historyOnly'] = true;
      json['conversationQueuePending'] = false;
      json['providerToolCallKeys'] = <String>[];
      json['reservedTokens'] = 0;
      json['revision'] = 0;
      if (!run.status.terminal) {
        json['status'] = run.answer.isEmpty
            ? RunStatus.cancelled.name
            : RunStatus.completed.name;
      }
      final portable = AgentRun.fromJson(json);
      portableRuns.add(portable.toJson());
      portableObjects.add(portable);
      for (final attachment in [
        ...portable.messages.expand((message) => message.attachments),
        ...portable.steering.expand((input) => input.attachments),
      ]) {
        final key = attachment.reference;
        if (!_isCanonicalAssistantAssetPath(key)) {
          throw FormatException('助手附件不属于受管数据空间：$key');
        }
        if (!await File(_storage.absolutePath(key)).exists()) {
          throw FormatException('助手附件不存在：$key');
        }
        assetKeys.add(key);
      }
    }
    final sortedKeys = assetKeys.toList()..sort();
    return _PortableAgentHistory(
      json: {
        'kind': _agentHistoryKind,
        'formatVersion': _agentHistoryFormatVersion,
        'runSchemaVersion': AgentRun.schemaVersion,
        'runs': portableRuns,
      },
      runs: List.unmodifiable(portableObjects),
      runCount: portableRuns.length,
      assetKeys: List.unmodifiable(sortedKeys),
      containsPrivateData: containsPrivateData,
    );
  }

  bool _runContainsPrivateData(AgentRun run, Set<String> privateNoteIds) =>
      run.scope.privateNotes ||
      run.requiresPrivateAccess ||
      run.messages
          .expand((message) => message.sources)
          .any((source) => privateNoteIds.contains(source['noteId'])) ||
      run.steering
          .expand((input) => input.sources)
          .any((source) => privateNoteIds.contains(source['noteId'])) ||
      run.actions.any(
        (action) =>
            ((action['preview'] as Json?)?['versions'] as Json?)?.keys.any(
              privateNoteIds.contains,
            ) ==
            true,
      ) ||
      run.pending.any(
        (pending) =>
            pending.preview?.versions.keys.any(privateNoteIds.contains) == true,
      );

  String _manifestFilesDigest(Map<String, Object?> files) => sha256
      .convert(utf8.encode(jsonEncode(SplayTreeMap<String, Object?>.of(files))))
      .toString();

  String _safeName(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    if (normalized.isEmpty ||
        normalized == '.' ||
        p.posix.isAbsolute(normalized) ||
        normalized.startsWith('../') ||
        normalized == '..') {
      throw const FormatException('备份中包含不安全路径');
    }
    return normalized;
  }

  bool _isAllowedArchivePath(String value, int formatVersion) =>
      value == NoteDatabaseService.databaseFileName ||
      _isCanonicalNoteAssetPath(value) ||
      formatVersion >= 3 &&
          (value == LocalChatDatabaseService.databaseFileName ||
              value == _agentHistoryName ||
              _isCanonicalAssistantAssetPath(value));

  bool _isCanonicalNoteAssetPath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    final parts = p.posix.split(normalized);
    return normalized == value &&
        parts.length >= 3 &&
        parts.first == 'notes' &&
        _noteAssetDirectories.contains(parts[1]) &&
        !parts.contains('..');
  }

  bool _isCanonicalAssistantAssetPath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    final parts = p.posix.split(normalized);
    return normalized == value &&
        parts.length == 2 &&
        parts.first == 'assistant' &&
        parts.last.isNotEmpty &&
        _assistantImageExtensions.contains(
          p.posix.extension(parts.last).toLowerCase(),
        );
  }

  Future<void> _moveManagedData(
    Directory source,
    Directory target, {
    bool includeAssistantData = false,
  }) async {
    await target.create(recursive: true);
    for (final name in {
      'notes',
      NoteDatabaseService.databaseFileName,
      ..._databaseSidecars,
      if (includeAssistantData)
        for (final database in _assistantDatabaseNames) ...{
          database,
          '$database-journal',
          '$database-shm',
          '$database-wal',
        },
    }) {
      final sourcePath = p.join(source.path, name);
      final targetPath = p.join(target.path, name);
      switch (await FileSystemEntity.type(sourcePath, followLinks: false)) {
        case FileSystemEntityType.file:
          await File(sourcePath).rename(targetPath);
        case FileSystemEntityType.directory:
          await Directory(sourcePath).rename(targetPath);
        default:
          break;
      }
    }
    if (includeAssistantData) {
      await _moveAssistantAssets(source, target);
    }
  }

  Future<void> _moveAssistantAssets(Directory source, Directory target) async {
    final directory = Directory(p.join(source.path, 'assistant'));
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.posix.join('assistant', p.basename(entity.path));
      if (!_isCanonicalAssistantAssetPath(relative)) continue;
      final destination = File(p.join(target.path, relative));
      await destination.parent.create(recursive: true);
      await entity.rename(destination.path);
    }
  }

  Future<void> _deleteManagedData(
    Directory root, {
    bool includeAssistantData = false,
  }) async {
    for (final name in {
      'notes',
      NoteDatabaseService.databaseFileName,
      ..._databaseSidecars,
      if (includeAssistantData)
        for (final database in _assistantDatabaseNames) ...{
          database,
          '$database-journal',
          '$database-shm',
          '$database-wal',
        },
    }) {
      final path = p.join(root.path, name);
      switch (await FileSystemEntity.type(path, followLinks: false)) {
        case FileSystemEntityType.file:
          await File(path).delete();
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
        default:
          break;
      }
    }
    if (includeAssistantData) {
      final assistant = Directory(p.join(root.path, 'assistant'));
      if (await assistant.exists()) {
        await for (final entity in assistant.list(followLinks: false)) {
          if (entity is! File) continue;
          final relative = p.posix.join('assistant', p.basename(entity.path));
          if (_isCanonicalAssistantAssetPath(relative)) await entity.delete();
        }
      }
    }
  }

  Future<void> _resetInternalDirectory(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Future<void> _writeRestoreScope(
    Directory rollback, {
    required bool includeAssistantData,
    required String phase,
  }) async {
    final destination = File(p.join(rollback.path, _restoreScopeName));
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'includeAssistantData': includeAssistantData,
        'phase': phase,
      }),
      flush: true,
    );
    await temporary.rename(destination.path);
  }

  Future<({bool includeAssistantData, String phase})> _readRestoreScope(
    Directory rollback,
  ) async {
    final scope = File(p.join(rollback.path, _restoreScopeName));
    if (await scope.exists()) {
      try {
        final value = jsonDecode(await scope.readAsString());
        if (value is Map && value['formatVersion'] == 1) {
          return (
            includeAssistantData: value['includeAssistantData'] == true,
            phase: value['phase'] == 'movingOld' ? 'movingOld' : 'movingNew',
          );
        }
      } catch (_) {
        // Fall back to the files already moved by an older/interrupted build.
      }
    }
    return (
      includeAssistantData:
          await File(
            p.join(rollback.path, LocalChatDatabaseService.databaseFileName),
          ).exists() ||
          await File(
            p.join(rollback.path, EncryptedRunStore.fileName),
          ).exists(),
      phase: 'movingNew',
    );
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_operationInProgress) {
      throw StateError('已有备份或恢复任务正在执行');
    }
    _operationInProgress = true;
    try {
      return await operation();
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _cleanupOldArtifacts(Directory directory, DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 1));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.fknotes.zip')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Temporary exports may still be held by a receiving system app.
      }
    }
  }

  Future<void> _writeHistory(List<BackupRecord> records) async {
    await backupDirectory.create(recursive: true);
    final temporary = File('${_historyIndex.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'formatVersion': _historyFormatVersion,
        'records': records.map((record) => record.toJson()).toList(),
      }),
      flush: true,
    );
    try {
      await temporary.rename(_historyIndex.path);
    } on FileSystemException {
      if (await _historyIndex.exists()) await _historyIndex.delete();
      await temporary.rename(_historyIndex.path);
    }
  }

  bool _isSafeBackupFileName(String value) =>
      value == p.basename(value) &&
      value.endsWith('.fknotes.zip') &&
      value.isNotEmpty;

  String _defaultLabel(DateTime createdAt) =>
      'FKNotes ${createdAt.year}-${_two(createdAt.month)}-${_two(createdAt.day)} '
      '${_two(createdAt.hour)}:${_two(createdAt.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}

final class _BackupGraph {
  const _BackupGraph({
    required this.noteCount,
    required this.assetCount,
    required this.assetKeys,
    required this.containsPrivateNotes,
    required this.privateNoteIds,
    required this.contentDigest,
  });

  final int noteCount;
  final int assetCount;
  final List<String> assetKeys;
  final bool containsPrivateNotes;
  final Set<String> privateNoteIds;
  final String contentDigest;
}

final class _ChatBackupGraph {
  const _ChatBackupGraph({
    required this.sessionCount,
    required this.messageCount,
    required this.assetKeys,
    required this.containsPrivateData,
    required this.contentDigest,
  });

  final int sessionCount;
  final int messageCount;
  final List<String> assetKeys;
  final bool containsPrivateData;
  final String contentDigest;
}

final class _PortableAgentHistory {
  const _PortableAgentHistory({
    required this.json,
    required this.runs,
    required this.runCount,
    required this.assetKeys,
    required this.containsPrivateData,
  });

  final Json json;
  final List<AgentRun> runs;
  final int runCount;
  final List<String> assetKeys;
  final bool containsPrivateData;
}

final class BackupRecord {
  const BackupRecord({
    required this.fileName,
    required this.label,
    required this.description,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
    required this.createdAt,
    required this.formatVersion,
    this.containsPrivateNotes = false,
  });

  factory BackupRecord.fromJson(Map<String, Object?> json) {
    final fileName = json['fileName'];
    final label = json['label'];
    final description = json['description'];
    final contentDigest = json['contentDigest'];
    final archiveSha256 = json['archiveSha256'];
    final sizeBytes = json['sizeBytes'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final formatVersion = json['formatVersion'];
    if (fileName is! String ||
        label is! String ||
        description is! String ||
        contentDigest is! String ||
        archiveSha256 is! String ||
        sizeBytes is! int ||
        createdAt == null ||
        formatVersion is! int) {
      throw const FormatException('备份历史记录损坏');
    }
    return BackupRecord(
      fileName: fileName,
      label: label,
      description: description,
      contentDigest: contentDigest,
      archiveSha256: archiveSha256,
      sizeBytes: sizeBytes,
      createdAt: createdAt.toUtc(),
      formatVersion: formatVersion,
      containsPrivateNotes: json['containsPrivateNotes'] == true,
    );
  }

  final String fileName;
  final String label;
  final String description;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;
  final int formatVersion;
  final bool containsPrivateNotes;

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'label': label,
    'description': description,
    'contentDigest': contentDigest,
    'archiveSha256': archiveSha256,
    'sizeBytes': sizeBytes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'formatVersion': formatVersion,
    'containsPrivateNotes': containsPrivateNotes,
  };
}

final class BackupArtifact {
  const BackupArtifact({
    required this.file,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
    required this.createdAt,
    this.containsPrivateNotes = false,
  });

  final File file;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;
  final DateTime createdAt;
  final bool containsPrivateNotes;
}

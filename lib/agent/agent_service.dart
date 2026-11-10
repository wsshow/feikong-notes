import 'dart:async';
import 'dart:io';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/local_chat.dart';
import '../models/note.dart';
import '../providers/private_notes_controller.dart';
import '../services/file_storage_service.dart';
import '../services/language_model_service.dart';
import '../services/local_assistant_service.dart';
import '../services/note_database_service.dart';
import '../services/note_repository.dart';
import 'agent_attachment_loader.dart';
import 'agent_policy.dart';
import 'credential_vault.dart';
import 'encrypted_run_store.dart';
import 'local_model_adapter.dart';
import 'mcp_tools.dart';
import 'model_profile.dart';
import 'model_catalog.dart';
import 'note_tools.dart';
import 'web_tools.dart';
import 'online_model_adapter.dart';

/// Application-owned runtime. Pages subscribe to snapshots; navigating away
/// does not destroy an agent, lose its approval, or create a second executor.
class AgentService extends ChangeNotifier {
  static AgentService? _instance;
  static AgentService get instance =>
      _instance ??= AgentService(storage: FileStorageService.instance);
  static AgentService? get currentInstance => _instance;
  final FileStorageService storage;
  final CredentialVault vault;
  final PrivateNotesController privateNotes;
  final Future<NoteRepository> Function() repository;
  final ModelResolver? _modelOverride;
  final bool _ownsPrivacy;
  late final ModelProfileStore profiles;
  late final ModelCatalog modelCatalog;
  late final McpConfigStore mcpConfigs;
  late final AgentPolicy policy;
  late final ProposeNoteChangesTool noteChanges;
  late final McpGateway mcp;
  RunStore? _store;
  HarnessRuntime? _runtime;
  StreamSubscription<RunEvent>? _subscription;
  Future<void>? _initializing;
  final _runs = <String, AgentRun>{};
  List<AgentRun>? _runsSnapshot;
  final _refreshing = <String>{};
  final _dirty = <String>{};
  final _protecting = <String>{};
  final _privateIds = <String>{};
  final _privacyUpdates = <String, bool>{};
  final _viewGrants = <String, int>{};
  final _startingSessions = <String>{};
  final _privateContentSessions = <String>{};
  NoteRepository? _observedRepository;
  Object? error;
  bool _closed = false;
  bool _savingModels = false;

  AgentService({
    required this.storage,
    this.vault = const SystemCredentialVault(),
    PrivateNotesController? privateNotes,
    Future<NoteRepository> Function()? repository,
    RunStore? runStore,
    ModelResolver? modelResolver,
    ModelCatalog? modelCatalog,
  }) : privateNotes = privateNotes ?? PrivateNotesController(),
       _ownsPrivacy = privateNotes == null,
       repository =
           repository ?? (() => NoteDatabaseService.instance.repository),
       _store = runStore,
       _modelOverride = modelResolver {
    profiles = ModelProfileStore(
      File(p.join(storage.baseDir, 'assistant', 'model-profiles.json')),
    );
    this.modelCatalog = modelCatalog ?? ModelCatalog(vault);
    mcpConfigs = McpConfigStore(
      File(p.join(storage.baseDir, 'assistant', 'mcp-servers.json')),
    );
    policy = AgentPolicy(
      privateNotes: this.privateNotes,
      repository: this.repository,
      profile: profiles.get,
      onPrivateNoteContent: (id) {
        if (_privateContentSessions.add(id)) _notify();
      },
    );
    noteChanges = ProposeNoteChangesTool(
      NoteToolAccess(
        repository: this.repository,
        validateScope: policy.validateScope,
      ),
    );
    mcp = McpGateway(vault);
    this.privateNotes.addListener(_privacyChanged);
  }

  bool get initialized => _runtime != null;
  HarnessRuntime get runtime =>
      _runtime ?? (throw StateError('Initialize AgentService first.'));
  List<AgentRun> get runs => _runsSnapshot ??= List<AgentRun>.unmodifiable(
    _runs.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
  List<AgentRun> sessionRuns(String id) => runs
      .where(
        (r) =>
            r.sessionId == id &&
            r.parentId == null &&
            !r.conversationQueuePending,
      )
      .toList()
      .reversed
      .toList();
  List<AgentRun> queuedSessionRuns(String id) => runs
      .where(
        (r) =>
            r.sessionId == id &&
            r.parentId == null &&
            r.conversationQueuePending &&
            r.status == RunStatus.queued,
      )
      .toList()
      .reversed
      .toList();
  bool canDisplay(AgentRun run) {
    if (!run.requiresPrivateAccess &&
        !run.scope.privateNotes &&
        !_protecting.contains(run.id) &&
        !_hasPrivateSource(run)) {
      return true;
    }
    if (privateNotes.protected) return false;
    // The workspace visit already authenticates viewing all of its history.
    // Execution still requires a fresh generation-bound scope in AgentPolicy.
    if (privateNotes.hasWorkspaceAuthorization) return true;
    final generation = privateNotes.authorizationGeneration;
    return _viewGrants[run.id] == generation ||
        run.scope.privateNotes && run.scope.privateGeneration == generation;
  }

  bool isPrivateRun(AgentRun run) =>
      run.scope.privateNotes ||
      run.requiresPrivateAccess ||
      _protecting.contains(run.id) ||
      _hasPrivateSource(run);

  bool hasPrivateNoteContent(AgentRun run) =>
      _hasPrivateSource(run) ||
      (isPrivateRun(run) &&
          run.messages.any(
            (message) =>
                message.sources.any((source) => source['noteId'] is String),
          ));

  bool sessionHasPrivateNoteContent(String id) =>
      _privateContentSessions.contains(id);

  bool _hasPrivateSource(AgentRun run) =>
      run.messages
          .expand((m) => m.sources)
          .any((s) => _privateIds.contains(s['noteId'])) ||
      run.actions.any(
        (a) =>
            ((a['preview'] as Json?)?['versions'] as Json?)?.keys.any(
              _privateIds.contains,
            ) ==
            true,
      ) ||
      run.pending.any(
        (p) => p.preview?.versions.keys.any(_privateIds.contains) == true,
      );

  Future<void> _observeRepository() async {
    final repo = await repository();
    if (identical(repo, _observedRepository)) return;
    _observedRepository?.removePrivacyListener(_notePrivacyChanged);
    _observedRepository = repo;
    _privacyUpdates.clear();
    repo.addPrivacyListener(_notePrivacyChanged);
    final ids = await repo.privateNoteIds();
    for (final update in _privacyUpdates.entries) {
      if (update.value) {
        ids.add(update.key);
      } else {
        ids.remove(update.key);
      }
    }
    _privateIds
      ..clear()
      ..addAll(ids);
    if (initialized) {
      for (final run in runs.where(_hasPrivateSource)) {
        _protectHistory(run);
      }
    }
  }

  void _notePrivacyChanged(NoteId id, bool private) {
    _privacyUpdates[id.value] = private;
    if (private) {
      _privateIds.add(id.value);
    } else {
      _privateIds.remove(id.value);
    }
    _notify();
    for (final run in runs.where(_hasPrivateSource)) {
      _protectHistory(run);
    }
  }

  void _protectHistory(AgentRun run) {
    if (run.requiresPrivateAccess || !_protecting.add(run.id)) return;
    unawaited(() async {
      try {
        await runtime.protectHistory(run.id);
        await _refresh(run.id);
      } catch (e) {
        error = e;
        _notify();
      } finally {
        _protecting.remove(run.id);
      }
    }());
  }

  Future<void> initialize() async {
    if (_initializing != null) return _initializing!;
    if (_runtime != null) return;
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> initializeIfHistoryExists() async {
    if (initialized ||
        _store != null ||
        await File(
          p.join(storage.baseDir, EncryptedRunStore.fileName),
        ).exists()) {
      await initialize();
    }
    if (initialized) await _observeRepository();
  }

  Future<void> _initialize() async {
    if (_closed) throw StateError('Agent service closed');
    _store ??= await EncryptedRunStore.open(
      p.join(storage.baseDir, EncryptedRunStore.fileName),
      vault,
    );
    try {
      await _observeRepository();
      await _installRuntime();
      await runtime.recover();
      _runs.addEntries((await runtime.list()).map((r) => MapEntry(r.id, r)));
      _runsSnapshot = null;
      for (final run in runs.where(_hasPrivateSource)) {
        _protectHistory(run);
      }
      _notify();
    } catch (_) {
      await _subscription?.cancel();
      await _runtime?.close();
      _runtime = null;
      rethrow;
    }
  }

  Future<void> _installRuntime() async {
    final access = NoteToolAccess(
      repository: repository,
      validateScope: policy.validateScope,
    );
    final configs = await mcpConfigs.list();
    _runtime = HarnessRuntime(
      store: _store!,
      resolveModel: _modelOverride ?? resolveModel,
      authorize: policy.authorize,
      tools: [
        SearchNotesTool(access),
        ReadNotesTool(access),
        noteChanges,
        WebFetchTool(),
        for (final server in configs.where((s) => s.enabled))
          for (final definition in server.tools)
            RemoteMcpTool(
              server: server,
              definition: definition,
              gateway: mcp,
              currentConfig: mcpConfigs.get,
            ),
      ],
    );
    _subscription = runtime.events.listen(
      (event) {
        unawaited(_refresh(event.runId));
      },
      onError: (Object e) {
        error = e;
        _notify();
      },
    );
  }

  Future<ModelPort> resolveModel(String id) async {
    if (_modelOverride != null) return _modelOverride(id);
    final profile = await profiles.get(id);
    final attachments = AgentAttachmentLoader(storage);
    if (profile.isRemote) {
      return OnlineModelAdapter(
        profile: profile,
        vault: vault,
        attachmentBytes: attachments.bytes,
      );
    }
    final models = LanguageModelService.instance;
    return LocalModelAdapter(
      service: LocalAssistantService.instance,
      descriptor: await models.descriptor(await models.selectedModelId()),
      attachments: attachments,
    );
  }

  Future<void> _refresh(String id) async {
    if (_closed) return;
    _dirty.add(id);
    if (!_refreshing.add(id)) return;
    try {
      while (_dirty.remove(id) && !_closed) {
        final run = await runtime.get(id);
        if (run != null) {
          _runs[id] = run;
          _runsSnapshot = null;
          if (_hasPrivateSource(run)) _protectHistory(run);
        } else {
          _runs.remove(id);
          _runsSnapshot = null;
        }
        _notify();
      }
    } catch (e) {
      error = e;
      _notify();
    } finally {
      _refreshing.remove(id);
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _privacyChanged() {
    // Redact synchronously, then cancel HTTP/native requests through runtime.
    _notify();
    if (privateNotes.protected && initialized) {
      for (final run in runs.where(
        (r) =>
            r.scope.privateNotes &&
            !r.status.terminal &&
            r.status != RunStatus.needsReconciliation,
      )) {
        unawaited(
          pause(run.id).catchError((Object e) {
            error = e;
            _notify();
          }),
        );
      }
    }
  }

  Future<RunScope> grant({
    required String profileId,
    String? expectedBinding,
    bool readNotes = false,
    Set<String> noteIds = const {},
    bool allNotes = false,
    bool privateAccess = false,
    bool online = false,
    bool networkTools = false,
    bool writeNotes = false,
    bool externalWrites = false,
    bool? requireApproval,
    Set<String>? expectedNetworkBindings,
  }) async {
    final profile = await profiles.get(profileId);
    if (expectedBinding != null && profile.binding != expectedBinding) {
      throw const HarnessException(
        'modelChanged',
        'Model configuration changed. Review access again.',
      );
    }
    final networkBindings = networkTools
        ? (await mcpConfigs.list())
              .where((s) => s.enabled)
              .map((s) => s.binding)
              .toSet()
        : <String>{};
    if (networkTools &&
        expectedNetworkBindings != null &&
        !setEquals(expectedNetworkBindings, networkBindings)) {
      throw const HarnessException(
        'networkChanged',
        'Review the changed network tools before granting access.',
      );
    }
    final scope = RunScope(
      online: online && profile.isRemote,
      modelBinding: profile.binding,
      networkTools: networkTools,
      externalWrites: externalWrites && networkTools,
      requireApproval:
          requireApproval ?? await profiles.defaultRequireApproval(),
      networkBindings: networkBindings,
      readNotes: readNotes,
      noteIds: Set.of(noteIds),
      allNotes: allNotes && readNotes,
      writeNotes: writeNotes,
      privateNotes: privateAccess,
      privateGeneration: privateAccess
          ? privateNotes.authorizationGeneration
          : null,
    );
    policy.validateScope(scope);
    return scope;
  }

  /// Builds the ordinary task scope from the user's saved model, MCP and
  /// approval settings. Configuring those services is the standing consent;
  /// task launch should not ask the user to restate the same choices.
  Future<RunScope> grantTaskDefaults({
    required String profileId,
    Set<String> noteIds = const {},
    RunScope? previous,
    bool privateAccess = false,
    bool privateSpace = false,
    bool editor = false,
  }) async {
    final profile = await profiles.get(profileId);
    final enabledServers = (await mcpConfigs.list())
        .where((server) => server.enabled)
        .toList(growable: false);
    final networkTools =
        !editor && (profile.isRemote || enabledServers.isNotEmpty);
    final continuingPrivateScope = previous?.privateNotes == true;
    return grant(
      profileId: profile.id,
      expectedBinding: profile.binding,
      readNotes: true,
      noteIds: {...?previous?.noteIds, ...noteIds},
      // Ordinary tasks can use the ordinary library. A newly introduced
      // private source stays limited to the explicitly known note IDs.
      allNotes:
          privateSpace ||
          (privateAccess ? continuingPrivateScope && previous!.allNotes : true),
      privateAccess: privateAccess || privateSpace,
      online: profile.isRemote,
      networkTools: networkTools,
      writeNotes: !editor,
      externalWrites: !editor && enabledServers.isNotEmpty,
      requireApproval: previous?.requireApproval,
      expectedNetworkBindings: networkTools
          ? enabledServers.map((server) => server.binding).toSet()
          : null,
    );
  }

  Future<bool> containsPrivateNotes(Iterable<String> ids) async {
    final repo = await repository();
    for (final value in ids.toSet()) {
      try {
        if (await repo.isPrivateNote(NoteId.parse(value))) return true;
      } on FormatException {
        // Untrusted source metadata cannot expand a task's private scope.
      }
    }
    return false;
  }

  Future<bool> hasEnabledNetworkTools() async =>
      (await mcpConfigs.list()).any((server) => server.enabled);

  Future<String> start({
    required String sessionId,
    required String input,
    required String profileId,
    required RunScope scope,
    List<AgentMessage> history = const [],
    List<ModelAttachment> attachments = const [],
    List<Json> inputSources = const [],
    List<ConversationQuote> inputQuotes = const [],
    String system = '',
    String skillId = 'assistant',
    RunLimits? limits,
    bool historyRequiresPrivateAccess = false,
  }) async {
    if (_savingModels || !_startingSessions.add(sessionId)) {
      throw const HarnessException(
        'taskActive',
        'This conversation is already starting a task.',
      );
    }
    try {
      await initialize();
      await _observeRepository();
      if ((await runtime.list(
        sessionId: sessionId,
      )).any((r) => r.parentId == null && !r.status.terminal)) {
        throw const HarnessException(
          'taskActive',
          'Continue or stop the existing task first.',
        );
      }
      policy.validateScope(scope);
      final id = await runtime.start(
        TaskRequest(
          sessionId: sessionId,
          input: input,
          profileId: profileId,
          noteStoreEpoch: await (await repository()).agentEpoch,
          scope: scope,
          history: history,
          attachments: attachments,
          inputSources: inputSources,
          inputQuotes: inputQuotes,
          system: system,
          skillId: skillId,
          limits: limits ?? (await profiles.get(profileId)).defaultRunLimits,
          historyRequiresPrivateAccess: historyRequiresPrivateAccess,
        ),
      );
      await _refresh(id);
      return id;
    } finally {
      _startingSessions.remove(sessionId);
    }
  }

  Future<void> pause(String id) async {
    await runtime.pause(id);
    await _refresh(id);
  }

  Future<void> cancel(String id) async {
    await runtime.cancel(id);
    await _refresh(id);
  }

  Future<void> resume(String id, RunScope scope, {String? profileId}) async {
    await _ensureExecutableHistory(id);
    policy.validateScope(scope);
    await runtime.resume(id, scope: scope, profileId: profileId);
    await _refresh(id);
  }

  /// Viewing authorization lives in memory and never changes execution scope.
  /// Resuming still requires explicit online/private/network consent.
  Future<void> renewViewGrant(String id, RunScope scope) async {
    if (await runtime.get(id) == null) return;
    policy.validateScope(scope);
    if (!scope.privateNotes) {
      throw const HarnessException('privateLocked', 'Renew private access.');
    }
    _viewGrants[id] = privateNotes.authorizationGeneration;
    _notify();
  }

  Future<String> retry(String id, RunScope scope, {String? profileId}) async {
    await _ensureExecutableHistory(id);
    policy.validateScope(scope);
    final next = await runtime.retry(id, scope: scope, profileId: profileId);
    await _refresh(next);
    return next;
  }

  Future<void> regenerate(
    String id,
    RunScope scope, {
    String? profileId,
  }) async {
    await _ensureExecutableHistory(id);
    policy.validateScope(scope);
    await runtime.regenerate(id, scope: scope, profileId: profileId);
    await _refresh(id);
  }

  Future<String> steer(
    String id,
    String input, {
    List<ModelAttachment> attachments = const [],
    List<ConversationQuote> quotes = const [],
    List<Json> sources = const [],
  }) async {
    await _ensureExecutableHistory(id);
    final queueId = await runtime.steer(
      id,
      input,
      attachments: attachments,
      quotes: quotes,
      sources: sources,
    );
    await _refresh(id);
    return queueId;
  }

  Future<String> enqueue(
    String predecessorId,
    String input, {
    List<ModelAttachment> attachments = const [],
    List<ConversationQuote> quotes = const [],
    List<Json> sources = const [],
  }) async {
    await _ensureExecutableHistory(predecessorId);
    final id = await runtime.enqueue(
      predecessorId,
      input,
      attachments: attachments,
      quotes: quotes,
      sources: sources,
    );
    await _refresh(id);
    return id;
  }

  Future<void> beginQueuedEdit(String id) async {
    await runtime.beginQueuedEdit(id);
    await _refresh(id);
  }

  Future<void> finishQueuedEdit(String id, String input) async {
    await runtime.finishQueuedEdit(id, input);
    await _refresh(id);
  }

  Future<void> cancelQueuedEdit(String id) async {
    await runtime.cancelQueuedEdit(id);
    await _refresh(id);
  }

  Future<void> cancelQueued(String id) async {
    await runtime.cancelQueued(id);
    await _refresh(id);
  }

  Future<String> promoteQueued(String id, String targetId) async {
    final steeringId = await runtime.promoteQueued(id, targetId);
    await Future.wait([_refresh(id), _refresh(targetId)]);
    return steeringId;
  }

  Future<void> editQueuedInput(String id, String queueId, String input) async {
    await runtime.editSteering(id, queueId, input);
    await _refresh(id);
  }

  Future<void> cancelQueuedInput(String id, String queueId) async {
    await runtime.cancelSteering(id, queueId);
    await _refresh(id);
  }

  Future<void> undo(String id, String operationId) async {
    final run = await runtime.get(id);
    if (run?.historyOnly == true) {
      throw const HarnessException(
        'historyOnly',
        'Restored history cannot replay an old operation.',
      );
    }
    if (run == null || !run.status.terminal) {
      throw const HarnessException(
        'taskActive',
        'Wait for this task to stop before undoing a change.',
      );
    }
    final index = run.actions.indexWhere(
      (a) =>
          a['operationId'] == operationId &&
          a['name'] == 'propose_note_changes',
    );
    if (index < 0) {
      throw const HarnessException(
        'undoUnavailable',
        'This action cannot be undone by FKNotes.',
      );
    }
    if (!canDisplay(run)) {
      throw const HarnessException(
        'privateLocked',
        'Unlock the history before undoing.',
      );
    }
    // Explicit undo is a local operation. Viewing a protected receipt must
    // never renew the original run's online/external execution permissions.
    final undoRun = run.clone();
    undoRun.scope = RunScope.fromJson({
      ...run.scope.toJson(),
      'online': false,
      'networkTools': false,
      'externalWrites': false,
      if (run.requiresPrivateAccess || _hasPrivateSource(run)) ...{
        'privateNotes': true,
        'privateGeneration': privateNotes.authorizationGeneration,
      },
    });
    await noteChanges.undo(
      ToolContext(
        run: undoRun,
        operationId: 'undo:$operationId',
        argumentsDigest: contentDigest({'undo': operationId}),
        cancel: CancellationToken(),
        ensureActive: () => policy.authorize(undoRun, tool: noteChanges.spec),
      ),
      run.actions[index],
    );
    run.actions[index]['undone'] = true;
    final revision = run.revision;
    run.revision++;
    run.updatedAt = DateTime.now().toUtc();
    await _store!.save(run, expectedRevision: revision);
    await _refresh(id);
  }

  Future<void> deleteRun(String id) async {
    await initialize();
    await runtime.cancel(id);
    await _store!.delete(id);
    _runs.removeWhere((key, run) => key == id || run.rootId == id);
    _runsSnapshot = null;
    _notify();
  }

  Future<void> deleteSession(String sessionId) async {
    await initializeIfHistoryExists();
    if (!initialized) return;
    for (final run in await runtime.list(sessionId: sessionId)) {
      if (run.parentId != null) continue;
      await deleteRun(run.id);
    }
  }

  Future<void> ensureConfigurationEditable() async {
    if (!initialized) return;
    if ((await runtime.list()).any(
      (r) => {
        RunStatus.running,
        RunStatus.queued,
        RunStatus.cancelling,
      }.contains(r.status),
    )) {
      throw const HarnessException(
        'taskActive',
        'Pause active tasks before changing model or tool configuration.',
      );
    }
  }

  Future<void> _ensureExecutableHistory(String id) async {
    await initializeIfHistoryExists();
    if (!initialized) return;
    if ((await runtime.get(id))?.historyOnly == true) {
      throw const HarnessException(
        'historyOnly',
        'Restored history is read-only. Send a new message to continue.',
      );
    }
  }

  /// Releases history database handles before an atomic data restore. The
  /// service itself stays alive and lazily opens the restored history later.
  Future<void> releaseHistoryForRestore() async {
    await _initializing;
    if (_startingSessions.isNotEmpty || _savingModels) {
      throw const HarnessException(
        'taskActive',
        'Wait for the active assistant operation before restoring.',
      );
    }
    await _subscription?.cancel();
    _subscription = null;
    await _runtime?.close();
    if (_store is EncryptedRunStore) {
      await (_store as EncryptedRunStore).close();
    }
    _runtime = null;
    _store = null;
    _runs.clear();
    _runsSnapshot = null;
    _viewGrants.clear();
    _privateContentSessions.clear();
    _protecting.clear();
    _dirty.clear();
    _refreshing.clear();
    error = null;
    _notify();
  }

  /// The default is only read when starting a task. Selecting another saved
  /// model must not restart the runtime or change an in-flight run's binding.
  Future<void> selectModel(String id) async {
    await profiles.select(id);
    _notify();
  }

  Future<void> saveModelService(
    String serviceId,
    List<ModelProfile> models, {
    String? apiKey,
    String? selectedId,
  }) async {
    if (_savingModels || _startingSessions.isNotEmpty) {
      throw const HarnessException(
        'taskActive',
        'Wait for the active operation.',
      );
    }
    _savingModels = true;
    try {
      await ensureConfigurationEditable();
      for (final model in models) {
        model.validate();
      }
      final keyId = 'fknotes.agent.key.$serviceId';
      final replaceKey = apiKey?.trim().isNotEmpty == true;
      final previousKey = replaceKey ? await vault.read(keyId) : null;
      if (replaceKey) await vault.write(keyId, apiKey!.trim());
      try {
        await profiles.saveService(serviceId, models, selectedId: selectedId);
      } catch (_) {
        // A failed metadata save must not leave the old service using a new key.
        if (replaceKey) {
          if (previousKey == null) {
            await vault.delete(keyId);
          } else {
            await vault.write(keyId, previousKey);
          }
        }
        rethrow;
      }
      await configurationChanged();
    } finally {
      _savingModels = false;
    }
  }

  Future<void> configurationChanged() async {
    await ensureConfigurationEditable();
    if (initialized) {
      await _subscription?.cancel();
      await runtime.close();
      await _installRuntime();
    }
    _notify();
  }

  Future<void> clearHistory() async {
    await _initializing;
    await ensureConfigurationEditable();
    await _subscription?.cancel();
    await _runtime?.close();
    if (_store is EncryptedRunStore) {
      await (_store as EncryptedRunStore).close();
    }
    _runtime = null;
    _store = null;
    _runs.clear();
    _runsSnapshot = null;
    _viewGrants.clear();
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File(
        p.join(storage.baseDir, '${EncryptedRunStore.fileName}$suffix'),
      );
      if (await file.exists()) await file.delete();
    }
    await vault.delete(EncryptedRunStore.keyId);
    error = null;
    _notify();
  }

  Future<void> testConnection(
    ModelProfile profile,
    CancellationToken cancel, {
    String? apiKey,
  }) async {
    final adapter = _modelOverride != null
        ? await _modelOverride(profile.id)
        : OnlineModelAdapter(
            profile: profile,
            vault: apiKey?.trim().isNotEmpty == true
                ? TransientCredentialVault(
                    vault,
                    profile.credentialId,
                    apiKey!.trim(),
                  )
                : vault,
          );
    try {
      final events = await adapter
          .generate(
            ModelRequest(
              messages: [
                AgentMessage(role: MessageRole.user, text: 'Reply with OK.'),
              ],
              tools: [],
              maxOutputTokens: 64.clamp(1, profile.maxOutputTokens),
            ),
            cancel,
          )
          .toList()
          .timeout(const Duration(seconds: 20));
      if (!events.any((e) => e is ModelCompleted)) {
        throw const HarnessException(
          'incompleteStream',
          'Connection ended without a complete response.',
        );
      }
    } finally {
      cancel.cancel();
    }
  }

  /// Legacy conversations remain readable. Only an explicitly granted scope
  /// may carry their note context into the new runtime.
  List<AgentMessage> legacyHistory(List<LocalChatMessage> messages) => [
    for (final m in messages)
      AgentMessage(
        role: m.role == LocalChatRole.user
            ? MessageRole.user
            : MessageRole.assistant,
        text:
            '${m.content}${m.noteContexts.map((n) => '\n\n<note_context id="${n.noteId.value}">\n${n.title}\n${n.content}\n</note_context>').join()}',
        attachments: [
          for (final a in m.attachments)
            ModelAttachment(a.filePath, a.mimeType),
        ],
        sources: [
          for (final n in m.noteContexts)
            {'noteId': n.noteId.value, 'title': n.title},
        ],
      ),
  ];

  Future<void> close() async {
    if (_closed) return;
    await _subscription?.cancel();
    await _runtime?.close();
    if (_store is EncryptedRunStore) {
      await (_store as EncryptedRunStore).close();
    }
    privateNotes.removeListener(_privacyChanged);
    _observedRepository?.removePrivacyListener(_notePrivacyChanged);
    if (_ownsPrivacy) privateNotes.dispose();
    _closed = true;
    super.dispose();
  }
}

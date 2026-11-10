import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';

import 'app_overlay.dart';

import '../agent/agent_service.dart';
import '../agent/model_profile.dart';
import '../agent/mcp_tools.dart';
import '../l10n/l10n.dart';
import '../models/local_chat.dart';
import '../services/device_authentication_service.dart';
import 'app_feedback.dart';
import 'local_chat_note_picker.dart';
import 'private_notes_scope.dart';

class AgentGrant {
  final RunScope scope;
  final RunLimits limits;
  final String skillId;
  final List<LocalChatNoteContext> selectedNotes;
  final bool includeHistory;
  const AgentGrant(
    this.scope,
    this.limits,
    this.skillId,
    this.selectedNotes, {
    this.includeHistory = true,
  });
}

/// Uses saved configuration and the current workspace's authorization.
/// Cloud disclosure is a persistent inline status, not a per-turn dialog.
Future<AgentGrant?> prepareAgentTask(
  BuildContext context, {
  required AgentService service,
  required ModelProfile profile,
  List<LocalChatNoteContext> notes = const [],
  Set<String> noteIds = const {},
  RunScope? previous,
  RunLimits? limits,
  String skillId = 'assistant',
  bool editor = false,
  bool historyRequiresPrivateAccess = false,
  bool? privateSpace,
}) async {
  final ids = {
    ...noteIds,
    ...notes.map((note) => note.noteId.value),
    ...?previous?.noteIds,
  };
  final privateContent =
      historyRequiresPrivateAccess ||
      previous?.privateNotes == true ||
      notes.any((note) => note.isPrivate) ||
      await service.containsPrivateNotes(ids);
  if (privateSpace == false && privateContent) {
    throw const HarnessException(
      'historyScope',
      'Open private content in the private workspace.',
    );
  }
  final privateAccess = privateSpace == true || privateContent;
  if (privateAccess) {
    if (!context.mounted) return null;
    final session = PrivateNotesScope.maybeOf(context);
    if (session != null) {
      if (session.protected) return null;
      service.privateNotes.followSession(session);
    }
    if (service.privateNotes.protected) {
      if (!context.mounted) return null;
      final verified = await service.privateNotes.unlock(
        prompt: DeviceAuthenticationPrompt(
          reason: context.l10n.agentPrivateUnlock,
        ),
      );
      if (!verified.authenticated) return null;
    }
  }
  final scope = await service.grantTaskDefaults(
    profileId: profile.id,
    noteIds: ids,
    previous: previous,
    privateAccess: privateAccess,
    privateSpace: privateSpace == true,
    editor: editor,
  );
  return AgentGrant(scope, limits ?? profile.defaultRunLimits, skillId, notes);
}

Future<AgentGrant?> showAgentPermissionSheet(
  BuildContext context, {
  required AgentService service,
  required ModelProfile profile,
  List<LocalChatNoteContext> notes = const [],
  RunScope? initialScope,
  RunLimits? limits,
  String skillId = 'assistant',
  bool showHistoryOption = false,
  bool editLimits = true,
}) => AppOverlay.bottomSheet<AgentGrant>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _GrantSheet(
    service: service,
    profile: profile,
    notes: notes,
    initialScope: initialScope,
    limits: limits ?? profile.defaultRunLimits,
    skillId: skillId,
    showHistoryOption: showHistoryOption,
    editLimits: editLimits,
  ),
);

class _GrantSheet extends StatefulWidget {
  final AgentService service;
  final ModelProfile profile;
  final List<LocalChatNoteContext> notes;
  final RunScope? initialScope;
  final RunLimits limits;
  final String skillId;
  final bool showHistoryOption;
  final bool editLimits;
  const _GrantSheet({
    required this.service,
    required this.profile,
    required this.notes,
    required this.initialScope,
    required this.limits,
    required this.skillId,
    required this.showHistoryOption,
    required this.editLimits,
  });
  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  late int _scope;
  late Set<String> _ids;
  late List<LocalChatNoteContext> _notes;
  late String _skill;
  bool _online = false,
      _network = false,
      _write = false,
      _external = false,
      _private = false,
      _privateSending = false,
      _busy = false;
  bool _includeHistory = true;
  bool? _requireApproval;
  bool _approvalLoadFailed = false;
  late final List<TextEditingController> _budgets;
  late final Future<List<McpServerConfig>> _servers;
  @override
  void initState() {
    super.initState();
    _servers = widget.service.mcpConfigs.list();
    _notes = List.of(widget.notes);
    _ids = {
      ...?widget.initialScope?.noteIds,
      ..._notes.map((n) => n.noteId.value),
    };
    _scope = widget.initialScope?.allNotes == true
        ? 2
        : (_ids.isNotEmpty ? 1 : 0);
    _skill = widget.skillId;
    _online = widget.initialScope?.online == true;
    _network = widget.initialScope?.networkTools == true;
    _write = widget.initialScope?.writeNotes == true;
    _external = widget.initialScope?.externalWrites == true;
    if (!widget.editLimits && widget.initialScope != null) {
      _requireApproval = widget.initialScope!.requireApproval;
    } else {
      _loadApprovalMode();
    }
    // Private access always needs an explicit renewed grant, including resume.
    _budgets = [
      widget.limits.maxRequests,
      widget.limits.maxTokens,
      widget.limits.maxOutputTokens,
      widget.limits.activeTimeout.inMinutes,
      widget.limits.requestTimeout.inSeconds,
    ].map((n) => TextEditingController(text: '$n')).toList();
  }

  Future<void> _loadApprovalMode() async {
    try {
      final value = await widget.service.profiles.defaultRequireApproval();
      if (mounted) setState(() => _requireApproval = value);
    } catch (_) {
      if (mounted) setState(() => _approvalLoadFailed = true);
    }
  }

  @override
  void dispose() {
    for (final c in _budgets) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      if (_private && widget.service.privateNotes.protected) {
        final verified = await widget.service.privateNotes.unlock(
          prompt: DeviceAuthenticationPrompt(
            reason: context.l10n.agentPrivateUnlock,
          ),
        );
        if (!verified.authenticated) {
          throw const HarnessException(
            'privateLocked',
            'Authentication was not completed.',
          );
        }
      }
      final values = _budgets.map((c) => int.tryParse(c.text)).toList();
      if (values.any((n) => n == null || n < 1) ||
          values[0]! > 100 ||
          values[1]! > 20 * 1024 * 1024 ||
          (widget.editLimits &&
              values[2]! >
                  (widget.profile.isRemote
                      ? widget.profile.maxOutputTokens
                      : 32768)) ||
          values[3]! > 60 ||
          values[4]! > 600) {
        throw const HarnessException('invalidBudget', 'Invalid task limits.');
      }
      final scope = await widget.service.grant(
        profileId: widget.profile.id,
        expectedBinding: widget.profile.binding,
        readNotes: _scope != 0,
        noteIds: _scope == 1 ? _ids : {},
        allNotes: _scope == 2,
        privateAccess: _private,
        online: _online,
        networkTools: _network,
        writeNotes: _write,
        externalWrites: _external,
        requireApproval: _requireApproval!,
        expectedNetworkBindings: _network
            ? (await _servers)
                  .where((s) => s.enabled)
                  .map((s) => s.binding)
                  .toSet()
            : null,
      );
      final limits = RunLimits(
        maxRequests: values[0]!,
        maxTokens: values[1]!,
        maxOutputTokens: values[2]!,
        activeTimeout: Duration(minutes: values[3]!),
        requestTimeout: Duration(seconds: values[4]!),
      );
      limits.validate();
      if (mounted) {
        Navigator.pop(
          context,
          AgentGrant(
            scope,
            widget.editLimits ? limits : widget.limits,
            _skill,
            _scope == 0 ? const [] : _notes,
            includeHistory: _includeHistory,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.agentError(
            e is HarnessException ? e.code : 'invalidConfiguration',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final remote = widget.profile.isRemote;
    final canStart =
        !_busy &&
        _requireApproval != null &&
        !_approvalLoadFailed &&
        (!remote || _online) &&
        (!_private || !(remote || _network) || _privateSending) &&
        (_scope != 1 || _ids.isNotEmpty);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.agentPermissionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.profile.displayName} · ${remote ? widget.profile.baseUri.toString() : l.agentLocal}',
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(l.agentPermissionBody),
                    if (_approvalLoadFailed)
                      Text(l.agentError('configuration')),
                    if (widget.showHistoryOption)
                      CheckboxListTile(
                        key: const Key('agent-include-history'),
                        title: Text(l.agentIncludeHistory),
                        subtitle: Text(l.agentHistoryScopeHint),
                        value: _includeHistory,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _includeHistory = v!),
                      ),
                    if (remote) ...[
                      const SizedBox(height: 8),
                      Text(l.agentByokNotice),
                      CheckboxListTile(
                        key: const Key('agent-online-consent'),
                        title: Text(l.agentOnlineConsent),
                        value: _online,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _online = v!),
                      ),
                    ],
                    DropdownButtonFormField<int>(
                      key: const Key('agent-data-scope'),
                      initialValue: _scope,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(l.agentScopeNone),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            '${l.agentScopeSelected} (${_ids.length})',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(l.agentScopeAll),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _scope = v!),
                    ),
                    if (_scope == 1)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final notes = await showLocalChatNotePicker(
                                  context,
                                  initialSelection: _notes,
                                );
                                if (notes != null && mounted) {
                                  setState(() {
                                    _notes = notes;
                                    _ids = notes
                                        .map((n) => n.noteId.value)
                                        .toSet();
                                  });
                                }
                              },
                        child: Text(l.agentChooseNotes),
                      ),
                    CheckboxListTile(
                      title: Text(l.agentPrivateConsent),
                      value: _private,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _private = v!),
                    ),
                    CheckboxListTile(
                      key: const Key('agent-network-consent'),
                      title: Text(l.agentNetworkConsent),
                      value: _network,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _network = v!),
                    ),
                    if (_network)
                      FutureBuilder<List<McpServerConfig>>(
                        future: _servers,
                        builder: (context, snapshot) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.profile.capabilities.webSearch)
                              Text(l.agentServerSearch),
                            for (final server
                                in snapshot.data ?? <McpServerConfig>[])
                              if (server.enabled)
                                Text('${server.name} · ${server.endpoint}'),
                          ],
                        ),
                      ),
                    if (_private && (remote || _network))
                      CheckboxListTile(
                        title: Text(l.agentPrivateOnlineConsent),
                        value: _privateSending,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _privateSending = v!),
                      ),
                    if (_skill != 'editor') ...[
                      CheckboxListTile(
                        key: const Key('agent-write-consent'),
                        title: Text(l.agentWriteConsent),
                        value: _write,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _write = v!),
                      ),
                      if (_network)
                        CheckboxListTile(
                          key: const Key('agent-external-consent'),
                          title: Text(l.agentExternalConsent),
                          value: _external,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _external = v!),
                        ),
                      if (_write || _external) ...[
                        SwitchListTile(
                          key: const Key('agent-skip-approval'),
                          title: Text(l.agentSkipApproval),
                          subtitle: Text(l.agentApprovalTaskHint),
                          value: _requireApproval != true,
                          onChanged: _busy || _requireApproval == null
                              ? null
                              : (skip) =>
                                    setState(() => _requireApproval = !skip),
                        ),
                        const SizedBox(height: 16),
                      ],
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _skill,
                        decoration: InputDecoration(labelText: l.agentSkill),
                        items: [
                          for (final id in [
                            'assistant',
                            'summarize',
                            'rewrite',
                            'tasks',
                            'organize',
                          ])
                            DropdownMenuItem(
                              value: id,
                              child: Text(l.agentSkillName(id)),
                            ),
                        ],
                        onChanged: _busy || !widget.editLimits
                            ? null
                            : (v) => setState(() => _skill = v!),
                      ),
                    ],
                    if (widget.editLimits)
                      ExpansionTile(
                        key: const Key('agent-task-limits'),
                        title: Text(l.agentBudget),
                        childrenPadding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                        children: [
                          for (var i = 0; i < _budgets.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      [
                                        l.agentMaxRequests,
                                        l.agentMaxTokens,
                                        l.agentMaxOutput,
                                        l.agentMaxMinutes,
                                        l.agentRequestSeconds,
                                      ][i],
                                      key: ValueKey(
                                        'agent-task-limit-label-$i',
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    key: ValueKey('agent-task-limit-$i'),
                                    enabled: !_busy,
                                    controller: _budgets[i],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            FilledButton(
              key: const Key('agent-start-task'),
              onPressed: canStart ? _start : null,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.agentStart),
            ),
          ],
        ),
      ),
    );
  }
}

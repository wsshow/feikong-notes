import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../agent/agent_service.dart';
import '../agent/credential_vault.dart';
import '../agent/mcp_tools.dart';
import '../agent/model_profile.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_overlay.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';
import '../widgets/settings_description.dart';
import 'agent_model_editor_page.dart';
import 'model_management_page.dart';

class AgentSettingsPage extends StatefulWidget {
  final AgentService? service;
  const AgentSettingsPage({super.key, this.service});
  @override
  State<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends State<AgentSettingsPage> {
  late final AgentService service = widget.service ?? AgentService.instance;
  List<ModelProfile> _profiles = [];
  List<McpServerConfig> _servers = [];
  String _selected = 'local';
  bool _requireApproval = false;
  bool _savingApproval = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final profiles = await service.profiles.list();
      final servers = await service.mcpConfigs.list();
      final selected = await service.profiles.selectedId();
      final requireApproval = await service.profiles.defaultRequireApproval();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _servers = servers;
          _selected = selected;
          _requireApproval = requireApproval;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await service.ensureConfigurationEditable();
      await action();
      await service.configurationChanged();
      await _reload();
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.agentError(
            e is HarnessException ? e.code : 'configuration',
          ),
        );
      }
    }
  }

  Future<void> _editModel([ModelProfile? profile]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgentModelEditorPage(
          service: service,
          models: profile == null
              ? const []
              : _profiles
                    .where((p) => p.connectionId == profile.connectionId)
                    .toList(),
          initialModelId: profile?.id,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _setSkipApproval(bool skip) async {
    setState(() => _savingApproval = true);
    try {
      // Applies to future grants only; do not restart or alter active tasks.
      await service.profiles.setDefaultRequireApproval(!skip);
      if (mounted) setState(() => _requireApproval = !skip);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.agentError('configuration'));
      }
    } finally {
      if (mounted) setState(() => _savingApproval = false);
    }
  }

  Map<String, List<ModelProfile>> get _groups {
    final groups = <String, List<ModelProfile>>{};
    for (final p in _profiles) {
      (groups[p.connectionId] ??= []).add(p);
    }
    return groups;
  }

  Future<void> _selectModel(String id) async {
    try {
      await service.selectModel(id);
      await _reload();
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.agentError('configuration'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final modelRows = <Widget>[];
    for (final group in _groups.values) {
      final local = !group.first.isRemote;
      final selected = group.any((profile) => profile.id == _selected);
      final profile = group.firstWhere(
        (profile) => profile.id == _selected,
        orElse: () => group.first,
      );
      if (local) {
        modelRows.add(
          InsetSettingsRow(
            rowKey: ValueKey('agent-profile-${profile.id}'),
            title: l.agentLocal,
            subtitle: l.agentOfflineNotice,
            onTap: () => _selectModel('local'),
            trailing: selected
                ? AppIcon(Icons.check_rounded, color: context.appColors.accent)
                : const SizedBox(width: 20),
          ),
        );
        modelRows.add(
          InsetSettingsRow(
            title: l.agentManageLocalModels,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ModelManagementPage()),
              );
              await _reload();
            },
          ),
        );
      } else {
        modelRows.add(
          InsetSettingsRow(
            rowKey: ValueKey('agent-profile-${profile.id}'),
            title: profile.name,
            subtitle:
                '${profile.protocol.name} · ${profile.baseUri.host} · ${l.agentServiceModelCount(group.length)}',
            onTap: () => _editModel(profile),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  AppIcon(
                    Icons.check_rounded,
                    size: 19,
                    color: context.appColors.accent,
                  ),
                  const SizedBox(width: 8),
                ],
                AppIcon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.appColors.subtle,
                ),
              ],
            ),
          ),
        );
      }
    }
    modelRows.add(
      InsetSettingsRow(
        rowKey: const Key('agent-add-model'),
        title: l.agentAddModel,
        leading: AppIcon(
          Icons.add_rounded,
          size: 20,
          color: context.appColors.accent,
        ),
        onTap: () => _editModel(),
      ),
    );

    final mcpRows = <Widget>[
      if (_servers.isEmpty)
        InsetSettingsRow(title: l.agentNoMcpServers, enabled: false)
      else
        for (final server in _servers)
          InsetSettingsRow(
            title: server.name,
            subtitle: '${server.uri.host} · ${server.tools.length}',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _McpEditor(service: service, config: server),
                ),
              );
              await _reload();
            },
          ),
      InsetSettingsRow(
        rowKey: const Key('agent-add-mcp'),
        title: l.agentAddMcp,
        leading: AppIcon(
          Icons.add_rounded,
          size: 20,
          color: context.appColors.accent,
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _McpEditor(service: service)),
          );
          await _reload();
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.agentSettings)),
      body: _AgentPaper(
        child: ListView(
          key: const Key('agent-settings-form'),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            SettingsInlineDescription(
              description: l.agentByokSummary,
              detailsTitle: l.agentSettings,
              detailsDescription: l.agentByokNotice,
              detailsButtonKey: const Key('agent-settings-description'),
            ),
            const SizedBox(height: 20),
            InsetSettingsSection(
              title: l.agentExecution,
              children: [
                InsetSettingsSwitchRow(
                  rowKey: const Key('agent-default-skip-approval'),
                  title: l.agentSkipApproval,
                  subtitle: l.agentApprovalDefaultHint,
                  value: !_requireApproval,
                  onChanged: _savingApproval || _profiles.isEmpty
                      ? null
                      : _setSkipApproval,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  l.agentError('configuration'),
                  style: TextStyle(color: context.appColors.danger),
                ),
              ),
            ],
            const SizedBox(height: 22),
            InsetSettingsSection(title: l.agentProfiles, children: modelRows),
            const SizedBox(height: 22),
            InsetSettingsSection(
              title: l.agentMcp,
              footnote: l.agentMcpSummary,
              detailsTitle: l.agentMcp,
              detailsDescription: l.agentMcpNotice,
              detailsButtonKey: const Key('agent-mcp-description'),
              children: mcpRows,
            ),
            const SizedBox(height: 24),
            InsetSettingsSection(
              children: [
                InsetSettingsRow(
                  title: l.agentClearHistory,
                  destructive: true,
                  onTap: () async {
                    final yes = await AppOverlay.dialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l.agentClearHistory),
                        content: Text(l.agentClearHistoryNotice),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(l.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(l.remove),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) await _action(service.clearHistory);
                  },
                  trailing: const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _McpEditor extends StatefulWidget {
  final AgentService service;
  final McpServerConfig? config;
  const _McpEditor({required this.service, this.config});
  @override
  State<_McpEditor> createState() => _McpEditorState();
}

class _McpEditorState extends State<_McpEditor> {
  late final _id = widget.config?.id ?? const Uuid().v4();
  late final _name = TextEditingController(text: widget.config?.name ?? '');
  late final _endpoint = TextEditingController(
    text: widget.config?.endpoint ?? 'https://',
  );
  final _token = TextEditingController();
  late List<McpToolDefinition> _tools = List.of(widget.config?.tools ?? []);
  bool _busy = false;
  CancellationToken? _cancel;
  McpServerConfig get _config => McpServerConfig(
    id: _id,
    name: _name.text.trim(),
    endpoint: _endpoint.text.trim(),
    tools: _tools,
  );
  @override
  void dispose() {
    _cancel?.cancel();
    _name.dispose();
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.agentError(
            e is HarnessException ? e.code : 'mcpConfiguration',
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
    return Scaffold(
      appBar: AppBar(title: Text(l.agentMcp)),
      body: _AgentPaper(
        child: ListView(
          key: const Key('agent-mcp-form'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            SettingsInlineDescription(
              description: l.agentMcpSummary,
              detailsTitle: l.agentMcp,
              detailsDescription: l.agentMcpNotice,
              detailsButtonKey: const Key('agent-mcp-form-description'),
            ),
            const SizedBox(height: 20),
            InsetSettingsSection(
              footnote: l.agentKeyHint,
              children: [
                InsetSettingsFieldRow(
                  fieldKey: const Key('agent-mcp-name'),
                  label: l.agentProfileName,
                  controller: _name,
                  enabled: !_busy,
                ),
                InsetSettingsFieldRow(
                  fieldKey: const Key('agent-mcp-endpoint'),
                  label: l.agentEndpoint,
                  controller: _endpoint,
                  enabled: !_busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() => _tools = []),
                ),
                InsetSettingsFieldRow(
                  fieldKey: const Key('agent-mcp-token'),
                  label: l.agentMcpToken,
                  controller: _token,
                  enabled: !_busy,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                ),
              ],
            ),
            const SizedBox(height: 20),
            InsetSettingsSection(
              children: [
                InsetSettingsRow(
                  rowKey: const Key('agent-mcp-discover'),
                  title: l.agentMcpDiscover,
                  enabled: !_busy,
                  busy: _busy,
                  showDisclosure: false,
                  foregroundColor: context.appColors.accent,
                  onTap: () => _run(() async {
                    final config = _config;
                    config.validate();
                    _cancel = CancellationToken();
                    final vault = _token.text.trim().isEmpty
                        ? widget.service.vault
                        : TransientCredentialVault(
                            widget.service.vault,
                            config.credentialId,
                            _token.text.trim(),
                          );
                    final tools = await McpGateway(
                      vault,
                    ).discover(config, _cancel!);
                    if (mounted) setState(() => _tools = tools);
                  }),
                ),
              ],
            ),
            if (_tools.isNotEmpty) ...[
              const SizedBox(height: 20),
              InsetSettingsSection(
                children: [
                  for (var i = 0; i < _tools.length; i++) ...[
                    InsetSettingsRow(
                      title: _tools[i].name,
                      subtitle: _tools[i].description.trim().isEmpty
                          ? null
                          : _tools[i].description.trim(),
                      enabled: !_busy,
                      showDisclosure: false,
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _tools.removeAt(i)),
                        child: Text(l.remove),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(l.agentMcpReadOnly),
                      value: _tools[i].trustedReadOnly,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              final t = _tools[i];
                              _tools[i] = McpToolDefinition(
                                name: t.name,
                                description: t.description,
                                schema: t.schema,
                                trustedReadOnly: v!,
                              );
                            }),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            InsetSettingsSection(
              children: [
                InsetSettingsRow(
                  rowKey: const Key('agent-save-mcp'),
                  title: l.save,
                  enabled: !_busy && _tools.isNotEmpty,
                  showDisclosure: false,
                  foregroundColor: context.appColors.accent,
                  onTap: () => _run(() async {
                    final config = _config;
                    config.validate();
                    await widget.service.ensureConfigurationEditable();
                    if (_token.text.trim().isNotEmpty) {
                      await widget.service.vault.write(
                        config.credentialId,
                        _token.text.trim(),
                      );
                    }
                    await widget.service.mcpConfigs.save(config);
                    await widget.service.configurationChanged();
                    if (context.mounted) Navigator.pop(context);
                  }),
                ),
              ],
            ),
            if (widget.config != null) ...[
              const SizedBox(height: 20),
              InsetSettingsSection(
                children: [
                  InsetSettingsRow(
                    title: l.remove,
                    destructive: true,
                    enabled: !_busy,
                    showDisclosure: false,
                    onTap: () => _run(() async {
                      await widget.service.ensureConfigurationEditable();
                      await widget.service.mcpConfigs.delete(_id);
                      await widget.service.vault.delete(
                        widget.config!.credentialId,
                      );
                      await widget.service.configurationChanged();
                      if (context.mounted) Navigator.pop(context);
                    }),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentPaper extends StatelessWidget {
  final Widget child;
  const _AgentPaper({required this.child});
  @override
  Widget build(BuildContext context) => PaperShell(
    child: Material(color: Colors.transparent, child: child),
  );
}

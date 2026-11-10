import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app.dart';
import '../agent/agent_service.dart';
import '../agent/model_catalog.dart';
import '../agent/model_profile.dart';
import '../l10n/l10n.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

/// One connection and key, with independently editable model presets.
class AgentModelEditorPage extends StatefulWidget {
  final AgentService service;
  final List<ModelProfile> models;
  final String? initialModelId;
  const AgentModelEditorPage({
    super.key,
    required this.service,
    this.models = const [],
    this.initialModelId,
  });
  @override
  State<AgentModelEditorPage> createState() => _AgentModelEditorPageState();
}

class _AgentModelEditorPageState extends State<AgentModelEditorPage> {
  late final _serviceId =
      widget.models.firstOrNull?.connectionId ?? const Uuid().v4();
  late final _name = TextEditingController(
    text: widget.models.firstOrNull?.name ?? '',
  );
  late final _endpoint = TextEditingController(
    text: widget.models.firstOrNull?.endpoint ?? 'https://api.openai.com/v1',
  );
  final _key = TextEditingController();
  final _manual = TextEditingController();
  late ModelProtocol _protocol =
      widget.models.firstOrNull?.protocol ?? ModelProtocol.chatCompletions;
  final _drafts = <String, _ModelDraft>{};
  final _ownedDrafts = <_ModelDraft>{};
  late _ModelDraft _fallback = _newDraft(_serviceId);
  String? _current;
  bool _busy = false;
  CancellationToken? _cancel;
  String? _catalogError;
  String? _connectionResult;
  bool _connectionSucceeded = false;

  _ModelDraft get _draft => _drafts[_current] ?? _fallback;

  _ModelDraft _newDraft(String id, [ModelProfile? profile]) {
    final draft = _ModelDraft(
      profile ?? ModelProfile(id: id, name: '', protocol: _protocol),
    );
    _ownedDrafts.add(draft);
    return draft;
  }

  @override
  void initState() {
    super.initState();
    for (final p in widget.models) {
      _drafts[p.model] = _newDraft(p.id, p);
      if (p.id == widget.initialModelId) _current = p.model;
    }
    _current ??= _drafts.keys.firstOrNull;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    for (final c in [_name, _endpoint, _key, _manual]) {
      c.dispose();
    }
    for (final d in _ownedDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  ModelProfile _connection() => ModelProfile(
    id: _serviceId,
    serviceId: _serviceId,
    name: _name.text.trim(),
    protocol: _protocol,
    endpoint: _endpoint.text.trim(),
  );

  void _addIds(Iterable<String> ids) {
    final added = ids.where((id) => !_drafts.containsKey(id)).toSet();
    if (_drafts.length + added.length > 100) {
      throw const HarnessException(
        'invalidModelList',
        'Select at most 100 models.',
      );
    }
    setState(() {
      for (final id in added) {
        _drafts[id] = _drafts.isEmpty
            ? _fallback
            : _newDraft(const Uuid().v4());
      }
      _current ??= _drafts.keys.firstOrNull;
      _connectionResult = null;
    });
  }

  void _addManual() {
    final ids = ModelProfile.parseModelIds(_manual.text);
    if (ids.isEmpty) return;
    _addIds(ids);
    _manual.clear();
  }

  void _removeCurrentModel() => setState(() {
    _drafts.remove(_current);
    _current = _drafts.keys.firstOrNull;
    _connectionResult = null;
    if (_drafts.isEmpty) _fallback = _newDraft(const Uuid().v4());
  });

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, _errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    final l = context.l10n;
    return switch (error) {
      HarnessException(code: 'invalidModelLimits') => l.agentModelLimitsError,
      HarnessException(code: 'invalidModelList' || 'invalidModel') =>
        l.agentModelListError,
      _ => l.agentError(
        error is HarnessException ? error.code : 'configuration',
      ),
    };
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _connectionResult = null;
      _connectionSucceeded = false;
    });
    try {
      final models = _profiles();
      final profile = models.firstWhere((p) => p.id == _drafts[_current]!.id);
      _cancel = CancellationToken();
      await widget.service.testConnection(profile, _cancel!, apiKey: _key.text);
      if (mounted) {
        setState(() {
          _connectionResult = context.l10n.agentConnectionOk;
          _connectionSucceeded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _connectionResult = _errorMessage(error);
          _connectionSucceeded = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ModelProfile> _profiles() {
    _addManual();
    if (_drafts.isEmpty) {
      throw const HarnessException('invalidModelList', 'Add a model.');
    }
    final result = [
      for (final item in _drafts.entries)
        item.value.build(_connection(), item.key),
    ];
    for (final p in result) {
      p.validate();
    }
    return result;
  }

  Future<void> _discover() => _run(() async {
    setState(() => _catalogError = null);
    List<CatalogModel> models;
    try {
      _cancel = CancellationToken();
      models = await widget.service.modelCatalog.fetch(
        _connection(),
        _cancel!,
        apiKey: _key.text,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _catalogError = e is HarnessException
              ? e.code
              : 'modelCatalogFormat',
        );
      }
      return;
    }
    if (!mounted) return;
    if (models.isEmpty) {
      setState(() => _catalogError = 'empty');
      return;
    }
    // The network operation is over; do not animate a loader behind the picker.
    setState(() => _busy = false);
    final selected = await AppOverlay.bottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _CatalogPicker(models: models, existing: _drafts.keys.toSet()),
    );
    if (selected != null && mounted) _addIds(selected);
  });

  Future<void> _save() => _run(() async {
    final profiles = _profiles();
    await widget.service.saveModelService(
      _serviceId,
      profiles,
      apiKey: _key.text,
      selectedId: _drafts[_current]!.id,
    );
    if (mounted) Navigator.pop(context);
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.models.firstOrNull?.name ?? l.agentAddModel),
        actions: [
          TextButton(
            key: const Key('agent-save-model'),
            onPressed: _busy ? null : _save,
            child: Text(l.done),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PaperShell(
        child: Material(
          color: Colors.transparent,
          child: ListView(
            key: const Key('agent-model-form'),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              InsetSettingsSection(
                title: l.agentConnection,
                footnote: l.agentByokSummary,
                detailsTitle:
                    widget.models.firstOrNull?.name ?? l.agentAddModel,
                detailsDescription: l.agentByokNotice,
                detailsButtonKey: const Key('agent-model-description'),
                children: [
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-name'),
                    label: l.agentProfileName,
                    controller: _name,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),
                  InsetSettingsControlRow(
                    label: l.agentProtocol,
                    control: DropdownButtonHideUnderline(
                      child: DropdownButton<ModelProtocol>(
                        key: const Key('agent-profile-protocol'),
                        value: _protocol,
                        isExpanded: true,
                        isDense: true,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.ink,
                          height: 1.45,
                        ),
                        borderRadius: BorderRadius.circular(
                          context.appRadii.medium,
                        ),
                        items: [
                          for (final protocol in ModelProtocol.values.where(
                            (protocol) => protocol != ModelProtocol.local,
                          ))
                            DropdownMenuItem(
                              value: protocol,
                              child: Text(switch (protocol) {
                                ModelProtocol.chatCompletions =>
                                  'Chat Completions',
                                ModelProtocol.responses => 'Responses',
                                _ => 'Anthropic Messages',
                              }),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (protocol) => setState(() {
                                _protocol = protocol!;
                                _catalogError = null;
                                _connectionResult = null;
                              }),
                      ),
                    ),
                  ),
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-endpoint'),
                    label: l.agentEndpoint,
                    controller: _endpoint,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {
                      _catalogError = null;
                      _connectionResult = null;
                    }),
                  ),
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-key'),
                    label: l.agentApiKey,
                    controller: _key,
                    enabled: !_busy,
                    obscureText: true,
                    hintText: widget.models.isEmpty ? null : l.agentKeyStored,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _connectionResult = null),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              InsetSettingsSection(
                title: l.agentServiceModels,
                footnote: l.agentServiceModelsSummary,
                detailsTitle: l.agentServiceModels,
                detailsDescription:
                    '${l.agentCatalogNotice}\n\n${l.agentBatchModelHint}',
                detailsButtonKey: const Key('agent-service-models-description'),
                children: [
                  InsetSettingsRow(
                    rowKey: const Key('agent-fetch-models'),
                    title: l.agentFetchModels,
                    enabled: !_busy,
                    onTap: _busy ? null : _discover,
                  ),
                  if (_catalogError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Text(
                        l.agentCatalogFailed(_catalogError!),
                        key: const Key('agent-catalog-error'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.danger,
                        ),
                      ),
                    ),
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-model'),
                    label: l.agentBatchModelIds,
                    controller: _manual,
                    enabled: !_busy,
                    hintText: 'model-a, provider/model-b',
                    autocorrect: false,
                    enableSuggestions: false,
                    minLines: 1,
                    maxLines: 4,
                  ),
                  InsetSettingsRow(
                    rowKey: const Key('agent-add-model-ids'),
                    title: l.agentAddModelsToList,
                    enabled: !_busy,
                    leading: AppIcon(
                      Icons.add_rounded,
                      size: 20,
                      color: context.appColors.accent,
                    ),
                    onTap: _busy ? null : () => _run(() async => _addManual()),
                  ),
                  if (_drafts.isNotEmpty) ...[
                    InsetSettingsControlRow(
                      label: l.agentEditingModel(_drafts.length),
                      forceStacked: true,
                      control: SizedBox(
                        width: double.infinity,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('agent-current-model'),
                            value: _current,
                            isExpanded: true,
                            isDense: true,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.appColors.ink,
                                  height: 1.45,
                                ),
                            borderRadius: BorderRadius.circular(
                              context.appRadii.medium,
                            ),
                            items: [
                              for (final id in _drafts.keys)
                                DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (id) => setState(() {
                                    _current = id;
                                    _connectionResult = null;
                                  }),
                          ),
                        ),
                      ),
                    ),
                    InsetSettingsRow(
                      rowKey: const Key('agent-remove-model-id'),
                      title: l.agentRemoveModelFromList,
                      destructive: true,
                      enabled: !_busy,
                      trailing: const SizedBox.shrink(),
                      onTap: _busy ? null : _removeCurrentModel,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              InsetSettingsSection(
                title: l.agentModelParameters,
                footnote: l.agentModelLimitsSummary,
                detailsTitle: l.agentModelLimits,
                detailsDescription:
                    '${l.agentPerModelHint}\n\n${l.agentTokenUnits}\n${l.agentModelLimitsHint}',
                detailsButtonKey: const Key('agent-model-limits-description'),
                children: [
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-context'),
                    label: l.agentContextTokens,
                    controller: draft.context,
                    enabled: !_busy,
                    hintText: '1M',
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _connectionResult = null),
                  ),
                  InsetSettingsFieldRow(
                    fieldKey: const Key('agent-profile-output'),
                    label: l.agentMaxOutput,
                    controller: draft.output,
                    enabled: !_busy,
                    hintText: '384K',
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _connectionResult = null),
                  ),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    title: Text(
                      l.agentCapabilities,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    children: [
                      InsetSettingsSwitchRow(
                        title: l.agentToolCalling,
                        value: draft.tools,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                draft.tools = value;
                                _connectionResult = null;
                              }),
                      ),
                      InsetSettingsSwitchRow(
                        title: l.agentImageInput,
                        value: draft.images,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                draft.images = value;
                                _connectionResult = null;
                              }),
                      ),
                      if (_protocol != ModelProtocol.chatCompletions)
                        InsetSettingsSwitchRow(
                          title: l.agentServerSearch,
                          value: draft.search,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  draft.search = value;
                                  _connectionResult = null;
                                }),
                        ),
                      InsetSettingsSwitchRow(
                        title: l.agentThinking,
                        value: draft.thinking,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                draft.thinking = value;
                                _connectionResult = null;
                              }),
                      ),
                      if (_protocol == ModelProtocol.chatCompletions)
                        InsetSettingsSwitchRow(
                          title: l.agentUsageOption,
                          value: draft.usage,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  draft.usage = value;
                                  _connectionResult = null;
                                }),
                        ),
                      if (_protocol == ModelProtocol.responses)
                        InsetSettingsSwitchRow(
                          title: l.agentStatelessOption,
                          value: draft.stateless,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  draft.stateless = value;
                                  _connectionResult = null;
                                }),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              InsetSettingsSection(
                footnote: l.agentTestNotice,
                children: [
                  InsetSettingsRow(
                    rowKey: const Key('agent-test-model'),
                    title: l.agentTestConnection,
                    enabled: !_busy,
                    trailing: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SizedBox.shrink(),
                    onTap: _busy ? null : _testConnection,
                  ),
                ],
              ),
              if (_connectionResult != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    key: const Key('agent-connection-result'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(
                        _connectionSucceeded
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 18,
                        color: _connectionSucceeded
                            ? context.appColors.success
                            : context.appColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _connectionResult!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _connectionSucceeded
                                    ? context.appColors.success
                                    : context.appColors.danger,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.models.isNotEmpty) ...[
                const SizedBox(height: 24),
                InsetSettingsSection(
                  children: [
                    InsetSettingsRow(
                      rowKey: const Key('agent-delete-service'),
                      title: l.agentDeleteService,
                      destructive: true,
                      enabled: !_busy,
                      trailing: const SizedBox.shrink(),
                      onTap: _busy
                          ? null
                          : () => _run(() async {
                              final yes = await AppOverlay.dialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(l.agentDeleteService),
                                  content: Text(l.agentDeleteServiceHint),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text(l.cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(l.remove),
                                    ),
                                  ],
                                ),
                              );
                              if (yes != true) return;
                              await widget.service
                                  .ensureConfigurationEditable();
                              await widget.service.profiles.deleteService(
                                _serviceId,
                              );
                              await widget.service.vault.delete(
                                _connection().credentialId,
                              );
                              await widget.service.configurationChanged();
                              if (context.mounted) Navigator.pop(context);
                            }),
                    ),
                  ],
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelDraft {
  final String id;
  final TextEditingController context;
  final TextEditingController output;
  final bool legacyMaxTokens;
  bool tools, images, search, thinking, usage, stateless;
  _ModelDraft(ModelProfile p)
    : id = p.id,
      context = TextEditingController(
        text: _compactTokenCount(p.capabilities.contextTokens),
      ),
      output = TextEditingController(
        text: _compactTokenCount(p.maxOutputTokens),
      ),
      legacyMaxTokens = p.legacyMaxTokens,
      tools = p.capabilities.tools,
      images = p.capabilities.images,
      search = p.capabilities.webSearch,
      thinking = p.thinking,
      usage = p.includeUsage,
      stateless = p.statelessResponses;

  static String _compactTokenCount(int value) {
    const million = 1024 * 1024;
    if (value % million == 0) return '${value ~/ million}M';
    if (value % 1024 == 0) return '${value ~/ 1024}K';
    return '$value';
  }

  ModelProfile build(ModelProfile connection, String model) =>
      connection.copyWith(
        id: id,
        model: model,
        capabilities: ModelCapabilities(
          tools: tools,
          images: images,
          webSearch:
              search && connection.protocol != ModelProtocol.chatCompletions,
          contextTokens: ModelProfile.parseTokenCount(context.text) ?? 0,
          maxOutputTokens: ModelProfile.parseTokenCount(output.text) ?? 0,
        ),
        thinking: thinking,
        includeUsage: usage,
        statelessResponses: stateless,
        legacyMaxTokens: legacyMaxTokens,
      );
  void dispose() {
    context.dispose();
    output.dispose();
  }
}

class _CatalogPicker extends StatefulWidget {
  final List<CatalogModel> models;
  final Set<String> existing;
  const _CatalogPicker({required this.models, required this.existing});
  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final _selected = <String>{};
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final visible = widget.models
        .where(
          (m) => '${m.id} ${m.name ?? ''}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    final remaining = 100 - widget.existing.length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                key: const Key('agent-catalog-list'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.agentSelectCatalogModels,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('agent-catalog-search'),
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            labelText: l.agentSearchModels,
                            prefixIcon: const AppIcon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() {
                              for (final m in visible) {
                                if (_selected.length >= remaining) break;
                                if (!widget.existing.contains(m.id)) {
                                  _selected.add(m.id);
                                }
                              }
                            }),
                            child: Text(l.agentSelectVisibleModels),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final model = visible[i];
                      final exists = widget.existing.contains(model.id);
                      final selected = _selected.contains(model.id);
                      return CheckboxListTile(
                        key: ValueKey('agent-catalog-${model.id}'),
                        contentPadding:
                            context.appComponents.edgeAlignedInteractivePadding,
                        value: exists || selected,
                        title: Text(model.id),
                        subtitle: exists
                            ? Text(l.agentModelAlreadyAdded)
                            : model.name == null
                            ? null
                            : Text(model.name!),
                        onChanged:
                            exists ||
                                (!selected && _selected.length >= remaining)
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(model.id);
                                } else {
                                  _selected.remove(model.id);
                                }
                              }),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('agent-catalog-add'),
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected.toList()),
              child: Text(l.agentAddSelectedModels(_selected.length)),
            ),
          ],
        ),
      ),
    );
  }
}

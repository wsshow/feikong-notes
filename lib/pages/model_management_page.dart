import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../models/local_model.dart';
import '../services/model_download_source_policy.dart';
import '../services/local_model_manager.dart';
import '../services/realtime_dictation_preferences_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/inset_settings.dart';
import 'taobao_mnn_catalog_page.dart';
import '../widgets/app_icon.dart';

class ModelManagementPage extends StatefulWidget {
  final String? focusModelId;
  final LocalModelCategory? category;
  final bool showDictationSettings;
  final bool showDownloadSettings;
  final bool showTransferTasks;

  const ModelManagementPage({
    super.key,
    this.focusModelId,
    this.category,
    this.showDictationSettings = false,
    this.showDownloadSettings = false,
    this.showTransferTasks = false,
  });

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  final _manager = LocalModelManager.instance;
  final _sourcePolicy = ModelDownloadSourcePolicy.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  RealtimeDictationPreferences _preferences =
      const RealtimeDictationPreferences();
  bool _showInstalledModels = true;
  bool _filterChosenByUser = false;

  @override
  void initState() {
    super.initState();
    _showInstalledModels = _initialInstalledFilter;
    _manager.addListener(_changed);
    _sourcePolicy.addListener(_changed);
    // Model files may have been replaced by an app upgrade or removed outside
    // this page. Always validate the on-disk runtime instead of showing a
    // possibly stale singleton snapshot.
    unawaited(_initializeModels());
    unawaited(_sourcePolicy.load());
    unawaited(_loadDictationPreferences());
  }

  bool get _initialInstalledFilter {
    final id = widget.focusModelId;
    if (id == null) return true;
    try {
      return _manager.modelOf(id).availability ==
              LocalModelAvailability.builtIn ||
          _manager.installationOf(id).installed;
    } catch (_) {
      // A discovered model may not be registered until initialization finishes.
      return true;
    }
  }

  Future<void> _initializeModels() async {
    await _manager.initialize(force: true);
    if (!mounted || _filterChosenByUser) return;
    // A deep link chooses the initial tab only. Refreshes and download state
    // changes must never override a tab the user has explicitly chosen.
    setState(() => _showInstalledModels = _initialInstalledFilter);
  }

  Future<void> _loadDictationPreferences() async {
    final preferences = await _dictationPreferences.load();
    if (mounted) setState(() => _preferences = preferences);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_changed);
    _sourcePolicy.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showDictationSettings) return _buildDictationSettings(context);
    if (widget.showDownloadSettings) return _buildDownloadSettings(context);
    if (widget.showTransferTasks) return _buildTransferTasks(context);
    final category = widget.category ?? _focusedCategory;
    if (category != null) return _buildCategory(context, category);
    return _buildOverview(context);
  }

  LocalModelCategory? get _focusedCategory {
    final id = widget.focusModelId;
    if (id == null) return null;
    try {
      return _manager.modelOf(id).category;
    } catch (_) {
      return null;
    }
  }

  Widget _buildOverview(BuildContext context) {
    final active = _manager.activeModels(_preferences);
    final transferModels = _sortedTransferModels(_manager.models);
    final activeSize = active.fold<int>(
      0,
      (total, item) => total + item.installation.installedSizeBytes,
    );
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      appBar: AppBar(
        title: Text(
          context.l10n.localModelsPageTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('local-model-overview-list'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _ModelSummary(
              installedCount: active.length,
              installedSizeBytes: activeSize,
              activeOnly: true,
            ),
            if (transferModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              InsetSettingsSection(
                children: [
                  _ModelCategoryLink(
                    key: const Key('model-transfer-tasks-link'),
                    title: context.l10n.modelTransfers,
                    subtitle: _transferTaskSummary(transferModels),
                    onTap: _openTransferTasks,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            InsetSettingsSection(
              title: context.l10n.modelsInUse,
              children: active.isEmpty
                  ? [
                      InsetSettingsRow(
                        title: context.l10n.noModelsInUse,
                        enabled: false,
                        showDisclosure: false,
                      ),
                    ]
                  : [
                      for (final item in active)
                        _ActiveModelRow(
                          model: item,
                          onTap: () => _openCategory(
                            item.definition.category,
                            focusModelId: item.definition.id,
                          ),
                          onDetails: () => _showDetails(item.definition),
                        ),
                    ],
            ),
            const SizedBox(height: 24),
            InsetSettingsSection(
              title: context.l10n.modelConfiguration,
              children: [
                _ModelCategoryLink(
                  key: const Key('model-category-language'),
                  title: context.l10n.languageModels,
                  subtitle: _categorySubtitle(LocalModelCategory.language),
                  onTap: () => _openCategory(LocalModelCategory.language),
                ),
                _ModelCategoryLink(
                  key: const Key('model-category-speech'),
                  title: context.l10n.speechModels,
                  subtitle: _categorySubtitle(LocalModelCategory.speech),
                  onTap: () => _openCategory(LocalModelCategory.speech),
                ),
                _ModelCategoryLink(
                  key: const Key('model-category-vision'),
                  title: context.l10n.visionModels,
                  subtitle: _categorySubtitle(LocalModelCategory.vision),
                  onTap: () => _openCategory(LocalModelCategory.vision),
                ),
                _ModelCategoryLink(
                  key: const Key('model-download-settings-link'),
                  title: context.l10n.modelDownloadsAndStorage,
                  subtitle: context.l10n.modelDownloadsAndStorageDescription,
                  onTap: _openDownloadSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategory(BuildContext context, LocalModelCategory category) {
    final models = _manager.models
        .where((model) => model.category == category)
        .toList();
    final showInstalled = _showInstalledModels;
    final transferModels = _sortedTransferModels(models);
    final transferModelIds = transferModels.map((model) => model.id).toSet();
    final visible = models.where((model) {
      final installed =
          model.availability == LocalModelAvailability.builtIn ||
          _manager.installationOf(model.id).installed;
      return !transferModelIds.contains(model.id) &&
          (showInstalled ? installed : !installed);
    }).toList();
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      appBar: AppBar(
        title: Text(_categoryTitle(category)),
        actions: category == LocalModelCategory.language
            ? [
                Tooltip(
                  message: context.l10n.discoverMnnModels,
                  child: TextButton(
                    key: const Key('discover-taobao-mnn-models'),
                    onPressed: _openMnnCatalog,
                    child: Text(context.l10n.more),
                  ),
                ),
                const SizedBox(width: 6),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: Key('model-category-list-${category.name}'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              _categoryDescription(category),
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (category == LocalModelCategory.speech) ...[
              const SizedBox(height: 16),
              InsetSettingsSection(
                children: [
                  _ModelCategoryLink(
                    title: context.l10n.liveDictationSettings,
                    subtitle: context.l10n.liveDictationSettingsDescription,
                    onTap: _openDictationSettings,
                  ),
                ],
              ),
            ],
            if (transferModels.isNotEmpty) ...[
              const SizedBox(height: 20),
              _TransferSectionHeader(
                count: transferModels.length,
                subtitle: _transferTaskSummary(transferModels),
              ),
              const SizedBox(height: 8),
              InsetSettingsGroup(
                children: [
                  for (final model in transferModels) _modelRow(model),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                key: const Key('model-installation-filter'),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(context.l10n.installedModels),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(context.l10n.availableModels),
                  ),
                ],
                selected: {showInstalled},
                onSelectionChanged: (value) => setState(() {
                  _filterChosenByUser = true;
                  _showInstalledModels = value.first;
                }),
              ),
            ),
            const SizedBox(height: 20),
            if (transferModels.isNotEmpty) ...[
              _sectionTitle(context.l10n.otherModels),
              const SizedBox(height: 8),
            ],
            if (visible.isEmpty)
              InsetSettingsGroup(
                children: [
                  _ModelEmptyState(
                    message: showInstalled
                        ? context.l10n.noInstalledModelsInCategory
                        : context.l10n.noAvailableModelsInCategory,
                  ),
                ],
              )
            else
              InsetSettingsGroup(
                children: [for (final model in visible) _modelRow(model)],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferTasks(BuildContext context) {
    final models = _sortedTransferModels(_manager.models);
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      appBar: AppBar(title: Text(context.l10n.modelTransfers)),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('model-transfer-list'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              context.l10n.modelTransfersDescription,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            if (models.isEmpty)
              InsetSettingsGroup(
                children: [
                  _ModelEmptyState(message: context.l10n.noModelTransfers),
                ],
              )
            else
              InsetSettingsGroup(
                children: [for (final model in models) _modelRow(model)],
              ),
          ],
        ),
      ),
    );
  }

  Widget _modelRow(LocalModelDefinition model) => _ModelRow(
    definition: model,
    installation: _manager.installationOf(model.id),
    transfer: _manager.transferOf(model.id),
    selectedForLiveDictation: model.id == _manager.selectedLiveDictationModelId,
    selectedForAssistant: model.id == _manager.selectedAssistantModelId,
    onDownload: () => _confirmDownload(model),
    onImport: () => _manager.import(model.id),
    onCancel: () => _manager.cancel(model.id),
    onDiscardPartial: () => _confirmDiscardPartial(model),
    onRemove: () => _confirmRemove(model),
    onSelect: () => model.category == LocalModelCategory.language
        ? _selectForAssistant(model)
        : _selectForLiveDictation(model),
    onDetails: () => _showDetails(model),
  );

  List<LocalModelDefinition> _sortedTransferModels(
    Iterable<LocalModelDefinition> source,
  ) {
    final result = source.where(_isTransferModel).toList();
    result.sort((left, right) {
      final rank = _transferRank(left).compareTo(_transferRank(right));
      if (rank != 0) return rank;
      return localizedModelName(
        context.l10n,
        left,
      ).compareTo(localizedModelName(context.l10n, right));
    });
    return result;
  }

  bool _isTransferModel(LocalModelDefinition model) {
    final installation = _manager.installationOf(model.id);
    if (installation.installed) return false;
    final transfer = _manager.transferOf(model.id);
    return installation.partialSizeBytes > 0 ||
        transfer?.isRunning == true ||
        transfer?.status == ModelTransferStatus.failed ||
        transfer?.status == ModelTransferStatus.canceled;
  }

  int _transferRank(LocalModelDefinition model) {
    final status = _manager.transferOf(model.id)?.status;
    return switch (status) {
      ModelTransferStatus.downloading || ModelTransferStatus.importing => 0,
      ModelTransferStatus.connecting => 1,
      ModelTransferStatus.waitingToInstall ||
      ModelTransferStatus.verifying ||
      ModelTransferStatus.canceling => 2,
      ModelTransferStatus.failed => 3,
      ModelTransferStatus.canceled => 4,
      _ => 5,
    };
  }

  String _transferTaskSummary(List<LocalModelDefinition> models) {
    final active = models.where((model) {
      return _manager.transferOf(model.id)?.isRunning == true;
    }).length;
    return context.l10n.modelTransferSummary(active, models.length - active);
  }

  Widget _buildDictationSettings(BuildContext context) {
    final selected = _manager.modelOf(_manager.selectedLiveDictationModelId);
    final installation = _manager.installationOf(selected.id);
    return Scaffold(
      backgroundColor: context.appColors.canvas,
      appBar: AppBar(title: Text(context.l10n.liveDictationSettings)),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('model-dictation-settings-list'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            InsetSettingsGroup(
              children: [
                if (installation.installed)
                  _ActiveModelRow(
                    model: ActiveLocalModel(
                      definition: selected,
                      installation: installation,
                      usages: const {LocalModelUsage.liveDictation},
                    ),
                    onTap: () => _openCategory(
                      LocalModelCategory.speech,
                      focusModelId: selected.id,
                    ),
                    onDetails: () => _showDetails(selected),
                  ),
                _HotwordsRow(preferences: _preferences, onTap: _editHotwords),
                _TwoPassRow(
                  enabled: _preferences.twoPassEnabled,
                  onChanged: _setTwoPassEnabled,
                ),
                _NoiseSuppressionRow(
                  enabled: _preferences.noiseSuppressionEnabled,
                  modelInstalled: _manager
                      .installationOf(LocalModelManager.speechDenoiserId)
                      .installed,
                  onChanged: _setNoiseSuppressionEnabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSettings(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.canvas,
    appBar: AppBar(title: Text(context.l10n.modelDownloadsAndStorage)),
    body: SafeArea(
      top: false,
      child: ListView(
        key: const Key('model-download-settings-list'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _ModelSummary(
            installedCount: _manager.installedCount,
            installedSizeBytes: _manager.installedSizeBytes,
          ),
          const SizedBox(height: 8),
          InsetSettingsGroup(
            children: [
              _DownloadSourceRow(
                preference: _sourcePolicy.preference,
                automaticPrefersMainland: _sourcePolicy.regionPrefersMainland,
                lastUsedSourceLabel: _sourcePolicy.lastUsedSourceLabel,
                onTap: _chooseDownloadSource,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.modelPrivacyHint,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _categoryTitle(LocalModelCategory category) => switch (category) {
    LocalModelCategory.language => context.l10n.languageModels,
    LocalModelCategory.speech => context.l10n.speechModels,
    LocalModelCategory.vision => context.l10n.visionModels,
  };

  String _categoryDescription(LocalModelCategory category) =>
      switch (category) {
        LocalModelCategory.language => context.l10n.languageModelsDescription,
        LocalModelCategory.speech => context.l10n.speechModelsDescription,
        LocalModelCategory.vision => context.l10n.visionModelsDescription,
      };

  String _categorySubtitle(LocalModelCategory category) {
    final installed = _manager.models.where((model) {
      return model.category == category &&
          (model.availability == LocalModelAvailability.builtIn ||
              _manager.installationOf(model.id).installed);
    }).length;
    return context.l10n.installedModelsCount(installed);
  }

  Widget _sectionTitle(String title) => Semantics(
    header: true,
    child: Text(
      title,
      style: TextStyle(
        color: context.appColors.muted,
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Future<void> _openCategory(
    LocalModelCategory category, {
    String? focusModelId,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ModelManagementPage(category: category, focusModelId: focusModelId),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

  Future<void> _openDictationSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showDictationSettings: true),
      ),
    );
    if (mounted) {
      await _loadDictationPreferences();
      await _manager.initialize(force: true);
    }
  }

  Future<void> _openDownloadSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showDownloadSettings: true),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

  Future<void> _openTransferTasks() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showTransferTasks: true),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

  Future<void> _openMnnCatalog() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TaobaoMnnCatalogPage()),
    );
    if (added == true && mounted) {
      await _manager.initialize(force: true);
    }
  }

  Future<void> _chooseDownloadSource() async {
    final selected =
        await AppOverlay.bottomSheet<ModelDownloadSourcePreference>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.modelDownloadSource,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.downloadSourceSecurityDescription,
                  style: TextStyle(
                    color: context.appColors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                InsetSettingsGroup(
                  children: [
                    for (final preference
                        in ModelDownloadSourcePreference.values)
                      InsetSettingsRow(
                        rowKey: Key('download-source-${preference.name}'),
                        title: _downloadSourceTitle(context.l10n, preference),
                        subtitle: _downloadSourceDescription(
                          context.l10n,
                          preference,
                        ),
                        selected: _sourcePolicy.preference == preference,
                        showDisclosure: false,
                        onTap: () => Navigator.pop(context, preference),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
    if (selected == null || !mounted) return;
    try {
      await _sourcePolicy.setPreference(selected);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.downloadSourceSaveFailed);
      }
    }
  }

  Future<void> _confirmDownload(LocalModelDefinition model) async {
    final installation = _manager.installationOf(model.id);
    final remaining = (model.downloadSizeBytes - installation.partialSizeBytes)
        .clamp(0, model.downloadSizeBytes);
    final l10n = context.l10n;
    final description = [
      l10n.modelDownloadDescription(
        localizedModelName(l10n, model),
        _formatBytes(remaining),
      ),
      if (model.recommendedMemoryBytes > 0)
        l10n.modelMemoryRecommendation(
          _formatMemory(model.recommendedMemoryBytes),
        ),
      if (model.task == LocalModelTask.textToSpeech)
        l10n.ttsStorageRecommendation,
    ].join('\n\n');
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          installation.partialSizeBytes > 0
              ? context.l10n.continueModelDownloadQuestion
              : context.l10n.downloadModelQuestion,
        ),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.startDownload),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_manager.download(model.id));
  }

  Future<void> _confirmRemove(LocalModelDefinition model) async {
    final size = _manager.installationOf(model.id).installedSizeBytes;
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.removeModelQuestion(
            localizedModelName(context.l10n, model),
          ),
        ),
        content: Text(context.l10n.removeModelDescription(_formatBytes(size))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.removeModel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.remove(model.id);
      await _loadDictationPreferences();
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _confirmDiscardPartial(LocalModelDefinition model) async {
    final size = _manager.installationOf(model.id).partialSizeBytes;
    if (size <= 0) return;
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.discardPartialDownloadQuestion(
            localizedModelName(context.l10n, model),
          ),
        ),
        content: Text(
          context.l10n.discardPartialDownloadDescription(_formatBytes(size)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.discardPartialDownload),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.remove(model.id);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.discardPartialDownloadFailed);
      }
    }
  }

  Future<void> _selectForLiveDictation(LocalModelDefinition model) async {
    if (model.task != LocalModelTask.liveDictation) return;
    try {
      await _manager.selectForLiveDictation(model.id);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _selectForAssistant(LocalModelDefinition model) async {
    if (model.category != LocalModelCategory.language) return;
    try {
      await _manager.selectForAssistant(model.id);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _editHotwords() async {
    final result = await AppOverlay.bottomSheet<RealtimeDictationPreferences>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _HotwordsSheet(initial: _preferences, service: _dictationPreferences),
    );
    if (result == null || !mounted) return;
    setState(() => _preferences = result);
  }

  Future<void> _setTwoPassEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: enabled,
        noiseSuppressionEnabled: _preferences.noiseSuppressionEnabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.settingsSaveFailed);
      }
    }
  }

  Future<void> _setNoiseSuppressionEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: _preferences.twoPassEnabled,
        noiseSuppressionEnabled: enabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.settingsSaveFailed);
      }
    }
  }

  void _showDetails(LocalModelDefinition model) {
    AppOverlay.bottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('model-details-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizedModelName(context.l10n, model),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                localizedModelDescription(context.l10n, model),
                style: const TextStyle(height: 1.55),
              ),
              const SizedBox(height: 18),
              _DetailRow(
                context.l10n.purpose,
                localizedModelSummary(context.l10n, model),
              ),
              _DetailRow(context.l10n.engine, model.engine),
              if (model.languages.isNotEmpty)
                _DetailRow(
                  context.l10n.supportedLanguages,
                  localizedModelLanguages(context.l10n, model),
                ),
              if (model.version.isNotEmpty)
                _DetailRow(
                  context.l10n.version,
                  localizedModelVersion(context.l10n, model),
                ),
              if (model.recommendedMemoryBytes > 0)
                _DetailRow(
                  context.l10n.recommendedMemory,
                  context.l10n.memoryAndAbove(
                    _formatMemory(model.recommendedMemoryBytes),
                  ),
                ),
              if (model.source.isNotEmpty)
                _DetailRow(
                  context.l10n.source,
                  localizedModelSource(context.l10n, model),
                ),
              if (model.license.isNotEmpty)
                _DetailRow(context.l10n.license, model.license),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotwordsSheet extends StatefulWidget {
  final RealtimeDictationPreferences initial;
  final RealtimeDictationPreferencesService service;

  const _HotwordsSheet({required this.initial, required this.service});

  @override
  State<_HotwordsSheet> createState() => _HotwordsSheetState();
}

class _HotwordsSheetState extends State<_HotwordsSheet> {
  late final TextEditingController _controller;
  late double _score;
  String? _validationMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial.hotwords.join('\n'),
    );
    _score = widget.initial.hotwordsScore;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    try {
      final saved = await widget.service.save(
        hotwordsText: _controller.text,
        hotwordsScore: _score,
        twoPassEnabled: widget.initial.twoPassEnabled,
        noiseSuppressionEnabled: widget.initial.noiseSuppressionEnabled,
      );
      if (mounted) Navigator.pop(context, saved);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = error.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = context.l10n.saveFailedStorage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        MediaQuery.sizeOf(context).height - keyboardInset - 24;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.liveDictationHotwords,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.hotwordsDescription,
                  style: TextStyle(
                    color: context.appColors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InsetSettingsGroup(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.hotwordsList,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    key: const Key(
                                      'live-dictation-hotwords-field',
                                    ),
                                    controller: _controller,
                                    contextMenuBuilder:
                                        buildAppEditableTextContextMenu,
                                    minLines: 4,
                                    maxLines: 8,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: context.l10n.hotwordsHint,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_validationMessage != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _validationMessage!,
                              style: TextStyle(
                                color: context.appColors.danger,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: Text(context.l10n.boostStrength)),
                            Text(
                              _score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          key: const Key('live-dictation-hotwords-score'),
                          value: _score,
                          min: RealtimeDictationPreferencesService
                              .minHotwordsScore,
                          max: RealtimeDictationPreferencesService
                              .maxHotwordsScore,
                          divisions: 8,
                          label: _score.toStringAsFixed(1),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _score = value),
                        ),
                        Text(
                          context.l10n.hotwordsStrengthWarning,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('save-live-dictation-hotwords'),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? context.l10n.saving : context.l10n.save,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoPassRow extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _TwoPassRow({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) => _ModelSettingSwitch(
    switchKey: const Key('live-dictation-two-pass-switch'),
    title: context.l10n.finalRefinement,
    subtitle: context.l10n.finalRefinementDescription,
    value: enabled,
    onChanged: onChanged,
  );
}

class _NoiseSuppressionRow extends StatelessWidget {
  final bool enabled;
  final bool modelInstalled;
  final ValueChanged<bool> onChanged;

  const _NoiseSuppressionRow({
    required this.enabled,
    required this.modelInstalled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => _ModelSettingSwitch(
    switchKey: const Key('live-dictation-noise-suppression-switch'),
    title: context.l10n.liveNoiseSuppression,
    subtitle: modelInstalled
        ? context.l10n.liveNoiseSuppressionDescription
        : context.l10n.installDenoiserFirst,
    value: modelInstalled && enabled,
    onChanged: modelInstalled ? onChanged : null,
  );
}

class _ModelSettingSwitch extends StatelessWidget {
  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ModelSettingSwitch({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(key: switchKey, value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _HotwordsRow extends StatelessWidget {
  final RealtimeDictationPreferences preferences;
  final VoidCallback onTap;

  const _HotwordsRow({required this.preferences, required this.onTap});

  @override
  Widget build(BuildContext context) => _ModelCategoryLink(
    key: const Key('live-dictation-hotwords-card'),
    title: context.l10n.hotwordBoost,
    subtitle: preferences.hotwordsEnabled
        ? context.l10n.hotwordSummary(
            preferences.hotwords.length,
            preferences.hotwordsScore.toStringAsFixed(1),
          )
        : context.l10n.hotwordBoostDescription,
    onTap: onTap,
  );
}

class _DownloadSourceRow extends StatelessWidget {
  final ModelDownloadSourcePreference preference;
  final bool automaticPrefersMainland;
  final String? lastUsedSourceLabel;
  final VoidCallback onTap;

  const _DownloadSourceRow({
    required this.preference,
    required this.automaticPrefersMainland,
    required this.lastUsedSourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effective = preference == ModelDownloadSourcePreference.automatic
        ? context.l10n.downloadSourceEffective(
            automaticPrefersMainland
                ? context.l10n.mainlandMirror
                : context.l10n.officialSource,
          )
        : _downloadSourceTitle(context.l10n, preference);
    final lastUsed = lastUsedSourceLabel;
    return _ModelCategoryLink(
      key: const Key('model-download-source-setting'),
      title: context.l10n.modelDownloadSource,
      subtitle: lastUsed == null
          ? effective
          : '$effective · ${context.l10n.lastUsedSource(lastUsed)}',
      onTap: onTap,
    );
  }
}

class _ModelEmptyState extends StatelessWidget {
  final String message;

  const _ModelEmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    child: Text(
      message,
      style: TextStyle(
        color: context.appColors.muted,
        fontSize: 13,
        height: 1.4,
      ),
    ),
  );
}

class _ModelCategoryLink extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModelCategoryLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppIcon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.appColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TransferSectionHeader extends StatelessWidget {
  final int count;
  final String subtitle;

  const _TransferSectionHeader({required this.count, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          context.l10n.modelTransferSectionCount(count),
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(
          color: context.appColors.muted,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    ],
  );
}

class _ActiveModelRow extends StatelessWidget {
  final ActiveLocalModel model;
  final VoidCallback onTap;
  final VoidCallback? onDetails;

  const _ActiveModelRow({
    required this.model,
    required this.onTap,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final definition = model.definition;
    final metadata = [
      for (final usage in model.usages) _usageLabel(context.l10n, usage),
      definition.engine,
      if (model.installation.installedSizeBytes > 0)
        _formatBytes(model.installation.installedSizeBytes),
      if (definition.availability == LocalModelAvailability.builtIn)
        context.l10n.bundledWithApp,
    ].join(' · ');
    return Material(
      key: Key('active-model-${definition.id}'),
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizedModelName(context.l10n, definition),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata,
                      key: Key('active-model-metadata-${definition.id}'),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDetails != null) ...[
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 48,
                  child: TextButton(
                    key: Key('active-model-details-${definition.id}'),
                    onPressed: onDetails,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size.square(48),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(context.l10n.modelDetails),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _usageLabel(AppLocalizations l10n, LocalModelUsage usage) =>
    switch (usage) {
      LocalModelUsage.assistant => l10n.localAssistantUsage,
      LocalModelUsage.liveDictation => l10n.liveDictationUsage,
      LocalModelUsage.audioTranscription => l10n.audioTranscriptionUsage,
      LocalModelUsage.voiceActivityDetection => l10n.voiceActivityUsage,
      LocalModelUsage.speechEnhancement => l10n.speechEnhancementUsage,
      LocalModelUsage.textRecognition => l10n.textRecognitionUsage,
    };

String _downloadSourceTitle(
  AppLocalizations l10n,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic => l10n.downloadSourceAutomatic,
  ModelDownloadSourcePreference.officialFirst =>
    l10n.downloadSourceOfficialFirst,
  ModelDownloadSourcePreference.mainlandFirst =>
    l10n.downloadSourceMainlandFirst,
};

String _downloadSourceDescription(
  AppLocalizations l10n,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic =>
    l10n.downloadSourceAutomaticDescription,
  ModelDownloadSourcePreference.officialFirst =>
    l10n.downloadSourceOfficialDescription,
  ModelDownloadSourcePreference.mainlandFirst =>
    l10n.downloadSourceMainlandDescription,
};

String _localizedDownloadSourceLabel(AppLocalizations l10n, String label) =>
    switch (label) {
      '第三方国内镜像' => l10n.thirdPartyMainlandMirror,
      'GitHub 官方源' => l10n.githubOfficialSource,
      'ModelScope 魔搭' => l10n.modelScopeSource,
      _ => label,
    };

class _ModelSummary extends StatelessWidget {
  final int installedCount;
  final int installedSizeBytes;
  final bool activeOnly;
  const _ModelSummary({
    required this.installedCount,
    required this.installedSizeBytes,
    this.activeOnly = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('local-model-summary'),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          activeOnly
              ? context.l10n.activeModelCount(installedCount)
              : context.l10n.installedModelCount(installedCount),
          style: const TextStyle(
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          activeOnly
              ? context.l10n.activeModelsUsage(_formatBytes(installedSizeBytes))
              : context.l10n.optionalModelsUsage(
                  _formatBytes(installedSizeBytes),
                ),
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _ModelRow extends StatelessWidget {
  final LocalModelDefinition definition;
  final LocalModelInstallation installation;
  final ModelTransferState? transfer;
  final bool selectedForLiveDictation;
  final bool selectedForAssistant;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onCancel;
  final VoidCallback onDiscardPartial;
  final VoidCallback onRemove;
  final VoidCallback onSelect;
  final VoidCallback onDetails;
  const _ModelRow({
    required this.definition,
    required this.installation,
    required this.transfer,
    this.selectedForLiveDictation = false,
    this.selectedForAssistant = false,
    required this.onDownload,
    required this.onImport,
    required this.onCancel,
    required this.onDiscardPartial,
    required this.onRemove,
    required this.onSelect,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final running = transfer?.isRunning == true;
    final metadata = [
      if (definition.recommended) context.l10n.recommended,
      if (selectedForLiveDictation &&
          !installation.installed &&
          definition.task == LocalModelTask.liveDictation)
        context.l10n.currentDictation,
      definition.engine,
      if (definition.downloadSizeBytes > 0)
        _formatBytes(definition.downloadSizeBytes),
      if (definition.recommendedMemoryBytes > 0)
        context.l10n.memoryBadge(
          _formatMemory(definition.recommendedMemoryBytes),
        ),
      if (definition.languages.isNotEmpty)
        localizedModelLanguages(context.l10n, definition),
    ].join(' · ');
    return Material(
      key: Key('model-row-${definition.id}'),
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizedModelName(context.l10n, definition),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localizedModelSummary(context.l10n, definition),
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 48,
                    child: TextButton(
                      key: Key('model-details-${definition.id}'),
                      onPressed: onDetails,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(48),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(context.l10n.modelDetails),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                metadata,
                key: Key('model-metadata-${definition.id}'),
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            if (running) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: transfer!.progress <= 0 ? null : transfer!.progress,
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _transferStatus(context, transfer!),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _actions(context),
              ),
            ],
            if (transfer?.status == ModelTransferStatus.failed) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  transfer?.errorMessage ?? context.l10n.modelDownloadFailed,
                  style: TextStyle(
                    color: context.appColors.coral,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _transferStatus(BuildContext context, ModelTransferState state) {
    final style = TextStyle(
      color: context.appColors.muted,
      fontSize: 12,
      height: 1.4,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final transferring =
        state.status == ModelTransferStatus.downloading ||
        state.status == ModelTransferStatus.importing;
    final preparing =
        state.status == ModelTransferStatus.importing && state.totalBytes <= 0;
    final amount =
        '${_formatBytes(state.transferredBytes)} / ${_formatBytes(state.totalBytes)}';
    final eta = state.estimatedRemaining;
    final etaText = context.l10n.estimatedRemainingCompact(
      eta == null ? '--:--:--' : _formatDurationClock(eta),
    );
    final source = state.status == ModelTransferStatus.importing
        ? context.l10n.localModelImportTransfer
        : state.sourceLabel.isEmpty
        ? context.l10n.modelDownloadTransfer
        : _localizedDownloadSourceLabel(context.l10n, state.sourceLabel);
    final speed = state.bytesPerSecond <= 0
        ? context.l10n.speedTesting
        : '${_formatBytes(state.bytesPerSecond.round())}/s';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (transferring && !preparing)
          Text('$amount · $etaText', style: style),
        Row(
          children: [
            Expanded(
              child: Text(
                preparing
                    ? context.l10n.preparingLocalModelImport
                    : transferring
                    ? '$source · $speed'
                    : _transferDescription(context, state),
                style: style,
              ),
            ),
            const SizedBox(width: 8),
            _transferAction(context, state),
          ],
        ),
      ],
    );
  }

  Widget _transferAction(BuildContext context, ModelTransferState state) {
    if (state.status == ModelTransferStatus.verifying ||
        state.status == ModelTransferStatus.canceling ||
        !state.cancelable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          context.l10n.pleaseWait,
          style: TextStyle(color: context.appColors.muted, fontSize: 12),
        ),
      );
    }
    return TextButton(
      key: Key('model-pause-${definition.id}'),
      onPressed: onCancel,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(64, 48),
      ),
      child: Text(context.l10n.pauseDownload),
    );
  }

  Widget _actions(BuildContext context) {
    if (definition.availability == LocalModelAvailability.builtIn) {
      return _ModelStatus(label: context.l10n.bundledWithApp);
    }
    if (definition.availability == LocalModelAvailability.planned) {
      return _ModelStatus(label: context.l10n.comingSoon);
    }
    if (installation.installed) {
      final currentAssistant =
          selectedForAssistant &&
          definition.category == LocalModelCategory.language;
      final currentDictation =
          selectedForLiveDictation &&
          definition.task == LocalModelTask.liveDictation;
      return Row(
        children: [
          Expanded(
            child: _ModelStatus(
              label: currentAssistant
                  ? context.l10n.currentAssistant
                  : currentDictation
                  ? context.l10n.currentDictation
                  : context.l10n.installed,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                if ((definition.task == LocalModelTask.liveDictation &&
                        !selectedForLiveDictation) ||
                    (definition.category == LocalModelCategory.language &&
                        !selectedForAssistant))
                  TextButton.icon(
                    key: Key('model-select-${definition.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: onSelect,
                    icon: const AppIcon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(
                      definition.category == LocalModelCategory.language
                          ? context.l10n.useForAssistant
                          : context.l10n.useForDictation,
                    ),
                  ),
                TextButton.icon(
                  key: Key('model-remove-${definition.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onRemove,
                  icon: const AppIcon(Icons.delete_outline_rounded, size: 19),
                  label: Text(context.l10n.remove),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final hasPartial = installation.partialSizeBytes > 0;
    final failed = transfer?.status == ModelTransferStatus.failed;
    final canContinue =
        hasPartial || transfer?.status == ModelTransferStatus.canceled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final importButton = TextButton.icon(
          key: Key('model-import-${definition.id}'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onImport,
          icon: const AppIcon(Icons.folder_open_rounded, size: 19),
          label: Text(context.l10n.importFromFile),
        );
        final buttonKey = Key('model-download-${definition.id}');
        final Widget downloadButton;
        if (failed) {
          downloadButton = OutlinedButton.icon(
            key: buttonKey,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(112, 48),
              foregroundColor: context.appColors.coral,
              side: BorderSide(color: context.appColors.coral),
            ),
            onPressed: onDownload,
            icon: const AppIcon(Icons.refresh_rounded, size: 19),
            label: Text(context.l10n.retry),
          );
        } else if (canContinue) {
          downloadButton = FilledButton.icon(
            key: buttonKey,
            style: FilledButton.styleFrom(minimumSize: const Size(112, 48)),
            onPressed: onDownload,
            icon: const AppIcon(Icons.play_arrow_rounded, size: 20),
            label: Text(context.l10n.continueDownload),
          );
        } else {
          downloadButton = FilledButton.tonalIcon(
            key: buttonKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size(112, 48),
              backgroundColor: context.appColors.softGreen,
              foregroundColor: context.appColors.moss,
            ),
            onPressed: onDownload,
            icon: const AppIcon(Icons.download_rounded, size: 19),
            label: Text(context.l10n.download),
          );
        }
        final actionRow =
            constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 17
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: importButton),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: downloadButton,
                  ),
                ],
              )
            : Row(
                children: [
                  importButton,
                  const Spacer(),
                  const SizedBox(width: 8),
                  downloadButton,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPartial) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.downloadedResumable(
                        _formatBytes(installation.partialSizeBytes),
                      ),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  AppAnchoredMenuButton<_PartialDownloadAction>(
                    key: Key('model-partial-menu-${definition.id}'),
                    tooltip: context.l10n.moreActions,
                    icon: const AppIcon(Icons.more_horiz_rounded, size: 20),
                    onSelected: (_) => onDiscardPartial(),
                    actions: [
                      AppMenuAction(
                        value: _PartialDownloadAction.discard,
                        icon: Icons.delete_sweep_outlined,
                        label: context.l10n.discardPartialDownload,
                        destructive: true,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            actionRow,
          ],
        );
      },
    );
  }

  String _transferDescription(BuildContext context, ModelTransferState state) {
    if (state.status == ModelTransferStatus.canceling) {
      return context.l10n.cancelingDownload;
    }
    if (state.status == ModelTransferStatus.connecting) {
      final source = state.sourceLabel.isEmpty
          ? ''
          : ' · ${_localizedDownloadSourceLabel(context.l10n, state.sourceLabel)}';
      return context.l10n.connectingDownloadSource(source);
    }
    if (state.status == ModelTransferStatus.verifying) {
      return context.l10n.downloadedInstalling(
        _formatBytes(state.transferredBytes),
      );
    }
    if (state.status == ModelTransferStatus.waitingToInstall) {
      return context.l10n.downloadedWaitingInstall(
        _formatBytes(state.transferredBytes),
      );
    }
    return '';
  }
}

enum _PartialDownloadAction { discard }

class _ModelStatus extends StatelessWidget {
  final String label;
  const _ModelStatus({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.appColors.muted,
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 13,
            height: 1.4,
          ),
        );
        final valueText = Text(
          value,
          style: const TextStyle(fontSize: 14, height: 1.4),
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, const SizedBox(height: 4), valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: labelText),
            const SizedBox(width: 12),
            Expanded(child: valueText),
          ],
        );
      },
    ),
  );
}

String _formatBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : bytes < 1073741824
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1073741824).toStringAsFixed(1)} GB';

String _formatMemory(int bytes) => '${(bytes / 1073741824).round()} GB';

String _formatDurationClock(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

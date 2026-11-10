import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../debug/debug_console_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/local_chat.dart';
import '../models/note.dart';
import '../providers/app_lock_controller.dart';
import '../providers/app_locale_controller.dart';
import '../providers/app_theme_controller.dart';
import '../providers/note_library_controller.dart';
import '../providers/editorial_material_controller.dart';
import '../providers/private_notes_controller.dart';
import '../services/device_authentication_service.dart';
import '../widgets/private_notes_auth.dart';
import '../widgets/incoming_share_coordinator.dart';
import '../services/app_build_metadata.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/app_update_service.dart';
import '../services/note_database_service.dart';
import '../services/note_reminder_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_update_coordinator.dart';
import '../widgets/sunny_growth_decoration.dart';
import 'app_lock_settings_page.dart';
import 'backup_export_page.dart';
import 'backup_restore_page.dart';
import 'cloud_sync_page.dart';
import 'language_settings_page.dart';
import 'theme_settings_page.dart';
import 'local_chat_page.dart';
import 'model_management_page.dart';
import 'agent_settings_page.dart';
import 'agent_tasks_page.dart';
import 'note_calendar_page.dart';
import 'note_library_page.dart';
import 'note_quill_editor_page.dart';
import 'note_tag_groups_page.dart';
import 'private_notes_page.dart';
import 'file_manager_page.dart';
import '../widgets/app_icon.dart';

typedef NoteHomeDataSizeLoader = Future<int> Function();
typedef NoteHomeNoteLoader = Future<Note?> Function(NoteId id);
typedef NoteHomeAssistantBuilder =
    Widget Function(BuildContext context, LocalChatNoteOpener onOpenNote);
typedef NoteHomeUpdateChecker =
    Future<AppUpdateCheckResult> Function(BuildContext context);

/// Primary application shell for the clean Delta note system.
///
/// It owns no compatibility provider or secondary note database. All note
/// entry points converge on [NoteQuillEditorPage].
final class QuillHomePage extends StatefulWidget {
  const QuillHomePage({
    this.controller,
    this.editorBuilder,
    this.assistantBuilder,
    this.noteLoader,
    this.dataSizeLoader,
    this.updateSupported,
    this.updateChecker,
    this.privateAuthenticator,
    this.privateControllerFactory,
    this.reminderRequests,
    this.privateNoteChecker,
    super.key,
  });

  final NoteLibraryController? controller;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteHomeAssistantBuilder? assistantBuilder;
  final NoteHomeNoteLoader? noteLoader;
  final NoteHomeDataSizeLoader? dataSizeLoader;
  final bool? updateSupported;
  final NoteHomeUpdateChecker? updateChecker;
  final DeviceAuthenticator? privateAuthenticator;
  final NoteLibraryController Function()? privateControllerFactory;
  final ValueNotifier<NoteId?>? reminderRequests;
  final Future<bool> Function(NoteId)? privateNoteChecker;

  @override
  State<QuillHomePage> createState() => _QuillHomePageState();
}

final class _QuillHomePageState extends State<QuillHomePage> {
  late final NoteLibraryController _controller;
  late final bool _ownsController;
  late final EditorialMaterialController _materials =
      EditorialMaterialController();
  NoteLibraryFocusRequest? _libraryFocusRequest;
  bool _openingPrivateNotes = false;
  bool _openingReminder = false;
  bool _reminderFrameScheduled = false;
  late final ValueNotifier<NoteId?> _reminderRequests;
  AppLockController? _appLock;
  final _privateReminderRequests = ValueNotifier<NoteId?>(null);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
    _reminderRequests =
        widget.reminderRequests ?? NoteReminderService.instance.pendingNote;
    _reminderRequests.addListener(_queueReminder);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lock = context.read<AppLockController?>();
    if (!identical(_appLock, lock)) {
      _appLock?.removeListener(_queueReminder);
      _appLock = lock;
      _appLock?.addListener(_queueReminder);
    }
    _queueReminder();
  }

  bool get _canOpenReminder =>
      _appLock == null ||
      (_appLock!.initialized && !_appLock!.locked && !_appLock!.obscured);

  void _queueReminder() {
    if (!mounted ||
        _reminderFrameScheduled ||
        _openingReminder ||
        _reminderRequests.value == null ||
        !_canOpenReminder) {
      return;
    }
    _reminderFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reminderFrameScheduled = false;
      if (mounted) unawaited(_openReminder());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openReminder() async {
    final id = _reminderRequests.value;
    if (id == null || _openingReminder || !_canOpenReminder) return;
    _openingReminder = true;
    _reminderRequests.value = null;
    try {
      final loader =
          widget.noteLoader ??
          (id) async => (await NoteDatabaseService.instance.repository).get(id);
      final note = await loader(id);
      if (!mounted) return;
      if (!_canOpenReminder) {
        _reminderRequests.value = id;
        return;
      }
      if (note != null && !note.isPrivate) {
        unawaited(_openEditor(note));
      } else {
        final private =
            note?.isPrivate == true ||
            await (widget.privateNoteChecker?.call(id) ??
                NoteDatabaseService.instance.repository.then(
                  (repository) => repository.isPrivateNote(id),
                ));
        if (!mounted) return;
        if (!_canOpenReminder) {
          _reminderRequests.value = id;
          return;
        }
        if (private) {
          unawaited(_openPrivateNotes(initialNoteId: id));
        } else {
          AppFeedback.error(context, context.l10n.toolActionTargetMissing);
        }
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.toolActionTargetMissing);
      }
    } finally {
      _openingReminder = false;
      _queueReminder();
    }
  }

  Future<NoteEditorRouteResult?> _openEditor([Note? note]) async {
    _dismissRouteFocus();
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    final rawResult = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (!mounted) return null;
    _dismissRouteFocus();
    final result = switch (rawResult) {
      NoteEditorRouteResult value => value,
      Note value => NoteEditorRouteResult(note: value, completed: false),
      _ => null,
    };
    if (result?.note case final savedNote?) {
      setState(() {
        _libraryFocusRequest = NoteLibraryFocusRequest(savedNote.id);
      });
      if (!_materials.loading) await _materials.refresh();
    } else {
      await _refreshAfterRestore();
    }
    return result;
  }

  Future<void> _openAssistant() async {
    _dismissRouteFocus();
    final builder =
        widget.assistantBuilder ??
        (context, onOpenNote) => LocalChatPage(onOpenNote: onOpenNote);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => builder(context, _openAssistantSource),
      ),
    );
    if (!mounted) return;
    _dismissRouteFocus();
    await _refreshAfterRestore();
  }

  Future<void> _openAssistantSource(LocalChatNoteContext source) async {
    final loader =
        widget.noteLoader ??
        (id) async => (await NoteDatabaseService.instance.repository).get(id);
    final note = await loader(source.noteId);
    if (!mounted) return;
    if (note == null || note.isPrivate) {
      AppFeedback.error(context, context.l10n.toolActionTargetMissing);
      return;
    }
    final result = await _openEditor(note);
    if (result?.completed == true &&
        mounted &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _refreshAfterRestore() async {
    await _controller.refresh();
    if (!_materials.loading) await _materials.refresh();
  }

  Future<void> _openPrivateNotes({NoteId? initialNoteId}) async {
    if (_openingPrivateNotes) {
      if (initialNoteId != null) _privateReminderRequests.value = initialNoteId;
      return;
    }
    _openingPrivateNotes = true;
    _dismissRouteFocus();
    final session = PrivateNotesController(
      authenticator: widget.privateAuthenticator,
    );
    try {
      final result = await session.unlock(
        prompt: privateNotesPrompt(context.l10n),
      );
      if (!mounted) return;
      if (!result.authenticated) {
        AppFeedback.show(
          context,
          privateNotesAuthMessage(context.l10n, result),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PrivateNotesPage(
            session: session,
            controller: widget.privateControllerFactory?.call(),
            editorBuilder: widget.editorBuilder,
            initialNoteId: initialNoteId,
            reminderRequests: _privateReminderRequests,
          ),
        ),
      );
      if (mounted) await _controller.refresh();
    } finally {
      session.dispose();
      _openingPrivateNotes = false;
    }
  }

  Future<bool> _changePrivacy(List<Note> notes, bool isPrivate) async {
    _dismissRouteFocus();
    final session = PrivateNotesController(
      authenticator: widget.privateAuthenticator,
    );
    try {
      final result = await session.unlock(
        prompt: privateNotesPrompt(context.l10n),
      );
      if (!mounted) return false;
      if (!result.authenticated) {
        AppFeedback.show(
          context,
          privateNotesAuthMessage(context.l10n, result),
        );
        return false;
      }
      await _controller.setPrivate(notes, isPrivate: isPrivate);
      return true;
    } finally {
      session.dispose();
    }
  }

  Future<void> _openSettings() async {
    _dismissRouteFocus();
    await _controller.refresh();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (settingsContext) => _QuillSettingsPage(
          controller: _controller,
          dataSizeLoader:
              widget.dataSizeLoader ??
              (() async => _controller.contentSizeBytes),
          onRestoreCompleted: _refreshAfterRestore,
          onBack: () => Navigator.pop(settingsContext),
          updateSupported:
              widget.updateSupported ?? AppUpdateService.instance.supported,
          updateChecker:
              widget.updateChecker ??
              (context) => checkForAppUpdate(context, interactive: false),
        ),
      ),
    );
    if (mounted) _dismissRouteFocus();
  }

  Future<void> _openCalendar() async {
    _dismissRouteFocus();
    await _controller.refresh();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteCalendarPage(
          controller: _controller,
          onOpenNote: (note) async {
            await _openEditor(note);
          },
        ),
      ),
    );
    if (mounted) await _refreshAfterRestore();
  }

  Future<void> _openTagGroups() async {
    _dismissRouteFocus();
    await _controller.refresh();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteTagGroupsPage(
          controller: _controller,
          onOpenNote: (note) async {
            await _openEditor(note);
          },
        ),
      ),
    );
    if (mounted) await _refreshAfterRestore();
  }

  Future<void> _openFiles() async {
    _dismissRouteFocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const FileManagerPage()),
    );
    if (mounted) {
      _dismissRouteFocus();
      if (!_materials.loading) await _materials.refresh();
    }
  }

  void _dismissRouteFocus() {
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
  }

  @override
  Widget build(BuildContext context) => IncomingShareCoordinator(
    onOpenNote: (note) async {
      await _controller.refresh();
      if (mounted) await _openEditor(note);
    },
    child: NoteLibraryPage(
      controller: _controller,
      materialController: _materials,
      editorBuilder: widget.editorBuilder,
      focusRequest: _libraryFocusRequest,
      onCreateNote: _openEditor,
      onOpenAssistant: _openAssistant,
      onOpenCalendar: () => unawaited(_openCalendar()),
      onOpenTagGroups: () => unawaited(_openTagGroups()),
      onOpenFiles: () => unawaited(_openFiles()),
      onOpenSettings: () => unawaited(_openSettings()),
      onOpenPrivateNotes: _openPrivateNotes,
      onChangePrivacy: _changePrivacy,
    ),
  );

  @override
  void dispose() {
    _privateReminderRequests.dispose();
    _reminderRequests.removeListener(_queueReminder);
    _appLock?.removeListener(_queueReminder);
    if (_ownsController) _controller.dispose();
    _materials.dispose();
    super.dispose();
  }
}

final class _QuillSettingsPage extends StatefulWidget {
  const _QuillSettingsPage({
    required this.controller,
    required this.dataSizeLoader,
    required this.onRestoreCompleted,
    required this.onBack,
    required this.updateSupported,
    required this.updateChecker,
  });

  final NoteLibraryController controller;
  final NoteHomeDataSizeLoader dataSizeLoader;
  final AsyncCallback onRestoreCompleted;
  final VoidCallback onBack;
  final bool updateSupported;
  final NoteHomeUpdateChecker updateChecker;

  @override
  State<_QuillSettingsPage> createState() => _QuillSettingsPageState();
}

final class _QuillSettingsPageState extends State<_QuillSettingsPage> {
  int? _dataSize;
  AppBuildMetadata? _metadata;
  Timer? _updateFeedbackTimer;
  bool _checkingForUpdates = false;
  AppUpdateCheckResult? _updateCheckResult;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDataSize());
    unawaited(_loadMetadata());
  }

  @override
  void dispose() {
    _updateFeedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDataSize() async {
    int? value;
    try {
      value = await widget.dataSizeLoader();
    } catch (_) {
      value = null;
    }
    if (mounted) setState(() => _dataSize = value);
  }

  Future<void> _loadMetadata() async {
    AppBuildMetadata metadata;
    try {
      metadata = await AppBuildMetadata.load();
    } catch (_) {
      metadata = const AppBuildMetadata(
        version: '',
        buildNumber: '',
        buildTime: null,
      );
    }
    if (mounted) setState(() => _metadata = metadata);
  }

  @override
  Widget build(BuildContext context) {
    final appLock = context.watch<AppLockController>();
    final locale = context.watch<AppLocaleController>();
    final appearance = context.watch<AppThemeController?>();
    final notes = widget.controller.notes;
    final attachmentCount = notes.fold<int>(
      0,
      (total, note) => total + note.assets.length,
    );
    return Scaffold(
      key: const Key('settings-page'),
      backgroundColor: context.appColors.paperPrimary,
      body: AppThemeCanvas(
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: const Key('settings-list'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 42),
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('settings-back'),
                    tooltip: context.l10n.back,
                    onPressed: widget.onBack,
                    style: IconButton.styleFrom(
                      foregroundColor: context.appColors.ink,
                      fixedSize: const Size.square(48),
                    ),
                    icon: const AppIcon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.settings,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.settingsSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _DataSummary(
                noteCount: notes.length,
                attachmentCount: attachmentCount,
                dataSize: _dataSize,
              ),
              const SizedBox(height: 32),
              _SettingsSection(
                title: context.l10n.backupAndMigration,
                children: [
                  _SettingsRow(
                    title: context.l10n.exportCompleteBackup,
                    subtitle: context.l10n.exportCompleteBackupSubtitle,
                    onTap: _openBackupExport,
                  ),
                  _SettingsRow(
                    title: context.l10n.restoreFromBackup,
                    subtitle: context.l10n.restoreFromBackupSubtitle,
                    onTap: _openBackupRestore,
                  ),
                  _SettingsRow(
                    title: context.l10n.cloudSync,
                    subtitle: context.l10n.cloudSyncSubtitle,
                    onTap: _openCloudSync,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: context.l10n.preferences,
                children: [
                  _SettingsRow(
                    title: context.l10n.themeSettings,
                    subtitle:
                        (appearance?.style.definition ??
                                AppThemeCatalog.definitionFor(
                                  AppThemeCatalog.defaultStyle,
                                ))
                            .label(context.l10n),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: appearance ?? AppThemeController.instance,
                          child: const ThemeSettingsPage(),
                        ),
                      ),
                    ),
                  ),
                  _SettingsRow(
                    title: context.l10n.language,
                    subtitle: _languageLabel(context.l10n, locale.language),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LanguageSettingsPage(),
                      ),
                    ),
                  ),
                  _SettingsRow(
                    title: context.l10n.appLock,
                    subtitle: appLock.enabled
                        ? context.l10n.appLockEnabledSubtitle(
                            _lockTimeoutLabel(context.l10n, appLock.timeout),
                          )
                        : context.l10n.appLockDisabledSubtitle,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AppLockSettingsPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: context.l10n.agentTitle,
                children: [
                  _SettingsRow(
                    title: context.l10n.agentSettings,
                    subtitle: context.l10n.agentSettingsSubtitle,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AgentSettingsPage(),
                      ),
                    ),
                  ),
                  _SettingsRow(
                    title: context.l10n.agentTasks,
                    subtitle: context.l10n.agentStatisticsSubtitle,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AgentStatisticsPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: context.l10n.unifiedStorage,
                children: [
                  _SettingsRow(
                    title: context.l10n.localModels,
                    subtitle: context.l10n.localModelsSubtitle,
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ModelManagementPage(),
                        ),
                      );
                      await _loadDataSize();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: context.l10n.about,
                children: [
                  _SettingsRow(
                    title: context.l10n.appTitle,
                    subtitle: _metadata == null
                        ? context.l10n.loadingVersion
                        : _buildMetadataSubtitle(context.l10n, _metadata!),
                  ),
                  if (widget.updateSupported) ...[
                    _SettingsRow(
                      key: const Key('check-for-updates'),
                      title: context.l10n.checkForUpdates,
                      subtitle: _updateCheckSubtitle(context.l10n),
                      subtitleColor: _updateCheckSubtitleColor,
                      busy: _checkingForUpdates,
                      onTap: _checkingForUpdates
                          ? null
                          : () => unawaited(_checkForUpdates()),
                    ),
                  ],
                  if (kDebugMode) ...[
                    _SettingsRow(
                      title: '调试中心 · Debug',
                      subtitle: '实时日志、异常堆栈与脱敏诊断包',
                      onTap: () => openDebugConsole(context),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBackupExport() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BackupExportPage()),
    );
    await _loadDataSize();
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdates) return;
    _updateFeedbackTimer?.cancel();
    setState(() {
      _checkingForUpdates = true;
      _updateCheckResult = null;
    });

    AppUpdateCheckResult result;
    try {
      result = await widget.updateChecker(context);
    } catch (_) {
      result = AppUpdateCheckResult.failed;
    }
    if (!mounted) return;
    setState(() {
      _checkingForUpdates = false;
      _updateCheckResult = result;
    });

    if (result == AppUpdateCheckResult.latest ||
        result == AppUpdateCheckResult.failed ||
        result == AppUpdateCheckResult.unsupported) {
      _updateFeedbackTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _updateCheckResult = null);
      });
    }
  }

  String _updateCheckSubtitle(AppLocalizations l10n) {
    if (_checkingForUpdates) return l10n.checkingForUpdates;
    return switch (_updateCheckResult) {
      AppUpdateCheckResult.latest => l10n.latestVersionInstalled,
      AppUpdateCheckResult.failed ||
      AppUpdateCheckResult.unsupported => l10n.updateCheckFailed,
      _ => l10n.updatesCheckedAutomatically,
    };
  }

  Color? get _updateCheckSubtitleColor => switch (_updateCheckResult) {
    AppUpdateCheckResult.latest => context.appColors.success,
    AppUpdateCheckResult.failed ||
    AppUpdateCheckResult.unsupported => context.appColors.danger,
    _ => null,
  };

  Future<void> _openBackupRestore() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
    if (restored != true) return;
    await widget.onRestoreCompleted();
    await _loadDataSize();
    if (mounted) {
      AppFeedback.success(context, context.l10n.backupRestored);
    }
  }

  Future<void> _openCloudSync() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CloudSyncPage()),
    );
    if (restored != true) return;
    await widget.onRestoreCompleted();
    await _loadDataSize();
  }
}

final class _DataSummary extends StatelessWidget {
  const _DataSummary({
    required this.noteCount,
    required this.attachmentCount,
    required this.dataSize,
  });

  final int noteCount;
  final int attachmentCount;
  final int? dataSize;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('settings-data-summary'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.appComponents.usesCardSettings
          ? context.appColors.surface
          : context.appColors.paperPrimary,
      borderRadius: BorderRadius.all(Radius.circular(context.appRadii.large)),
      border: context.appComponents.usesCardSettings
          ? Border.all(color: context.appColors.line)
          : null,
      boxShadow: [
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: .06),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: .04),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              Icons.shield_outlined,
              color: context.appColors.muted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.localFirst,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                context.l10n.offlineSecure,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _DataMetric('$noteCount', context.l10n.totalItems),
            _DataMetric('$attachmentCount', context.l10n.attachments),
            _DataMetric(
              dataSize == null ? '—' : _formatBytes(dataSize!),
              context.l10n.noteDataSize,
            ),
          ],
        ),
      ],
    ),
  );
}

final class _DataMetric extends StatelessWidget {
  const _DataMetric(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: context.appColors.ink,
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.appColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Material(
        color: context.appComponents.usesCardSettings
            ? context.appColors.surface
            : Colors.transparent,
        elevation: context.appComponents.usesCardSettings
            ? context.appComponents.cardElevation
            : 0,
        shadowColor: context.appColors.shadow.withValues(alpha: .14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.appRadii.large),
          side: context.appComponents.usesCardSettings
              ? BorderSide(color: context.appColors.line)
              : BorderSide.none,
        ),
        clipBehavior: context.appComponents.usesCardSettings
            ? Clip.antiAlias
            : Clip.none,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) Divider(height: 1, color: context.appColors.line),
              children[index],
            ],
          ],
        ),
      ),
    ],
  );
}

final class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.busy = false,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 76,
    contentPadding: context.appComponents.usesCardSettings
        ? const EdgeInsets.symmetric(horizontal: 16)
        : EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: subtitleColor ?? context.appColors.muted,
        fontSize: 12,
        height: 1.35,
      ),
    ),
    trailing: busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.appColors.ink,
            ),
          )
        : onTap == null
        ? null
        : AppIcon(
            Icons.chevron_right_rounded,
            color: context.appColors.subtle,
            size: 21,
          ),
    onTap: onTap,
  );
}

String _languageLabel(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.english => l10n.languageEnglish,
    };

String _lockTimeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) =>
    switch (timeout) {
      AppLockTimeout.immediately => l10n.lockImmediately,
      AppLockTimeout.oneMinute => l10n.lockAfterOneMinute,
      AppLockTimeout.fiveMinutes => l10n.lockAfterFiveMinutes,
      AppLockTimeout.fifteenMinutes => l10n.lockAfterFifteenMinutes,
    };

String _buildMetadataSubtitle(
  AppLocalizations l10n,
  AppBuildMetadata metadata,
) {
  if (metadata.version.isEmpty) return l10n.unavailable;
  final version = metadata.buildNumber.isEmpty
      ? l10n.versionNumber(metadata.version)
      : l10n.versionNumberWithBuild(metadata.version, metadata.buildNumber);
  final time = metadata.buildTime == null
      ? l10n.buildTimeUnrecorded
      : l10n.buildTime(
          DateFormat.yMd(l10n.localeName).add_Hm().format(metadata.buildTime!),
        );
  return '$version\n$time';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

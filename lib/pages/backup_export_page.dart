import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/backup_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/backup_record_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_icon.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

class BackupExportPage extends StatefulWidget {
  const BackupExportPage({super.key});

  @override
  State<BackupExportPage> createState() => _BackupExportPageState();
}

class _BackupExportPageState extends State<BackupExportPage> {
  final _service = BackupService.instance;
  final _label = TextEditingController();
  final _description = TextEditingController();
  List<BackupRecord> _records = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final records = await _service.listManagedBackups();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          leading: IconButton(
            tooltip: l10n.back,
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const AppIcon(Icons.arrow_back_rounded),
          ),
          title: Text(l10n.exportCompleteBackup),
        ),
        body: PaperShell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              Text(
                l10n.backupScopeDescription,
                style: TextStyle(color: context.appColors.muted, height: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.privateNotesExportNotice,
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              InsetSettingsSection(
                title: l10n.createNewBackup,
                children: [
                  InsetSettingsFieldRow(
                    fieldKey: const Key('backup-label-field'),
                    label: l10n.backupName,
                    controller: _label,
                    enabled: !_busy,
                    maxLength: 40,
                    hintText: l10n.backupNameHint,
                    textInputAction: TextInputAction.next,
                  ),
                  InsetSettingsFieldRow(
                    fieldKey: const Key('backup-description-field'),
                    label: l10n.backupDescription,
                    controller: _description,
                    enabled: !_busy,
                    maxLength: 240,
                    minLines: 2,
                    maxLines: 4,
                    forceStacked: true,
                    hintText: l10n.backupDescriptionHint,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InsetSettingsSection(
                footnote: l10n.backupStoredLocally,
                children: [
                  InsetSettingsRow(
                    rowKey: const Key('create-managed-backup'),
                    title: _busy ? l10n.creatingBackup : l10n.createBackup,
                    enabled: !_busy,
                    busy: _busy,
                    showDisclosure: false,
                    foregroundColor: context.appColors.accent,
                    onTap: _create,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _sectionTitle(l10n.backupHistory),
              const SizedBox(height: 4),
              Text(
                l10n.backupHistorySubtitle,
                style: TextStyle(color: context.appColors.muted, height: 1.45),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_records.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: l10n.noBackupHistory,
                  alignment: const Alignment(0, -0.1),
                )
              else
                for (var index = 0; index < _records.length; index++) ...[
                  BackupRecordCard(
                    key: Key('backup-record-${_records[index].fileName}'),
                    record: _records[index],
                    enabled: !_busy,
                    onDetails: () =>
                        showBackupDetailsDialog(context, _records[index]),
                    onShare: () => _share(_records[index]),
                    onSaveCopy: () => _saveCopy(_records[index]),
                    onDelete: () => _delete(_records[index]),
                  ),
                  if (index != _records.length - 1) const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Text(
    value,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _service.createManagedBackup(
        label: _label.text,
        description: _description.text,
      );
      _label.clear();
      _description.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BackupRecord record) async {
    setState(() => _busy = true);
    try {
      final size = MediaQuery.sizeOf(context);
      final shared = await _service.shareManagedBackup(
        record,
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2,
          size.height / 2,
          1,
          1,
        ),
      );
      if (shared && mounted) {
        AppFeedback.success(context, context.l10n.backupExported);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCopy(BackupRecord record) async {
    setState(() => _busy = true);
    try {
      final saved = await _service.saveManagedBackupCopy(record);
      if (saved && mounted) {
        AppFeedback.success(context, context.l10n.backupCopySaved);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupRecord record) async {
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteBackupQuestion),
        content: Text(context.l10n.deleteBackupDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.deleteBackup),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteManagedBackup(record);
      await _load();
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.exportFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

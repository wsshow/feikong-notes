import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/backup_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/backup_record_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_icon.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final _service = BackupService.instance;
  List<BackupRecord> _records = const [];
  bool _loading = true;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
      canPop: !_restoring,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          leading: IconButton(
            tooltip: l10n.back,
            onPressed: _restoring ? null : () => Navigator.pop(context),
            icon: const AppIcon(Icons.arrow_back_rounded),
          ),
          title: Text(l10n.restoreFromBackup),
        ),
        body: PaperShell(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      Icons.warning_amber_rounded,
                      color: context.appColors.warning,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _restoring ? l10n.restoringBackup : l10n.restoreWarning,
                        style: TextStyle(
                          color: context.appColors.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (_restoring)
                      const Padding(
                        padding: EdgeInsets.only(left: 12, top: 2),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              InsetSettingsSection(
                children: [
                  InsetSettingsRow(
                    rowKey: const Key('choose-external-backup'),
                    title: l10n.chooseExternalBackup,
                    enabled: !_restoring,
                    onTap: _chooseExternal,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                l10n.backupHistory,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
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
                    key: Key(
                      'restore-backup-record-${_records[index].fileName}',
                    ),
                    record: _records[index],
                    enabled: !_restoring,
                    onDetails: () =>
                        showBackupDetailsDialog(context, _records[index]),
                    onRestore: () => _confirmAndRestore(
                      _service.managedBackupFile(_records[index]),
                      _records[index].label,
                    ),
                  ),
                  if (index != _records.length - 1) const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseExternal() async {
    try {
      final file = await _service.chooseBackupFile();
      if (file == null || !mounted) return;
      await _confirmAndRestore(file, p.basename(file.path));
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.restoreFailed('$error'));
      }
    }
  }

  Future<void> _confirmAndRestore(File file, String label) async {
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.restoreCompleteBackupQuestion),
        content: Text('$label\n\n${context.l10n.restoreWarning}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.restoreBackupAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    try {
      await _service.restoreBackupFile(file);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.restoreFailed('$error'));
        setState(() => _restoring = false);
      }
    }
  }
}

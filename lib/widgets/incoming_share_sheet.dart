import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/incoming_share_service.dart';
import 'app_icon.dart';

final class IncomingShareSheet extends StatefulWidget {
  const IncomingShareSheet({
    required this.share,
    required this.importer,
    required this.finish,
    super.key,
  });
  final IncomingShare share;
  final Future<Note> Function(IncomingShare) importer;
  final Future<void> Function() finish;

  @override
  State<IncomingShareSheet> createState() => _IncomingShareSheetState();
}

final class _IncomingShareSheetState extends State<IncomingShareSheet> {
  bool _busy = false;
  bool _failed = false;
  Note? _saved;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      _saved ??= await widget.importer(widget.share);
      await widget.finish();
      if (mounted) {
        setState(() => _busy = false);
        final route = ModalRoute.of(context)!;
        if (route.isCurrent) {
          Navigator.pop(context, _saved);
        } else {
          Navigator.of(context).removeRoute(route, _saved);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final share = widget.share;
    final error = switch (share.error) {
      'too_large' || 'too_many' => l10n.incomingShareLimit,
      'queue_full' => l10n.incomingShareQueueFull,
      null => _failed ? l10n.incomingShareSaveFailed : null,
      _ => l10n.incomingShareReadFailed,
    };
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.incomingShareTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.incomingShareDescription,
                style: TextStyle(color: context.appColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (share.title.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            share.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      if (share.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            share.text,
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                      for (final file in share.files)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              AppIcon(
                                Icons.insert_drive_file_outlined,
                                color: context.appColors.muted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  file.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: context.appColors.danger,
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _saved),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  if (share.error == null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        child: _busy
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(l10n.saving),
                                ],
                              )
                            : Text(
                                _failed ? l10n.retry : l10n.incomingShareSave,
                              ),
                      ),
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
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_overlay.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../providers/app_lock_controller.dart';
import '../services/incoming_share_service.dart';
import '../services/shared_note_import_service.dart';
import 'app_feedback.dart';
import 'incoming_share_sheet.dart';

final class IncomingShareCoordinator extends StatefulWidget {
  const IncomingShareCoordinator({
    required this.child,
    required this.onOpenNote,
    this.service,
    this.importer,
    super.key,
  });
  final Widget child;
  final Future<void> Function(Note note) onOpenNote;
  final IncomingShareService? service;
  final Future<Note> Function(IncomingShare share)? importer;

  @override
  State<IncomingShareCoordinator> createState() =>
      _IncomingShareCoordinatorState();
}

final class _IncomingShareCoordinatorState
    extends State<IncomingShareCoordinator> {
  late final IncomingShareService _service;
  AppLockController? _lock;
  bool _scheduled = false;
  bool _showing = false;
  Note? _awaitingNote;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IncomingShareService();
    _service.addListener(_changed);
    unawaited(_service.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lock = context.read<AppLockController?>();
    if (!identical(lock, _lock)) {
      _lock?.removeListener(_queue);
      _lock = lock;
      _lock?.addListener(_queue);
    }
    _queue();
  }

  bool get _unlocked =>
      _lock == null ||
      (_lock!.initialized && !_lock!.locked && !_lock!.obscured);

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _queue();
  }

  void _queue() {
    if (!mounted || _scheduled || _showing || !_unlocked) return;
    if (_service.pending == null && _awaitingNote == null && !_service.failed) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _unlocked && !_showing) unawaited(_handle());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _handle() async {
    _showing = true;
    try {
      if (_service.failed) {
        _service.clearFailure();
        AppFeedback.error(context, context.l10n.incomingShareReadFailed);
      }
      if (_awaitingNote == null) {
        final share = _service.pending;
        if (share == null) return;
        FocusManager.instance.primaryFocus?.unfocus();
        final note = await AppOverlay.bottomSheet<Note>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          sheetAnimationStyle: AnimationStyle.noAnimation,
          builder: (_) => IncomingShareSheet(
            share: share,
            importer: widget.importer ?? SharedNoteImportService().import,
            finish: () => _service.finish(share.id),
          ),
        );
        if (!mounted) return;
        _awaitingNote = note;
        // Idempotent acknowledgement also covers closing after a save succeeded
        // but the sheet's first acknowledgement failed.
        await _service.finish(share.id);
      }
      if (!mounted || !_unlocked) return;
      final note = _awaitingNote;
      if (note != null) {
        _awaitingNote = null;
        await widget.onOpenNote(note);
      }
    } catch (_) {
      if (mounted && _unlocked) {
        AppFeedback.error(context, context.l10n.incomingShareSaveFailed);
      }
      // Keep the native entry for a subsequent resume, not an immediate retry loop.
      return;
    } finally {
      _showing = false;
    }
    if (mounted) {
      await _service.refresh();
      _queue();
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_service.receiving)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(child: LinearProgressIndicator()),
        ),
    ],
  );

  @override
  void dispose() {
    _lock?.removeListener(_queue);
    _service.removeListener(_changed);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../providers/note_library_controller.dart';
import '../providers/private_notes_controller.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_feedback_navigator_observer.dart';
import '../widgets/app_icon.dart';
import '../widgets/private_notes_auth.dart';
import '../widgets/private_notes_scope.dart';
import '../models/local_chat.dart';
import 'local_chat_page.dart';
import 'note_calendar_page.dart';
import 'note_library_page.dart';
import 'note_quill_editor_page.dart';

/// All private routes, including editors and their sheets, stay inside this
/// navigator. The authorization shield therefore covers the entire visit.
final class PrivateNotesPage extends StatefulWidget {
  const PrivateNotesPage({
    required this.session,
    this.controller,
    this.editorBuilder,
    this.initialNoteId,
    this.reminderRequests,
    this.assistantBuilder,
    super.key,
  });

  final PrivateNotesController session;
  final NoteLibraryController? controller;
  final NoteLibraryEditorBuilder? editorBuilder;
  final NoteId? initialNoteId;
  final ValueNotifier<NoteId?>? reminderRequests;
  final Widget Function(BuildContext, LocalChatNoteOpener)? assistantBuilder;

  @override
  State<PrivateNotesPage> createState() => _PrivateNotesPageState();
}

final class _PrivateNotesPageState extends State<PrivateNotesPage> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final NoteLibraryController _library;
  bool _loaded = false;
  bool _openingInitial = false;
  NoteId? _pendingInitial;

  @override
  void initState() {
    super.initState();
    _library = widget.controller ?? NoteLibraryController(privateSpace: true);
    assert(_library.privateSpace);
    _loaded = !widget.session.protected;
    widget.session.addListener(_onSessionChanged);
    _pendingInitial = widget.initialNoteId;
    widget.reminderRequests?.addListener(_onReminderRequest);
    _onReminderRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialNote());
  }

  void _onReminderRequest() {
    final id = widget.reminderRequests?.value;
    if (id == null) return;
    _pendingInitial = id;
    widget.reminderRequests!.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialNote());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (widget.session.protected) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => _loaded = _loaded || !widget.session.protected);
    if (!widget.session.protected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialNote());
    }
  }

  Future<void> _openInitialNote() async {
    final id = _pendingInitial;
    if (!mounted || id == null || _openingInitial || widget.session.protected) {
      return;
    }
    _openingInitial = true;
    Note? target;
    try {
      await _library.refresh();
      if (!mounted || widget.session.protected) return;
      if (_pendingInitial != id) return;
      _pendingInitial = null;
      target = _library.notes.where((note) => note.id == id).firstOrNull;
      if (target == null) {
        AppFeedback.error(context, context.l10n.toolActionTargetMissing);
        return;
      }
    } finally {
      _openingInitial = false;
      if (mounted && _pendingInitial != null && !widget.session.protected) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialNote());
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
    await _navigatorKey.currentState!.push<Object?>(
      MaterialPageRoute(builder: (context) => _editor(context, target)),
    );
    if (mounted) await _library.refresh();
  }

  Widget _editor(BuildContext context, Note? note) =>
      widget.editorBuilder?.call(context, note) ??
      NoteQuillEditorPage(initialNote: note);

  Future<void> _createNote() async {
    if (widget.session.protected) return;
    await _navigatorKey.currentState!.push<Object?>(
      MaterialPageRoute(
        builder: (context) => _editor(context, Note.newDraft(isPrivate: true)),
      ),
    );
    if (mounted) await _library.refresh();
  }

  Future<void> _openNote(Note note) async {
    if (widget.session.protected || !note.isPrivate) return;
    await _navigatorKey.currentState!.push<Object?>(
      MaterialPageRoute(builder: (context) => _editor(context, note)),
    );
    if (mounted) await _library.refresh();
  }

  Future<void> _openCalendar() async {
    if (widget.session.protected) return;
    await _library.refresh();
    if (!mounted || widget.session.protected) return;
    await _navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) =>
            NoteCalendarPage(controller: _library, onOpenNote: _openNote),
      ),
    );
    if (mounted) await _library.refresh();
  }

  Future<void> _openAssistantSource(LocalChatNoteContext source) async {
    if (widget.session.protected) return;
    await _library.refresh();
    if (!mounted || widget.session.protected) return;
    final note = _library.notes
        .where((note) => note.id == source.noteId)
        .firstOrNull;
    if (note == null) {
      AppFeedback.error(context, context.l10n.toolActionTargetMissing);
      return;
    }
    await _openNote(note);
  }

  Future<void> _openAssistant() async {
    if (widget.session.protected) return;
    await _navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) =>
            widget.assistantBuilder?.call(context, _openAssistantSource) ??
            LocalChatPage(privateSpace: true, onOpenNote: _openAssistantSource),
      ),
    );
    if (mounted) await _library.refresh();
  }

  Future<bool> _changePrivacy(List<Note> notes, bool isPrivate) async {
    if (widget.session.protected) return false;
    await _library.setPrivate(notes, isPrivate: isPrivate);
    return true;
  }

  void _exit() {
    if (_navigatorKey.currentState?.canPop() == true) {
      // Let the editor's normal save-before-pop flow run; do not dispose a
      // potentially unsaved draft just because the space has been locked.
      if (!widget.session.protected) _navigatorKey.currentState!.maybePop();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final protected = widget.session.protected;
    return PrivateNotesScope(
      session: widget.session,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) {
          if (!protected) _navigatorKey.currentState?.maybePop();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loaded)
              Offstage(
                offstage: protected,
                child: ExcludeFocus(
                  excluding: protected,
                  child: Navigator(
                    key: _navigatorKey,
                    observers: [AppFeedbackNavigatorObserver()],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => NoteLibraryPage(
                        controller: _library,
                        editorBuilder: _editor,
                        onCreateNote: () => unawaited(_createNote()),
                        onOpenCalendar: _openCalendar,
                        onOpenAssistant: _openAssistant,
                        onExitPrivateNotes: _exit,
                        onChangePrivacy: _changePrivacy,
                      ),
                    ),
                  ),
                ),
              ),
            if (protected)
              Scaffold(
                key: const Key('private-notes-locked'),
                backgroundColor: context.appColors.paperPrimary,
                appBar: AppBar(
                  title: Text(context.l10n.privateNotes),
                  leading: IconButton(
                    tooltip: context.l10n.exitPrivateNotes,
                    onPressed: _navigatorKey.currentState?.canPop() == true
                        ? null
                        : _exit,
                    icon: const AppIcon(Icons.arrow_back_rounded),
                  ),
                ),
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(Icons.lock_outline_rounded, size: 40),
                          const SizedBox(height: 24),
                          Text(
                            context.l10n.privateNotesLocked,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.privateNotesLockedHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.appColors.muted,
                              height: 1.6,
                            ),
                          ),
                          if (widget.session.lastResult case final result?
                              when !result.authenticated) ...[
                            const SizedBox(height: 16),
                            Text(
                              privateNotesAuthMessage(context.l10n, result),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            key: const Key('private-notes-unlock'),
                            onPressed:
                                widget.session.authenticating ||
                                    widget.session.obscured
                                ? null
                                : () => unawaited(
                                    widget.session.unlock(
                                      prompt: privateNotesPrompt(context.l10n),
                                    ),
                                  ),
                            icon: const AppIcon(Icons.fingerprint_rounded),
                            label: Text(
                              widget.session.authenticating
                                  ? context.l10n.authenticationInProgress
                                  : context.l10n.unlockPrivateNotes,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.reminderRequests?.removeListener(_onReminderRequest);
    widget.session.removeListener(_onSessionChanged);
    widget.session.lock();
    if (widget.controller == null) _library.dispose();
    super.dispose();
  }
}

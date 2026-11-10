import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/local_chat.dart';
import '../models/note.dart';
import '../services/local_chat_note_context_builder.dart';
import '../services/note_database_service.dart';
import '../services/note_repository.dart';
import 'app_feedback.dart';
import 'editor_context_menu.dart';
import 'note_delta_preview.dart';
import 'app_icon.dart';

Future<List<LocalChatNoteContext>?> showLocalChatNotePicker(
  BuildContext context, {
  List<LocalChatNoteContext> initialSelection = const [],
  Set<NoteId> excludedNoteIds = const {},
  int maxSelection = LocalChatNoteContextBuilder.maxNotes,
  bool privateSpace = false,
  Future<NoteRepository> Function()? repository,
}) => AppOverlay.bottomSheet<List<LocalChatNoteContext>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _LocalChatNotePicker(
    initialSelection: initialSelection,
    excludedNoteIds: excludedNoteIds,
    maxSelection: maxSelection,
    privateSpace: privateSpace,
    repository: repository ?? (() => NoteDatabaseService.instance.repository),
  ),
);

class _LocalChatNotePicker extends StatefulWidget {
  final Future<NoteRepository> Function() repository;
  final bool privateSpace;
  final List<LocalChatNoteContext> initialSelection;
  final Set<NoteId> excludedNoteIds;
  final int maxSelection;

  const _LocalChatNotePicker({
    required this.privateSpace,
    required this.repository,
    required this.initialSelection,
    required this.excludedNoteIds,
    required this.maxSelection,
  });

  @override
  State<_LocalChatNotePicker> createState() => _LocalChatNotePickerState();
}

class _LocalChatNotePickerState extends State<_LocalChatNotePicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _selected = <NoteId, LocalChatNoteContext>{};
  Timer? _debounce;
  List<Note> _results = const [];
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    for (final context in widget.initialSelection) {
      if (context.isPrivate == widget.privateSpace &&
          !widget.excludedNoteIds.contains(context.noteId)) {
        _selected[context.noteId] = context;
      }
    }
    _controller.addListener(_onQueryChanged);
    unawaited(_loadRecent());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      unawaited(_loadRecent());
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 260),
      () => _searchNotes(query),
    );
  }

  Future<void> _loadRecent() async {
    final request = ++_requestId;
    final repository = await widget.repository();
    final notes = await repository.list(privateSpace: widget.privateSpace);
    if (!mounted ||
        request != _requestId ||
        _controller.text.trim().isNotEmpty) {
      return;
    }
    setState(() {
      _results = notes
          .where((note) => !widget.excludedNoteIds.contains(note.id))
          .take(30)
          .toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _searchNotes(String query) async {
    final request = ++_requestId;
    final repository = await widget.repository();
    final results = await repository.search(
      query,
      privateSpace: widget.privateSpace,
    );
    if (!mounted || request != _requestId || query != _controller.text.trim()) {
      return;
    }
    setState(() {
      _results = results
          .where((note) => !widget.excludedNoteIds.contains(note.id))
          .take(40)
          .toList(growable: false);
      _loading = false;
    });
  }

  void _toggle(Note note) {
    final noteId = note.id;
    if (_selected.remove(noteId) != null) {
      setState(() {});
      return;
    }
    if (_selected.length >= widget.maxSelection) {
      AppFeedback.show(
        context,
        context.l10n.noteReferenceLimit(widget.maxSelection),
      );
      return;
    }
    setState(() {
      _selected[noteId] = LocalChatNoteContextBuilder.fromNote(
        note,
        untitledLabel: context.l10n.untitled,
      );
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.referenceNotes,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.selectedNoteCount(_selected.length),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.cancel,
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            key: const Key('local-chat-note-search'),
            controller: _controller,
            focusNode: _focusNode,
            contextMenuBuilder: buildAppEditableTextContextMenu,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.searchNotes,
              prefixIcon: const AppIcon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _controller.clear,
                      icon: const AppIcon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _controller.text.trim().isEmpty
                  ? context.l10n.recentNotes
                  : context.l10n.searchNotes,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _buildResults()),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border(top: BorderSide(color: context.appColors.line)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('local-chat-confirm-note-selection'),
              onPressed: () => Navigator.pop(
                context,
                LocalChatNoteContextBuilder.fit(_selected.values),
              ),
              icon: const AppIcon(Icons.library_add_check_outlined),
              label: Text(context.l10n.addSelectedNotes),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildResults() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noMatchingNotes,
          style: TextStyle(color: context.appColors.muted),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final note = _results[index];
        final noteId = note.id;
        final selected = _selected.containsKey(noteId);
        return CheckboxListTile(
          key: Key('local-chat-note-option-$noteId'),
          value: selected,
          onChanged: (_) => _toggle(note),
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: CircleAvatar(
            backgroundColor: context.appColors.canvas,
            foregroundColor: context.appColors.muted,
            child: AppIcon(Icons.description_outlined, size: 19),
          ),
          title: Text(
            note.title.trim().isEmpty ? context.l10n.untitled : note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: NoteDeltaPreview(
            note: note,
            maxLines: 2,
            maxCharacters: 400,
          ),
        );
      },
    );
  }
}

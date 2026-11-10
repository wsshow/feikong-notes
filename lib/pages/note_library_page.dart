import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../experience/editorial/editorial_note_library_surface.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/library_file.dart';
import '../providers/editorial_material_controller.dart';
import '../providers/file_library_controller.dart';
import '../providers/note_library_controller.dart';
import '../services/file_storage_service.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_feedback.dart';
import '../widgets/navigation_icons.dart';
import '../widgets/privacy_pull_to_open.dart';
import 'note_quill_editor_page.dart';
import '../widgets/app_icon.dart';
import '../widgets/editorial_material_deck.dart';
import '../widgets/library_file_icon.dart';
import 'file_manager_page.dart';
import 'file_preview_page.dart';
import '../widgets/note_reminder_indicator.dart';
import '../widgets/sunny_growth_decoration.dart';

typedef NoteLibraryEditorBuilder =
    Widget Function(BuildContext context, Note? note);

typedef NoteLibraryImageResolver = ImageProvider? Function(NoteAsset asset);

/// A one-shot request for the library to refresh after an editor route closes.
final class NoteLibraryFocusRequest {
  const NoteLibraryFocusRequest(this.noteId);

  final NoteId noteId;
}

/// The mobile-first note library.
///
/// It owns note-library state and delegates rendering to the active theme's
/// semantic home layout. Theme surfaces never access storage or navigation.
final class NoteLibraryPage extends StatefulWidget {
  const NoteLibraryPage({
    this.controller,
    this.materialController,
    this.editorBuilder,
    this.resolveImage,
    this.focusRequest,
    this.onCreateNote,
    this.onOpenAssistant,
    this.onOpenCalendar,
    this.onOpenTagGroups,
    this.onOpenFiles,
    this.onOpenSettings,
    this.onSelectionModeChanged,
    this.onOpenPrivateNotes,
    this.onChangePrivacy,
    this.onExitPrivateNotes,
    super.key,
  });

  final NoteLibraryController? controller;
  final EditorialMaterialController? materialController;
  final NoteLibraryEditorBuilder? editorBuilder;

  /// Resolves the small image shown on a note card. Production uses the
  /// managed thumbnail and tests can provide an in-memory image.
  final NoteLibraryImageResolver? resolveImage;
  final NoteLibraryFocusRequest? focusRequest;
  final VoidCallback? onCreateNote;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenTagGroups;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenSettings;
  final ValueChanged<bool>? onSelectionModeChanged;
  final Future<void> Function()? onOpenPrivateNotes;
  final Future<bool> Function(List<Note> notes, bool isPrivate)?
  onChangePrivacy;
  final VoidCallback? onExitPrivateNotes;

  @override
  State<NoteLibraryPage> createState() => _NoteLibraryPageState();
}

final class _NoteLibraryPageState extends State<NoteLibraryPage> {
  late final NoteLibraryController _controller;
  late final bool _ownsController;
  late final EditorialMaterialController _materials =
      widget.materialController ?? EditorialMaterialController();
  String? _materialBusyFileId;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'note-library-search');
  late final ScrollController _scrollController;
  final Set<NoteId> _selectedNoteIds = {};
  Timer? _searchTimer;
  String? _activeEditorialTag;
  var _selectionRequested = false;
  var _selectionBusy = false;

  bool get _selectionMode => _selectionRequested || _selectedNoteIds.isNotEmpty;

  List<Note> get _selectedNotes => _controller.notes
      .where((note) => _selectedNoteIds.contains(note.id))
      .toList(growable: false);

  List<Note> get _editorialNotes {
    final tag = _activeEditorialTag;
    if (tag == null) return _controller.notes;
    return _controller.notes
        .where((note) => note.tags.contains(tag))
        .toList(growable: false);
  }

  List<String> get _editorialTags {
    final frequency = <String, int>{};
    for (final note in _controller.notes) {
      for (final tag in note.tags) {
        frequency.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final tags = frequency.keys.toList()
      ..sort((first, second) {
        final byFrequency = frequency[second]!.compareTo(frequency[first]!);
        return byFrequency != 0 ? byFrequency : first.compareTo(second);
      });
    return List.unmodifiable(tags);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NoteLibraryController();
    _controller.addListener(_onControllerChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(_controller.initialize());
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant NoteLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final request = widget.focusRequest;
    if (request == null || identical(request, oldWidget.focusRequest)) return;
    unawaited(_refreshAndReveal(request.noteId));
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final wasSelectionMode = _selectionMode;
    final available = _controller.notes.map((note) => note.id).toSet();
    _selectedNoteIds.removeWhere((id) => !available.contains(id));
    final activeTag = _activeEditorialTag;
    if (_controller.query.isEmpty &&
        activeTag != null &&
        !_controller.notes.any((note) => note.tags.contains(activeTag))) {
      _activeEditorialTag = null;
    }
    if (_controller.notes.isEmpty) _selectionRequested = false;
    setState(() {});
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _scheduleSearch(String value) {
    _searchTimer?.cancel();
    _activeEditorialTag = null;
    _searchTimer = Timer(
      const Duration(milliseconds: 220),
      () => unawaited(_controller.search(value)),
    );
    setState(() {});
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _activeEditorialTag = null;
    _searchController.clear();
    _searchFocusNode.unfocus();
    unawaited(_controller.search(''));
    setState(() {});
  }

  Future<void> _openLibraryDestination(VoidCallback callback) async {
    _searchTimer?.cancel();
    _activeEditorialTag = null;
    _dismissSearchFocus();
    _searchController.clear();
    if (_controller.query.isNotEmpty) await _controller.search('');
    if (!mounted) return;
    setState(() {});
    callback();
  }

  Future<void> _selectEditorialTag(String? tag) async {
    _searchTimer?.cancel();
    _dismissSearchFocus();
    _searchController.clear();
    if (_controller.query.isNotEmpty) await _controller.search('');
    if (!mounted) return;
    setState(() => _activeEditorialTag = tag);
  }

  void _dismissSearchFocus() {
    _searchFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
  }

  void _toggleSelection(Note note) {
    if (_controller.isBusy(note.id) || _selectionBusy) return;
    final wasSelectionMode = _selectionMode;
    _dismissSearchFocus();
    setState(() {
      _selectionRequested = true;
      if (!_selectedNoteIds.add(note.id)) _selectedNoteIds.remove(note.id);
    });
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _clearSelection() {
    if (_selectionBusy) return;
    final wasSelectionMode = _selectionMode;
    setState(() {
      _selectionRequested = false;
      _selectedNoteIds.clear();
    });
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _selectAll() {
    if (_selectionBusy) return;
    final wasSelectionMode = _selectionMode;
    final visibleNotes = _activeEditorialTag == null
        ? _controller.notes
        : _editorialNotes;
    final selectable = visibleNotes
        .where((note) => !_controller.isBusy(note.id))
        .map((note) => note.id)
        .toSet();
    final allSelected =
        selectable.isNotEmpty && selectable.every(_selectedNoteIds.contains);
    setState(() {
      _selectionRequested = true;
      if (allSelected) {
        _selectedNoteIds.removeAll(selectable);
      } else {
        _selectedNoteIds.addAll(selectable);
      }
    });
    _notifySelectionModeChanged(wasSelectionMode);
  }

  void _notifySelectionModeChanged(bool wasSelectionMode) {
    if (wasSelectionMode == _selectionMode) return;
    widget.onSelectionModeChanged?.call(_selectionMode);
  }

  Future<void> _openEditor(Note note) async {
    _dismissSearchFocus();
    final builder =
        widget.editorBuilder ??
        (context, value) => NoteQuillEditorPage(initialNote: value);
    final rawResult = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (context) => builder(context, note)),
    );
    if (!mounted) return;
    _dismissSearchFocus();
    final savedNote = switch (rawResult) {
      NoteEditorRouteResult(:final note) => note,
      Note value => value,
      _ => null,
    };
    if (savedNote == null) {
      await _controller.refresh();
    } else {
      await _refreshAndReveal(savedNote.id);
    }
    if (!_materials.loading) await _materials.refresh();
  }

  Future<void> _refreshAndReveal(NoteId noteId) async {
    _searchTimer?.cancel();
    _activeEditorialTag = null;
    _dismissSearchFocus();
    _searchController.clear();
    if (_controller.query.isEmpty) {
      await _controller.refresh();
    } else {
      await _controller.search('');
    }
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  Future<void> _openMaterialLibrary(
    LibraryFileKind? filter,
    bool import,
  ) async {
    _dismissSearchFocus();
    final controller = FileLibraryController(store: _materials.store);
    if (filter != null) controller.setFilter(filter);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FileManagerPage(controller: controller, importOnOpen: import),
        ),
      );
    } finally {
      controller.dispose();
    }
    if (mounted) await _materials.refresh();
  }

  Future<void> _openMaterialFile(LibraryFile file) async {
    _dismissSearchFocus();
    try {
      await _materials.store.markOpened(file.id);
    } catch (_) {
      /* History does not block preview. */
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewPage(entry: file, store: _materials.store),
      ),
    );
    if (mounted) await _materials.refresh();
  }

  Future<void> _writeMaterialNote(LibraryFile file) async {
    if (_materialBusyFileId != null) return;
    _dismissSearchFocus();
    setState(() => _materialBusyFileId = file.id);
    try {
      final note = await _materials.notes.openOrCreate(file);
      if (!mounted) return;
      await _openEditor(note);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorOperation);
    } finally {
      if (mounted) {
        setState(() => _materialBusyFileId = null);
        await _materials.refresh();
        await _controller.refresh();
      }
    }
  }

  Future<void> _chooseMaterialFavorites() async {
    if (_materials.files.isEmpty) {
      await _openMaterialLibrary(null, true);
      return;
    }
    final selected = _materials.files
        .where((e) => e.favorite)
        .map((e) => e.id)
        .toSet();
    final result = await AppOverlay.bottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  sheetContext.l10n.materialPickFavorites,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _materials.files.length,
                  itemBuilder: (context, index) {
                    final file = _materials.files[index];
                    return CheckboxListTile(
                      value: selected.contains(file.id),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(file.id);
                        } else {
                          selected.remove(file.id);
                        }
                      }),
                      title: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${file.extension.toUpperCase()} · ${formatFileSize(file.size)}',
                      ),
                      secondary: LibraryFileIcon(
                        entry: file,
                        filePath: _materials.store.fileFor(file).path,
                        size: 40,
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: Text(sheetContext.l10n.materialSaveFavorites),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _materials.store.setFavorite(result, true);
      await _materials.store.setFavorite(
        _materials.files
            .where((e) => e.favorite && !result.contains(e.id))
            .map((e) => e.id)
            .toSet(),
        false,
      );
      await _materials.refresh();
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorOperation);
    }
  }

  Future<bool?> _confirmDelete({required String title}) =>
      AppOverlay.bottomSheet<bool>(
        context: context,
        useSafeArea: true,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                context.l10n.deletePermanentlyDescription,
                style: TextStyle(color: context.appColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('delta-library-confirm-delete'),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.appColors.danger,
                      ),
                      child: Text(context.l10n.deletePermanently),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _setSelectedPinned() async {
    final notes = _selectedNotes;
    if (notes.isEmpty || _selectionBusy) return;
    final allPinned = notes.every((note) => note.isPinned);
    final wasSelectionMode = _selectionMode;
    setState(() => _selectionBusy = true);
    try {
      await _controller.setPinned(notes, pinned: !allPinned);
      if (!mounted) return;
      setState(() {
        _selectionBusy = false;
        _selectionRequested = false;
        _selectedNoteIds.clear();
      });
      _notifySelectionModeChanged(wasSelectionMode);
    } catch (error) {
      if (mounted) {
        setState(() => _selectionBusy = false);
        AppFeedback.error(context, context.l10n.toolActionFailed('$error'));
      }
    }
  }

  Future<void> _deleteSelected() async {
    final notes = _selectedNotes;
    if (notes.isEmpty || _selectionBusy) return;
    final confirmed = await _confirmDelete(
      title: context.l10n.deleteSelectedNotesQuestion(notes.length),
    );
    if (confirmed != true || !mounted) return;
    final wasSelectionMode = _selectionMode;
    setState(() => _selectionBusy = true);
    try {
      await _controller.deletePermanentlyAll(notes);
      if (!_materials.loading) await _materials.refresh();
      if (!mounted) return;
      setState(() {
        _selectionBusy = false;
        _selectionRequested = false;
        _selectedNoteIds.clear();
      });
      _notifySelectionModeChanged(wasSelectionMode);
    } catch (error) {
      if (mounted) {
        setState(() => _selectionBusy = false);
        AppFeedback.error(context, context.l10n.toolActionFailed('$error'));
      }
    }
  }

  Future<void> _changeSelectedPrivacy() async {
    final notes = _selectedNotes;
    final change = widget.onChangePrivacy;
    if (notes.isEmpty || _selectionBusy || change == null) return;
    setState(() => _selectionBusy = true);
    try {
      final changed = await change(notes, !_controller.privateSpace);
      if (!mounted) return;
      setState(() => _selectionBusy = false);
      if (changed) {
        _clearSelection();
        if (!_materials.loading) await _materials.refresh();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _selectionBusy = false);
      AppFeedback.error(context, context.l10n.toolActionFailed('$error'));
    }
  }

  @override
  Widget build(BuildContext context) =>
      switch (context.appComponents.homeLayout) {
        AppHomeLayout.quietList => _buildQuietLibrary(context),
        AppHomeLayout.editorialBoard => _buildEditorialLibrary(context),
      };

  Widget _buildEditorialLibrary(BuildContext context) =>
      EditorialNoteLibrarySurface(
        materialDeck: EditorialMaterialDeck(
          controller: _materials,
          busyFileId: _materialBusyFileId,
          onOpenFile: (file) => unawaited(_openMaterialFile(file)),
          onWriteNote: (file) => unawaited(_writeMaterialNote(file)),
          onOpenLibrary: (filter, import) =>
              unawaited(_openMaterialLibrary(filter, import)),
          onChooseFavorites: () => unawaited(_chooseMaterialFavorites()),
        ),
        notes: _editorialNotes,
        totalNoteCount: _controller.notes.length,
        availableTags: _editorialTags,
        activeTag: _activeEditorialTag,
        query: _controller.query,
        isLoading: _controller.isLoading,
        hasError: _controller.hasError,
        privateSpace: _controller.privateSpace,
        selectionMode: _selectionMode,
        selectionBusy: _selectionBusy,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        scrollController: _scrollController,
        selectionHeader: _buildSelectionHeader(context),
        selectionActions: _buildSelectionActions(context),
        onSearchChanged: _scheduleSearch,
        onClearSearch: _clearSearch,
        onSelectTag: (tag) => unawaited(_selectEditorialTag(tag)),
        onRefresh: _controller.refresh,
        onRetry: () => unawaited(_controller.refresh()),
        onOpenNote: (note) => unawaited(_openEditor(note)),
        onToggleNote: _toggleSelection,
        isBusy: (note) => _controller.isBusy(note.id),
        isSelected: (note) => _selectedNoteIds.contains(note.id),
        resolveImage: (note) {
          final asset = _preferredImageAsset(note);
          return asset == null ? null : _resolveThumbnail(asset);
        },
        onCreateNote: widget.onCreateNote,
        onOpenCalendar: widget.onOpenCalendar == null
            ? null
            : () => unawaited(_openLibraryDestination(widget.onOpenCalendar!)),
        onOpenAssistant: widget.onOpenAssistant == null
            ? null
            : () => unawaited(_openLibraryDestination(widget.onOpenAssistant!)),
        onOpenTagGroups: widget.onOpenTagGroups == null
            ? null
            : () => unawaited(_openLibraryDestination(widget.onOpenTagGroups!)),
        onOpenFiles: widget.onOpenFiles == null
            ? null
            : () => unawaited(_openLibraryDestination(widget.onOpenFiles!)),
        onOpenSettings: widget.onOpenSettings == null
            ? null
            : () => unawaited(_openLibraryDestination(widget.onOpenSettings!)),
        onOpenPrivateNotes: widget.onOpenPrivateNotes,
        onExitPrivateNotes: widget.onExitPrivateNotes,
      );

  Widget _buildQuietLibrary(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.paperPrimary,
    body: AppThemeCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_selectionMode)
              _buildSelectionHeader(context)
            else
              _buildLibraryHeader(context),
            if (!_selectionMode) _buildSearchBar(context),
            if (_controller.isLoading && _controller.notes.isEmpty)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(
              child: widget.onOpenPrivateNotes == null
                  ? _buildContent(context)
                  : PrivacyPullToOpen(
                      enabled:
                          !_selectionMode &&
                          !_selectionBusy &&
                          _searchController.text.isEmpty &&
                          !_searchFocusNode.hasFocus,
                      onOpen: widget.onOpenPrivateNotes!,
                      child: _buildContent(context),
                    ),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: _selectionMode
        ? _buildSelectionActions(context)
        : _buildBottomActions(context),
  );

  Widget _buildLibraryHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_controller.privateSpace)
          IconButton(
            key: const Key('private-notes-back'),
            tooltip: context.l10n.exitPrivateNotes,
            onPressed: widget.onExitPrivateNotes,
            icon: const AppIcon(Icons.arrow_back_rounded),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SunnyGrowthHeading(
                child: Text(
                  _controller.privateSpace
                      ? context.l10n.privateNotes
                      : context.l10n.appTitle,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.noteCountShort(_controller.notes.length),
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize:
                      context.appComponents.libraryPresentation ==
                          AppLibraryPresentation.spacious
                      ? context.appComponents.labelSize
                      : 13,
                ),
              ),
            ],
          ),
        ),
        if (!_controller.privateSpace && widget.onOpenFiles != null)
          IconButton(
            key: const Key('delta-library-open-files'),
            tooltip: context.l10n.fmTitle,
            onPressed: () =>
                unawaited(_openLibraryDestination(widget.onOpenFiles!)),
            icon: const AppIcon(Icons.folder_open_rounded),
          ),
        if (!_controller.privateSpace)
          IconButton(
            key: const Key('delta-library-open-tag-groups'),
            tooltip: context.l10n.tagGroups,
            style: IconButton.styleFrom(
              foregroundColor: context.appColors.accent,
            ),
            onPressed: widget.onOpenTagGroups == null
                ? null
                : () => unawaited(
                    _openLibraryDestination(widget.onOpenTagGroups!),
                  ),
            icon: const TagOutlineIcon(size: 27),
          ),
        if (!_controller.privateSpace)
          IconButton(
            key: const Key('delta-library-open-settings'),
            tooltip: context.l10n.settings,
            style: IconButton.styleFrom(
              foregroundColor: context.appColors.accent,
            ),
            onPressed: widget.onOpenSettings == null
                ? null
                : () => unawaited(
                    _openLibraryDestination(widget.onOpenSettings!),
                  ),
            icon: const SettingsOutlineIcon(size: 27),
          ),
      ],
    ),
  );

  Widget _buildSearchBar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    child: Container(
      key: const Key('delta-library-search-pull'),
      height:
          context.appComponents.libraryPresentation ==
              AppLibraryPresentation.spacious
          ? null
          : 48,
      constraints:
          context.appComponents.libraryPresentation ==
              AppLibraryPresentation.spacious
          ? BoxConstraints(minHeight: context.appComponents.buttonHeight)
          : null,
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(
          context.appComponents.libraryPresentation ==
                  AppLibraryPresentation.spacious
              ? context.appRadii.medium
              : 18,
        ),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          context.appComponents.libraryPresentation ==
                  AppLibraryPresentation.spacious
              ? context.appRadii.medium
              : 18,
        ),
        border: Border.all(
          color: _searchFocusNode.hasFocus
              ? context.appColors.accent
              : context.appComponents.outlinesControls
              ? context.appColors.control
              : Colors.transparent,
          width: _searchFocusNode.hasFocus ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 15),
          AppIcon(
            Icons.search_rounded,
            color:
                context.appComponents.libraryPresentation ==
                    AppLibraryPresentation.spacious
                ? context.appColors.accent
                : context.appColors.muted,
            size: context.appComponents.iconSize,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              key: const Key('delta-library-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: _scheduleSearch,
              style:
                  context.appComponents.libraryPresentation ==
                      AppLibraryPresentation.spacious
                  ? TextStyle(
                      fontSize: context.appComponents.bodySize,
                      height: context.appComponents.bodyHeight,
                    )
                  : const TextStyle(fontSize: 15, height: 1.25),
              decoration: InputDecoration(
                hintText: context.l10n.searchNotes,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              key: const Key('delta-library-clear-shelf-search'),
              tooltip: context.l10n.clear,
              onPressed: _clearSearch,
              icon: const AppIcon(Icons.close_rounded, size: 19),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    ),
  );

  Widget _buildSelectionHeader(BuildContext context) {
    final visibleNotes =
        context.appComponents.homeLayout == AppHomeLayout.editorialBoard
        ? _editorialNotes
        : _controller.notes;
    final visibleIds = visibleNotes.map((note) => note.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedNoteIds.contains);
    return SizedBox(
      key: const Key('delta-library-selection-header'),
      height: 72,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            key: const Key('delta-library-exit-selection'),
            tooltip: context.l10n.close,
            onPressed: _clearSelection,
            icon: const AppIcon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              context.l10n.selectedNoteCount(_selectedNoteIds.length),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            key: const Key('delta-library-select-all'),
            tooltip: allSelected
                ? context.l10n.deselectAll
                : context.l10n.selectAll,
            onPressed: _selectAll,
            icon: AppIcon(
              allSelected ? Icons.remove_done_rounded : Icons.checklist_rounded,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_controller.hasError && _controller.notes.isEmpty) {
      return _scrollableMessage(
        _LibraryMessage(
          icon: Icons.error_outline_rounded,
          title: context.l10n.localStorageInitializationFailed,
          actionLabel: context.l10n.retry,
          onAction: () => unawaited(_controller.refresh()),
        ),
      );
    }
    if (!_controller.isLoading && _controller.notes.isEmpty) {
      final searching = _controller.query.isNotEmpty;
      return _scrollableMessage(
        _LibraryMessage(
          icon: searching ? Icons.search_off_rounded : Icons.note_add_outlined,
          title: searching
              ? context.l10n.noMatchingNotes
              : _controller.privateSpace
              ? context.l10n.emptyPrivateNotes
              : context.l10n.emptyActive,
          description: searching
              ? null
              : _controller.privateSpace
              ? context.l10n.emptyPrivateNotesHint
              : context.l10n.createNoteEmptyHint,
          actionLabel: searching ? context.l10n.clear : null,
          onAction: searching ? _clearSearch : null,
        ),
      );
    }
    final list = ListView.separated(
      key: const Key('delta-library-list'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      itemCount: _controller.notes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final note = _controller.notes[index];
        final imageAsset = _preferredImageAsset(note);
        return _MinimalNoteTile(
          key: ValueKey('delta-library-note-${note.id.value}'),
          note: note,
          thumbnail: imageAsset == null ? null : _resolveThumbnail(imageAsset),
          hasImage: imageAsset != null,
          busy: _controller.isBusy(note.id),
          selected: _selectedNoteIds.contains(note.id),
          selectionMode: _selectionMode,
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(note);
            } else {
              unawaited(_openEditor(note));
            }
          },
          onLongPress: () => _toggleSelection(note),
        );
      },
    );
    // The home pull gesture is a private-space entrance, not a refresh action.
    return widget.onOpenPrivateNotes != null
        ? list
        : RefreshIndicator(
            onRefresh: _controller.refresh,
            color: context.appColors.ink,
            child: list,
          );
  }

  Widget _scrollableMessage(Widget message) => LayoutBuilder(
    builder: (_, constraints) => ListView(
      key: const Key('delta-library-empty-list'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: message,
        ),
      ],
    ),
  );

  NoteAsset? _preferredImageAsset(Note note) {
    final coverId = note.coverAttachmentId;
    if (coverId != null) {
      final cover = note.assetsById[coverId];
      if (cover?.kind == NoteAssetKind.image) return cover;
    }
    for (final asset in note.assets) {
      if (asset.kind == NoteAssetKind.image) return asset;
    }
    return null;
  }

  ImageProvider? _resolveThumbnail(NoteAsset asset) {
    final customResolver = widget.resolveImage;
    if (customResolver != null) return customResolver(asset);
    if (FileStorageService.instance.baseDirOrNull == null) return null;
    final storageKey = asset.previewStorageKey ?? asset.storageKey;
    try {
      return FileImage(
        File(FileStorageService.instance.absolutePath(storageKey)),
      );
    } on Object {
      return null;
    }
  }

  Widget _buildBottomActions(BuildContext context) => AppBottomDock(
    key: const Key('delta-library-action-dock'),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _BottomIconAction(
            key: const Key('delta-library-open-calendar'),
            icon: Icons.calendar_month_outlined,
            label: context.l10n.calendar,
            onPressed: widget.onOpenCalendar == null
                ? null
                : () => unawaited(
                    _openLibraryDestination(widget.onOpenCalendar!),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height:
                  context.appComponents.libraryPresentation ==
                          AppLibraryPresentation.spacious &&
                      MediaQuery.textScalerOf(context).scale(14) > 20
                  ? context.appComponents.largeTextButtonHeight
                  : context.appComponents.buttonHeight,
              child: AppPrimaryButton(
                key: const Key('quill-home-new-note'),
                onPressed: widget.onCreateNote,
                icon: const AppIcon(Icons.add_rounded, size: 23),
                label: Text(
                  _controller.privateSpace
                      ? context.l10n.newPrivateNote
                      : context.l10n.newNote,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _BottomIconAction(
            key: const Key('quill-home-assistant'),
            icon: Icons.auto_awesome_outlined,
            label: context.l10n.localAssistant,
            onPressed: widget.onOpenAssistant,
          ),
        ],
      ),
    ),
  );

  Widget _buildSelectionActions(BuildContext context) {
    final notes = _selectedNotes;
    final allPinned = notes.isNotEmpty && notes.every((note) => note.isPinned);
    return AppBottomDock(
      key: const Key('delta-library-selection-actions'),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: AppBottomDock.floatingContentHeight,
          child: Row(
            children: [
              if (widget.onChangePrivacy != null)
                _SelectionAction(
                  key: const Key('delta-library-privacy-selected'),
                  icon: _controller.privateSpace
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  label: _controller.privateSpace
                      ? context.l10n.makeNotesPublic
                      : context.l10n.makeNotesPrivate,
                  onPressed: notes.isEmpty || _selectionBusy
                      ? null
                      : () => unawaited(_changeSelectedPrivacy()),
                ),
              _SelectionAction(
                key: const Key('delta-library-pin-selected'),
                icon: Icons.push_pin_outlined,
                label: allPinned ? context.l10n.unpin : context.l10n.pin,
                onPressed: notes.isEmpty || _selectionBusy
                    ? null
                    : () => unawaited(_setSelectedPinned()),
              ),
              _SelectionAction(
                key: const Key('delta-library-delete-selected'),
                icon: Icons.delete_outline_rounded,
                label: context.l10n.delete,
                foregroundColor: context.appColors.danger,
                onPressed: notes.isEmpty || _selectionBusy
                    ? null
                    : () => unawaited(_deleteSelected()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _scrollController.dispose();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    if (widget.materialController == null) _materials.dispose();
    super.dispose();
  }
}

final class _MinimalNoteTile extends StatelessWidget {
  const _MinimalNoteTile({
    required this.note,
    required this.thumbnail,
    required this.hasImage,
    required this.busy,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final Note note;
  final ImageProvider? thumbnail;
  final bool hasImage;
  final bool busy;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final projection = note.overviewText;
    return Material(
      key: ValueKey('delta-note-${note.id.value}'),
      color: selected ? context.appColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(context.appRadii.small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('delta-note-record-${note.id.value}'),
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (note.isPinned) ...[
                          AppIcon(
                            Icons.push_pin_outlined,
                            size: 14,
                            color: context.appColors.muted,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            note.title.trim().isEmpty
                                ? context.l10n.untitled
                                : note.title.trim(),
                            maxLines:
                                context.appComponents.libraryPresentation ==
                                    AppLibraryPresentation.spacious
                                ? 2
                                : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.ink,
                              fontSize: context.appComponents.itemTitleSize,
                              height: context.appComponents.itemTitleHeight,
                              fontWeight:
                                  context.appComponents.libraryPresentation ==
                                      AppLibraryPresentation.spacious
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (projection.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        projection,
                        key: ValueKey('delta-note-preview-${note.id.value}'),
                        maxLines:
                            context.appComponents.libraryPresentation ==
                                AppLibraryPresentation.spacious
                            ? 3
                            : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: context.appComponents.bodySize,
                          height:
                              context.appComponents.libraryPresentation ==
                                  AppLibraryPresentation.spacious
                              ? context.appComponents.bodyHeight
                              : 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _NoteMetadata(note: note),
                  ],
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 14),
                _NoteThumbnail(noteId: note.id, image: thumbnail),
              ],
              if (selectionMode || busy) ...[
                const SizedBox(width: 14),
                if (busy)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  AppIcon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 24,
                    color: selected
                        ? context.appColors.ink
                        : context.appColors.subtle,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _NoteMetadata extends StatefulWidget {
  const _NoteMetadata({required this.note});

  final Note note;

  @override
  State<_NoteMetadata> createState() => _NoteMetadataState();
}

final class _NoteMetadataState extends State<_NoteMetadata>
    with WidgetsBindingObserver {
  Timer? _deadlineTimer;
  Note get note => widget.note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchDeadline();
  }

  void _watchDeadline() {
    _deadlineTimer?.cancel();
    final remaining = note.reminderAt?.difference(DateTime.now());
    if (remaining == null || remaining <= Duration.zero) return;
    _deadlineTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_NoteMetadata oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.reminderAt != note.reminderAt) _watchDeadline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _watchDeadline();
    }
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingReminder = note.reminderAt?.isAfter(DateTime.now()) == true
        ? note.reminderAt
        : null;
    final visibleTags = note.tags.take(2).join(' · ');
    final hiddenTagCount = note.tags.length - 2;
    final tagLabel = hiddenTagCount > 0
        ? '$visibleTags +$hiddenTagCount'
        : visibleTags;
    return Row(
      children: [
        Flexible(
          child: Text(
            _formatNoteTime(context, note.updatedAt),
            key: ValueKey('delta-note-time-${note.id.value}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appColors.muted, fontSize: 12),
          ),
        ),
        _NoteAssetSignals(note: note),
        if (note.tags.isNotEmpty) ...[
          const SizedBox(width: 9),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  Icons.tag_rounded,
                  size: 13,
                  color: context.appColors.accent,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    tagLabel,
                    key: ValueKey('delta-note-tags-${note.id.value}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize:
                          context.appComponents.libraryPresentation ==
                              AppLibraryPresentation.spacious
                          ? context.appComponents.captionSize
                          : 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (pendingReminder case final time?) ...[
          const SizedBox(width: 9),
          Flexible(
            flex: 2,
            child: NoteReminderIndicator(
              key: ValueKey('delta-note-reminder-${note.id.value}'),
              at: time,
            ),
          ),
        ],
        if (note.tags.isEmpty && pendingReminder == null) const Spacer(),
      ],
    );
  }
}

final class _NoteThumbnail extends StatelessWidget {
  const _NoteThumbnail({required this.noteId, required this.image});

  final NoteId noteId;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: ValueKey('delta-note-thumbnail-${noteId.value}'),
    borderRadius: BorderRadius.circular(
      context.appComponents.libraryPresentation ==
              AppLibraryPresentation.spacious
          ? context.appRadii.medium
          : AppRadius.large,
    ),
    child: ColoredBox(
      color: context.appColors.surfaceMuted,
      child: SizedBox.square(
        dimension: 72,
        child: image == null
            ? AppIcon(
                Icons.image_outlined,
                color: context.appColors.subtle,
                size: 23,
              )
            : Image(
                image: ResizeImage.resizeIfNeeded(180, 180, image!),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => AppIcon(
                  Icons.broken_image_outlined,
                  color: context.appColors.subtle,
                  size: 22,
                ),
              ),
      ),
    ),
  );
}

final class _NoteAssetSignals extends StatelessWidget {
  const _NoteAssetSignals({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final kinds = note.assets.map((asset) => asset.kind).toSet();
    final signals = <(NoteAssetKind, IconData, String)>[
      if (kinds.contains(NoteAssetKind.audio))
        (NoteAssetKind.audio, Icons.graphic_eq_rounded, context.l10n.audio),
      if (kinds.contains(NoteAssetKind.video))
        (NoteAssetKind.video, Icons.videocam_outlined, context.l10n.video),
      if (kinds.contains(NoteAssetKind.file))
        (
          NoteAssetKind.file,
          Icons.description_outlined,
          context.l10n.attachments,
        ),
    ];
    if (signals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < signals.length; index++) ...[
            Tooltip(
              message: signals[index].$3,
              child: AppIcon(
                signals[index].$2,
                key: ValueKey(
                  'delta-note-${signals[index].$1.name}-${note.id.value}',
                ),
                size: 16,
                color: context.appColors.accent,
              ),
            ),
            if (index != signals.length - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

final class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => Expanded(
    child: SizedBox(
      height: 58,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor ?? context.appColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 23),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

final class _BottomIconAction extends StatelessWidget {
  const _BottomIconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(fixedSize: const Size.square(52)),
    icon: AppIcon(icon, size: 22),
  );
}

final class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, color: context.appColors.subtle, size: 30),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (description case final value?) ...[
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted, height: 1.5),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _formatNoteTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final locale = Localizations.localeOf(context).toLanguageTag();
  if (date == today) return DateFormat.Hm(locale).format(local);
  if (date == today.subtract(const Duration(days: 1))) {
    return context.l10n.yesterday;
  }
  if (local.year == now.year) return DateFormat.Md(locale).format(local);
  return DateFormat.yMd(locale).format(local);
}

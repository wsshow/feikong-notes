import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../models/library_file.dart';
import '../providers/file_library_controller.dart';
import '../services/file_library_actions.dart';
import '../services/file_library_store.dart';
import '../services/file_library_picker.dart';
import '../services/library_file_note_service.dart';
import 'note_quill_editor_page.dart';
import '../theme/app_theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_overlay.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/library_file_icon.dart';
import '../widgets/library_file_grid_card.dart';
import '../widgets/sunny_growth_decoration.dart';
import 'file_preview_page.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({
    this.controller,
    this.pickFiles,
    this.previewBuilder,
    this.importOnOpen = false,
    this.onWriteNote,
    super.key,
  });
  final FileLibraryController? controller;
  final Future<List<XFile>> Function()? pickFiles;
  final bool importOnOpen;
  final Future<void> Function(List<LibraryFile>)? onWriteNote;
  final Widget Function(LibraryFile entry, FileLibraryStore store)?
  previewBuilder;
  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late final FileLibraryController _controller =
      widget.controller ?? FileLibraryController();
  late final FileLibraryActions _actions = FileLibraryActions(
    _controller.store,
  );
  final _search = TextEditingController();
  final _selected = <String>{};
  bool _selecting = false;
  bool _picking = false;
  bool _externalBusy = false;
  bool get _busy => _controller.busy || _picking || _externalBusy;
  List<LibraryFile> get _selection => _selected
      .map((id) => _controller.byId[id])
      .whereType<LibraryFile>()
      .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_controller.loading) await _controller.load();
    if (!mounted || !widget.importOnOpen || _controller.error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_import());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _search.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  String _locationName(FileLibraryLocation location) => switch (location) {
    FileLibraryLocation.files => context.l10n.fmAllFiles,
    FileLibraryLocation.recent => context.l10n.fmRecent,
    FileLibraryLocation.favorites => context.l10n.fmFavorites,
    FileLibraryLocation.trash => context.l10n.fmTrash,
  };

  void _navigate(FileLibraryLocation location, {String? folder}) {
    FocusManager.instance.primaryFocus?.unfocus();
    _search.clear();
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    _controller.navigate(location, folder: folder);
  }

  void _toggle(LibraryFile entry) {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selecting = true;
      if (!_selected.add(entry.id)) _selected.remove(entry.id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _selectAll() {
    final ids = _controller.visible.map((e) => e.id).toSet();
    setState(() {
      if (ids.every(_selected.contains)) {
        _selected.clear();
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _picking = true);
    try {
      final files =
          await (widget.pickFiles?.call() ??
              FileLibraryPicker.instance.pickFiles());
      if (!mounted) return;
      setState(() => _picking = false);
      _clearSelection();
      _search.clear();
      await _controller.importFiles(files);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorImport);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _open(LibraryFile entry) async {
    if (_selecting) {
      _toggle(entry);
      return;
    }
    if (_busy || _controller.location == FileLibraryLocation.trash) return;
    if (entry.isFolder) {
      _navigate(FileLibraryLocation.files, folder: entry.id);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_controller.opened(entry));
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.previewBuilder?.call(entry, _controller.store) ??
            FilePreviewPage(entry: entry, store: _controller.store),
      ),
    );
  }

  Future<void> _editName({LibraryFile? entry}) async {
    final name = await AppOverlay.inputSheet<String>(
      context: context,
      builder: (context) => _FileNameSheet(entry: entry),
    );
    if (name == null || !mounted) return;
    await _controller.run(() async {
      if (entry == null) {
        await _controller.store.createFolder(
          name,
          parentId: _controller.location == FileLibraryLocation.files
              ? _controller.folderId
              : null,
        );
      } else {
        await _controller.store.rename(entry.id, name);
      }
    });
  }

  Future<void> _transfer(
    List<LibraryFile> entries, {
    required bool copy,
  }) async {
    final result = await AppOverlay.bottomSheet<_FolderDestination>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FolderPicker(
        controller: _controller,
        ids: entries.map((e) => e.id).toSet(),
        copy: copy,
      ),
    );
    if (result == null || !mounted) return;
    if (await _controller.run(
          () => _controller.store.transfer(
            entries.map((e) => e.id).toSet(),
            result.id,
            copy: copy,
          ),
        ) &&
        mounted) {
      _clearSelection();
    }
  }

  Future<void> _trash(List<LibraryFile> entries) async {
    final ids = entries.map((e) => e.id).toSet();
    if (await _controller.run(() => _controller.store.trash(ids)) && mounted) {
      _clearSelection();
      AppFeedback.action(
        context,
        context.l10n.fmTrashed,
        actionLabel: context.l10n.fmUndo,
        onAction: () =>
            unawaited(_controller.run(() => _controller.store.restore(ids))),
      );
    }
  }

  Future<void> _deleteForever(List<LibraryFile> entries) async {
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.fmDeleteForever),
        content: Text(context.l10n.fmDeleteConfirm(entries.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.fmCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: context.appColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.fmDeleteForever),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (await _controller.run(
          () => _controller.store.deletePermanently(
            entries.map((e) => e.id).toSet(),
          ),
        ) &&
        mounted) {
      _clearSelection();
    }
  }

  Future<void> _writeNote(List<LibraryFile> entries) async {
    setState(() => _externalBusy = true);
    try {
      if (widget.onWriteNote != null) {
        await widget.onWriteNote!(entries);
      } else {
        final note = await LibraryFileNoteService(
          store: _controller.store,
        ).openOrCreateMany(entries);
        if (!mounted) return;
        await Navigator.of(context).push<NoteEditorRouteResult>(
          MaterialPageRoute(
            builder: (_) => NoteQuillEditorPage(initialNote: note),
          ),
        );
      }
      await _controller.load();
      if (mounted) _clearSelection();
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorOperation);
    } finally {
      if (mounted) setState(() => _externalBusy = false);
    }
  }

  Future<void> _action(String action, List<LibraryFile> entries) async {
    if (_busy || entries.isEmpty) return;
    switch (action) {
      case 'note':
        await _writeNote(entries);
      case 'rename':
        await _editName(entry: entries.single);
      case 'move':
        await _transfer(entries, copy: false);
      case 'copy':
        await _transfer(entries, copy: true);
      case 'favorite':
        await _controller.run(
          () => _controller.store.setFavorite(
            entries.map((e) => e.id).toSet(),
            !entries.every((e) => e.favorite),
          ),
        );
      case 'trash':
        await _trash(entries);
      case 'restore':
        if (await _controller.run(
              () => _controller.store.restore(entries.map((e) => e.id).toSet()),
            ) &&
            mounted) {
          _clearSelection();
        }
      case 'delete':
        await _deleteForever(entries);
      case 'details':
        _details(entries.single);
      case 'share' || 'save' || 'open':
        setState(() => _externalBusy = true);
        try {
          if (action == 'share') {
            final box = context.findRenderObject() as RenderBox?;
            await _actions.share(
              entries,
              origin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            );
          } else if (action == 'save') {
            if (await _actions.save(entries.single) && mounted) {
              AppFeedback.show(context, context.l10n.fmSaved);
            }
          } else if (!await _actions.openExternal(entries.single) && mounted) {
            AppFeedback.error(context, context.l10n.fmOpenFailed);
          }
        } catch (_) {
          if (mounted) {
            AppFeedback.error(
              context,
              action == 'open'
                  ? context.l10n.fmOpenFailed
                  : context.l10n.fmErrorOperation,
            );
          }
        } finally {
          if (mounted) setState(() => _externalBusy = false);
        }
    }
  }

  void _details(LibraryFile entry) {
    final l10n = context.l10n;
    final map = _controller.byId;
    final path = <String>[];
    var parent = map[entry.parentId];
    while (parent != null) {
      path.insert(0, parent.name);
      parent = map[parent.parentId];
    }
    final format = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm();
    AppOverlay.bottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.fmDetails,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.fmCancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const AppIcon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                child: LibraryFileIcon(
                  entry: entry,
                  size: 72,
                  filePath: entry.isFolder
                      ? null
                      : _controller.store.fileFor(entry).path,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                entry.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              for (final pair in [
                (
                  l10n.fmType,
                  entry.isFolder
                      ? l10n.fmFolder
                      : '${libraryKindLabel(l10n, entry.kind)}${entry.extension.isEmpty ? '' : ' · ${entry.extension.toUpperCase()}'}',
                ),
                (l10n.fmSize, formatFileSize(_controller.sizeOf(entry))),
                (l10n.fmLocation, '${l10n.fmAllFiles}/${path.join('/')}'),
                (l10n.fmCreated, format.format(entry.createdAt.toLocal())),
                (l10n.fmModified, format.format(entry.modifiedAt.toLocal())),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pair.$1,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(pair.$2),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<AppMenuAction<String>> _entryActions(LibraryFile entry) {
    final l10n = context.l10n;
    if (_controller.location == FileLibraryLocation.trash) {
      return [
        AppMenuAction(
          value: 'restore',
          label: l10n.fmRestore,
          icon: Icons.restore_rounded,
        ),
        AppMenuAction(
          value: 'details',
          label: l10n.fmDetails,
          icon: Icons.info_outline_rounded,
        ),
        AppMenuAction(
          value: 'delete',
          label: l10n.fmDeleteForever,
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ];
    }
    return [
      AppMenuAction(
        value: 'favorite',
        label: entry.favorite ? l10n.fmUnfavorite : l10n.fmFavorite,
        icon: Icons.star_outline_rounded,
      ),
      AppMenuAction(
        value: 'rename',
        label: l10n.fmRename,
        icon: Icons.edit_outlined,
      ),
      AppMenuAction(
        value: 'move',
        label: l10n.fmMove,
        icon: Icons.folder_open_rounded,
      ),
      AppMenuAction(
        value: 'copy',
        label: l10n.fmCopy,
        icon: Icons.content_copy_rounded,
      ),
      if (!entry.isFolder) ...[
        AppMenuAction(
          value: 'note',
          label: l10n.materialWrite,
          icon: Icons.edit_note_rounded,
        ),
        AppMenuAction(
          value: 'share',
          label: l10n.fmShare,
          icon: Icons.ios_share_rounded,
        ),
        AppMenuAction(
          value: 'save',
          label: l10n.fmExport,
          icon: Icons.download_outlined,
        ),
        AppMenuAction(
          value: 'open',
          label: l10n.fmOpenSystem,
          icon: Icons.north_east_rounded,
        ),
      ],
      AppMenuAction(
        value: 'details',
        label: l10n.fmDetails,
        icon: Icons.info_outline_rounded,
      ),
      AppMenuAction(
        value: 'trash',
        label: l10n.fmDelete,
        icon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    ];
  }

  bool _handleBack() {
    if (_selecting) {
      _clearSelection();
      return true;
    }
    if (_controller.query.isNotEmpty || _controller.filter != null) {
      _search.clear();
      _controller.search('');
      _controller.setFilter(null);
      return true;
    }
    if (_controller.folderId != null) {
      _navigate(
        FileLibraryLocation.files,
        folder: _controller.byId[_controller.folderId]?.parentId,
      );
      return true;
    }
    if (_controller.location != FileLibraryLocation.files) {
      _navigate(FileLibraryLocation.files);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final l10n = context.l10n;
      final colors = context.appColors;
      final visible = _controller.visible;
      final interceptedBack =
          _selecting ||
          _controller.folderId != null ||
          _controller.location != FileLibraryLocation.files ||
          _controller.query.isNotEmpty ||
          _controller.filter != null;
      final page = PopScope(
        canPop: !interceptedBack,
        onPopInvokedWithResult: (popped, result) {
          if (!popped) _handleBack();
        },
        child: Scaffold(
          key: const Key('file-manager-page'),
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: _selecting
                ? IconButton(
                    tooltip: l10n.fmCancel,
                    onPressed: _busy ? null : _clearSelection,
                    icon: const AppIcon(Icons.close_rounded),
                  )
                : BackButton(
                    key: const Key('file-manager-back'),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(context);
                    },
                  ),
            title: Text(
              _selecting ? l10n.fmSelected(_selected.length) : l10n.fmTitle,
            ),
            actions: _selecting
                ? [
                    IconButton(
                      tooltip: l10n.selectAll,
                      onPressed: _busy ? null : _selectAll,
                      icon: const AppIcon(Icons.select_all_rounded),
                    ),
                  ]
                : [
                    IconButton(
                      key: const Key('file-manager-import'),
                      tooltip: l10n.fmImport,
                      onPressed:
                          _busy ||
                              _controller.loading ||
                              _controller.error == 'load'
                          ? null
                          : _import,
                      icon: const AppIcon(Icons.add_rounded),
                    ),
                    AppAnchoredMenuButton<String>(
                      tooltip: l10n.fmMore,
                      icon: const AppIcon(Icons.more_horiz_rounded),
                      enabled:
                          !_busy &&
                          !_controller.loading &&
                          _controller.error != 'load',
                      actions: [
                        AppMenuAction(
                          value: 'folder',
                          label: l10n.fmNewFolder,
                          icon: Icons.create_new_folder_outlined,
                          enabled:
                              _controller.location == FileLibraryLocation.files,
                        ),
                        AppMenuAction(
                          value: 'select',
                          label: l10n.fmSelect,
                          icon: Icons.check_circle_outline_rounded,
                          enabled: visible.isNotEmpty,
                        ),
                        if (_controller.location == FileLibraryLocation.trash)
                          AppMenuAction(
                            value: 'empty',
                            label: l10n.fmEmptyTrash,
                            icon: Icons.delete_sweep_outlined,
                            destructive: true,
                            enabled: _controller.trashCount > 0,
                          ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'folder':
                            unawaited(_editName());
                          case 'select':
                            setState(() => _selecting = true);
                          case 'empty':
                            unawaited(
                              _deleteForever(
                                _controller.entries
                                    .where(
                                      (e) =>
                                          e.deletedAt != null &&
                                          !FileLibraryStore.isInTrashParent(
                                            e,
                                            _controller.byId,
                                          ),
                                    )
                                    .toList(),
                              ),
                            );
                        }
                      },
                    ),
                  ],
          ),
          body: SafeArea(
            bottom: false,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (!_selecting) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.fmSubtitle,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.fmLocalStorage(
                                  formatFileSize(_controller.totalBytes),
                                ),
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              for (final location in FileLibraryLocation.values)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    key: ValueKey(
                                      'file-location-${location.name}',
                                    ),
                                    label: Text(_locationName(location)),
                                    selected: _controller.location == location,
                                    onSelected: _busy
                                        ? null
                                        : (_) => _navigate(location),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: TextField(
                          key: const Key('file-manager-search'),
                          controller: _search,
                          onChanged: (value) {
                            _controller.search(value);
                            if (_selecting) _clearSelection();
                          },
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: InputDecoration(
                            hintText: l10n.fmSearch,
                            prefixIcon: const AppIcon(
                              Icons.search_rounded,
                              size: 20,
                            ),
                            suffixIcon: _controller.query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: l10n.fmCancel,
                                    icon: const AppIcon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _search.clear();
                                      _controller.search('');
                                    },
                                  ),
                            filled: true,
                            fillColor: colors.surfaceMuted,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(l10n.fmAllTypes),
                                selected: _controller.filter == null,
                                onSelected: (_) => _changeFilter(null),
                              ),
                            ),
                            for (final kind in LibraryFileKind.values.where(
                              (e) => e != LibraryFileKind.folder,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(libraryKindLabel(l10n, kind)),
                                  selected: _controller.filter == kind,
                                  onSelected: (_) => _changeFilter(
                                    _controller.filter == kind ? null : kind,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_controller.importName != null) _importProgress(),
                      if (_controller.busy && _controller.importName == null ||
                          _externalBusy)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_controller.error != null) _errorPanel(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        child: Row(
                          children: [
                            Expanded(child: _breadcrumbs()),
                            AppAnchoredMenuButton<FileLibrarySort>(
                              tooltip: l10n.fmSort,
                              icon: const AppIcon(Icons.sort_rounded, size: 20),
                              actions: [
                                for (final sort in FileLibrarySort.values)
                                  AppMenuAction(
                                    value: sort,
                                    label: switch (sort) {
                                      FileLibrarySort.name => l10n.fmSortName,
                                      FileLibrarySort.modified =>
                                        l10n.fmSortModified,
                                      FileLibrarySort.size => l10n.fmSortSize,
                                      FileLibrarySort.type => l10n.fmSortType,
                                    },
                                    selected: _controller.sort == sort,
                                  ),
                              ],
                              onSelected: _controller.setSort,
                            ),
                            IconButton(
                              tooltip: _controller.ascending
                                  ? l10n.fmAscending
                                  : l10n.fmDescending,
                              onPressed: () =>
                                  _controller.setSort(_controller.sort),
                              icon: RotatedBox(
                                quarterTurns: _controller.ascending ? 0 : 2,
                                child: const AppIcon(
                                  Icons.arrow_upward_rounded,
                                  size: 18,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('file-manager-view'),
                              tooltip: _controller.grid
                                  ? l10n.fmList
                                  : l10n.fmGrid,
                              onPressed: _controller.toggleGrid,
                              icon: AppIcon(
                                _controller.grid
                                    ? Icons.view_list_rounded
                                    : Icons.grid_view_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              body: _controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _controller.error == 'load'
                  ? const SizedBox.shrink()
                  : visible.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _busy ? () async {} : _controller.load,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (!_controller.grid) {
                            return ListView.separated(
                              key: const PageStorageKey('file-list'),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: visible.length,
                              separatorBuilder: (_, index) => Divider(
                                indent: 76,
                                endIndent: 12,
                                height: 1,
                                color: colors.line.withValues(alpha: .65),
                              ),
                              itemBuilder: (context, index) =>
                                  _tile(visible[index], grid: false),
                            );
                          }
                          final scale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          final columns =
                              (constraints.maxWidth / (scale > 1.5 ? 220 : 160))
                                  .floor()
                                  .clamp(1, 6);
                          return GridView.builder(
                            key: const PageStorageKey('file-grid'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  mainAxisExtent: LibraryFileGridCard.extentFor(
                                    (constraints.maxWidth -
                                            40 -
                                            (columns - 1) * 12) /
                                        columns,
                                    MediaQuery.textScalerOf(context),
                                  ),
                                ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _tile(visible[index], grid: true),
                          );
                        },
                      ),
                    ),
            ),
          ),
          bottomNavigationBar: _bottomBar(),
        ),
      );
      return AppThemeCanvas(child: page);
    },
  );

  void _changeFilter(LibraryFileKind? kind) {
    _clearSelection();
    _controller.setFilter(kind);
  }

  Widget _breadcrumbs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        TextButton(
          onPressed: _busy ? null : () => _navigate(_controller.location),
          child: Text(
            _locationName(_controller.location),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        for (final folder in _controller.breadcrumbs) ...[
          AppIcon(
            Icons.chevron_right_rounded,
            size: 14,
            color: context.appColors.subtle,
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _navigate(FileLibraryLocation.files, folder: folder.id),
            child: Text(folder.name, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ],
    ),
  );

  Widget _tile(LibraryFile entry, {required bool grid}) {
    final colors = context.appColors;
    final selected = _selected.contains(entry.id);
    final icon = LibraryFileIcon(
      entry: entry,
      filePath: entry.isFolder ? null : _controller.store.fileFor(entry).path,
      size: 48,
    );
    final subtitle = entry.isFolder
        ? context.l10n.fmItems(_controller.childrenOf(entry))
        : '${entry.extension.isEmpty ? '' : '${entry.extension.toUpperCase()} · '}${formatFileSize(entry.size)}';
    final menu = _selecting
        ? SizedBox(
            width: 48,
            height: 48,
            child: AppIcon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? colors.accent : colors.subtle,
              size: 22,
            ),
          )
        : AppAnchoredMenuButton<String>(
            tooltip: context.l10n.fmMore,
            enabled: !_busy,
            actions: _entryActions(entry),
            onSelected: (action) => _action(action, [entry]),
            icon: const AppIcon(Icons.more_horiz_rounded, size: 20),
          );
    void open() {
      if (_controller.location == FileLibraryLocation.trash && !_selecting) {
        _toggle(entry);
      } else {
        unawaited(_open(entry));
      }
    }

    if (grid) {
      return LibraryFileGridCard(
        entry: entry,
        subtitle: subtitle,
        trailing: menu,
        selected: selected,
        selecting: _selecting,
        filePath: entry.isFolder ? null : _controller.store.fileFor(entry).path,
        onTap: _busy ? null : open,
        onLongPress: _busy ? null : () => _toggle(entry),
      );
    }
    final title = Row(
      children: [
        Expanded(
          child: Text(
            entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        if (entry.favorite)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: AppIcon(
              Icons.star_outline_rounded,
              size: 14,
              color: colors.warning,
            ),
          ),
      ],
    );
    return Semantics(
      selected: _selecting ? selected : null,
      child: Material(
        key: ValueKey('library-file-${entry.id}'),
        color: selected ? colors.accentSoft : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : open,
          onLongPress: _busy ? null : () => _toggle(entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat.yMMMd(
                          Localizations.localeOf(context).toLanguageTag(),
                        ).format(
                          (_controller.location == FileLibraryLocation.trash
                                  ? entry.deletedAt!
                                  : entry.modifiedAt)
                              .toLocal(),
                        ),
                        style: TextStyle(fontSize: 11, color: colors.subtle),
                      ),
                    ],
                  ),
                ),
                menu,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final l10n = context.l10n;
    final searching =
        _controller.query.isNotEmpty || _controller.filter != null;
    final title = searching
        ? l10n.fmNoResults
        : switch (_controller.location) {
            FileLibraryLocation.recent => l10n.fmNoRecent,
            FileLibraryLocation.favorites => l10n.fmNoFavorites,
            FileLibraryLocation.trash => l10n.fmTrashEmpty,
            FileLibraryLocation.files =>
              _controller.folderId == null
                  ? l10n.fmEmptyTitle
                  : l10n.fmFolderEmpty,
          };
    final description = searching
        ? l10n.fmNoResultsBody
        : switch (_controller.location) {
            FileLibraryLocation.recent => l10n.fmNoRecentBody,
            FileLibraryLocation.favorites => l10n.fmNoFavoritesBody,
            FileLibraryLocation.trash => l10n.fmTrashHint,
            FileLibraryLocation.files => l10n.fmEmptyBody,
          };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.appColors.surfaceMuted,
                borderRadius: BorderRadius.circular(28),
              ),
              child: AppIcon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.folder_open_rounded,
                size: 42,
                color: context.appColors.subtle,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appColors.muted,
                height: 1.6,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _importProgress() => Container(
    margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.appColors.accentSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.fmImporting(
                  _controller.imported + 1,
                  _controller.importTotal,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.fmImportCancelled,
              onPressed: _controller.cancelImport,
              icon: const AppIcon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        Text(
          _controller.importName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: _controller.importFileBytes == 0
              ? null
              : (_controller.importBytes / _controller.importFileBytes).clamp(
                  0,
                  1,
                ),
        ),
        const SizedBox(height: 6),
        Text(
          '${formatFileSize(_controller.importBytes)} / ${formatFileSize(_controller.importFileBytes)}',
          style: TextStyle(color: context.appColors.muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _errorPanel() {
    final l10n = context.l10n;
    final message = switch (_controller.error) {
      'load' || 'corrupt' => l10n.fmErrorLoad,
      'name' => l10n.fmErrorName,
      'exists' => l10n.fmErrorExists,
      'destination' => l10n.fmErrorDestination,
      'cycle' => l10n.fmErrorCycle,
      'import' => l10n.fmErrorImport,
      _ => l10n.fmErrorOperation,
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.appColors.danger, fontSize: 13),
            ),
          ),
          if (_controller.error == 'load')
            TextButton(onPressed: _controller.load, child: Text(l10n.fmRetry))
          else
            IconButton(
              tooltip: l10n.fmCancel,
              onPressed: () => setState(() => _controller.error = null),
              icon: const AppIcon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.canvas,
        border: Border(
          top: BorderSide(color: context.appColors.line.withValues(alpha: .6)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: _selecting
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_controller.location == FileLibraryLocation.trash) ...[
                      _batchButton(
                        l10n.fmRestore,
                        Icons.restore_rounded,
                        'restore',
                      ),
                      _batchButton(
                        l10n.fmDeleteForever,
                        Icons.delete_outline_rounded,
                        'delete',
                        danger: true,
                      ),
                    ] else ...[
                      if (_selection.isNotEmpty &&
                          _selection.every((e) => !e.isFolder))
                        _batchButton(
                          l10n.materialWrite,
                          Icons.edit_note_rounded,
                          'note',
                        ),
                      _batchButton(
                        l10n.fmMove,
                        Icons.folder_open_rounded,
                        'move',
                      ),
                      _batchButton(
                        l10n.fmCopy,
                        Icons.content_copy_rounded,
                        'copy',
                      ),
                      _batchButton(
                        l10n.fmFavorite,
                        Icons.star_outline_rounded,
                        'favorite',
                      ),
                      if (_selection.every((e) => !e.isFolder))
                        _batchButton(
                          l10n.fmShare,
                          Icons.ios_share_rounded,
                          'share',
                        ),
                      _batchButton(
                        l10n.fmDelete,
                        Icons.delete_outline_rounded,
                        'trash',
                        danger: true,
                      ),
                    ],
                  ],
                ),
              )
            : _controller.location == FileLibraryLocation.trash
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.fmTrashHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.muted,
                  ),
                ),
              )
            : Row(
                children: [
                  IconButton(
                    tooltip: l10n.fmNewFolder,
                    onPressed:
                        _busy ||
                            _controller.loading ||
                            _controller.error == 'load'
                        ? null
                        : _editName,
                    icon: const AppIcon(Icons.create_new_folder_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('file-manager-import-button'),
                      onPressed:
                          _busy ||
                              _controller.loading ||
                              _controller.error == 'load'
                          ? null
                          : _import,
                      icon: const AppIcon(Icons.add_rounded, size: 20),
                      label: Text(l10n.fmImport),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _batchButton(
    String label,
    IconData icon,
    String action, {
    bool danger = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TextButton.icon(
      onPressed: _busy || _selected.isEmpty
          ? null
          : () => _action(action, _selection),
      icon: AppIcon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: danger
            ? context.appColors.danger
            : context.appColors.accent,
      ),
    ),
  );
}

class _FileNameSheet extends StatefulWidget {
  const _FileNameSheet({this.entry});
  final LibraryFile? entry;
  @override
  State<_FileNameSheet> createState() => _FileNameSheetState();
}

class _FileNameSheetState extends State<_FileNameSheet> {
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final name = FileLibraryStore.validateName(_name.text);
      Navigator.pop(context, name);
    } on FileLibraryException {
      setState(() => _error = context.l10n.fmErrorName);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.entry == null
                  ? context.l10n.fmNewFolder
                  : context.l10n.fmRename,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('file-name-input'),
              controller: _name,
              autofocus: true,
              maxLength: 240,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: context.l10n.fmName,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.fmCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(
                      widget.entry == null
                          ? context.l10n.fmCreate
                          : context.l10n.fmConfirm,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _FolderDestination {
  const _FolderDestination(this.id);
  final String? id;
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({
    required this.controller,
    required this.ids,
    required this.copy,
  });
  final FileLibraryController controller;
  final Set<String> ids;
  final bool copy;
  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  String? _folder;
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final excluded = FileLibraryStore.descendants(
      widget.ids,
      controller.entries,
    );
    final folders =
        controller.entries
            .where(
              (e) =>
                  e.isFolder &&
                  e.parentId == _folder &&
                  !controller.isTrashed(e) &&
                  !excluded.contains(e.id),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final l10n = context.l10n;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.copy ? l10n.fmCopy : l10n.fmMove,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.fmCancel,
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (_folder != null)
                IconButton(
                  tooltip: l10n.fmAllFiles,
                  onPressed: () => setState(
                    () => _folder = controller.byId[_folder]?.parentId,
                  ),
                  icon: const AppIcon(Icons.arrow_back_rounded),
                ),
              TextButton(
                onPressed: () => setState(() => _folder = null),
                child: Text(l10n.fmAllFiles),
              ),
              if (_folder != null) ...[
                const AppIcon(Icons.chevron_right_rounded, size: 16),
                Expanded(
                  child: Text(
                    controller.byId[_folder]?.name ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          Expanded(
            child: folders.isEmpty
                ? Center(
                    child: Text(
                      l10n.fmFolderEmpty,
                      style: TextStyle(color: context.appColors.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        leading: const AppIcon(Icons.folder_open_rounded),
                        title: Text(folder.name),
                        trailing: const AppIcon(Icons.chevron_right_rounded),
                        onTap: () => setState(() => _folder = folder.id),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _FolderDestination(_folder)),
                child: Text(widget.copy ? l10n.fmCopyHere : l10n.fmMoveHere),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

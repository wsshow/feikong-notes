import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/library_file.dart';
import '../providers/editorial_material_controller.dart';
import '../services/editorial_material_preferences.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'editorial_paper_surface.dart';
import 'library_file_icon.dart';

String materialLayoutLabel(
  AppLocalizations l10n,
  EditorialMaterialLayout layout,
) => switch (layout) {
  EditorialMaterialLayout.recent => l10n.materialRecent,
  EditorialMaterialLayout.favorites => l10n.materialFavorites,
  EditorialMaterialLayout.images => l10n.materialImages,
  EditorialMaterialLayout.continueNotes => l10n.materialContinue,
  EditorialMaterialLayout.categories => l10n.materialCategories,
};

/// Warm paper, serif file titles and coral ink extend the existing journal.
/// File content leads; two quiet backing sheets establish the spatial model.
/// The top sheet slides away to uncover the actual next sheet underneath.
/// A new drag interrupts the spring at its actual position.
class EditorialMaterialDeck extends StatefulWidget {
  const EditorialMaterialDeck({
    required this.controller,
    required this.onOpenFile,
    required this.onWriteNote,
    required this.onOpenLibrary,
    required this.onChooseFavorites,
    this.busyFileId,
    super.key,
  });
  final EditorialMaterialController controller;
  final ValueChanged<LibraryFile> onOpenFile;
  final ValueChanged<LibraryFile> onWriteNote;
  final void Function(LibraryFileKind? filter, bool import) onOpenLibrary;
  final VoidCallback onChooseFavorites;
  final String? busyFileId;

  @override
  State<EditorialMaterialDeck> createState() => _EditorialMaterialDeckState();
}

class _EditorialMaterialDeckState extends State<EditorialMaterialDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  late int _index = widget.controller.layout.index;
  int _previewStep = 1;
  int _settleRevision = 0;
  double _width = 1;
  bool _interacted = false;
  bool _dragging = false;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);
  int _neighbor(int step) =>
      (_index + step) % EditorialMaterialLayout.values.length;

  @override
  void initState() {
    super.initState();
    if (widget.controller.loading) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await widget.controller.initialize();
    if (!mounted || _interacted) return;
    setState(() => _index = widget.controller.layout.index);
  }

  // Stopping preserves the current position. A new finger owns the same card,
  // including while it is springing home or leaving the stack.
  void _interrupt() {
    _settleRevision++;
    _offset.stop();
    _interacted = true;
  }

  void _drag(DragUpdateDetails details) {
    final value = (_offset.value + details.delta.dx).clamp(
      -_width * 1.4,
      _width * 1.4,
    );
    final step = value < 0 ? 1 : -1;
    if (step != _previewStep && value.abs() > .5) {
      setState(() => _previewStep = step);
    }
    _offset.value = value;
  }

  Future<void> _settle(double velocity, {bool cancelled = false}) async {
    final commit =
        !cancelled &&
        (_offset.value.abs() > _width * .24 || velocity.abs() > 650);
    final sign = velocity.abs() > 650 ? velocity.sign : _offset.value.sign;
    final step = sign < 0 ? 1 : -1;
    if (commit && step != _previewStep) {
      setState(() => _previewStep = step);
    }
    final revision = ++_settleRevision;
    final target = commit ? sign * _width * 1.25 : 0.0;
    if (!_reduce) {
      try {
        await _offset
            .animateWith(
              _CardSlideSpring(
                _offset.value,
                target,
                velocity,
                exitDistance: commit ? _width * 1.18 : null,
              ),
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || revision != _settleRevision) return;
    if (commit) {
      _select(_neighbor(step));
    } else {
      _offset.value = 0;
    }
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _previewStep = 1;
      _offset.value = 0;
    });
    widget.controller.select(EditorialMaterialLayout.values[index]);
  }

  void _go(int step) {
    _interrupt();
    _select(_neighbor(step));
  }

  String _pageValue(int index) => context.l10n.materialPage(
    materialLayoutLabel(context.l10n, EditorialMaterialLayout.values[index]),
    index + 1,
    EditorialMaterialLayout.values.length,
  );

  @override
  void dispose() {
    _settleRevision++;
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final colors = context.appColors;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return Padding(
        key: const Key('editorial-material-deck'),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            final height =
                228 +
                math.max(0, scale - 1) * 120 +
                (constraints.maxWidth < 300 ? 16 : 0);
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                    _go(-1),
                const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                    _go(1),
              },
              child: Focus(
                child: Semantics(
                  value: _pageValue(_index),
                  increasedValue: _pageValue(_neighbor(1)),
                  decreasedValue: _pageValue(_neighbor(-1)),
                  onIncrease: () => _go(1),
                  onDecrease: () => _go(-1),
                  child: Column(
                    children: [
                      Listener(
                        onPointerDown: (_) {
                          _dragging = false;
                          _interrupt();
                        },
                        onPointerUp: (_) {
                          if (!_dragging && _offset.value.abs() > .5) {
                            unawaited(_settle(0));
                          }
                        },
                        child: GestureDetector(
                          key: const Key('editorial-material-stack'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) => _dragging = true,
                          onHorizontalDragUpdate: _drag,
                          onHorizontalDragEnd: (details) =>
                              unawaited(_settle(details.primaryVelocity ?? 0)),
                          onHorizontalDragCancel: () =>
                              unawaited(_settle(0, cancelled: true)),
                          child: SizedBox(
                            height: height + 12,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  bottom: 12,
                                  child: Transform.translate(
                                    offset: const Offset(0, 14),
                                    child: Transform.scale(
                                      scale: .94,
                                      child: EditorialPaperSurface(
                                        color: colors.surfaceMuted,
                                        borderColor: colors.decoration
                                            .withValues(alpha: .4),
                                        radius: 24,
                                        depth: EditorialSurfaceDepth.lifted,
                                        textureOpacity: .16,
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  bottom: 12,
                                  child: ExcludeSemantics(
                                    child: ExcludeFocus(
                                      child: IgnorePointer(
                                        child: AnimatedBuilder(
                                          animation: _offset,
                                          child: RepaintBoundary(
                                            child: _face(
                                              EditorialMaterialLayout
                                                  .values[_neighbor(
                                                _previewStep,
                                              )],
                                            ),
                                          ),
                                          builder: (context, child) {
                                            final progress =
                                                (_offset.value.abs() / _width)
                                                    .clamp(0.0, 1.0);
                                            return Transform.translate(
                                              key: const Key(
                                                'material-card-underneath',
                                              ),
                                              offset: Offset(
                                                0,
                                                8 * (1 - progress),
                                              ),
                                              child: Transform.scale(
                                                scale: _reduce
                                                    ? .975
                                                    : .975 + .025 * progress,
                                                child: child,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  bottom: 12,
                                  child: AnimatedBuilder(
                                    animation: _offset,
                                    child: RepaintBoundary(
                                      child: _face(
                                        EditorialMaterialLayout.values[_index],
                                      ),
                                    ),
                                    builder: (context, child) => IgnorePointer(
                                      ignoring: _offset.value.abs() > .5,
                                      child: Transform.translate(
                                        key: const Key('material-card-top'),
                                        offset: Offset(_offset.value, 0),
                                        child: Transform.rotate(
                                          key: const Key(
                                            'material-card-rotation',
                                          ),
                                          angle: _reduce
                                              ? 0
                                              : (_offset.value / _width).clamp(
                                                      -1.0,
                                                      1.0,
                                                    ) *
                                                    .06,
                                          alignment: Alignment.bottomCenter,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (widget.controller.preferenceFailed)
                        Text(
                          context.l10n.materialSavedLayoutFailed,
                          style: TextStyle(color: colors.warning, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );

  Widget _face(EditorialMaterialLayout layout) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final headerIcon = switch (layout) {
      EditorialMaterialLayout.recent => Icons.attach_file_rounded,
      EditorialMaterialLayout.favorites => Icons.star_outline_rounded,
      EditorialMaterialLayout.images => Icons.photo_library_outlined,
      EditorialMaterialLayout.continueNotes => Icons.edit_note_rounded,
      EditorialMaterialLayout.categories => Icons.folder_open_rounded,
    };
    return EditorialPaperSurface(
      key: ValueKey('editorial-material-${layout.name}'),
      color: colors.surface,
      radius: 24,
      depth: EditorialSurfaceDepth.raised,
      textureOpacity: .2,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppIcon(headerIcon, size: 18, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      materialLayoutLabel(l10n, layout),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .35,
                    ),
                    child: TextButton(
                      onPressed: () => widget.onOpenLibrary(null, false),
                      child: Text(
                        l10n.materialAllFiles,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: widget.controller.loading
                    ? Center(
                        child: Text(
                          l10n.materialLoading,
                          style: TextStyle(color: colors.muted),
                        ),
                      )
                    : widget.controller.failed
                    ? _loadError()
                    : switch (layout) {
                        EditorialMaterialLayout.recent => _recent(),
                        EditorialMaterialLayout.favorites => _favorites(),
                        EditorialMaterialLayout.images => _images(),
                        EditorialMaterialLayout.continueNotes => _continue(),
                        EditorialMaterialLayout.categories => _categories(),
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadError() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(context.l10n.materialLoadFailed, style: _headline),
      TextButton(
        onPressed: widget.controller.refresh,
        child: Text(context.l10n.fmRetry),
      ),
    ],
  );

  TextStyle get _headline => TextStyle(
    fontFamily: EditorialJournalTokens.serifFamily,
    fontFamilyFallback: EditorialJournalTokens.serifFallback,
    color: context.appColors.ink,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );
  Widget _empty(
    String title,
    String description,
    String action,
    VoidCallback onPressed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _headline,
            ),
            const SizedBox(height: 6),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onPressed, child: Text('$action  →')),
      ),
    ],
  );

  Widget _fileSummary(LibraryFile file, {bool note = false}) {
    final linked = widget.controller.linkedNotes[file.id];
    final title = note && linked != null && linked.title.trim().isNotEmpty
        ? linked.title
        : file.name;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => note ? widget.onWriteNote(file) : widget.onOpenFile(file),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            LibraryFileIcon(
              entry: file,
              filePath: widget.controller.store.fileFor(file).path,
              size: 58,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _headline,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    note
                        ? file.name
                        : '${file.extension.toUpperCase()} · ${formatFileSize(file.size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (!note)
                    Text(
                      linked != null
                          ? context.l10n.materialLinked
                          : file.openedAt != null
                          ? context.l10n.materialRecentlyOpened
                          : context.l10n.materialRecentlyImported,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _writeButton(LibraryFile file, {bool compact = false}) {
    final linked = widget.controller.linkedNotes.containsKey(file.id);
    final label = linked
        ? context.l10n.materialContinueNote
        : context.l10n.materialWrite;
    final busy = widget.busyFileId != null;
    final content = widget.busyFileId == file.id
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          );
    if (compact) {
      return TextButton(
        onPressed: busy ? null : () => widget.onWriteNote(file),
        child: content,
      );
    }
    return FilledButton(
      onPressed: busy ? null : () => widget.onWriteNote(file),
      child: content,
    );
  }

  Widget _recent() {
    final l10n = context.l10n;
    final file = widget.controller.recent.firstOrNull;
    if (file == null) {
      return _empty(
        l10n.materialEmptyRecentTitle,
        l10n.materialEmptyRecentBody,
        l10n.fmImport,
        () => widget.onOpenLibrary(null, true),
      );
    }
    return Column(
      children: [
        Expanded(child: Center(child: _fileSummary(file))),
        Divider(
          height: 8,
          color: context.appColors.line.withValues(alpha: .65),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => widget.onOpenFile(file),
                  child: Text(
                    l10n.materialPreview,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: _writeButton(file)),
          ],
        ),
      ],
    );
  }

  Widget _favorites() {
    final l10n = context.l10n;
    final files = widget.controller.favorites.take(2).toList();
    if (files.isEmpty) {
      return _empty(
        l10n.materialEmptyFavoritesTitle,
        l10n.materialEmptyFavoritesBody,
        l10n.materialPickFavorites,
        widget.onChooseFavorites,
      );
    }
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              for (final (index, file) in files.indexed) ...[
                if (index > 0)
                  Divider(
                    height: 8,
                    color: context.appColors.line.withValues(alpha: .65),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      LibraryFileIcon(
                        entry: file,
                        filePath: widget.controller.store.fileFor(file).path,
                        size: 38,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onOpenFile(file),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${file.extension.toUpperCase()} · ${formatFileSize(file.size)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .3,
                        ),
                        child: _writeButton(file, compact: true),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onChooseFavorites,
            child: Text(
              '${l10n.materialPickFavorites}  +',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _images() {
    final l10n = context.l10n;
    final files = widget.controller.images
        .take(MediaQuery.textScalerOf(context).scale(14) > 21 ? 2 : 3)
        .toList();
    if (files.isEmpty) {
      return _empty(
        l10n.materialEmptyImagesTitle,
        l10n.materialEmptyImagesBody,
        l10n.fmImport,
        () => widget.onOpenLibrary(LibraryFileKind.image, true),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (final (index, file) in files.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onOpenFile(file),
                          borderRadius: BorderRadius.circular(10),
                          child: LayoutBuilder(
                            builder: (context, size) => Center(
                              child: LibraryFileIcon(
                                entry: file,
                                filePath: widget.controller.store
                                    .fileFor(file)
                                    .path,
                                size: math.min(size.maxWidth, size.maxHeight),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _writeButton(file, compact: true),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => widget.onOpenLibrary(LibraryFileKind.image, false),
            child: Text(
              '${l10n.materialOpenImages}  →',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _continue() {
    final l10n = context.l10n;
    final file = widget.controller.continuing.firstOrNull;
    if (file == null) {
      return _empty(
        l10n.materialEmptyContinueTitle,
        l10n.materialEmptyContinueBody,
        l10n.materialPickFavorites,
        () => widget.onOpenLibrary(null, false),
      );
    }
    return Column(
      children: [
        Expanded(child: Center(child: _fileSummary(file, note: true))),
        Align(alignment: Alignment.centerRight, child: _writeButton(file)),
      ],
    );
  }

  Widget _categories() => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final large = MediaQuery.textScalerOf(context).scale(14) > 21;
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              crossAxisCount: 2,
              childAspectRatio: (bounds.maxWidth - 8) / (bounds.maxHeight - 8),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                for (final kind in [
                  LibraryFileKind.pdf,
                  LibraryFileKind.image,
                  LibraryFileKind.audio,
                  LibraryFileKind.video,
                ])
                  Material(
                    color: context.appColors.surfaceMuted.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onOpenLibrary(kind, false),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            if (!large) ...[
                              AppIcon(
                                libraryKindIcon(kind),
                                size: 20,
                                color: context.appColors.accent,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    libraryKindLabel(context.l10n, kind),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.fmItems(
                                      widget.controller.files
                                          .where((e) => e.kind == kind)
                                          .length,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.appColors.muted,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => widget.onOpenLibrary(null, false),
          child: Text(
            context.l10n.materialFileCount(widget.controller.files.length),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

/// Once an outgoing sheet clears the screen, the revealed sheet is usable.
/// Waiting for the invisible tail of its spring would leave it unresponsive.
class _CardSlideSpring extends SpringSimulation {
  _CardSlideSpring(
    double start,
    double end,
    double velocity, {
    this.exitDistance,
  }) : _sign = end.sign,
       super(
         const SpringDescription(mass: 1, stiffness: 100, damping: 10),
         start,
         end,
         velocity,
         tolerance: const Tolerance(distance: .5, velocity: 1),
       );

  final double? exitDistance;
  final double _sign;

  @override
  bool isDone(double time) =>
      (exitDistance != null && x(time) * _sign >= exitDistance!) ||
      super.isDone(time);
}

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../models/note.dart';
import '../../models/note_document.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/editorial_paper_surface.dart';
import '../../widgets/navigation_icons.dart';
import '../../widgets/privacy_pull_to_open.dart';
import '../../widgets/sunny_growth_decoration.dart';

typedef EditorialNoteImageResolver = ImageProvider? Function(Note note);
typedef EditorialNotePredicate = bool Function(Note note);
typedef EditorialNoteAction = void Function(Note note);

/// The complete note-library presentation owned by the Letters Unending theme.
///
/// It receives immutable note state and semantic actions from NoteLibraryPage;
/// database access, search, selection and navigation remain outside the theme.
final class EditorialNoteLibrarySurface extends StatelessWidget {
  const EditorialNoteLibrarySurface({
    required this.notes,
    required this.totalNoteCount,
    required this.availableTags,
    required this.activeTag,
    required this.query,
    required this.isLoading,
    required this.hasError,
    required this.privateSpace,
    required this.selectionMode,
    required this.selectionBusy,
    required this.searchController,
    required this.searchFocusNode,
    required this.scrollController,
    required this.selectionHeader,
    required this.selectionActions,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSelectTag,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenNote,
    required this.onToggleNote,
    required this.isBusy,
    required this.isSelected,
    required this.resolveImage,
    this.onCreateNote,
    this.materialDeck,
    this.onOpenCalendar,
    this.onOpenAssistant,
    this.onOpenTagGroups,
    this.onOpenFiles,
    this.onOpenSettings,
    this.onOpenPrivateNotes,
    this.onExitPrivateNotes,
    super.key,
  });

  final List<Note> notes;
  final int totalNoteCount;
  final List<String> availableTags;
  final String? activeTag;
  final String query;
  final bool isLoading;
  final bool hasError;
  final bool privateSpace;
  final bool selectionMode;
  final bool selectionBusy;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ScrollController scrollController;
  final Widget selectionHeader;
  final Widget selectionActions;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onSelectTag;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final EditorialNoteAction onOpenNote;
  final EditorialNoteAction onToggleNote;
  final EditorialNotePredicate isBusy;
  final EditorialNotePredicate isSelected;
  final EditorialNoteImageResolver resolveImage;
  final VoidCallback? onCreateNote;
  final Widget? materialDeck;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenAssistant;
  final VoidCallback? onOpenTagGroups;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenSettings;
  final Future<void> Function()? onOpenPrivateNotes;
  final VoidCallback? onExitPrivateNotes;

  @override
  Widget build(BuildContext context) {
    Widget scrollable = LayoutBuilder(
      key: const Key('editorial-library-width-layout'),
      builder: (context, constraints) => _buildScrollView(
        context,
        columns: constraints.maxWidth - 40 >= 700 ? 3 : 2,
      ),
    );
    if (onOpenPrivateNotes case final openPrivate?) {
      scrollable = PrivacyPullToOpen(
        enabled:
            !selectionMode &&
            !selectionBusy &&
            searchController.text.isEmpty &&
            !searchFocusNode.hasFocus,
        onOpen: openPrivate,
        child: scrollable,
      );
    } else {
      scrollable = RefreshIndicator(
        onRefresh: onRefresh,
        color: context.appColors.accent,
        child: scrollable,
      );
    }

    return Scaffold(
      key: const Key('editorial-library-surface'),
      extendBody: true,
      backgroundColor: context.appColors.canvas,
      body: AppThemeCanvas(
        child: SafeArea(
          bottom: false,
          child: selectionMode
              ? Column(
                  children: [
                    selectionHeader,
                    Expanded(child: scrollable),
                  ],
                )
              : scrollable,
        ),
      ),
      bottomNavigationBar: selectionMode
          ? selectionActions
          : _EditorialBottomDock(
              privateSpace: privateSpace,
              onCreateNote: onCreateNote,
              onOpenCalendar: onOpenCalendar,
              onOpenAssistant: onOpenAssistant,
            ),
    );
  }

  Widget _buildScrollView(BuildContext context, {required int columns}) {
    final topPadding = selectionMode ? 8.0 : 18.0;
    return CustomScrollView(
      key: const Key('editorial-library-scroll'),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: topPadding)),
        if (!selectionMode) ...[
          SliverToBoxAdapter(child: _buildHeader(context)),
          SliverToBoxAdapter(child: _buildSearch(context)),
          if (isLoading && notes.isEmpty)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (!privateSpace) ...[
            SliverToBoxAdapter(child: materialDeck ?? const SizedBox.shrink()),
            if (availableTags.isNotEmpty)
              SliverToBoxAdapter(child: _buildFilters(context)),
          ],
        ],
        SliverToBoxAdapter(child: _buildSectionHeader(context)),
        ..._buildContent(context, columns: columns),
        SliverPadding(
          key: const Key('editorial-library-scroll-clearance'),
          padding: EdgeInsets.only(
            bottom: 24 + AppBottomDock.floatingScrollClearance(context),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? l10n.editorialGreetingMorning
        : hour < 18
        ? l10n.editorialGreetingAfternoon
        : l10n.editorialGreetingEvening;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (privateSpace) ...[
                IconButton(
                  key: const Key('private-notes-back'),
                  tooltip: l10n.exitPrivateNotes,
                  onPressed: onExitPrivateNotes,
                  icon: const AppIcon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  privateSpace ? l10n.privateNotes : l10n.appTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: EditorialJournalTokens.serifFamily,
                    fontFamilyFallback: EditorialJournalTokens.serifFallback,
                    fontSize: 20,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
              if (!privateSpace && onOpenFiles != null)
                IconButton(
                  key: const Key('delta-library-open-files'),
                  tooltip: l10n.fmTitle,
                  onPressed: onOpenFiles,
                  icon: const AppIcon(Icons.folder_open_rounded),
                ),
              if (!privateSpace && onOpenTagGroups != null)
                IconButton(
                  key: const Key('delta-library-open-tag-groups'),
                  tooltip: l10n.tagGroups,
                  onPressed: onOpenTagGroups,
                  icon: const TagOutlineIcon(size: 24),
                ),
              if (!privateSpace)
                _EditorialAvatarButton(onPressed: onOpenSettings),
            ],
          ),
          const SizedBox(height: 24),
          if (privateSpace)
            Text(
              l10n.noteCountShort(totalNoteCount),
              style: TextStyle(color: context.appColors.muted, fontSize: 14),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) => Text(
                '$greeting\n${l10n.editorialGreetingQuestion}',
                style: TextStyle(
                  fontFamily: EditorialJournalTokens.serifFamily,
                  fontFamilyFallback: EditorialJournalTokens.serifFallback,
                  color: context.appColors.ink,
                  fontSize: constraints.maxWidth < 330 ? 32 : 38,
                  height: 1.23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.noteCountShort(totalNoteCount),
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Transform.rotate(
                  angle: -.08,
                  child: Container(
                    width: 64,
                    height: 3,
                    decoration: BoxDecoration(
                      color: EditorialJournalTokens.colorCoralDecoration,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
    child: EditorialPaperSurface(
      radius: 999,
      depth: EditorialSurfaceDepth.raised,
      textureOpacity: .13,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const SizedBox(width: 18),
              AppIcon(
                Icons.search_rounded,
                color: searchFocusNode.hasFocus
                    ? context.appColors.accent
                    : context.appColors.muted,
                size: 23,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('delta-library-search'),
                  controller: searchController,
                  focusNode: searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: onSearchChanged,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                  decoration: InputDecoration(
                    hintText: context.l10n.editorialSearchHint,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              if (searchController.text.isNotEmpty)
                IconButton(
                  key: const Key('delta-library-clear-shelf-search'),
                  tooltip: context.l10n.clear,
                  onPressed: onClearSearch,
                  icon: const AppIcon(Icons.close_rounded, size: 19),
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildFilters(BuildContext context) => SizedBox(
    height: 58,
    child: ListView(
      key: const Key('editorial-filter-scroll'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        _EditorialFilterChip(
          key: const Key('editorial-filter-all'),
          label: context.l10n.all,
          selected: activeTag == null,
          onSelected: () => onSelectTag(null),
        ),
        for (final (index, tag) in availableTags.indexed) ...[
          const SizedBox(width: 9),
          _EditorialFilterChip(
            key: ValueKey('editorial-filter-$tag'),
            label: tag,
            tone: index + 1,
            selected: activeTag == tag,
            onSelected: () => onSelectTag(tag),
          ),
        ],
      ],
    ),
  );

  Widget _buildSectionHeader(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, selectionMode ? 8 : 22, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.recentNotes,
            style: const TextStyle(
              fontFamily: EditorialJournalTokens.serifFamily,
              fontFamilyFallback: EditorialJournalTokens.serifFallback,
              fontSize: 23,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
        ),
        if (activeTag != null || query.isNotEmpty)
          TextButton(
            key: const Key('editorial-view-all'),
            onPressed: () => onSelectTag(null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.editorialViewAll),
                const SizedBox(width: 3),
                const AppIcon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    ),
  );

  List<Widget> _buildContent(BuildContext context, {required int columns}) {
    if (hasError && notes.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EditorialMessage(
            icon: Icons.error_outline_rounded,
            title: context.l10n.localStorageInitializationFailed,
            actionLabel: context.l10n.retry,
            onAction: onRetry,
          ),
        ),
      ];
    }
    if (!isLoading && notes.isEmpty) {
      final filtering = query.isNotEmpty || activeTag != null;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EditorialMessage(
            icon: filtering
                ? Icons.search_off_rounded
                : Icons.note_add_outlined,
            title: filtering
                ? context.l10n.noMatchingNotes
                : privateSpace
                ? context.l10n.emptyPrivateNotes
                : context.l10n.emptyActive,
            description: filtering
                ? null
                : privateSpace
                ? context.l10n.emptyPrivateNotesHint
                : context.l10n.createNoteEmptyHint,
            actionLabel: filtering
                ? context.l10n.clear
                : privateSpace
                ? null
                : context.l10n.newNote,
            onAction: filtering ? () => onSelectTag(null) : onCreateNote,
          ),
        ),
      ];
    }
    return [
      _EditorialNoteGrid(
        notes: notes,
        columns: columns,
        selectionMode: selectionMode,
        resolveImage: resolveImage,
        isBusy: isBusy,
        isSelected: isSelected,
        onOpenNote: onOpenNote,
        onToggleNote: onToggleNote,
      ),
    ];
  }
}

/// Keeps width-dependent masonry structure and presentation data stable while
/// the viewport's scroll constraints change on every frame.
final class _EditorialNoteGrid extends StatefulWidget {
  const _EditorialNoteGrid({
    required this.notes,
    required this.columns,
    required this.selectionMode,
    required this.resolveImage,
    required this.isBusy,
    required this.isSelected,
    required this.onOpenNote,
    required this.onToggleNote,
  });

  final List<Note> notes;
  final int columns;
  final bool selectionMode;
  final EditorialNoteImageResolver resolveImage;
  final EditorialNotePredicate isBusy;
  final EditorialNotePredicate isSelected;
  final EditorialNoteAction onOpenNote;
  final EditorialNoteAction onToggleNote;

  @override
  State<_EditorialNoteGrid> createState() => _EditorialNoteGridState();
}

final class _EditorialNoteGridState extends State<_EditorialNoteGrid> {
  static const _maxCachedCards = 256;
  final LinkedHashMap<NoteId, _EditorialCardViewData> _viewData =
      LinkedHashMap();
  String? _dateLocale;
  DateFormat? _dateFormat;

  @override
  void didUpdateWidget(covariant _EditorialNoteGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes)) {
      final activeIds = widget.notes.map((note) => note.id).toSet();
      _viewData.removeWhere((id, _) => !activeIds.contains(id));
    }
  }

  _EditorialCardViewData _dataFor(
    Note note,
    String locale,
    DateFormat dateFormat,
  ) {
    final cached = _viewData.remove(note.id);
    if (cached != null &&
        cached.document == note.document &&
        cached.updatedAt == note.updatedAt &&
        cached.locale == locale) {
      _viewData[note.id] = cached;
      return cached;
    }
    final data = _EditorialCardViewData(
      document: note.document,
      updatedAt: note.updatedAt,
      locale: locale,
      projection: _projection(note),
      date: dateFormat.format(note.updatedAt),
    );
    _viewData[note.id] = data;
    if (_viewData.length > _maxCachedCards) {
      _viewData.remove(_viewData.keys.first);
    }
    return data;
  }

  DateFormat _dateFormatFor(String locale) {
    if (_dateLocale != locale) {
      _dateLocale = locale;
      _dateFormat = DateFormat.Md(locale);
    }
    return _dateFormat!;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateFormat = _dateFormatFor(locale);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      sliver: SliverCrossAxisGroup(
        key: const Key('editorial-library-grid'),
        slivers: [
          for (var column = 0; column < widget.columns; column++)
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverPadding(
                padding: EdgeInsets.only(
                  left: column == 0 ? 0 : 6,
                  right: column == widget.columns - 1 ? 0 : 6,
                ),
                sliver: SliverList.separated(
                  itemCount:
                      (widget.notes.length - column + widget.columns - 1) ~/
                      widget.columns,
                  itemBuilder: (context, itemIndex) {
                    final index = itemIndex * widget.columns + column;
                    final note = widget.notes[index];
                    final data = _dataFor(note, locale, dateFormat);
                    return _EditorialNoteCard(
                      note: note,
                      index: index,
                      projection: data.projection,
                      date: data.date,
                      image: widget.resolveImage(note),
                      busy: widget.isBusy(note),
                      selected: widget.isSelected(note),
                      selectionMode: widget.selectionMode,
                      onTap: () => widget.selectionMode
                          ? widget.onToggleNote(note)
                          : widget.onOpenNote(note),
                      onLongPress: () => widget.onToggleNote(note),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _EditorialCardViewData {
  const _EditorialCardViewData({
    required this.document,
    required this.updatedAt,
    required this.locale,
    required this.projection,
    required this.date,
  });

  final NoteDocument document;
  final DateTime updatedAt;
  final String locale;
  final String projection;
  final String date;
}

final class _EditorialFilterChip extends StatelessWidget {
  const _EditorialFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.tone = 0,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final paperTone = switch (tone % 5) {
      1 => EditorialJournalTokens.colorButter.withValues(alpha: .78),
      2 => EditorialJournalTokens.colorSky.withValues(alpha: .88),
      3 => const Color(0xFFE2EADB),
      4 => context.appColors.accentSoft.withValues(alpha: .72),
      _ => context.appColors.surface,
    };
    return EditorialPaperSurface(
      color: selected ? context.appColors.primaryFill : paperTone,
      gradient: selected ? context.appColors.primaryGradient : null,
      borderColor: selected
          ? Colors.white.withValues(alpha: .74)
          : Color.alphaBlend(
              Colors.white.withValues(alpha: .38),
              context.appColors.line,
            ),
      radius: 999,
      depth: EditorialSurfaceDepth.lifted,
      textureOpacity: selected ? 0 : .11,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onSelected,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  strutStyle: const StrutStyle(
                    fontSize: 13,
                    height: 1,
                    forceStrutHeight: true,
                  ),
                  style: TextStyle(
                    color: selected ? Colors.white : context.appColors.ink,
                    fontSize: 13,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _EditorialNoteCard extends StatelessWidget {
  const _EditorialNoteCard({
    required this.note,
    required this.index,
    required this.projection,
    required this.date,
    required this.image,
    required this.busy,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final int index;
  final String projection;
  final String date;
  final ImageProvider? image;
  final bool busy;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isPhoto = image != null;
    final cobalt = !isPhoto && index % 5 == 0;
    final background = cobalt
        ? EditorialJournalTokens.colorCobalt
        : switch (index % 4) {
            2 => EditorialJournalTokens.colorButter,
            3 => EditorialJournalTokens.colorSky,
            _ => context.appColors.surface,
          };
    final foreground = selected
        ? context.appColors.ink
        : cobalt
        ? Colors.white
        : context.appColors.ink;
    final muted = selected
        ? context.appColors.muted
        : cobalt
        ? Colors.white.withValues(alpha: .76)
        : context.appColors.muted;
    final tabColor = switch (index % 3) {
      0 => EditorialJournalTokens.colorCoralDecoration,
      1 => EditorialJournalTokens.colorButter,
      _ => EditorialJournalTokens.colorCobalt,
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: index.isEven ? -5 : null,
          right: index.isOdd ? -5 : null,
          top: 30,
          child: Container(
            width: 9,
            height: 44,
            decoration: BoxDecoration(
              color: tabColor,
              borderRadius: BorderRadius.horizontal(
                left: index.isEven ? const Radius.circular(5) : Radius.zero,
                right: index.isOdd ? const Radius.circular(5) : Radius.zero,
              ),
            ),
          ),
        ),
        EditorialPaperSurface(
          key: ValueKey('delta-note-${note.id.value}'),
          color: selected ? context.appColors.accentSoft : background,
          borderColor: selected
              ? context.appColors.accent
              : isPhoto
              ? Colors.white.withValues(alpha: .78)
              : null,
          borderWidth: selected ? 2 : 1,
          radius: 20,
          depth: EditorialSurfaceDepth.raised,
          textureOpacity: isPhoto
              ? 0
              : cobalt
              ? .06
              : .14,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('delta-note-record-${note.id.value}'),
              onTap: busy ? null : onTap,
              onLongPress: busy ? null : onLongPress,
              child: isPhoto
                  ? AspectRatio(aspectRatio: 1.06, child: _buildPhoto(context))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 14, 13),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (index % 5 == 0 && !cobalt)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppIcon(
                                Icons.attach_file_rounded,
                                size: 16,
                                color: muted,
                              ),
                            ),
                          Padding(
                            padding: EdgeInsetsDirectional.only(
                              end: selectionMode || busy ? 28 : 0,
                            ),
                            child: Text(
                              note.title.trim().isEmpty
                                  ? context.l10n.untitled
                                  : note.title.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: EditorialJournalTokens.serifFamily,
                                fontFamilyFallback:
                                    EditorialJournalTokens.serifFallback,
                                color: foreground,
                                fontSize: 16,
                                height: 1.38,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (projection.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Text(
                              key: ValueKey(
                                'delta-note-preview-${note.id.value}',
                              ),
                              projection,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _EditorialCardMetadata(
                            note: note,
                            date: date,
                            foreground: muted,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        if (selectionMode || busy)
          Positioned(
            right: 9,
            top: 9,
            child: busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AppIcon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 24,
                    color: selected ? context.appColors.accent : Colors.white,
                  ),
          ),
      ],
    );
  }

  Widget _buildPhoto(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final decodeExtent = _thumbnailDecodeExtent(
        constraints.maxWidth,
        MediaQuery.devicePixelRatioOf(context),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: ResizeImage.resizeIfNeeded(
              decodeExtent,
              decodeExtent,
              image!,
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => ColoredBox(
              color: context.appColors.surfaceMuted,
              child: AppIcon(
                Icons.broken_image_outlined,
                color: context.appColors.subtle,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0xB8000000)],
                stops: [.25, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: selectionMode || busy ? 28 : 0,
                  ),
                  child: Text(
                    note.title.trim().isEmpty
                        ? context.l10n.untitled
                        : note.title.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: EditorialJournalTokens.serifFamily,
                      fontFamilyFallback: EditorialJournalTokens.serifFallback,
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 5)],
                    ),
                  ),
                ),
                const Spacer(),
                _EditorialCardMetadata(
                  note: note,
                  date: date,
                  foreground: Colors.white.withValues(alpha: .88),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  static int _thumbnailDecodeExtent(double width, double pixelRatio) {
    final requested = (width * pixelRatio).ceil();
    for (final extent in const [256, 384, 512, 640]) {
      if (requested <= extent) return extent;
    }
    return 640;
  }
}

final class _EditorialCardMetadata extends StatelessWidget {
  const _EditorialCardMetadata({
    required this.note,
    required this.date,
    required this.foreground,
  });

  final Note note;
  final String date;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    const metadataStyle = TextStyle(
      fontSize: 11,
      height: 1.25,
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          key: ValueKey('delta-note-time-${note.id.value}'),
          date,
          maxLines: 1,
          style: metadataStyle.copyWith(color: foreground),
        ),
        if (note.isPinned) ...[
          const SizedBox(width: 7),
          _EditorialCardStatus(
            key: ValueKey('delta-note-status-pinned-${note.id.value}'),
            icon: Icons.push_pin_outlined,
            label: context.l10n.pin,
            foreground: foreground,
            style: metadataStyle,
          ),
        ],
        if (note.tags.isNotEmpty) ...[
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              key: ValueKey('delta-note-tags-${note.id.value}'),
              note.tags.take(2).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metadataStyle.copyWith(color: foreground),
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }
}

final class _EditorialCardStatus extends StatelessWidget {
  const _EditorialCardStatus({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.style,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: AppIcon(icon, size: 11, color: foreground),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.clip,
    style: style.copyWith(color: foreground),
  );
}

final class _EditorialBottomDock extends StatelessWidget {
  const _EditorialBottomDock({
    required this.privateSpace,
    required this.onCreateNote,
    required this.onOpenCalendar,
    required this.onOpenAssistant,
  });

  final bool privateSpace;
  final VoidCallback? onCreateNote;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenAssistant;

  @override
  Widget build(BuildContext context) => AppBottomDock(
    key: const Key('delta-library-action-dock'),
    child: SizedBox(
      height: AppBottomDock.floatingContentHeight,
      child: Row(
        children: [
          _EditorialDockIconAction(
            key: const Key('delta-library-open-calendar'),
            tooltip: context.l10n.calendar,
            icon: Icons.calendar_month_outlined,
            onPressed: onOpenCalendar,
          ),
          const _EditorialDockDivider(
            key: Key('editorial-home-dock-divider-left'),
          ),
          Expanded(
            flex: 4,
            child: EditorialDockPrimaryAction(
              actionKey: const Key('quill-home-new-note'),
              label: privateSpace
                  ? context.l10n.newPrivateNote
                  : context.l10n.newNote,
              icon: Icons.add_rounded,
              onTap: onCreateNote,
            ),
          ),
          const _EditorialDockDivider(
            key: Key('editorial-home-dock-divider-right'),
          ),
          _EditorialDockIconAction(
            key: const Key('quill-home-assistant'),
            tooltip: context.l10n.localAssistant,
            icon: Icons.auto_awesome_outlined,
            onPressed: onOpenAssistant,
          ),
        ],
      ),
    ),
  );
}

final class _EditorialDockIconAction extends StatelessWidget {
  const _EditorialDockIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 3,
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: AppIcon(
            icon,
            size: 25,
            color: onPressed == null
                ? context.appColors.subtle
                : context.appColors.muted,
          ),
        ),
      ),
    ),
  );
}

final class _EditorialDockDivider extends StatelessWidget {
  const _EditorialDockDivider({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 1,
      height: 28,
      color: context.appColors.line.withValues(alpha: .62),
    ),
  );
}

final class _EditorialAvatarButton extends StatelessWidget {
  const _EditorialAvatarButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.settings,
    child: InkWell(
      key: const Key('delta-library-open-settings'),
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.appColors.surface, width: 2),
          boxShadow: context.appColors.lowShadows,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              EditorialJournalTokens.colorButter,
              EditorialJournalTokens.colorCoralDecoration,
              EditorialJournalTokens.colorCobalt,
            ],
          ),
        ),
        child: const Center(
          child: AppIcon(
            Icons.settings_outlined,
            color: Colors.white,
            size: 19,
          ),
        ),
      ),
    ),
  );
}

final class _EditorialMessage extends StatelessWidget {
  const _EditorialMessage({
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
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.appColors.line),
          boxShadow: context.appColors.lowShadows,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, color: context.appColors.decoration, size: 32),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (description case final value?) ...[
                const SizedBox(height: 7),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.muted, height: 1.5),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

final _projectionWhitespace = RegExp(r'\s+');

String _projection(Note note) {
  final lines = <String>[];
  var line = StringBuffer();
  var containsChecklist = false;

  void finishLine(Map<String, dynamic>? attributes) {
    final text = line.toString().replaceAll(_projectionWhitespace, ' ').trim();
    line = StringBuffer();
    if (text.isEmpty) return;
    final marker = switch (attributes?['list']) {
      'checked' => '☑ ',
      'unchecked' => '☐ ',
      _ => '',
    };
    containsChecklist = containsChecklist || marker.isNotEmpty;
    lines.add('$marker$text');
  }

  void appendText(String value, Map<String, dynamic>? attributes) {
    var start = 0;
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) != 10) continue;
      line.write(value.substring(start, index));
      finishLine(attributes);
      start = index + 1;
    }
    if (start < value.length) line.write(value.substring(start));
  }

  for (final operation in note.document.previewOperations(
    maxCharacters: 600,
    maxOperations: 48,
    maxEmbeds: 2,
  )) {
    final data = operation.data;
    if (data is String) {
      appendText(data, operation.attributes);
      continue;
    }
    final embed = NoteEmbed.parse(data);
    if (embed.kind == NoteEmbedKind.table) {
      appendText(embed.table!.plainTextPreview(600), null);
    }
  }
  finishLine(null);

  final text = lines.join(containsChecklist ? '\n' : ' ').trim();
  if (text.length <= 600) return text;
  var end = 600;
  if (_isHighSurrogate(text.codeUnitAt(end - 1)) &&
      _isLowSurrogate(text.codeUnitAt(end))) {
    end--;
  }
  return text.substring(0, end);
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

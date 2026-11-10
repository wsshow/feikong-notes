import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../providers/note_library_controller.dart';
import '../widgets/app_icon.dart';
import '../widgets/navigation_icons.dart';
import '../widgets/quiet_paper.dart';

typedef NoteTagGroupOpener = Future<void> Function(Note note);

final class NoteTagGroupsPage extends StatelessWidget {
  const NoteTagGroupsPage({
    required this.controller,
    required this.onOpenNote,
    super.key,
  });

  final NoteLibraryController controller;
  final NoteTagGroupOpener onOpenNote;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.canvas,
    appBar: AppBar(
      backgroundColor: context.appColors.canvas,
      surfaceTintColor: Colors.transparent,
      title: Text(context.l10n.tagGroups),
    ),
    body: PaperShell(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final groups = _buildGroups(context, controller.notes);
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.emptyActive,
                  style: TextStyle(color: context.appColors.muted),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                context.l10n.tagGroupsSubtitle,
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                key: const ValueKey('tag-groups-surface'),
                color: context.appColors.surface,
                elevation: context.appComponents.cardElevation,
                shadowColor: context.appColors.shadow.withValues(alpha: .12),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.appRadii.large),
                  side: context.appComponents.outlinesSurfaces
                      ? BorderSide(
                          color: context.appColors.line,
                          width: context.appComponents.surfaceBorderWidth,
                        )
                      : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var index = 0; index < groups.length; index++) ...[
                      _TagGroupSection(
                        key: ValueKey((
                          groups[index].label,
                          groups[index].untagged,
                        )),
                        group: groups[index],
                        onOpenNote: (note) async {
                          await onOpenNote(note);
                          await controller.refresh();
                        },
                      ),
                      if (index != groups.length - 1)
                        Divider(
                          height: 1,
                          thickness: context.appComponents.outlinesSurfaces
                              ? context.appComponents.surfaceBorderWidth
                              : .7,
                          color: context.appColors.line.withValues(alpha: .78),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  List<_TagNoteGroup> _buildGroups(BuildContext context, List<Note> notes) {
    final grouped = <String, List<Note>>{};
    final untagged = <Note>[];
    for (final note in notes) {
      final tags = note.tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet();
      if (tags.isEmpty) {
        untagged.add(note);
        continue;
      }
      for (final tag in tags) {
        grouped.putIfAbsent(tag, () => []).add(note);
      }
    }
    final labels = grouped.keys.toList()..sort();
    final groups = [
      for (final label in labels)
        _TagNoteGroup(label: label, notes: _sortNotes(grouped[label]!)),
    ];
    if (untagged.isNotEmpty) {
      groups.add(
        _TagNoteGroup(
          label: context.l10n.untaggedNotes,
          notes: _sortNotes(untagged),
          untagged: true,
        ),
      );
    }
    return groups;
  }

  List<Note> _sortNotes(List<Note> notes) => [...notes]
    ..sort((left, right) {
      if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
      return right.updatedAt.compareTo(left.updatedAt);
    });
}

final class _TagNoteGroup {
  const _TagNoteGroup({
    required this.label,
    required this.notes,
    this.untagged = false,
  });

  final String label;
  final List<Note> notes;
  final bool untagged;
}

final class _TagGroupSection extends StatefulWidget {
  const _TagGroupSection({
    required this.group,
    required this.onOpenNote,
    super.key,
  });

  final _TagNoteGroup group;
  final NoteTagGroupOpener onOpenNote;

  @override
  State<_TagGroupSection> createState() => _TagGroupSectionState();
}

final class _TagGroupSectionState extends State<_TagGroupSection> {
  bool _expanded = false;

  _TagNoteGroup get group => widget.group;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Semantics(
          button: true,
          toggled: _expanded,
          label:
              '${group.label}，${context.l10n.noteCountShort(group.notes.length)}',
          child: Ink(
            key: ValueKey('tag-group-header-${group.label}'),
            color: _expanded
                ? colors.accentSoft.withValues(
                    alpha: context.appComponents.usesPaperCraftDecoration
                        ? .24
                        : .4,
                  )
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('tag-group-${group.label}'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                child: Row(
                  children: [
                    _TagGroupIcon(
                      untagged: group.untagged,
                      expanded: _expanded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.noteCountShort(group.notes.length),
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: context.appComponents.captionSize,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(width: 5),
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: AppIcon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _expanded ? colors.accent : colors.muted,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          key: ValueKey('tag-group-expansion-${group.label}'),
          duration: const Duration(milliseconds: 220),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => ClipRect(
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            ),
          ),
          child: _expanded
              ? _TagNoteList(
                  key: ValueKey('tag-group-expanded-${group.label}'),
                  groupLabel: group.label,
                  notes: group.notes,
                  onOpenNote: widget.onOpenNote,
                )
              : SizedBox.shrink(
                  key: ValueKey('tag-group-collapsed-${group.label}'),
                ),
        ),
      ],
    );
  }
}

final class _TagGroupIcon extends StatelessWidget {
  const _TagGroupIcon({required this.untagged, required this.expanded});

  final bool untagged;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icon = TagOutlineIcon(
      color: untagged ? colors.muted : (expanded ? colors.accent : colors.ink),
      size: 20,
    );
    if (!context.appComponents.usesSunCloudDecoration) {
      return SizedBox.square(dimension: 24, child: Center(child: icon));
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: expanded ? colors.accentSoft : colors.surfaceMuted,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

final class _TagNoteList extends StatelessWidget {
  const _TagNoteList({
    required this.groupLabel,
    required this.notes,
    required this.onOpenNote,
    super.key,
  });

  final String groupLabel;
  final List<Note> notes;
  final NoteTagGroupOpener onOpenNote;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: ValueKey('tag-group-notes-$groupLabel'),
    color: context.appColors.surfaceMuted.withValues(
      alpha: context.appComponents.usesPaperCraftDecoration ? .38 : .62,
    ),
    child: Column(
      children: [
        for (var index = 0; index < notes.length; index++) ...[
          _TagNoteRow(
            groupLabel: groupLabel,
            note: notes[index],
            onTap: () => unawaited(onOpenNote(notes[index])),
          ),
          if (index != notes.length - 1)
            Divider(
              height: 1,
              indent: 48,
              endIndent: 12,
              color: context.appColors.line.withValues(alpha: .7),
            ),
        ],
      ],
    ),
  );
}

final class _TagNoteRow extends StatelessWidget {
  const _TagNoteRow({
    required this.groupLabel,
    required this.note,
    required this.onTap,
  });

  final String groupLabel;
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final summary = note.overviewTextWithAttachments;
    final time = _formatNoteTime(context, note.updatedAt);
    return InkWell(
      key: ValueKey('tag-note-$groupLabel-${note.id.value}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (note.isPinned) ...[
                  AppIcon(
                    Icons.push_pin_outlined,
                    size: 13,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    note.title.trim().isEmpty
                        ? context.l10n.untitled
                        : note.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.ink,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time,
                  key: ValueKey('tag-note-time-$groupLabel-${note.id.value}'),
                  semanticsLabel: context.l10n.calendarUpdatedAt(time),
                  style: TextStyle(
                    color: colors.subtle,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '$summary${note.overviewTextWithAttachmentsTruncated ? '…' : ''}',
                key: ValueKey('tag-note-summary-$groupLabel-${note.id.value}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

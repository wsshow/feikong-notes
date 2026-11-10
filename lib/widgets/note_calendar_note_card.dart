import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import 'app_icon.dart';

/// A lightweight, directly openable preview for week and day browsing.
class NoteCalendarNoteCard extends StatelessWidget {
  const NoteCalendarNoteCard({
    required this.note,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final Note note;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hm(
      context.l10n.localeName,
    ).format(note.updatedAt.toLocal());
    final summary = note.overviewTextWithAttachments;
    final title = note.title.trim().isEmpty
        ? context.l10n.untitled
        : note.title.trim();
    final metadata = <Widget>[
      for (final tag in note.tags.take(3))
        _MetadataLabel(label: '#$tag', accented: true),
      if (note.tags.length > 3)
        _MetadataLabel(label: '+${note.tags.length - 3}'),
      for (final kind in NoteAssetKind.values)
        if (note.assets.where((asset) => asset.kind == kind).length
            case final count when count > 0)
          _MetadataLabel(
            label: switch (kind) {
              NoteAssetKind.image => context.l10n.imageAttachmentMetadata(
                count,
              ),
              NoteAssetKind.audio => context.l10n.audioAttachmentMetadata(
                count,
              ),
              NoteAssetKind.video => context.l10n.videoAttachmentMetadata(
                count,
              ),
              NoteAssetKind.file => context.l10n.fileAttachmentMetadata(count),
            },
          ),
    ];
    return Material(
      color: compact
          ? context.appColors.surfaceMuted
          : context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          context.appComponents.usesLayeredCalendarSurfaces && !compact
              ? context.appRadii.large
              : context.appRadii.medium,
        ),
        side: compact
            ? BorderSide.none
            : BorderSide(color: context.appColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('calendar-note-${note.id.value}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.all(compact ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.isPinned) ...[
                    AppIcon(
                      Icons.push_pin_outlined,
                      size: 14,
                      color: context.appColors.accent,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.appComponents.usesIllustratedCalendar
                            ? (compact
                                  ? SunnyGrowthTokens.typeBody.fontSize
                                  : SunnyGrowthTokens.typeItem.fontSize)
                            : (compact ? 14 : 17),
                        fontWeight:
                            context.appComponents.usesIllustratedCalendar
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.35,
                        color: context.appColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    time,
                    semanticsLabel: context.l10n.calendarUpdatedAt(time),
                    style: TextStyle(
                      fontSize: context.appComponents.usesIllustratedCalendar
                          ? SunnyGrowthTokens.typeCaption.fontSize
                          : 11,
                      color: context.appColors.muted,
                    ),
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                SizedBox(height: compact ? 4 : 8),
                Text(
                  '$summary${note.overviewTextWithAttachmentsTruncated ? '…' : ''}',
                  key: ValueKey('calendar-note-summary-${note.id.value}'),
                  maxLines: compact ? 1 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: context.appComponents.usesIllustratedCalendar
                        ? (compact
                              ? SunnyGrowthTokens.typeLabel.fontSize
                              : SunnyGrowthTokens.typeBody.fontSize)
                        : (compact ? 12 : 14),
                    height: 1.5,
                  ),
                ),
              ],
              if (!compact && metadata.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: metadata),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataLabel extends StatelessWidget {
  const _MetadataLabel({required this.label, this.accented = false});

  final String label;
  final bool accented;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: accented
          ? context.appColors.accentSoft
          : context.appColors.surfaceMuted,
      borderRadius: BorderRadius.circular(context.appRadii.small),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: accented
            ? context.appColors.onAccentSoft
            : context.appColors.muted,
        fontSize: context.appComponents.usesIllustratedCalendar
            ? SunnyGrowthTokens.typeCaption.fontSize
            : 11,
        height: 1.4,
      ),
    ),
  );
}

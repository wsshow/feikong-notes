import 'package:flutter/material.dart';

import '../app.dart';
import '../editor/note_editor_controller.dart';
import '../editor/note_outline.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

final class NoteOutlineSheet extends StatelessWidget {
  const NoteOutlineSheet({required this.controller, super.key});

  final NoteEditorController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entries = NoteOutlineEntry.fromDelta(
          controller.quillController.document.toDelta(),
        );
        final selection = controller.quillController.selection.extentOffset;
        NoteOutlineEntry? current;
        for (final entry in entries) {
          if (entry.offset > selection) break;
          current = entry;
        }
        return Column(
          key: const Key('note-outline-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20, end: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.noteOutline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('note-outline-close'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const AppIcon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                      child: Column(
                        children: [
                          AppIcon(
                            Icons.toc_rounded,
                            size: 32,
                            color: context.appColors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.l10n.noteOutlineEmpty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.noteOutlineEmptyHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.appColors.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      key: const Key('note-outline-list'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: entries.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                            child: Text(
                              context.l10n.noteOutlineHint,
                              style: TextStyle(
                                color: context.appColors.muted,
                                height: 1.5,
                              ),
                            ),
                          );
                        }
                        final entry = entries[index - 1];
                        final selected = identical(entry, current);
                        return Semantics(
                          selected: selected,
                          label:
                              '${context.l10n.headingLevel(entry.level)}: ${entry.text}',
                          button: true,
                          excludeSemantics: true,
                          onTap: () => Navigator.pop(context, entry),
                          child: Material(
                            color: selected
                                ? context.appColors.surfaceMuted
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppRadius.small,
                            ),
                            child: InkWell(
                              key: ValueKey(
                                'note-outline-entry-${entry.offset}',
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.small,
                              ),
                              onTap: () => Navigator.pop(context, entry),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                child: Padding(
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                    12 + entry.depth * 16,
                                    12,
                                    12,
                                    12,
                                  ),
                                  child: Text(
                                    entry.text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: entry.depth >= 2
                                          ? context.appColors.muted
                                          : context.appColors.ink,
                                      fontSize: switch (entry.depth) {
                                        0 => 16,
                                        1 => 15.5,
                                        _ => 15,
                                      },
                                      height: 1.5,
                                      fontWeight: switch (entry.depth) {
                                        0 => FontWeight.w700,
                                        1 => FontWeight.w500,
                                        _ => FontWeight.w400,
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

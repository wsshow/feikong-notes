import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/library_file.dart';
import '../models/note_document.dart';
import '../pages/file_preview_page.dart';
import '../services/file_library_store.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'app_overlay.dart';
import 'app_popup_menu.dart';
import 'library_file_icon.dart';

/// One quiet block in the document, regardless of how many files it references.
class NoteFileReferenceCard extends StatelessWidget {
  const NoteFileReferenceCard({
    required this.references,
    this.onRemove,
    this.onInteraction,
    this.store,
    this.previewBuilder,
    super.key,
  });

  final List<NoteFileReference> references;
  final VoidCallback? onRemove;
  final VoidCallback? onInteraction;
  final FileLibraryStore? store;
  final Widget Function(LibraryFile, FileLibraryStore)? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label =
        '${context.l10n.fileReferences} · ${context.l10n.fileReferenceCount(references.length)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: label,
                hint: context.l10n.fileReferencesHint,
                child: InkWell(
                  key: const Key('note-file-reference-open'),
                  onTap: () {
                    onInteraction?.call();
                    unawaited(
                      AppOverlay.bottomSheet<void>(
                        context: context,
                        useSafeArea: true,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => _ReferenceListSheet(
                          references: references,
                          store: store ?? FileLibraryStore.instance,
                          previewBuilder: previewBuilder,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AppIcon(Icons.link, size: 24, color: colors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                references
                                    .take(3)
                                    .map((file) => file.name)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppIcon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colors.subtle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              AppAnchoredMenuButton<String>(
                tooltip: context.l10n.fmMore,
                icon: const AppIcon(Icons.more_horiz_rounded, size: 20),
                actions: [
                  AppMenuAction(
                    value: 'remove',
                    label: context.l10n.fileReferencesRemove,
                    icon: Icons.link_off_rounded,
                  ),
                ],
                onSelected: (_) => onRemove!(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceListSheet extends StatefulWidget {
  const _ReferenceListSheet({
    required this.references,
    required this.store,
    this.previewBuilder,
  });
  final List<NoteFileReference> references;
  final FileLibraryStore store;
  final Widget Function(LibraryFile, FileLibraryStore)? previewBuilder;

  @override
  State<_ReferenceListSheet> createState() => _ReferenceListSheetState();
}

class _ReferenceListSheetState extends State<_ReferenceListSheet> {
  late Future<Map<String, LibraryFile>> _files = _load();

  Future<Map<String, LibraryFile>> _load() async {
    final files = await widget.store.load();
    final byId = {for (final file in files) file.id: file};
    final available = <String, LibraryFile>{};
    for (final reference in widget.references) {
      final file = byId[reference.fileId];
      if (file != null &&
          !file.isFolder &&
          !FileLibraryStore.isInTrash(file, byId) &&
          await widget.store.fileFor(file).exists()) {
        available[file.id] = file;
      }
    }
    return available;
  }

  Future<void> _open(LibraryFile file) async {
    // History must not prevent opening the underlying file.
    unawaited(widget.store.markOpened(file.id).catchError((Object _) {}));
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            widget.previewBuilder?.call(file, widget.store) ??
            FilePreviewPage(entry: file, store: widget.store),
      ),
    );
    if (mounted) {
      setState(() {
        _files = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .55,
    minChildSize: .35,
    maxChildSize: .9,
    expand: false,
    builder: (context, scrollController) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.fileReferences,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.fileReferenceCount(widget.references.length),
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.close,
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, LibraryFile>>(
            future: _files,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  controller: scrollController,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.l10n.fmErrorLoad),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _files = _load();
                      }),
                      child: Text(context.l10n.retry),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                key: const Key('note-file-reference-list'),
                controller: scrollController,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                ),
                itemCount: widget.references.length,
                itemBuilder: (context, index) {
                  final reference = widget.references[index];
                  final file = snapshot.data![reference.fileId];
                  return ListTile(
                    key: ValueKey('note-file-reference-${reference.fileId}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    leading: file == null
                        ? AppIcon(
                            Icons.link_off_rounded,
                            color: context.appColors.subtle,
                          )
                        : LibraryFileIcon(
                            entry: file,
                            size: 40,
                            filePath: widget.store.fileFor(file).path,
                          ),
                    title: Text(
                      file?.name ?? reference.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      file == null
                          ? context.l10n.fileReferenceUnavailable
                          : '${libraryKindLabel(context.l10n, file.kind)} · ${formatFileSize(file.size)}',
                    ),
                    trailing: file == null
                        ? null
                        : const AppIcon(Icons.chevron_right_rounded, size: 18),
                    enabled: file != null,
                    onTap: file == null ? null : () => _open(file),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

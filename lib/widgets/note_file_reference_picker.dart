import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/library_file.dart';
import '../models/note_document.dart';
import '../providers/file_library_controller.dart';
import '../services/file_library_picker.dart';
import '../services/file_library_store.dart';
import '../services/library_file_note_service.dart';
import '../theme/app_theme.dart';
import 'app_feedback.dart';
import 'app_icon.dart';
import 'app_overlay.dart';
import 'library_file_icon.dart';

Future<List<NoteFileReference>?> showNoteFileReferencePicker(
  BuildContext context,
) => AppOverlay.bottomSheet<List<NoteFileReference>>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const NoteFileReferencePicker(),
);

class NoteFileReferencePicker extends StatefulWidget {
  const NoteFileReferencePicker({this.store, this.pickFiles, super.key});
  final FileLibraryStore? store;
  final Future<List<XFile>> Function()? pickFiles;

  @override
  State<NoteFileReferencePicker> createState() =>
      _NoteFileReferencePickerState();
}

class _NoteFileReferencePickerState extends State<NoteFileReferencePicker> {
  late final _controller = FileLibraryController(store: widget.store);
  final _selected = <String>{};
  String _query = '';
  bool _working = false;
  bool get _busy => _working || _controller.busy;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _working = true);
    try {
      final picked =
          await (widget.pickFiles?.call() ??
              FileLibraryPicker.instance.pickFiles());
      if (!mounted) return;
      final previous = _controller.entries.map((file) => file.id).toSet();
      await _controller.importFiles(picked);
      if (!mounted) return;
      setState(() {
        _selected.addAll(
          _controller.entries
              .where((file) => !previous.contains(file.id) && !file.isFolder)
              .map((file) => file.id),
        );
      });
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorImport);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _selected.isEmpty) return;
    setState(() => _working = true);
    try {
      final references = await LibraryFileNoteService(store: _controller.store)
          .referencesFor(
            _selected
                .map((id) => _controller.byId[id])
                .whereType<LibraryFile>(),
          );
      if (mounted) Navigator.pop(context, references);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.fmErrorOperation);
        await _controller.load();
        _selected.removeWhere(
          (id) =>
              !_controller.byId.containsKey(id) ||
              _controller.isTrashed(_controller.byId[id]!),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .45,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final files =
              _controller.entries
                  .where(
                    (file) =>
                        !file.isFolder &&
                        !_controller.isTrashed(file) &&
                        file.name.toLowerCase().contains(_query),
                  )
                  .toList()
                ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.fileReferencesChoose,
                        style: Theme.of(context).textTheme.titleLarge,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  key: const Key('file-reference-search'),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: context.l10n.fmSearch,
                    prefixIcon: const AppIcon(Icons.search_rounded),
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_controller.importName != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    context.l10n.fmImporting(
                      _controller.imported + 1,
                      _controller.importTotal,
                    ),
                  ),
                ),
              if (_controller.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: _busy ? null : _controller.load,
                    child: Text(context.l10n.fmErrorLoad),
                  ),
                ),
              Expanded(
                child: _controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: files.isEmpty ? 1 : files.length,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemBuilder: (context, index) {
                          if (files.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _query.isEmpty
                                    ? context.l10n.fileReferencesEmpty
                                    : context.l10n.fmNoResultsBody,
                                style: TextStyle(
                                  color: context.appColors.muted,
                                ),
                              ),
                            );
                          }
                          final file = files[index];
                          return CheckboxListTile(
                            key: ValueKey('pick-file-reference-${file.id}'),
                            value: _selected.contains(file.id),
                            onChanged: _busy
                                ? null
                                : (selected) => setState(() {
                                    if (selected == true) {
                                      _selected.add(file.id);
                                    } else {
                                      _selected.remove(file.id);
                                    }
                                  }),
                            secondary: LibraryFileIcon(
                              entry: file,
                              size: 40,
                              filePath: _controller.store.fileFor(file).path,
                            ),
                            title: Text(
                              file.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${libraryKindLabel(context.l10n, file.kind)} · ${formatFileSize(file.size)}',
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 4,
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    TextButton.icon(
                      key: const Key('file-reference-import'),
                      onPressed: _busy ? null : _import,
                      icon: const AppIcon(Icons.add_rounded, size: 18),
                      label: Text(context.l10n.fmImport),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('file-reference-submit'),
                        onPressed: _busy || _selected.isEmpty ? null : _submit,
                        child: Text(
                          context.l10n.fileReferencesAdd(_selected.length),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../l10n/l10n.dart';
import '../models/library_file.dart';
import '../services/file_library_actions.dart';
import '../services/file_library_store.dart';
import '../services/note_audio_playback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/fk_markdown_view.dart';
import '../widgets/library_file_icon.dart';
import '../widgets/note_video_player_page.dart';

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({required this.entry, required this.store, super.key});
  final LibraryFile entry;
  final FileLibraryStore store;
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final File _file = widget.store.fileFor(widget.entry);
  late final FileLibraryActions _actions = FileLibraryActions(widget.store);
  late final Future<bool> _exists = _file.exists();
  bool _working = false;

  Future<void> _action(String action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (action == 'open') {
        if (!await _actions.openExternal(widget.entry) && mounted) {
          AppFeedback.error(context, context.l10n.fmOpenFailed);
        }
      } else if (action == 'share') {
        final box = context.findRenderObject() as RenderBox?;
        await _actions.share(
          [widget.entry],
          origin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } else if (action == 'save') {
        if (await _actions.save(widget.entry) && mounted) {
          AppFeedback.show(context, context.l10n.fmSaved);
        }
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
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _fallback({String? message, bool failed = false}) {
    final l10n = context.l10n;
    final office = {
      LibraryFileKind.document,
      LibraryFileKind.spreadsheet,
      LibraryFileKind.presentation,
    }.contains(widget.entry.kind);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LibraryFileIcon(entry: widget.entry, size: 88, thumbnail: false),
            const SizedBox(height: 24),
            Text(
              failed ? l10n.fmPreviewFailed : l10n.fmPreviewUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? (office ? l10n.fmOfficeHint : l10n.fmPreviewHint),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted, height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _working ? null : () => _action('open'),
              icon: const AppIcon(Icons.north_east_rounded, size: 20),
              label: Text(l10n.fmOpenSystem),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.entry.extension.toUpperCase()} · ${formatFileSize(widget.entry.size)}',
              style: TextStyle(color: context.appColors.subtle, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final entry = widget.entry;
    switch (entry.kind) {
      case LibraryFileKind.pdf:
        return _PdfPreview(
          filePath: _file.path,
          fallback: () => _fallback(failed: true),
        );
      case LibraryFileKind.image:
        return InteractiveViewer(
          minScale: .25,
          maxScale: 8,
          child: Center(
            child: Image(
              image: ResizeImage(
                FileImage(_file),
                width: 2400,
                height: 2400,
                policy: ResizeImagePolicy.fit,
              ),
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) => _fallback(failed: true),
            ),
          ),
        );
      case LibraryFileKind.audio:
        return _AudioPreview(
          entry: entry,
          filePath: _file.path,
          onError: () => _fallback(failed: true),
        );
      case LibraryFileKind.video:
        return NoteVideoPlayerPage(
          filePath: _file.path,
          title: entry.name,
          showAppBar: false,
        );
      case LibraryFileKind.text:
        return _TextPreview(
          file: _file,
          markdown: entry.extension == 'md' || entry.extension == 'markdown',
          fallback: () => _fallback(failed: true),
        );
      case LibraryFileKind.spreadsheet:
        if (entry.extension == 'csv' || entry.extension == 'tsv') {
          return _TextPreview(
            file: _file,
            markdown: false,
            fallback: () => _fallback(failed: true),
          );
        }
        return _fallback();
      case LibraryFileKind.archive:
        if (entry.extension == 'zip' && entry.size <= 32 * 1024 * 1024) {
          return _ArchivePreview(
            file: _file,
            fallback: () => _fallback(failed: true),
          );
        }
        return _fallback();
      default:
        return _fallback();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.canvas,
    appBar: AppBar(
      title: Text(
        widget.entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: context.l10n.fmOpenSystem,
          onPressed: _working ? null : () => _action('open'),
          icon: const AppIcon(Icons.north_east_rounded),
        ),
        AppAnchoredMenuButton<String>(
          tooltip: context.l10n.fmMore,
          icon: const AppIcon(Icons.more_horiz_rounded),
          enabled: !_working,
          actions: [
            AppMenuAction(
              value: 'share',
              label: context.l10n.fmShare,
              icon: Icons.ios_share_rounded,
            ),
            AppMenuAction(
              value: 'save',
              label: context.l10n.fmExport,
              icon: Icons.download_outlined,
            ),
          ],
          onSelected: _action,
        ),
      ],
      bottom: _working
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: SafeArea(
      child: FutureBuilder<bool>(
        future: _exists,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != true) {
            return _fallback(message: context.l10n.fmMissing, failed: true);
          }
          return _preview();
        },
      ),
    ),
  );
}

class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.filePath, required this.fallback});
  final String filePath;
  final Widget Function() fallback;
  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _pages = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PdfViewer.file(
          widget.filePath,
          controller: _controller,
          params: PdfViewerParams(
            backgroundColor: context.appColors.surfaceMuted,
            onViewerReady: (document, controller) {
              if (mounted) setState(() => _pages = document.pages.length);
            },
            onPageChanged: (page) {
              if (mounted && page != null) setState(() => _page = page);
            },
            errorBannerBuilder: (context, error, stack, document) =>
                widget.fallback(),
          ),
        ),
      ),
      if (_pages > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                onPressed: _page > 1
                    ? () => _controller.goToPage(pageNumber: _page - 1)
                    : null,
                icon: const AppIcon(Icons.chevron_left_rounded),
              ),
              Text(
                '$_page / $_pages',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                onPressed: _page < _pages
                    ? () => _controller.goToPage(pageNumber: _page + 1)
                    : null,
                icon: const AppIcon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
    ],
  );
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({
    required this.entry,
    required this.filePath,
    required this.onError,
  });
  final LibraryFile entry;
  final String filePath;
  final Widget Function() onError;
  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview>
    with WidgetsBindingObserver {
  final _driver = LocalNoteAudioPlaybackDriver();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _driver.status == NoteAudioPlaybackStatus.playing) {
      unawaited(
        _driver.toggle(assetId: widget.entry.id, filePath: widget.filePath),
      );
    } else if (state != AppLifecycleState.resumed &&
        _driver.status == NoteAudioPlaybackStatus.loading) {
      unawaited(_driver.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _driver,
    builder: (context, _) {
      if (_driver.status == NoteAudioPlaybackStatus.failed) {
        return widget.onError();
      }
      final playing = _driver.status == NoteAudioPlaybackStatus.playing;
      final loading = _driver.status == NoteAudioPlaybackStatus.loading;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LibraryFileIcon(entry: widget.entry, size: 120),
              const SizedBox(height: 28),
              Text(
                widget.entry.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.entry.extension.toUpperCase()} · ${formatFileSize(widget.entry.size)}',
                style: TextStyle(color: context.appColors.muted),
              ),
              const SizedBox(height: 32),
              Slider(
                value: _driver.position.inMilliseconds.toDouble().clamp(
                  0,
                  _driver.duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                ),
                max: _driver.duration.inMilliseconds.toDouble().clamp(
                  1,
                  double.infinity,
                ),
                onChanged: _driver.duration > Duration.zero
                    ? (value) => _driver.seek(
                        assetId: widget.entry.id,
                        position: Duration(milliseconds: value.round()),
                      )
                    : null,
              ),
              Text(
                '${_duration(_driver.position)} / ${_duration(_driver.duration)}',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 68,
                height: 68,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => _driver.toggle(
                          assetId: widget.entry.id,
                          filePath: widget.filePath,
                        ),
                        child: AppIcon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 30,
                          semanticLabel: playing
                              ? context.l10n.fmPause
                              : context.l10n.fmPlay,
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _duration(Duration value) =>
    '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class _TextPreview extends StatefulWidget {
  const _TextPreview({
    required this.file,
    required this.markdown,
    required this.fallback,
  });
  final File file;
  final bool markdown;
  final Widget Function() fallback;
  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  late final Future<String> _text = _readText(widget.file.path);
  static Future<String> _readText(String path) => Isolate.run(() async {
    final file = File(path);
    final length = await file.length();
    final bytes = await file
        .openRead(0, length.clamp(0, 1024 * 1024))
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      final littleEndian = bytes[0] == 0xff;
      return String.fromCharCodes([
        for (var i = 2; i + 1 < bytes.length; i += 2)
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
      ]);
    }
    if (bytes.take(8192).contains(0)) {
      throw const FileLibraryException('binary');
    }
    return utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text,
    builder: (context, snapshot) {
      if (snapshot.hasError) return widget.fallback();
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      var text = snapshot.data!;
      final truncated =
          text.length > 200000 || widget.file.lengthSync() > 1024 * 1024;
      if (text.length > 200000) text = text.substring(0, 200000);
      return Column(
        children: [
          if (truncated)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.fmTextTruncated,
                style: TextStyle(color: context.appColors.warning),
              ),
            ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: widget.markdown
                    ? FkMarkdownView(data: text)
                    : SelectableText(
                        text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.65,
                          color: context.appColors.ink,
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ArchivePreview extends StatefulWidget {
  const _ArchivePreview({required this.file, required this.fallback});
  final File file;
  final Widget Function() fallback;
  @override
  State<_ArchivePreview> createState() => _ArchivePreviewState();
}

class _ArchivePreviewState extends State<_ArchivePreview> {
  late final Future<List<(String, int)>> _entries = _readArchive(
    widget.file.path,
  );
  static Future<List<(String, int)>> _readArchive(String path) =>
      Isolate.run(() {
        final input = InputFileStream(path);
        try {
          final archive = ZipDecoder().decodeStream(input);
          return archive.files.take(1001).map((e) => (e.name, e.size)).toList();
        } finally {
          input.closeSync();
        }
      });
  @override
  Widget build(BuildContext context) => FutureBuilder<List<(String, int)>>(
    future: _entries,
    builder: (context, snapshot) {
      if (snapshot.hasError) return widget.fallback();
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final entries = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              entries.length > 1000
                  ? context.l10n.fmArchiveLimit
                  : context.l10n.fmArchiveHint,
              style: TextStyle(color: context.appColors.muted),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length.clamp(0, 1000),
              separatorBuilder: (_, index) =>
                  Divider(height: 1, color: context.appColors.line),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  leading: const AppIcon(Icons.insert_drive_file_outlined),
                  title: Text(entry.$1),
                  subtitle: Text(formatFileSize(entry.$2)),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

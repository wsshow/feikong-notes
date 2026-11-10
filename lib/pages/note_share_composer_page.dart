import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../models/note_share.dart';
import '../services/file_storage_service.dart';
import '../services/note_share_image_service.dart';
import '../services/note_share_layout_engine.dart';
import '../services/note_share_preferences_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/note_share_page_canvas.dart';
import '../widgets/app_icon.dart';

typedef NoteShareFilesOverride = Future<void> Function(List<File> files);

class NoteShareComposerPage extends StatefulWidget {
  final NoteShareDraft draft;
  final NoteShareImageService imageService;
  final NoteShareFilesOverride? shareFilesOverride;

  const NoteShareComposerPage({
    super.key,
    required this.draft,
    this.imageService = const NoteShareImageService(),
    this.shareFilesOverride,
  });

  @override
  State<NoteShareComposerPage> createState() => _NoteShareComposerPageState();
}

class _NoteShareComposerPageState extends State<NoteShareComposerPage> {
  final _captureKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  final _layoutEngine = const NoteShareLayoutEngine();
  Timer? _preferenceSave;
  NoteShareOptions _options = const NoteShareOptions(
    canvas: NoteShareCanvasSpec.singleLongUltra,
  );
  NoteShareLayoutResult? _latestLayout;
  var _previewPageIndex = 0;
  var _renderPageIndex = 0;
  var _rendering = false;
  var _renderedPages = 0;
  var _totalPages = 0;
  var _optionsChangedBeforeLoad = false;
  Map<NoteAttachmentId, double> _imageAspectRatios = const {};
  Future<void>? _imageAspectRatioLoad;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
    unawaited(_ensureImageAspectRatios());
  }

  Future<void> _loadPreferences() async {
    final loaded = await NoteSharePreferencesService.instance.load();
    if (!mounted || _optionsChangedBeforeLoad) return;
    setState(() {
      _options = loaded.copyWith(
        canvas: NoteShareCanvasSpec.singleLongUltra,
        density: NoteShareDensity.standard,
      );
      _previewPageIndex = 0;
      _renderPageIndex = 0;
    });
  }

  @override
  void dispose() {
    _preferenceSave?.cancel();
    unawaited(NoteSharePreferencesService.instance.save(_options));
    super.dispose();
  }

  void _updateOptions(NoteShareOptions options) {
    if (_rendering) return;
    _optionsChangedBeforeLoad = true;
    setState(() {
      _options = options;
      _previewPageIndex = 0;
      _renderPageIndex = 0;
    });
    _preferenceSave?.cancel();
    _preferenceSave = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(NoteSharePreferencesService.instance.save(_options)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layout = _layoutEngine.paginate(
      draft: widget.draft,
      options: _options,
      textDirection: Directionality.of(context),
      untitledTitle: l10n.noteShareUntitled,
      imageAspectRatios: _imageAspectRatios,
    );
    _latestLayout = layout;
    final pageIndex = _rendering
        ? _renderPageIndex.clamp(0, layout.pages.length - 1)
        : _previewPageIndex.clamp(0, layout.pages.length - 1);
    final pixelSize = layout.outputPixelSize;

    return Scaffold(
      backgroundColor: context.appColors.canvas,
      appBar: AppBar(
        title: Text(l10n.createShareImage),
        toolbarHeight: 64,
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _previewPane(
                        context,
                        layout: layout,
                        pageIndex: pageIndex,
                        pixelSize: pixelSize,
                        standalone: true,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 4,
                      child: _controlsList(context, layout, pixelSize),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 128),
                children: [
                  _previewPane(
                    context,
                    layout: layout,
                    pageIndex: pageIndex,
                    pixelSize: pixelSize,
                  ),
                  const SizedBox(height: 24),
                  ..._controlSections(context),
                ],
              );
            },
          ),
          if (_rendering)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: layout.logicalWidth,
                    maxWidth: layout.logicalWidth,
                    minHeight: layout.logicalHeight,
                    maxHeight: layout.logicalHeight,
                    child: SizedBox(
                      width: layout.logicalWidth,
                      height: layout.logicalHeight,
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: NoteSharePageCanvas(
                          draft: widget.draft,
                          options: _options,
                          layout: layout,
                          pageIndex: pageIndex,
                          untitledTitle: l10n.noteShareUntitled,
                          sourceLabel: l10n.noteShareSource,
                          locale: Localizations.localeOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_rendering)
            Positioned.fill(
              child: ColoredBox(
                color: context.appColors.scrim,
                child: Center(
                  child: Container(
                    width: 250,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: context.appColors.floatingShadows,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          l10n.generatingShareImageProgress(
                            math.min(_renderedPages + 1, _totalPages),
                            _totalPages,
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Material(
        key: const Key('note-share-action-region'),
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: _shareButtonKey,
                onPressed: _rendering ? null : _generateAndShare,
                icon: const AppIcon(Icons.ios_share_rounded, size: 20),
                label: Text(l10n.generateAndShare),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPane(
    BuildContext context, {
    required NoteShareLayoutResult layout,
    required int pageIndex,
    required NoteSharePixelSize pixelSize,
    bool standalone = false,
  }) {
    final l10n = context.l10n;
    final preview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '${pixelSize.width} × ${pixelSize.height}',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              l10n.shareImagePageIndicator(pageIndex + 1, layout.pages.length),
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const maxPreviewHeight = 520.0;
            final ratio = pixelSize.aspectRatio;
            final canvas = RepaintBoundary(
              child: NoteSharePageCanvas(
                draft: widget.draft,
                options: _options,
                layout: layout,
                pageIndex: pageIndex,
                untitledTitle: l10n.noteShareUntitled,
                sourceLabel: l10n.noteShareSource,
                locale: Localizations.localeOf(context),
              ),
            );
            if (_options.canvas.isLong) {
              final width = constraints.maxWidth;
              final scaledHeight = width / ratio;
              return Container(
                width: width,
                height: math.min(maxPreviewHeight, scaledHeight),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: SizedBox(
                    width: width,
                    height: scaledHeight,
                    child: FittedBox(
                      alignment: Alignment.topCenter,
                      fit: BoxFit.fitWidth,
                      child: canvas,
                    ),
                  ),
                ),
              );
            }
            final width = math.min(
              constraints.maxWidth,
              maxPreviewHeight * ratio,
            );
            final height = width / ratio;
            return SizedBox(
              width: width,
              height: height,
              child: FittedBox(fit: BoxFit.contain, child: canvas),
            );
          },
        ),
        const SizedBox(height: 10),
        if (_options.canvas.isLong)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.shareLongImageHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.appColors.muted),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.previousPage,
                onPressed: _rendering || pageIndex <= 0
                    ? null
                    : () => setState(() {
                        _previewPageIndex = pageIndex - 1;
                        _renderPageIndex = _previewPageIndex;
                      }),
                icon: const AppIcon(Icons.chevron_left_rounded),
              ),
              Text('${pageIndex + 1} / ${layout.pages.length}'),
              IconButton(
                tooltip: l10n.nextPage,
                onPressed: _rendering || pageIndex >= layout.pages.length - 1
                    ? null
                    : () => setState(() {
                        _previewPageIndex = pageIndex + 1;
                        _renderPageIndex = _previewPageIndex;
                      }),
                icon: const AppIcon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
    if (!standalone) return preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      children: [preview],
    );
  }

  Widget _controlsList(
    BuildContext context,
    NoteShareLayoutResult layout,
    NoteSharePixelSize pixelSize,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
    children: _controlSections(context),
  );

  List<Widget> _controlSections(BuildContext context) {
    final l10n = context.l10n;
    return [
      _sectionTitle(l10n.shareImageStyle),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final template in NoteShareTemplateId.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: _options.template == template,
                  showCheckmark: false,
                  onSelected: _rendering
                      ? null
                      : (_) => _updateOptions(
                          _options.copyWith(template: template),
                        ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  label: Text(_templateLabel(l10n, template)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _sectionTitle(l10n.shareImageContent),
      _settingsCard([
        _toggle(
          context,
          icon: Icons.title_rounded,
          label: l10n.includeNoteTitle,
          value: _options.includeTitle,
          onChanged: (value) =>
              _updateOptions(_options.copyWith(includeTitle: value)),
        ),
        _toggle(
          context,
          icon: Icons.calendar_today_outlined,
          label: l10n.includeNoteDate,
          value: _options.includeDate,
          onChanged: (value) =>
              _updateOptions(_options.copyWith(includeDate: value)),
        ),
        _toggle(
          context,
          icon: Icons.tag_rounded,
          label: l10n.includeNoteTags,
          value: _options.includeTags,
          onChanged: widget.draft.tags.isEmpty
              ? null
              : (value) =>
                    _updateOptions(_options.copyWith(includeTags: value)),
        ),
        _toggle(
          context,
          icon: Icons.image_outlined,
          label: l10n.includeNoteImages,
          value: _options.includeImages,
          onChanged:
              widget.draft.attachments.any(
                (item) => item.kind == NoteAssetKind.image,
              )
              ? (value) =>
                    _updateOptions(_options.copyWith(includeImages: value))
              : null,
        ),
        _toggle(
          context,
          icon: Icons.attach_file_rounded,
          label: l10n.includeNoteAttachments,
          value: _options.includeAttachments,
          onChanged: widget.draft.attachments.isEmpty
              ? null
              : (value) => _updateOptions(
                  _options.copyWith(includeAttachments: value),
                ),
        ),
        ListTile(
          leading: AppIcon(
            Icons.verified_outlined,
            color: context.appColors.moss,
          ),
          title: Text(l10n.noteShareSource),
          subtitle: Text(l10n.noteShareSourceAlwaysIncluded),
          trailing: const AppIcon(Icons.lock_outline_rounded, size: 18),
        ),
      ]),
      const SizedBox(height: 16),
      Builder(
        builder: (context) {
          final layout = _latestLayout;
          final size = layout?.outputPixelSize;
          return Text(
            layout == null || size == null
                ? ''
                : l10n.shareImageOutputSummary(
                    layout.pages.length,
                    size.width,
                    size.height,
                  ),
            style: TextStyle(color: context.appColors.muted, fontSize: 12),
          );
        },
      ),
    ];
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -.1,
      ),
    ),
  );

  Widget _settingsCard(List<Widget> children) => Material(
    color: context.appColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const Divider(height: 1),
        ],
      ],
    ),
  );

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    secondary: DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
      ),
      child: SizedBox.square(
        dimension: 38,
        child: AppIcon(icon, size: 20, color: context.appColors.ink),
      ),
    ),
    title: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    value: value,
    onChanged: _rendering ? null : onChanged,
  );

  Future<void> _generateAndShare() async {
    if (_rendering) return;
    await _ensureImageAspectRatios();
    if (!mounted || _rendering) return;
    await WidgetsBinding.instance.endOfFrame;
    final layout = _latestLayout;
    if (!mounted || layout == null || _rendering) return;
    final l10n = context.l10n;
    final exportTitle = widget.draft.title.trim().isEmpty
        ? l10n.noteShareUntitled
        : widget.draft.title.trim();
    final originalPage = _previewPageIndex;
    setState(() {
      _rendering = true;
      _renderedPages = 0;
      _totalPages = layout.pages.length;
      _renderPageIndex = 0;
    });
    Directory? session;
    try {
      await _precacheImages();
      session = await widget.imageService.createSession();
      final files = <File>[];
      for (var index = 0; index < layout.pages.length; index++) {
        if (!mounted) return;
        setState(() => _renderPageIndex = index);
        await WidgetsBinding.instance.endOfFrame;
        final boundary = _captureKey.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Share image boundary unavailable');
        }
        final output = layout.outputPixelSize;
        final pixelRatio = output.width / boundary.size.width;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) throw StateError('Share image encoding failed');
          files.add(
            await widget.imageService.writePage(
              session: session,
              bytes: bytes.buffer.asUint8List(),
              title: exportTitle,
              pageIndex: index,
              pageCount: layout.pages.length,
            ),
          );
        } finally {
          image.dispose();
        }
        if (mounted) setState(() => _renderedPages = index + 1);
      }
      if (!mounted) return;
      if (widget.shareFilesOverride != null) {
        await widget.shareFilesOverride!(files);
        await widget.imageService.deleteSession(session);
      } else {
        final box = _shareButtonKey.currentContext?.findRenderObject();
        final origin = box is RenderBox
            ? box.localToGlobal(Offset.zero) & box.size
            : null;
        final result = await widget.imageService.shareFiles(
          files: files,
          title: l10n.shareNoteImageTitle(exportTitle),
          sharePositionOrigin: origin,
        );
        if (result.status == ShareResultStatus.dismissed) {
          await widget.imageService.deleteSession(session);
        }
      }
    } catch (_) {
      if (session != null) await widget.imageService.deleteSession(session);
      if (mounted) {
        AppFeedback.error(context, context.l10n.shareImageGenerationFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _rendering = false;
          _previewPageIndex = originalPage.clamp(0, layout.pages.length - 1);
          _renderPageIndex = _previewPageIndex;
        });
      }
    }
  }

  Future<void> _precacheImages() async {
    if (!_options.includeAttachments || !_options.includeImages) return;
    for (final attachment in widget.draft.attachments) {
      if (attachment.kind != NoteAssetKind.image) continue;
      try {
        final path = FileStorageService.instance.absolutePath(
          attachment.storageKey,
        );
        await precacheImage(FileImage(File(path)), context);
      } catch (_) {
        // The renderer will show a neutral placeholder for unreadable images.
      }
    }
  }

  Future<void> _ensureImageAspectRatios() =>
      _imageAspectRatioLoad ??= _loadImageAspectRatios();

  Future<void> _loadImageAspectRatios() async {
    final ratios = <NoteAttachmentId, double>{};
    for (final attachment in widget.draft.attachments) {
      if (attachment.kind != NoteAssetKind.image) continue;
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        final previewKey = attachment.previewStorageKey;
        final dimensionKey =
            previewKey != null && previewKey.endsWith('_thumb_v3.jpg')
            ? previewKey
            : attachment.storageKey;
        final path = FileStorageService.instance.absolutePath(dimensionKey);
        buffer = await ui.ImmutableBuffer.fromFilePath(path);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 0 && descriptor.height > 0) {
          ratios[attachment.id] = descriptor.width / descriptor.height;
        }
      } catch (_) {
        // Missing dimensions fall back to a contained legacy-height preview.
      } finally {
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    if (!mounted) return;
    setState(() => _imageAspectRatios = Map.unmodifiable(ratios));
  }

  String _templateLabel(AppLocalizations l10n, NoteShareTemplateId template) =>
      switch (template) {
        NoteShareTemplateId.letter => l10n.shareTemplateLetter,
        NoteShareTemplateId.plain => l10n.shareTemplatePlain,
        NoteShareTemplateId.night => l10n.shareTemplateNight,
        NoteShareTemplateId.editorial => l10n.shareTemplateEditorial,
        NoteShareTemplateId.newspaper => l10n.shareTemplateNewspaper,
        NoteShareTemplateId.manuscript => l10n.shareTemplateManuscript,
        NoteShareTemplateId.botanical => l10n.shareTemplateBotanical,
        NoteShareTemplateId.blueprint => l10n.shareTemplateBlueprint,
        NoteShareTemplateId.amber => l10n.shareTemplateAmber,
        NoteShareTemplateId.film => l10n.shareTemplateFilm,
        NoteShareTemplateId.postcard => l10n.shareTemplatePostcard,
        NoteShareTemplateId.gallery => l10n.shareTemplateGallery,
        NoteShareTemplateId.neon => l10n.shareTemplateNeon,
        NoteShareTemplateId.tide => l10n.shareTemplateTide,
        NoteShareTemplateId.vermilion => l10n.shareTemplateVermilion,
      };
}

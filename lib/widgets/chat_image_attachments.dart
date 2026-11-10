import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/file_storage_service.dart';
import 'app_icon.dart';

class ChatImageItem {
  final String id;
  final String filePath;

  const ChatImageItem({required this.id, required this.filePath});
}

/// Shared image gallery for user messages in legacy chat and agent runs.
class ChatImageAttachments extends StatelessWidget {
  static const double singleImageWidth = 156;
  static const double singleImageHeight = 176;
  static const double thumbnailExtent = 104;

  final List<ChatImageItem> images;
  final String imageKeyPrefix;
  final String stripKey;

  const ChatImageAttachments({
    super.key,
    required this.images,
    this.imageKeyPrefix = 'sent-chat-image',
    this.stripKey = 'sent-chat-image-strip',
  });

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return _ChatImage(
        image: images.single,
        index: 0,
        images: images,
        imageKeyPrefix: imageKeyPrefix,
        single: true,
      );
    }
    return SizedBox(
      key: Key(stripKey),
      height: thumbnailExtent,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) => _ChatImage(
          image: images[index],
          index: index,
          images: images,
          imageKeyPrefix: imageKeyPrefix,
        ),
      ),
    );
  }
}

class _ChatImage extends StatelessWidget {
  final ChatImageItem image;
  final int index;
  final List<ChatImageItem> images;
  final String imageKeyPrefix;
  final bool single;

  const _ChatImage({
    required this.image,
    required this.index,
    required this.images,
    required this.imageKeyPrefix,
    this.single = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(15);
    final width = single
        ? ChatImageAttachments.singleImageWidth
        : ChatImageAttachments.thumbnailExtent;
    final height = single
        ? ChatImageAttachments.singleImageHeight
        : ChatImageAttachments.thumbnailExtent;
    final imageWidget = Image.file(
      File(FileStorageService.instance.absolutePath(image.filePath)),
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: single ? 480 : 320,
      errorBuilder: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: context.appColors.softBlue,
          child: const AppIcon(Icons.broken_image_outlined),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: context.l10n.previewImageNumber(index + 1),
      child: Material(
        color: context.appColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: context.appColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('$imageKeyPrefix-${image.id}'),
          onTap: () => showChatImagePreview(context, images, index),
          child: imageWidget,
        ),
      ),
    );
  }
}

Future<void> showChatImagePreview(
  BuildContext context,
  List<ChatImageItem> images,
  int initialIndex,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ChatImagePreviewPage(
      images: List.unmodifiable(images),
      initialIndex: initialIndex,
    ),
  ),
);

class _ChatImagePreviewPage extends StatefulWidget {
  final List<ChatImageItem> images;
  final int initialIndex;

  const _ChatImagePreviewPage({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState extends State<_ChatImagePreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('local-chat-image-preview'),
    backgroundColor: context.appColors.canvas,
    appBar: AppBar(
      backgroundColor: context.appColors.canvas,
      foregroundColor: context.appColors.ink,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: context.l10n.closePreview,
        onPressed: () => Navigator.pop(context),
        icon: const AppIcon(Icons.close_rounded),
      ),
      title: Text(
        '${_currentIndex + 1} / ${widget.images.length}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
    ),
    body: PageView.builder(
      key: const Key('local-chat-image-preview-pages'),
      controller: _pageController,
      itemCount: widget.images.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (context, index) {
        final image = widget.images[index];
        return InteractiveViewer(
          key: Key('local-chat-image-zoom-${image.id}'),
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(72),
          child: Center(
            child: Image.file(
              File(FileStorageService.instance.absolutePath(image.filePath)),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    Icons.broken_image_outlined,
                    color: context.appColors.muted,
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.imageCannotOpen,
                    style: TextStyle(color: context.appColors.muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

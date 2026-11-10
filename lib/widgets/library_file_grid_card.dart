import 'dart:io';

import 'package:flutter/material.dart';

import '../models/library_file.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'library_file_icon.dart';

/// A shared preview area and a compact information block keep grid rows aligned
/// without pushing metadata away from the file name.
class LibraryFileGridCard extends StatelessWidget {
  const LibraryFileGridCard({
    required this.entry,
    required this.subtitle,
    required this.trailing,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    this.filePath,
    super.key,
  });

  final LibraryFile entry;
  final String subtitle;
  final Widget trailing;
  final bool selected;
  final bool selecting;
  final String? filePath;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static double previewHeight(double width) => (width * .65).clamp(88, 160);

  static double _nameHeight(TextScaler scaler) =>
      (scaler.scale(14) * 1.4 * 2).ceilToDouble();
  static double _metadataHeight(TextScaler scaler) =>
      (scaler.scale(11) * 1.4).ceilToDouble() + 1;

  static double extentFor(double width, TextScaler scaler) =>
      previewHeight(width) +
      24 +
      _nameHeight(scaler) +
      6 +
      _metadataHeight(scaler);

  Widget _preview(BuildContext context) {
    final colors = context.appColors;
    final tint = switch (entry.kind) {
      LibraryFileKind.folder => colors.warning,
      LibraryFileKind.pdf => colors.danger,
      LibraryFileKind.spreadsheet || LibraryFileKind.audio => colors.success,
      _ => colors.accent,
    };
    final placeholder = ColoredBox(
      color: tint.withValues(alpha: .055),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(libraryKindIcon(entry.kind), size: 36, color: tint),
            if (!entry.isFolder && entry.extension.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                entry.extension.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // This is a format mark in the preview, not body text.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .8,
                  color: tint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (entry.kind != LibraryFileKind.image ||
        filePath == null ||
        entry.extension == 'svg') {
      return placeholder;
    }
    return Image(
      key: ValueKey('file-grid-thumbnail-${entry.id}'),
      image: ResizeImage(
        FileImage(File(filePath!)),
        width: 640,
        height: 640,
        policy: ResizeImagePolicy.fit,
      ),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => placeholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      selected: selecting ? selected : null,
      child: Material(
        key: ValueKey('library-file-${entry.id}'),
        color: selected ? colors.accentSoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? colors.accent : colors.line.withValues(alpha: .7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) => InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: ValueKey('file-grid-preview-${entry.id}'),
                  height: previewHeight(constraints.maxWidth),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(child: _preview(context)),
                      if (selected)
                        ColoredBox(color: colors.accent.withValues(alpha: .08)),
                      if (entry.favorite)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: AppIcon(
                            Icons.star_outline_rounded,
                            size: 16,
                            color: colors.warning,
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox.square(
                            dimension: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: colors.surface.withValues(
                                      alpha: .94,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                trailing,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 0,
                  thickness: 1,
                  color: colors.line.withValues(alpha: .5),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _nameHeight(scaler),
                        child: Text(
                          entry.name,
                          key: ValueKey('file-grid-name-${entry.id}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: _metadataHeight(scaler),
                        child: Text(
                          subtitle,
                          key: ValueKey('file-grid-metadata-${entry.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 11,
                            height: 1.4,
                          ),
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
    );
  }
}

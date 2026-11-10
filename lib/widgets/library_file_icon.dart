import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_file.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

String libraryKindLabel(AppLocalizations l10n, LibraryFileKind kind) =>
    switch (kind) {
      LibraryFileKind.folder => l10n.fmFolder,
      LibraryFileKind.pdf => 'PDF',
      LibraryFileKind.document => l10n.fmDocuments,
      LibraryFileKind.spreadsheet => l10n.fmSpreadsheets,
      LibraryFileKind.presentation => l10n.fmPresentations,
      LibraryFileKind.image => l10n.fmImages,
      LibraryFileKind.audio => l10n.fmAudio,
      LibraryFileKind.video => l10n.fmVideo,
      LibraryFileKind.text => l10n.fmText,
      LibraryFileKind.archive => l10n.fmArchives,
      LibraryFileKind.other => l10n.fmOther,
    };

IconData libraryKindIcon(LibraryFileKind kind) => switch (kind) {
  LibraryFileKind.folder => Icons.folder_open_rounded,
  LibraryFileKind.pdf ||
  LibraryFileKind.document ||
  LibraryFileKind.text => Icons.description_outlined,
  LibraryFileKind.spreadsheet => Icons.table_rows_outlined,
  LibraryFileKind.presentation => Icons.view_column_outlined,
  LibraryFileKind.image => Icons.image_outlined,
  LibraryFileKind.audio => Icons.graphic_eq_rounded,
  LibraryFileKind.video => Icons.movie_outlined,
  LibraryFileKind.archive => Icons.inventory_2_outlined,
  LibraryFileKind.other => Icons.insert_drive_file_outlined,
};

class LibraryFileIcon extends StatelessWidget {
  const LibraryFileIcon({
    required this.entry,
    this.filePath,
    this.size = 48,
    this.thumbnail = true,
    super.key,
  });
  final LibraryFile entry;
  final String? filePath;
  final double size;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = switch (entry.kind) {
      LibraryFileKind.folder => colors.warning,
      LibraryFileKind.pdf => colors.danger,
      LibraryFileKind.spreadsheet || LibraryFileKind.audio => colors.success,
      _ => colors.accent,
    };
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        libraryKindIcon(entry.kind),
        size: size * .48,
        color: tint,
      ),
    );
    if (!thumbnail ||
        filePath == null ||
        entry.kind != LibraryFileKind.image ||
        entry.extension == 'svg') {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: ResizeImage(
          FileImage(File(filePath!)),
          width: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
            1,
            640,
          ),
          height: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
            1,
            640,
          ),
          policy: ResizeImagePolicy.fit,
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => placeholder,
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class FileLibraryException implements Exception {
  const FileLibraryException(this.code);
  final String code;
  @override
  String toString() => code;
}

enum LibraryFileKind {
  folder,
  pdf,
  document,
  spreadsheet,
  presentation,
  image,
  audio,
  video,
  text,
  archive,
  other,
}

enum FileLibraryLocation { files, recent, favorites, trash }

enum FileLibrarySort { name, modified, size, type }

@immutable
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.parentId,
    this.storageName,
    this.size = 0,
    this.favorite = false,
    this.deletedAt,
    this.openedAt,
    this.linkedNoteId,
  });

  final String id;
  final String name;
  final String? parentId;
  final String? storageName;
  final int size;
  final bool favorite;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? deletedAt;
  final DateTime? openedAt;
  final String? linkedNoteId;

  bool get isFolder => storageName == null;
  String get extension => p.extension(name).replaceFirst('.', '').toLowerCase();
  LibraryFileKind get kind =>
      isFolder ? LibraryFileKind.folder : kindForName(name);

  LibraryFile copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    bool? favorite,
    DateTime? modifiedAt,
    DateTime? deletedAt,
    bool restore = false,
    DateTime? openedAt,
    String? linkedNoteId,
  }) => LibraryFile(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : parentId ?? this.parentId,
    storageName: storageName,
    size: size,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deletedAt: restore ? null : deletedAt ?? this.deletedAt,
    openedAt: openedAt ?? this.openedAt,
    linkedNoteId: linkedNoteId ?? this.linkedNoteId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'storageName': storageName,
    'size': size,
    'favorite': favorite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'openedAt': openedAt?.toUtc().toIso8601String(),
    if (linkedNoteId != null) 'linkedNoteId': linkedNoteId,
  };

  factory LibraryFile.fromJson(Map<String, dynamic> json) => LibraryFile(
    id: json['id'] as String,
    name: json['name'] as String,
    parentId: json['parentId'] as String?,
    storageName: json['storageName'] as String?,
    size: json['size'] as int,
    favorite: json['favorite'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    deletedAt: json['deletedAt'] == null
        ? null
        : DateTime.parse(json['deletedAt'] as String),
    openedAt: json['openedAt'] == null
        ? null
        : DateTime.parse(json['openedAt'] as String),
    linkedNoteId: json['linkedNoteId'] as String?,
  );

  static LibraryFileKind kindForName(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') return LibraryFileKind.pdf;
    if ({'.doc', '.docx', '.odt', '.rtf', '.pages'}.contains(ext)) {
      return LibraryFileKind.document;
    }
    if ({'.xls', '.xlsx', '.ods', '.numbers', '.csv', '.tsv'}.contains(ext)) {
      return LibraryFileKind.spreadsheet;
    }
    if ({'.ppt', '.pptx', '.odp', '.key'}.contains(ext)) {
      return LibraryFileKind.presentation;
    }
    if ({
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif',
      '.tif',
      '.tiff',
      '.svg',
      '.avif',
      '.ico',
    }.contains(ext)) {
      return LibraryFileKind.image;
    }
    if ({
      '.mp3',
      '.wav',
      '.m4a',
      '.aac',
      '.flac',
      '.ogg',
      '.opus',
      '.aiff',
      '.wma',
      '.amr',
    }.contains(ext)) {
      return LibraryFileKind.audio;
    }
    if ({
      '.mp4',
      '.mov',
      '.m4v',
      '.webm',
      '.mkv',
      '.avi',
      '.3gp',
      '.mpeg',
      '.mpg',
      '.wmv',
    }.contains(ext)) {
      return LibraryFileKind.video;
    }
    if ({'.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz'}.contains(ext)) {
      return LibraryFileKind.archive;
    }
    if ({
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.xml',
      '.html',
      '.htm',
      '.css',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.dart',
      '.py',
      '.java',
      '.kt',
      '.swift',
      '.c',
      '.cpp',
      '.h',
      '.rs',
      '.go',
      '.yaml',
      '.yml',
      '.toml',
      '.ini',
      '.conf',
      '.log',
      '.sql',
      '.sh',
      '.srt',
      '.vtt',
    }.contains(ext)) {
      return LibraryFileKind.text;
    }
    return LibraryFileKind.other;
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

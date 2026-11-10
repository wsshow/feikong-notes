import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_quill/quill_delta.dart';
import 'package:path/path.dart' as p;

import '../editor/note_markdown_codec.dart';
import '../markdown/markdown_front_matter.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import 'file_storage_service.dart';
import 'incoming_share_service.dart';
import 'note_asset_import_service.dart';
import 'note_database_service.dart';
import 'note_repository.dart';

final class SharedNoteImportService {
  SharedNoteImportService({
    Future<NoteRepository> Function()? repositoryLoader,
    NoteAssetImportService? assets,
    FileStorageService? storage,
  }) : _repositoryLoader =
           repositoryLoader ?? (() => NoteDatabaseService.instance.repository),
       _assets = assets ?? NoteAssetImportService.instance,
       _storage = storage ?? FileStorageService.instance;

  final Future<NoteRepository> Function() _repositoryLoader;
  final NoteAssetImportService _assets;
  final FileStorageService _storage;

  static const _maxInlineTextCharacters = 100000;
  static const _plainTextExtensions = {
    '.txt',
    '.text',
    '.log',
    '.md',
    '.markdown',
  };

  Future<Note> import(IncomingShare share) async {
    if (share.error != null) throw const FormatException('Unreadable share');
    final repository = await _repositoryLoader();
    // The native inbox ID is also the note ID. Retrying after a process exit
    // between commit and acknowledgement must not duplicate the note.
    final existing = await repository.get(share.id);
    if (existing != null) return existing;
    if (await repository.isPrivateNote(share.id)) {
      throw StateError('Already imported into private space');
    }
    final imported = <NoteAsset>[];
    var saving = false;
    try {
      final delta = _textDelta(share.text);
      var title = share.title.trim();
      if (title.isEmpty) title = _metadataTitle(share.text);
      var remainingCharacters = _maxInlineTextCharacters - share.text.length;
      final stagedRoot = share.files.isEmpty
          ? null
          : await Directory(share.directory).resolveSymbolicLinks();
      for (final file in share.files) {
        final source = File(p.join(share.directory, file.fileName));
        final resolved = await source.resolveSymbolicLinks();
        if (!p.isWithin(stagedRoot!, resolved) ||
            await source.length() != file.byteLength) {
          throw const FormatException('Shared file changed');
        }
        final text = await _readPlainText(source, file, remainingCharacters);
        if (text != null) {
          if (title.isEmpty) title = _metadataTitle(text);
          for (final operation in _textDelta(text).operations) {
            delta.push(operation);
          }
          remainingCharacters -= text.length;
        } else {
          final asset = await _importAsset(source, file);
          imported.add(asset);
          delta.insert(NoteEmbed.attachment(asset.id).toDeltaData());
          delta.insert('\n');
        }
      }
      if (delta.isEmpty) delta.insert('\n');
      if (share.title.trim().isEmpty &&
          share.text.trim().isEmpty &&
          share.files.isEmpty) {
        throw const FormatException('Empty share');
      }
      final note = Note(
        id: share.id,
        title: title,
        document: NoteDocument.fromDelta(delta),
        assets: imported,
        createdAt: share.createdAt,
        updatedAt: share.createdAt,
        coverAttachmentId: imported
            .where((asset) => asset.kind == NoteAssetKind.image)
            .firstOrNull
            ?.id,
      );
      saving = true;
      return await repository.create(note);
    } catch (_) {
      if (saving) {
        // A post-commit hook may fail. Never remove a committed note's files.
        final committed = await repository.get(share.id);
        if (committed != null) return committed;
      }
      for (final asset in imported) {
        await _storage.deleteFile(asset.storageKey);
        await _storage.deleteFile(asset.previewStorageKey);
      }
      rethrow;
    }
  }

  static Future<String?> _readPlainText(
    File source,
    SharedFile file,
    int remainingCharacters,
  ) async {
    final mime = file.mimeType.split(';').first.trim().toLowerCase();
    final isPlainText =
        const {
          'text/plain',
          'text/markdown',
          'text/x-markdown',
        }.contains(mime) ||
        _plainTextExtensions.contains(p.extension(file.name).toLowerCase()) ||
        _plainTextExtensions.contains(p.extension(file.fileName).toLowerCase());
    // Bound the read before decoding. Keep oversized/empty files as attachments
    // instead of truncating their contents or producing an empty note.
    if (!isPlainText ||
        file.byteLength == 0 ||
        remainingCharacters <= 0 ||
        file.byteLength > remainingCharacters * 4 + 3) {
      return null;
    }
    final bytes = await source.readAsBytes();
    final String text;
    try {
      text = _decodePlainText(bytes);
    } on FormatException {
      // Do not guess legacy encodings or replace malformed bytes with gibberish.
      return null;
    }
    if (text.trim().isEmpty ||
        text.length > remainingCharacters ||
        RegExp(r'[\x00-\x08\x0B\x0E-\x1F\x7F]').hasMatch(text)) {
      return null;
    }
    return text;
  }

  static String _decodePlainText(Uint8List bytes) {
    final littleEndian =
        bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;
    final bigEndian = bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;
    if (!littleEndian && !bigEndian) return utf8.decode(bytes);
    if (bytes.length.isOdd) {
      throw const FormatException('Incomplete UTF-16 text');
    }
    final data = ByteData.sublistView(bytes);
    final units = [
      for (var offset = 2; offset < bytes.length; offset += 2)
        data.getUint16(offset, littleEndian ? Endian.little : Endian.big),
    ];
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (++index >= units.length ||
            units[index] < 0xDC00 ||
            units[index] > 0xDFFF) {
          throw const FormatException('Invalid UTF-16 surrogate pair');
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw const FormatException('Invalid UTF-16 surrogate');
      }
    }
    return String.fromCharCodes(units);
  }

  Future<NoteAsset> _importAsset(File source, SharedFile file) async {
    final extension = p.extension(source.path).toLowerCase();
    if (file.mimeType.startsWith('image/') ||
        const {
          '.jpg',
          '.jpeg',
          '.png',
          '.gif',
          '.webp',
          '.bmp',
        }.contains(extension)) {
      if (file.byteLength <= 20 * 1024 * 1024) {
        try {
          return await _assets.importImageBytes(
            await source.readAsBytes(),
            originalName: file.name,
          );
        } on FormatException {
          // Preserve unsupported image encodings as files instead of losing them.
        }
      }
    } else if (const {
      '.m4a',
      '.aac',
      '.wav',
      '.mp3',
      '.ogg',
      '.opus',
      '.flac',
      '.amr',
    }.contains(extension)) {
      return _assets.importAudioFile(
        source,
        originalName: file.name,
        displayName: file.name,
        durationMs: null,
      );
    } else if (const {'.mp4', '.mov', '.m4v', '.webm'}.contains(extension)) {
      return _assets.importVideoFile(source, originalName: file.name);
    }
    return _assets.importFile(
      source,
      originalName: file.name,
      mimeType: file.mimeType,
    );
  }

  static Delta _textDelta(String source) {
    final text = MarkdownFrontMatter.normalize(source).replaceAll('\uFFFC', '');
    final markdown = NoteMarkdownCodec.decodeIfRich(text);
    if (markdown != null) return markdown;
    final delta = Delta();
    var offset = 0;
    for (final match in RegExp(r'https?://[^\s<>]+').allMatches(text)) {
      if (offset < match.start) {
        delta.insert(text.substring(offset, match.start));
      }
      final url = match.group(0)!;
      delta.insert(url, {'link': url});
      offset = match.end;
    }
    if (offset < text.length) delta.insert(text.substring(offset));
    if (text.isNotEmpty && !text.endsWith('\n')) delta.insert('\n');
    return delta;
  }

  static String _metadataTitle(String source) {
    final title = MarkdownFrontMatter.read(source)?.title ?? '';
    // Respect the same bound as a share subject; the full value stays in-body.
    return title.length <= 500 ? title : '';
  }
}

import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:uuid/uuid.dart';

/// The stable identity of a file owned by a note.
///
/// Documents store this ID instead of a path. The attachment repository is
/// responsible for resolving the ID to metadata and managed local storage.
final class NoteAttachmentId {
  NoteAttachmentId._(this.value);

  factory NoteAttachmentId.generate() => NoteAttachmentId._(const Uuid().v4());

  factory NoteAttachmentId.parse(String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw FormatException('Invalid canonical attachment ID: $value');
    }
    return NoteAttachmentId._(value);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAttachmentId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum NoteEmbedKind { attachment, divider, table, fileReferences }

/// A stable library identity with a small display snapshot, never a local path.
/// The library resolves current names and availability when the card is opened.
final class NoteFileReference {
  factory NoteFileReference({
    required String fileId,
    required String name,
    required int size,
  }) {
    NoteAttachmentId.parse(fileId);
    if (name.trim().isEmpty ||
        name.length > 240 ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(name) ||
        size < 0) {
      throw const FormatException('Invalid file reference.');
    }
    return NoteFileReference._(fileId, name, size);
  }

  const NoteFileReference._(this.fileId, this.name, this.size);

  factory NoteFileReference.fromJson(Object? data) {
    if (data is! Map ||
        data.length != 3 ||
        data['id'] is! String ||
        data['name'] is! String ||
        data['size'] is! int) {
      throw const FormatException('Invalid file reference payload.');
    }
    return NoteFileReference(
      fileId: data['id'] as String,
      name: data['name'] as String,
      size: data['size'] as int,
    );
  }

  final String fileId;
  final String name;
  final int size;

  Map<String, Object> toJson() => {'id': fileId, 'name': name, 'size': size};
}

enum NoteTableAlignment { start, center, end }

/// A bounded, presentation-neutral table stored inside a note Delta.
final class NoteTable {
  factory NoteTable({
    required Iterable<Iterable<String>> rows,
    Iterable<NoteTableAlignment> alignments = const [],
  }) {
    final normalizedRows = _normalizeRows(rows);
    return NoteTable._(
      normalizedRows,
      _normalizeAlignments(normalizedRows.first.length, alignments),
    );
  }

  const NoteTable._(this.rows, this.alignments);

  factory NoteTable.fromJson(Object? source) {
    if (source is! Map ||
        source.keys.any((key) => key is! String) ||
        source['rows'] is! List ||
        source['alignments'] is! List) {
      throw const FormatException('Invalid table embed payload.');
    }
    final rawRows = source['rows'] as List;
    final rawAlignments = source['alignments'] as List;
    if (rawRows.any(
          (row) => row is! List || row.any((cell) => cell is! String),
        ) ||
        rawAlignments.any((alignment) => alignment is! String)) {
      throw const FormatException('Invalid table embed values.');
    }
    return NoteTable(
      rows: rawRows.map((row) => (row as List).cast<String>()),
      alignments: rawAlignments.map(
        (value) => NoteTableAlignment.values.firstWhere(
          (alignment) => alignment.name == value,
          orElse: () => throw const FormatException('Invalid table alignment.'),
        ),
      ),
    );
  }

  static const int maxRows = 200;
  static const int maxColumns = 24;
  static const int maxCellCharacters = 4000;
  static const int maxTotalCharacters = 100000;

  final List<List<String>> rows;
  final List<NoteTableAlignment> alignments;

  int get columnCount => rows.first.length;

  String get plainText => rows.map((row) => row.join('\t')).join('\n');

  /// Returns a bounded prefix without materializing a potentially large table.
  String plainTextPreview(int maxCharacters) {
    if (maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters');
    }
    final text = StringBuffer();
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      if (rowIndex > 0 && !_writePreviewPart(text, '\n', maxCharacters)) break;
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        if (columnIndex > 0 && !_writePreviewPart(text, '\t', maxCharacters)) {
          return text.toString();
        }
        if (!_writePreviewPart(text, row[columnIndex], maxCharacters)) {
          return text.toString();
        }
      }
    }
    return text.toString();
  }

  static bool _writePreviewPart(
    StringBuffer target,
    String value,
    int maxCharacters,
  ) {
    final remaining = maxCharacters - target.length;
    if (remaining <= 0) return false;
    var end = value.length < remaining ? value.length : remaining;
    if (end > 0 &&
        end < value.length &&
        NoteDocument._isHighSurrogate(value.codeUnitAt(end - 1)) &&
        NoteDocument._isLowSurrogate(value.codeUnitAt(end))) {
      end--;
    }
    target.write(value.substring(0, end));
    return end == value.length && target.length < maxCharacters;
  }

  Map<String, Object> toJson() => <String, Object>{
    'rows': [for (final row in rows) List<String>.of(row)],
    'alignments': alignments.map((alignment) => alignment.name).toList(),
  };

  static List<List<String>> _normalizeRows(Iterable<Iterable<String>> source) {
    final materialized = source
        .map((row) => row.map((cell) => cell.trim()).toList(growable: false))
        .toList(growable: false);
    if (materialized.isEmpty || materialized.length > maxRows) {
      throw const FormatException('A table must contain 1 to 200 rows.');
    }
    final columns = materialized.fold<int>(
      0,
      (count, row) => row.length > count ? row.length : count,
    );
    if (columns == 0 || columns > maxColumns) {
      throw const FormatException('A table must contain 1 to 24 columns.');
    }
    var totalCharacters = 0;
    final normalized = <List<String>>[];
    for (final row in materialized) {
      final cells = <String>[];
      for (var index = 0; index < columns; index++) {
        final cell = index < row.length ? row[index] : '';
        if (cell.length > maxCellCharacters) {
          throw const FormatException('A table cell is too large.');
        }
        totalCharacters += cell.length;
        cells.add(cell);
      }
      normalized.add(List.unmodifiable(cells));
    }
    if (totalCharacters > maxTotalCharacters) {
      throw const FormatException('A table is too large.');
    }
    return List.unmodifiable(normalized);
  }

  static List<NoteTableAlignment> _normalizeAlignments(
    int columns,
    Iterable<NoteTableAlignment> source,
  ) {
    final values = source.toList(growable: false);
    return List.unmodifiable([
      for (var index = 0; index < columns; index++)
        index < values.length ? values[index] : NoteTableAlignment.start,
    ]);
  }
}

/// A domain-owned Quill embed.
///
/// Keeping the payload deliberately small prevents presentation details and
/// local file paths from leaking into the canonical document.
final class NoteEmbed {
  const NoteEmbed._({
    required this.kind,
    this.attachmentId,
    this.table,
    this.fileReferences = const [],
  });

  factory NoteEmbed.attachment(NoteAttachmentId id) =>
      NoteEmbed._(kind: NoteEmbedKind.attachment, attachmentId: id);

  const NoteEmbed.divider()
    : kind = NoteEmbedKind.divider,
      attachmentId = null,
      table = null,
      fileReferences = const [];

  factory NoteEmbed.table(NoteTable table) =>
      NoteEmbed._(kind: NoteEmbedKind.table, table: table);

  factory NoteEmbed.fileReferences(Iterable<NoteFileReference> references) {
    final byId = {
      for (final reference in references) reference.fileId: reference,
    };
    if (byId.isEmpty || byId.length > 1000) {
      throw const FormatException(
        'A reference card must contain 1 to 1000 files.',
      );
    }
    return NoteEmbed._(
      kind: NoteEmbedKind.fileReferences,
      fileReferences: List.unmodifiable(byId.values),
    );
  }

  static const String attachmentType = 'fknotes.attachment';
  static const String dividerType = 'fknotes.divider';
  static const String tableType = 'fknotes.table';
  static const String fileReferencesType = 'fknotes.fileReferences';

  final NoteEmbedKind kind;
  final NoteAttachmentId? attachmentId;
  final NoteTable? table;
  final List<NoteFileReference> fileReferences;
  String get fileReferenceText =>
      fileReferences.map((file) => file.name).join('、');

  Map<String, Object> toDeltaData() => switch (kind) {
    NoteEmbedKind.attachment => <String, Object>{
      attachmentType: <String, Object>{'id': attachmentId!.value},
    },
    NoteEmbedKind.divider => const <String, Object>{dividerType: true},
    NoteEmbedKind.table => <String, Object>{tableType: table!.toJson()},
    NoteEmbedKind.fileReferences => <String, Object>{
      fileReferencesType: fileReferences.map((file) => file.toJson()).toList(),
    },
  };

  static NoteEmbed parse(Object? data) {
    if (data is! Map || data.length != 1) {
      throw const FormatException('A note embed must contain one type.');
    }
    final type = data.keys.single;
    final payload = data.values.single;
    if (type == attachmentType) {
      if (payload is! Map || payload.length != 1 || payload['id'] is! String) {
        throw const FormatException('Invalid attachment embed payload.');
      }
      return NoteEmbed.attachment(
        NoteAttachmentId.parse(payload['id'] as String),
      );
    }
    if (type == dividerType && payload == true) {
      return const NoteEmbed.divider();
    }
    if (type == tableType) {
      return NoteEmbed.table(NoteTable.fromJson(payload));
    }
    if (type == fileReferencesType &&
        payload is List &&
        payload.length <= 1000) {
      return NoteEmbed.fileReferences(payload.map(NoteFileReference.fromJson));
    }
    throw FormatException('Unsupported note embed type: $type');
  }
}

typedef NoteEmbedTextResolver = String Function(NoteEmbed embed);

/// A presentation-neutral view of a note document.
final class NoteDocumentProjection {
  const NoteDocumentProjection({
    required this.plainText,
    required this.searchText,
    required this.referencedAttachmentIds,
    required this.hasEmbeds,
    required this.truncated,
  });

  final String plainText;
  final String searchText;
  final List<NoteAttachmentId> referencedAttachmentIds;
  final bool hasEmbeds;
  final bool truncated;

  bool get isVisuallyEmpty => plainText.trim().isEmpty && !hasEmbeds;
}

/// A bounded prefix of a document for surfaces that cannot afford to lay out
/// an arbitrarily large note, such as animated library cards.
final class NoteDocumentPreviewSlice {
  const NoteDocumentPreviewSlice({
    required this.document,
    required this.truncated,
  });

  final NoteDocument document;
  final bool truncated;
}

/// One bounded operation exposed to lightweight rich-text previews.
///
/// Keeping this projection inside [NoteDocument] lets callers preserve inline
/// styling without cloning the complete Delta before applying their limits.
final class NoteDocumentPreviewOperation {
  const NoteDocumentPreviewOperation({required this.data, this.attributes});

  final Object? data;
  final Map<String, dynamic>? attributes;
}

/// The sole canonical body model for a note.
///
/// Storage uses a small versioned envelope around Quill Delta JSON. Only
/// insert-only document deltas are accepted; change deltas must be applied by
/// Quill before persistence.
final class NoteDocument {
  NoteDocument._(
    this._delta,
    this._encoded,
    this.referencedAttachmentIds,
    this.isVisuallyEmpty,
  );

  factory NoteDocument.empty() {
    final delta = Delta()..insert('\n');
    return NoteDocument.fromDelta(delta);
  }

  factory NoteDocument.fromPlainText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final delta = Delta()..insert(normalized);
    if (!normalized.endsWith('\n')) {
      delta.insert('\n');
    }
    return NoteDocument.fromDelta(delta);
  }

  factory NoteDocument.fromDelta(Delta source) {
    final delta = _canonicalize(source);
    final metadata = _validateDocumentDelta(delta);
    final envelope = <String, Object>{
      'schemaVersion': schemaVersion,
      'delta': delta.toJson(),
    };
    return NoteDocument._(
      delta,
      jsonEncode(envelope),
      List.unmodifiable(metadata.attachmentIds),
      !metadata.hasVisualContent,
    );
  }

  factory NoteDocument.fromJsonString(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException catch (error) {
      throw FormatException('Invalid note document JSON: ${error.message}');
    }
    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['delta'] is! List) {
      throw const FormatException('Unsupported note document envelope.');
    }
    final delta = Delta.fromJson(decoded['delta'] as List);
    return NoteDocument.fromDelta(delta);
  }

  static const int schemaVersion = 1;
  static const String objectReplacementCharacter = '\uFFFC';
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  final Delta _delta;
  final String _encoded;
  final List<NoteAttachmentId> referencedAttachmentIds;
  final bool isVisuallyEmpty;

  String toJsonString() => _encoded;

  Delta toDelta() => Delta.from(_delta);

  Document toQuillDocument() => Document.fromJson(_delta.toJson());

  List<NoteDocumentPreviewOperation> previewOperations({
    int maxCharacters = 600,
    int maxOperations = 48,
    int maxLineBreaks = 32,
    int maxEmbeds = 4,
  }) {
    if (maxCharacters < 1 ||
        maxOperations < 1 ||
        maxLineBreaks < 1 ||
        maxEmbeds < 0) {
      throw ArgumentError('Preview limits must be positive.');
    }
    final result = <NoteDocumentPreviewOperation>[];
    var remainingCharacters = maxCharacters;
    var remainingLineBreaks = maxLineBreaks;
    var embedCount = 0;
    for (final operation in _delta.operations) {
      if (result.length >= maxOperations ||
          remainingCharacters <= 0 ||
          remainingLineBreaks <= 0) {
        break;
      }
      final data = operation.data;
      if (data is String) {
        final prefix = _boundedPreviewText(
          data,
          maxCharacters: remainingCharacters,
          maxLineBreaks: remainingLineBreaks,
        );
        if (prefix.isNotEmpty) {
          result.add(
            NoteDocumentPreviewOperation(
              data: prefix,
              attributes: operation.attributes,
            ),
          );
          remainingCharacters -= prefix.length;
          remainingLineBreaks -= '\n'.allMatches(prefix).length;
        }
        if (prefix.length != data.length) break;
        continue;
      }
      if (embedCount >= maxEmbeds) break;
      result.add(NoteDocumentPreviewOperation(data: data));
      embedCount++;
    }
    return List.unmodifiable(result);
  }

  NoteDocumentPreviewSlice previewSlice({
    int maxCharacters = 900,
    int maxOperations = 72,
    int maxLineBreaks = 32,
    int maxEmbeds = 2,
  }) {
    if (maxCharacters < 1 ||
        maxOperations < 1 ||
        maxLineBreaks < 1 ||
        maxEmbeds < 0) {
      throw ArgumentError('Preview limits must be positive.');
    }

    final preview = Delta();
    var remainingCharacters = maxCharacters;
    var remainingLineBreaks = maxLineBreaks;
    var operationCount = 0;
    var embedCount = 0;
    var truncated = false;

    for (final operation in _delta.operations) {
      if (operationCount >= maxOperations ||
          remainingCharacters <= 0 ||
          remainingLineBreaks <= 0) {
        truncated = true;
        break;
      }
      final data = operation.data;
      if (data is String) {
        final prefix = _boundedPreviewText(
          data,
          maxCharacters: remainingCharacters,
          maxLineBreaks: remainingLineBreaks,
        );
        if (prefix.isNotEmpty) {
          preview.insert(prefix, operation.attributes);
          remainingCharacters -= prefix.length;
          remainingLineBreaks -= '\n'.allMatches(prefix).length;
          operationCount++;
        }
        if (prefix.length != data.length) {
          truncated = true;
          break;
        }
        continue;
      }
      if (embedCount >= maxEmbeds) {
        truncated = true;
        break;
      }
      preview.insert(data);
      embedCount++;
      operationCount++;
    }

    if (preview.isEmpty) {
      preview.insert('\n');
    } else if (!_deltaEndsWithNewline(preview)) {
      preview.insert('\n');
    }
    return NoteDocumentPreviewSlice(
      document: NoteDocument.fromDelta(preview),
      truncated: truncated,
    );
  }

  NoteDocumentProjection project({
    NoteEmbedTextResolver? resolveEmbedText,
    int? maxCharacters,
    int? maxOperations,
    int? maxEmbeds,
  }) {
    if (maxCharacters != null && maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters');
    }
    if (maxOperations != null && maxOperations < 1) {
      throw ArgumentError.value(maxOperations, 'maxOperations');
    }
    if (maxEmbeds != null && maxEmbeds < 0) {
      throw ArgumentError.value(maxEmbeds, 'maxEmbeds');
    }
    final text = StringBuffer();
    final attachmentIds = <NoteAttachmentId>[];
    final seenAttachmentIds = <NoteAttachmentId>{};
    var hasEmbeds = false;
    var truncated = false;
    var operationCount = 0;
    var embedCount = 0;

    for (final operation in _delta.operations) {
      if ((maxOperations != null && operationCount >= maxOperations) ||
          (maxCharacters != null && text.length >= maxCharacters)) {
        truncated = true;
        break;
      }
      operationCount++;
      final data = operation.data;
      if (data is String) {
        if (!_writeProjectionPart(text, data, maxCharacters)) {
          truncated = true;
          break;
        }
        continue;
      }
      if (maxEmbeds != null && embedCount >= maxEmbeds) {
        truncated = true;
        break;
      }
      final embed = NoteEmbed.parse(data);
      hasEmbeds = true;
      embedCount++;
      final attachmentId = embed.attachmentId;
      if (attachmentId != null && seenAttachmentIds.add(attachmentId)) {
        attachmentIds.add(attachmentId);
      }
      if (!_writeProjectionPart(
        text,
        resolveEmbedText?.call(embed) ??
            (embed.kind == NoteEmbedKind.table ? embed.table!.plainText : ''),
        maxCharacters,
      )) {
        truncated = true;
        break;
      }
    }

    final plainText = _withoutTerminalNewline(text.toString());
    return NoteDocumentProjection(
      plainText: plainText,
      searchText: plainText.replaceAll(_whitespacePattern, ' ').trim(),
      referencedAttachmentIds: List.unmodifiable(attachmentIds),
      hasEmbeds: hasEmbeds,
      truncated: truncated,
    );
  }

  static String _withoutTerminalNewline(String value) =>
      value.endsWith('\n') ? value.substring(0, value.length - 1) : value;

  static bool _writeProjectionPart(
    StringBuffer target,
    String value,
    int? maxCharacters,
  ) {
    if (maxCharacters == null) {
      target.write(value);
      return true;
    }
    final remaining = maxCharacters - target.length;
    if (remaining <= 0) return false;
    var end = value.length < remaining ? value.length : remaining;
    if (end > 0 &&
        end < value.length &&
        _isHighSurrogate(value.codeUnitAt(end - 1)) &&
        _isLowSurrogate(value.codeUnitAt(end))) {
      end--;
    }
    target.write(value.substring(0, end));
    return end == value.length;
  }

  static String _boundedPreviewText(
    String value, {
    required int maxCharacters,
    required int maxLineBreaks,
  }) {
    var end = value.length < maxCharacters ? value.length : maxCharacters;
    var lineBreaks = 0;
    for (var index = 0; index < end; index++) {
      if (value.codeUnitAt(index) != 10) continue;
      lineBreaks++;
      if (lineBreaks >= maxLineBreaks) {
        end = index + 1;
        break;
      }
    }
    if (end > 0 &&
        end < value.length &&
        _isHighSurrogate(value.codeUnitAt(end - 1)) &&
        _isLowSurrogate(value.codeUnitAt(end))) {
      end--;
    }
    return value.substring(0, end);
  }

  static bool _deltaEndsWithNewline(Delta value) {
    final data = value.operations.last.data;
    return data is String && data.endsWith('\n');
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  static Delta _canonicalize(Delta source) {
    final canonical = Delta();
    for (final operation in source.operations) {
      if (operation.isInsert && operation.data is! String) {
        // Quill can apply a selected inline style to an embed while formatting
        // across the whole document. It has no visual meaning for our block
        // nodes, so do not persist that incidental editor state.
        canonical.insert(operation.data);
      } else {
        canonical.push(operation);
      }
    }
    return canonical;
  }

  static ({List<NoteAttachmentId> attachmentIds, bool hasVisualContent})
  _validateDocumentDelta(Delta delta) {
    if (delta.isEmpty) {
      throw const FormatException('A note document cannot be empty.');
    }

    final attachmentIds = <NoteAttachmentId>[];
    final seenAttachmentIds = <NoteAttachmentId>{};
    var hasVisualContent = false;
    var lineHasText = false;
    var expectsNewlineAfterEmbed = false;
    var endsWithNewline = false;

    for (final operation in delta.operations) {
      if (!operation.isInsert) {
        throw const FormatException(
          'A persisted note must be an insert-only document delta.',
        );
      }
      final data = operation.data;
      if (data is String) {
        if (!hasVisualContent && data.trim().isNotEmpty) {
          hasVisualContent = true;
        }
        if (data.contains('\r')) {
          throw const FormatException('Note documents use LF line endings.');
        }
        if (data.contains(objectReplacementCharacter)) {
          throw const FormatException(
            'Object replacement characters must be represented as embeds.',
          );
        }
        for (final codeUnit in data.codeUnits) {
          final isNewline = codeUnit == 10;
          if (expectsNewlineAfterEmbed) {
            if (!isNewline) {
              throw const FormatException(
                'A block embed must occupy its own line.',
              );
            }
            expectsNewlineAfterEmbed = false;
            lineHasText = false;
            endsWithNewline = true;
            continue;
          }
          if (isNewline) {
            lineHasText = false;
            endsWithNewline = true;
          } else {
            lineHasText = true;
            endsWithNewline = false;
          }
        }
        continue;
      }

      if (lineHasText || expectsNewlineAfterEmbed) {
        throw const FormatException('A block embed must occupy its own line.');
      }
      final embed = NoteEmbed.parse(data);
      final attachmentId = embed.attachmentId;
      if (attachmentId != null && seenAttachmentIds.add(attachmentId)) {
        attachmentIds.add(attachmentId);
      }
      hasVisualContent = true;
      expectsNewlineAfterEmbed = true;
      endsWithNewline = false;
    }

    if (expectsNewlineAfterEmbed || !endsWithNewline) {
      throw const FormatException(
        'A Quill note document must end with a newline.',
      );
    }

    try {
      jsonEncode(delta.toJson());
    } on JsonUnsupportedObjectError {
      throw const FormatException(
        'The note document is not JSON serializable.',
      );
    }
    return (attachmentIds: attachmentIds, hasVisualContent: hasVisualContent);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteDocument && other._encoded == _encoded;

  @override
  int get hashCode => _encoded.hashCode;
}

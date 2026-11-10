import 'package:flutter_quill/quill_delta.dart';

import '../models/note_document.dart';
import 'note_markdown_codec.dart';

/// Applies assistant-authored Markdown at note mutation boundaries.
///
/// Existing notes stay native Delta documents. Only the incoming fragment is
/// decoded, so formatting and embeds outside the edited range are preserved.
final class NoteMarkdownMutation {
  static NoteDocument replaceDocument(String markdown) =>
      NoteDocument.fromDelta(NoteMarkdownCodec.decode(markdown));

  static NoteDocument append(NoteDocument document, String markdown) {
    final source = document.toDelta();
    final documentLength = _contentLength(source);
    final offset = (documentLength - 1).clamp(0, documentLength);
    final replacement = Delta();

    // Replace the terminal newline instead of inserting before it. Reusing its
    // attributes closes the existing block before the generated blocks begin.
    if (documentLength > 1) {
      final terminalAttributes = source.operations.last.attributes;
      replacement.insert(
        '\n',
        terminalAttributes == null
            ? null
            : Map<String, dynamic>.of(terminalAttributes),
      );
    }
    for (final operation in NoteMarkdownCodec.decode(markdown).operations) {
      replacement.push(operation);
    }

    final patch = Delta()..retain(offset);
    for (final operation in replacement.operations) {
      patch.push(operation);
    }
    if (documentLength > 0) patch.delete(1);
    return NoteDocument.fromDelta(source.compose(patch));
  }

  static NoteDocument replaceRange(
    NoteDocument document, {
    required int start,
    required int end,
    required String markdown,
  }) {
    final source = document.toDelta();
    final generated = NoteMarkdownCodec.decode(markdown);
    final replacement = _isSingleParagraph(generated)
        ? _withoutTerminalNewline(generated)
        : generated;
    final patch = Delta()..retain(start);
    for (final operation in replacement.operations) {
      patch.push(operation);
    }

    var deleteLength = end - start;
    // A block fragment already owns its terminal newline. When replacing all
    // visible content, consume the old terminal newline to avoid a blank block.
    if (end == _contentLength(source) - 1 && _endsWithNewline(replacement)) {
      deleteLength++;
    }
    if (deleteLength > 0) patch.delete(deleteLength);
    return NoteDocument.fromDelta(source.compose(patch));
  }

  static bool _isSingleParagraph(Delta delta) {
    final operations = delta.operations;
    if (operations.isEmpty || operations.last.attributes?.isNotEmpty == true) {
      return false;
    }
    for (var index = 0; index < operations.length; index++) {
      final data = operations[index].data;
      if (data is! String) return false;
      if (index < operations.length - 1 && data.contains('\n')) return false;
      if (index == operations.length - 1) {
        if (!data.endsWith('\n')) return false;
        if (data.substring(0, data.length - 1).contains('\n')) return false;
      }
    }
    return true;
  }

  static Delta _withoutTerminalNewline(Delta source) {
    final json = source.toJson().map(Map<String, dynamic>.from).toList();
    if (json.isEmpty) return Delta();
    final last = json.last;
    if (last['insert'] == '\n') {
      json.removeLast();
    } else if (last['insert'] case final String value
        when value.endsWith('\n')) {
      if (value.length == 1) {
        json.removeLast();
      } else {
        last['insert'] = value.substring(0, value.length - 1);
      }
    }
    return Delta.fromJson(json);
  }

  static bool _endsWithNewline(Delta delta) {
    if (delta.operations.isEmpty) return false;
    final data = delta.operations.last.data;
    return data is String && data.endsWith('\n');
  }

  static int _contentLength(Delta delta) => delta.operations.fold(
    0,
    (length, operation) => length + (operation.length ?? 0),
  );
}

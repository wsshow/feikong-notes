import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_document.dart';

typedef NotePreviewEmbedLabel =
    String Function(NoteEmbed embed, NoteAsset? asset);

/// A lightweight card projection of Delta content.
///
/// It preserves inline emphasis without creating an editor controller for
/// every list row. Markdown markers never participate in this path.
final class NoteDeltaPreview extends StatelessWidget {
  const NoteDeltaPreview({
    required this.note,
    this.maxLines = 3,
    this.maxCharacters = 600,
    this.maxOperations = 48,
    this.maxEmbeds = 4,
    this.style,
    this.embedLabel,
    this.includeAttachmentLabels = true,
    this.compactWhitespace = false,
    super.key,
  }) : assert(maxCharacters > 0),
       assert(maxOperations > 0),
       assert(maxEmbeds >= 0);

  final Note note;
  final int maxLines;
  final int maxCharacters;
  final int maxOperations;
  final int maxEmbeds;
  final TextStyle? style;
  final NotePreviewEmbedLabel? embedLabel;
  final bool includeAttachmentLabels;
  final bool compactWhitespace;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle();
    Map<NoteAttachmentId, NoteAsset>? assets;
    final spans = <InlineSpan>[];
    final operations = note.document.previewOperations(
      maxCharacters: maxCharacters,
      maxOperations: maxOperations,
      maxEmbeds: maxEmbeds,
    );
    var remainingCharacters = maxCharacters;
    var removeNextAttachmentLineBreak = false;
    var wroteCompactContent = false;
    var compactTrailingWhitespace = false;
    for (var index = 0; index < operations.length; index++) {
      if (remainingCharacters <= 0) break;
      final operation = operations[index];
      final data = operation.data;
      if (data is String) {
        var value = data;
        if (removeNextAttachmentLineBreak && value.startsWith('\n')) {
          value = value.substring(1);
        }
        removeNextAttachmentLineBreak = false;
        if (index == operations.length - 1 && value.endsWith('\n')) {
          value = value.substring(0, value.length - 1);
        }
        var reachedCharacterLimit = false;
        if (value.length > remainingCharacters) {
          value = _safePrefix(value, remainingCharacters);
          reachedCharacterLimit = true;
        }
        if (compactWhitespace) {
          final hadLeadingWhitespace =
              value.isNotEmpty && _leadingWhitespace.hasMatch(value);
          final hadTrailingWhitespace =
              value.isNotEmpty && _trailingWhitespace.hasMatch(value);
          final compactValue = value
              .replaceAll(_consecutiveWhitespace, ' ')
              .trim();
          if (compactValue.isEmpty) {
            compactTrailingWhitespace =
                compactTrailingWhitespace || value.isNotEmpty;
            continue;
          }
          final needsSpace =
              wroteCompactContent &&
              (compactTrailingWhitespace || hadLeadingWhitespace);
          value = '${needsSpace ? ' ' : ''}$compactValue';
          wroteCompactContent = true;
          compactTrailingWhitespace = hadTrailingWhitespace;
        }
        if (value.isEmpty) continue;
        remainingCharacters -= value.length;
        spans.add(
          TextSpan(
            text: value,
            style: _inlineStyle(baseStyle, operation.attributes),
          ),
        );
        if (reachedCharacterLimit) break;
        continue;
      }
      final embed = NoteEmbed.parse(data);
      final asset = (assets ??= note.assetsById)[embed.attachmentId];
      if (!includeAttachmentLabels &&
          (embed.kind == NoteEmbedKind.attachment ||
              embed.kind == NoteEmbedKind.fileReferences)) {
        removeNextAttachmentLineBreak = true;
        continue;
      }
      final label =
          embedLabel?.call(embed, asset) ??
          switch (embed.kind) {
            NoteEmbedKind.divider => '  —  ',
            NoteEmbedKind.fileReferences => '【${embed.fileReferenceText}】',
            NoteEmbedKind.table => embed.table!.plainTextPreview(
              remainingCharacters,
            ),
            NoteEmbedKind.attachment =>
              asset == null ? '【附件】' : '【${asset.displayTitle}】',
          };
      final prefix =
          compactWhitespace && wroteCompactContent && compactTrailingWhitespace
          ? ' '
          : '';
      var value = '$prefix$label';
      var reachedCharacterLimit = false;
      if (value.length > remainingCharacters) {
        value = _safePrefix(value, remainingCharacters);
        reachedCharacterLimit = true;
      }
      if (value.isEmpty) break;
      remainingCharacters -= value.length;
      spans.add(
        TextSpan(
          text: value,
          style: baseStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      );
      if (compactWhitespace) {
        wroteCompactContent = true;
        compactTrailingWhitespace = false;
      }
      if (reachedCharacterLimit) break;
    }
    return Text.rich(
      TextSpan(children: spans),
      key: const Key('note-delta-preview-text'),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle,
    );
  }

  static TextStyle _inlineStyle(
    TextStyle base,
    Map<String, dynamic>? attributes,
  ) {
    final values = attributes ?? const <String, dynamic>{};
    final decorations = <TextDecoration>[];
    if (values['underline'] == true) decorations.add(TextDecoration.underline);
    if (values['strike'] == true) decorations.add(TextDecoration.lineThrough);
    return base.copyWith(
      fontWeight: values['bold'] == true ? FontWeight.w700 : null,
      fontStyle: values['italic'] == true ? FontStyle.italic : null,
      fontFamily: values['code'] == true ? 'monospace' : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
    );
  }

  static String _safePrefix(String value, int length) {
    var end = length.clamp(0, value.length);
    if (end > 0 &&
        end < value.length &&
        _isHighSurrogate(value.codeUnitAt(end - 1)) &&
        _isLowSurrogate(value.codeUnitAt(end))) {
      end--;
    }
    return value.substring(0, end);
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  static final RegExp _leadingWhitespace = RegExp(r'^\s');
  static final RegExp _trailingWhitespace = RegExp(r'\s$');
  static final RegExp _consecutiveWhitespace = RegExp(r'\s+');
}

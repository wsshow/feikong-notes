import 'package:flutter_quill/quill_delta.dart';

/// A heading in the current editing document, addressed by its UTF-16 offset.
final class NoteOutlineEntry {
  const NoteOutlineEntry({
    required this.text,
    required this.level,
    required this.depth,
    required this.offset,
  });

  final String text;
  final int level;
  final int depth;
  final int offset;

  /// Read only when the outline is visible; never serialize or modify the note.
  static List<NoteOutlineEntry> fromDelta(Delta delta) {
    final entries = <NoteOutlineEntry>[];
    final ancestors = <int>[];
    final text = StringBuffer();
    var offset = 0;
    var lineOffset = 0;
    for (final operation in delta.operations) {
      final data = operation.data;
      if (data is! String) {
        // An embed occupies one document position, but is not a heading label.
        offset += operation.length ?? 1;
        continue;
      }
      var start = 0;
      for (
        var index = data.indexOf('\n');
        index >= 0;
        index = data.indexOf('\n', start)
      ) {
        text.write(data.substring(start, index));
        final level = operation.attributes?['header'];
        final label = text.toString().trim();
        if (level is int && level >= 1 && level <= 6 && label.isNotEmpty) {
          while (ancestors.isNotEmpty && ancestors.last >= level) {
            ancestors.removeLast();
          }
          entries.add(
            NoteOutlineEntry(
              text: label,
              level: level,
              depth: ancestors.length,
              offset: lineOffset,
            ),
          );
          ancestors.add(level);
        }
        text.clear();
        start = index + 1;
        lineOffset = offset + start;
      }
      text.write(data.substring(start));
      offset += data.length;
    }
    return List.unmodifiable(entries);
  }
}

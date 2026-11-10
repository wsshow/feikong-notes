import 'package:markdown/markdown.dart' as md;
import 'package:yaml/yaml.dart';

import '../models/note_document.dart';

/// A leading YAML mapping is metadata, not Markdown headings or rules.
/// Keep it as literal, editable table cells rather than hiding document data.
final class MarkdownFrontMatter {
  const MarkdownFrontMatter._(this.lineCount, this.rows, this.title);

  final int lineCount;
  final List<List<String>> rows;
  final String? title;

  static String normalize(String source) => source
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  static MarkdownFrontMatter? read(String source) {
    final lines = normalize(source).split('\n');
    return _readLines((index) => index < lines.length ? lines[index] : null);
  }

  static MarkdownFrontMatter? _readLines(String? Function(int) lineAt) {
    var opening = 0;
    while (lineAt(opening)?.trim().isEmpty == true) {
      opening++;
    }
    if (!RegExp(r'^---[ \t]*$').hasMatch(lineAt(opening) ?? '')) return null;
    final yaml = StringBuffer();
    // Bound work on untrusted shares and incomplete assistant streams.
    for (var index = opening + 1; index <= opening + 512; index++) {
      final line = lineAt(index);
      if (line == null) return null;
      if (RegExp(r'^(?:---|\.\.\.)[ \t]*$').hasMatch(line)) {
        try {
          final node = loadYamlNode(yaml.toString());
          if (node is! YamlMap ||
              node.isEmpty ||
              node.length > NoteTable.maxRows) {
            return null;
          }
          final rows = <List<String>>[];
          var totalCharacters = 0;
          String? title;
          for (final entry in node.nodes.entries) {
            final key = (entry.key as YamlNode).value;
            if (key is! String || key.trim().isEmpty) return null;
            final value = entry.value;
            // Do not recursively expand aliases or stringify YAML collections.
            // Source spans keep lists, nested mappings and numeric spellings.
            final text = value is YamlScalar && value.value is String
                ? value.value as String
                : value.span.text;
            if (key.length > NoteTable.maxCellCharacters ||
                text.length > NoteTable.maxCellCharacters) {
              return null;
            }
            totalCharacters += key.length + text.length;
            if (totalCharacters > NoteTable.maxTotalCharacters) return null;
            rows.add([key, text.trim()]);
            if (key == 'title' &&
                value is YamlScalar &&
                value.value is String) {
              title = text.trim();
            }
          }
          return MarkdownFrontMatter._(index + 1, rows, title);
        } on YamlException {
          return null;
        }
      }
      yaml.writeln(line);
      if (yaml.length > 32 * 1024) return null;
    }
    return null;
  }

  md.Element toElement() => md.Element('table', [
    md.Element('thead', [_row(rows.first, 'th')]),
    md.Element('tbody', [for (final row in rows.skip(1)) _row(row, 'td')]),
  ]);

  static md.Element _row(List<String> cells, String tag) =>
      md.Element('tr', [for (final cell in cells) md.Element.text(tag, cell)]);
}

/// Shared by the reading surface and Markdown-to-Delta conversion.
final class MarkdownFrontMatterSyntax extends md.BlockSyntax {
  const MarkdownFrontMatterSyntax();

  @override
  RegExp get pattern => RegExp(r'^---[ \t]*$');

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser) || parser.parentSyntax != null) return false;
    // A rule elsewhere, including inside a quote/list, is never front matter.
    for (final line in parser.lines) {
      if (identical(line, parser.current)) break;
      if (line.content.trim().isNotEmpty) return false;
    }
    return MarkdownFrontMatter._readLines(
          (index) => parser.peek(index)?.content,
        ) !=
        null;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final metadata = MarkdownFrontMatter._readLines(
      (index) => parser.peek(index)?.content,
    )!;
    for (var index = 0; index < metadata.lineCount; index++) {
      parser.advance();
    }
    return metadata.toElement();
  }
}

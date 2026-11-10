import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';

enum NoteAssistantEditScope { selection, currentLine, document }

enum NoteAssistantEditPlacement { replace, insertBelow, append }

/// The inline editor target chosen before generation starts.
///
/// Unlike background note tools, every target is applied by the active Quill
/// editor and remains available as one atomic undo operation.
enum NoteInlineAssistantTarget {
  cursor,
  selection,
  currentLine,
  document,
  metadata,
}

final class NoteAssistantAnchor {
  const NoteAssistantAnchor({
    required this.expectedDocument,
    required this.selection,
    required this.lineStart,
    required this.lineEnd,
    required this.selectedText,
    required this.currentLineText,
  });

  final String expectedDocument;
  final TextSelection selection;
  final int lineStart;
  final int lineEnd;
  final String selectedText;
  final String currentLineText;

  bool get hasSelection => selectedText.trim().isNotEmpty;
  bool get hasCurrentLine => currentLineText.trim().isNotEmpty;
}

String encodeAssistantExpectedDocument(Delta delta) =>
    jsonEncode(delta.toJson());

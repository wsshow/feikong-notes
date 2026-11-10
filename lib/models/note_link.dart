import 'note.dart';

/// An undirected, persistent relationship between two notes.
///
/// IDs are stored in lexical order so the same relationship can never be
/// inserted twice in opposite directions.
final class NoteLink {
  NoteLink({
    required this.firstNoteId,
    required this.secondNoteId,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc() {
    if (firstNoteId == secondNoteId) {
      throw ArgumentError('A note cannot be linked to itself');
    }
    if (firstNoteId.value.compareTo(secondNoteId.value) >= 0) {
      throw ArgumentError('Note link IDs must use canonical lexical order');
    }
  }

  factory NoteLink.between(
    NoteId first,
    NoteId second, {
    required DateTime createdAt,
  }) {
    if (first == second) {
      throw ArgumentError('A note cannot be linked to itself');
    }
    return first.value.compareTo(second.value) < 0
        ? NoteLink(
            firstNoteId: first,
            secondNoteId: second,
            createdAt: createdAt,
          )
        : NoteLink(
            firstNoteId: second,
            secondNoteId: first,
            createdAt: createdAt,
          );
  }

  final NoteId firstNoteId;
  final NoteId secondNoteId;
  final DateTime createdAt;

  bool connects(NoteId noteId) =>
      firstNoteId == noteId || secondNoteId == noteId;

  NoteId other(NoteId noteId) {
    if (firstNoteId == noteId) return secondNoteId;
    if (secondNoteId == noteId) return firstNoteId;
    throw ArgumentError.value(noteId, 'noteId', 'Not part of this link');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteLink &&
          other.firstNoteId == firstNoteId &&
          other.secondNoteId == secondNoteId;

  @override
  int get hashCode => Object.hash(firstNoteId, secondNoteId);
}

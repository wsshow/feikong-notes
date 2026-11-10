import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'overview text is bounded, normalized and cached per immutable note',
    () {
      final note = _note(
        Delta()
          ..insert('  ${List.filled(800, '正文  ').join()}')
          ..insert('不应读取的尾部\n'),
      );

      final first = note.overviewText;
      final second = note.overviewText;

      expect(identical(first, second), isTrue);
      expect(first.length, lessThanOrEqualTo(Note.overviewMaxCharacters));
      expect(first, isNot(contains('不应读取的尾部')));
      expect(first, isNot(contains('  ')));
    },
  );

  test('overview attachment labels are opt-in and remain bounded', () {
    final attachmentId = NoteAttachmentId.generate();
    final now = DateTime.utc(2026, 9, 3);
    final asset = NoteAsset(
      id: attachmentId,
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/overview.png',
      originalName: '概览图片.png',
      byteLength: 10,
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final note = Note(
      id: NoteId.generate(),
      title: '图片笔记',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('正文\n')
          ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
      createdAt: now,
      updatedAt: now,
    );

    expect(note.overviewText, '正文');
    expect(note.overviewTextWithAttachments, '正文 概览图片.png');
  });

  test('document metadata avoids projecting text to validate note assets', () {
    final attachmentId = NoteAttachmentId.generate();
    final document = NoteDocument.fromDelta(
      Delta()
        ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
        ..insert('\n'),
    );

    expect(document.referencedAttachmentIds, [attachmentId]);
    expect(document.isVisuallyEmpty, isFalse);
    expect(NoteDocument.empty().isVisuallyEmpty, isTrue);
  });
}

Note _note(Delta delta) {
  final now = DateTime.utc(2026, 9, 3);
  return Note(
    id: NoteId.generate(),
    title: '长笔记',
    document: NoteDocument.fromDelta(delta),
    createdAt: now,
    updatedAt: now,
  );
}

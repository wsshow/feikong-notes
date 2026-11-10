import 'dart:convert';

import 'package:fknotes/models/note_document.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteDocument', () {
    test('stores a versioned canonical Delta envelope', () {
      final document = NoteDocument.empty();

      expect(jsonDecode(document.toJsonString()), {
        'schemaVersion': 1,
        'delta': [
          {'insert': '\n'},
        ],
      });
      expect(document.toQuillDocument().toPlainText(), '\n');
    });

    test('round trips Quill styles without exposing markup as plain text', () {
      final delta = Delta()
        ..insert('加粗', {'bold': true})
        ..insert('与普通文本\n');
      final document = NoteDocument.fromDelta(delta);
      final restored = NoteDocument.fromJsonString(document.toJsonString());

      expect(restored, document);
      expect(restored.toDelta().toJson(), delta.toJson());
      expect(restored.project().plainText, '加粗与普通文本');
      expect(restored.project().searchText, '加粗与普通文本');
    });

    test('creates a bounded valid prefix for animated card previews', () {
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert('${List.filled(400, '正文').join()}\n', {'header': 1})
          ..insert('不会进入预览\n'),
      );

      final slice = document.previewSlice(
        maxCharacters: 121,
        maxOperations: 8,
        maxLineBreaks: 4,
      );

      expect(slice.truncated, isTrue);
      expect(slice.document.toQuillDocument().toPlainText(), endsWith('\n'));
      expect(slice.document.project().plainText.length, lessThanOrEqualTo(121));
      expect(slice.document.project().plainText, isNot(contains('不会进入预览')));
    });

    test('projects a bounded prefix without copying the document', () {
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert('${List.filled(100, '甲').join()}🙂')
          ..insert('\n不会进入投影\n'),
      );

      final projection = document.project(
        maxCharacters: 101,
        maxOperations: 4,
        maxEmbeds: 0,
      );

      expect(projection.plainText.length, 100);
      expect(projection.plainText, isNot(contains('不会进入投影')));
      expect(
        projection.plainText.codeUnits.last,
        isNot(inInclusiveRange(0xD800, 0xDBFF)),
      );
    });

    test('projects stable attachment embeds through the consumer resolver', () {
      final firstId = NoteAttachmentId.parse(
        '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
      );
      final secondId = NoteAttachmentId.parse(
        'dca51acb-2e50-4ef1-9ad8-c4ce1e150f48',
      );
      final delta = Delta()
        ..insert('正文\n')
        ..insert(NoteEmbed.attachment(firstId).toDeltaData())
        ..insert('\n')
        ..insert(NoteEmbed.attachment(secondId).toDeltaData())
        ..insert('\n')
        ..insert(NoteEmbed.attachment(firstId).toDeltaData())
        ..insert('\n');
      final document = NoteDocument.fromDelta(delta);

      final projection = document.project(
        resolveEmbedText: (embed) => switch (embed.kind) {
          NoteEmbedKind.attachment => '【${embed.attachmentId}】',
          NoteEmbedKind.divider => '——',
          NoteEmbedKind.fileReferences => embed.fileReferenceText,
          NoteEmbedKind.table => embed.table!.plainText,
        },
      );

      expect(projection.plainText, '正文\n【$firstId】\n【$secondId】\n【$firstId】');
      expect(projection.referencedAttachmentIds, [firstId, secondId]);
      expect(projection.hasEmbeds, isTrue);
      expect(projection.isVisuallyEmpty, isFalse);
    });

    test('round trips a bounded table embed without losing cell content', () {
      final table = NoteTable(
        rows: const [
          ['项目', '状态'],
          ['Quill', '完成'],
          ['分享图', '待检查'],
        ],
        alignments: const [NoteTableAlignment.start, NoteTableAlignment.center],
      );
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.table(table).toDeltaData())
          ..insert('\n'),
      );
      final restored = NoteDocument.fromJsonString(document.toJsonString());
      final embed = NoteEmbed.parse(restored.toDelta().operations.first.data);

      expect(embed.kind, NoteEmbedKind.table);
      expect(embed.table!.rows, table.rows);
      expect(embed.table!.alignments, table.alignments);
      expect(restored.project().plainText, '项目\t状态\nQuill\t完成\n分享图\t待检查');
      expect(restored.project().searchText, '项目 状态 Quill 完成 分享图 待检查');
      expect(table.plainTextPreview(8), '项目\t状态\nQu');
    });

    test('rejects malformed and unbounded table embeds', () {
      expect(
        () => NoteEmbed.parse({
          NoteEmbed.tableType: {
            'rows': [
              ['项目', 1],
            ],
            'alignments': ['start', 'end'],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => NoteTable(
          rows: [
            for (var index = 0; index <= NoteTable.maxRows; index++) ['$index'],
          ],
        ),
        throwsFormatException,
      );
    });

    test(
      'round trips grouped file identities without adding note attachments',
      () {
        final reference = NoteFileReference(
          fileId: NoteAttachmentId.generate().value,
          name: '方案.zip',
          size: 900,
        );
        final embed = NoteEmbed.fileReferences([reference, reference]);
        final document = NoteDocument.fromDelta(
          Delta()
            ..insert(embed.toDeltaData())
            ..insert('\n'),
        );
        final restored = NoteDocument.fromJsonString(document.toJsonString());
        expect(restored.referencedAttachmentIds, isEmpty);
        expect(restored.isVisuallyEmpty, isFalse);
        final group = NoteEmbed.parse(restored.toDelta().operations.first.data);
        expect(group.fileReferences.single.fileId, reference.fileId);
        expect(group.fileReferenceText, '方案.zip');
        expect(() => NoteEmbed.fileReferences([]), throwsFormatException);
        expect(
          () => NoteFileReference(fileId: '../file', name: 'bad', size: 1),
          throwsFormatException,
        );
        expect(
          () => NoteEmbed.parse({
            NoteEmbed.fileReferencesType: [
              {'id': reference.fileId, 'name': 'bad', 'size': -1},
            ],
          }),
          throwsFormatException,
        );
        expect(
          () => NoteEmbed.parse({
            NoteEmbed.fileReferencesType: List.filled(1001, reference.toJson()),
          }),
          throwsFormatException,
        );
      },
    );

    test('an embed-only document is not visually empty', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(id).toDeltaData())
          ..insert('\n'),
      );

      expect(document.project().plainText, '');
      expect(document.project().isVisuallyEmpty, isFalse);
    });

    test('removes incidental inline styles from block embeds', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(id).toDeltaData(), {'bold': true})
          ..insert('\n'),
      );

      expect(document.toDelta().toJson(), [
        {'insert': NoteEmbed.attachment(id).toDeltaData()},
        {'insert': '\n'},
      ]);
    });

    test('rejects file paths and non-canonical attachment IDs', () {
      final delta = Delta()
        ..insert({
          NoteEmbed.attachmentType: {'id': '/data/user/0/note/image.png'},
        })
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects built-in image embeds that can persist local paths', () {
      final delta = Delta()
        ..insert({'image': '/data/user/0/note/image.png'})
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects block embeds mixed into a text line', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final delta = Delta()
        ..insert('前文')
        ..insert(NoteEmbed.attachment(id).toDeltaData())
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects change deltas and missing terminal newline', () {
      expect(
        () => NoteDocument.fromDelta(Delta()..retain(1)),
        throwsFormatException,
      );
      expect(
        () => NoteDocument.fromDelta(Delta()..insert('正文')),
        throwsFormatException,
      );
    });

    test('rejects unversioned and unknown document envelopes', () {
      expect(
        () => NoteDocument.fromJsonString('[{"insert":"正文\\n"}]'),
        throwsFormatException,
      );
      expect(
        () => NoteDocument.fromJsonString(
          '{"schemaVersion":2,"delta":[{"insert":"\\n"}]}',
        ),
        throwsFormatException,
      );
    });
  });

  group('NoteAttachmentId', () {
    test('generates canonical stable IDs', () {
      final id = NoteAttachmentId.generate();

      expect(NoteAttachmentId.parse(id.value), id);
    });
  });
}

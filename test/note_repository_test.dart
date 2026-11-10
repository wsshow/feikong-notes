import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late NoteRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    repository = NoteRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test(
    'reminders round trip in UTC, survive ordinary edits and can be cleared',
    () async {
      final time = DateTime(2026, 9, 1, 10, 30);
      final note = await repository.create(
        Note.newDraft().copyWith(reminderAt: time),
      );
      expect(note.isMeaningfullyEmpty, isFalse);
      expect(note.reminderAt!.isUtc, isTrue);
      expect((await repository.get(note.id))?.reminderAt, time.toUtc());
      final edited = await repository.update(
        note.copyWith(title: '稍后处理', isPrivate: true),
      );
      expect(edited.reminderAt, time.toUtc());
      expect(await repository.isPrivateNote(note.id), isTrue);
      final removed = await repository.update(
        edited.copyWith(reminderAt: null),
      );
      expect(removed.reminderAt, isNull);
      expect(
        (await repository.get(note.id, privateSpace: true))?.reminderAt,
        isNull,
      );
    },
  );

  test(
    'reminder synchronization observes committed writes, never failed revisions',
    () async {
      final changes = <NoteId>[];
      final hooked = NoteRepository(
        database,
        onNoteChanged: (id) async {
          // Reading here would deadlock if the hook ran inside the transaction.
          await database.query('notes', where: 'id = ?', whereArgs: [id.value]);
          changes.add(id);
        },
      );
      final note = await hooked.create(Note.newDraft());
      await hooked.update(note.copyWith(reminderAt: DateTime.utc(2027)));
      await expectLater(hooked.update(note), throwsA(isA<NoteWriteConflict>()));
      await hooked.deletePermanently(note.id);
      expect(changes, [note.id, note.id, note.id]);
    },
  );

  test(
    'private notes require an explicit space for list, lookup and all search paths',
    () async {
      final private = await repository.create(
        _noteFixture().note.copyWith(isPrivate: true),
      );
      final public = await repository.create(
        Note.newDraft().copyWith(title: '公开笔记'),
      );
      expect(await repository.hasPrivateNotes(), isTrue);
      expect((await repository.list()).map((n) => n.id), [public.id]);
      expect((await repository.list(privateSpace: true)).map((n) => n.id), [
        private.id,
      ]);
      expect(await repository.get(private.id), isNull);
      expect(await repository.get(public.id, privateSpace: true), isNull);
      expect(
        (await repository.get(private.id, privateSpace: true))?.isPrivate,
        isTrue,
      );
      expect(await repository.search('', privateSpace: true), isEmpty);
      for (final query in ['正', '正文', '设计', '原图', '手写会议纪要']) {
        expect(
          (await repository.search(query)).map((n) => n.id),
          isNot(contains(private.id)),
        );
        expect(
          (await repository.search(query, privateSpace: true)).map((n) => n.id),
          contains(private.id),
        );
      }
      final edited = await repository.update(private.copyWith(title: '隐私编辑后'));
      expect(edited.isPrivate, isTrue);
      final moved = await repository.update(edited.copyWith(isPrivate: false));
      expect((await repository.get(moved.id))?.title, '隐私编辑后');
      expect(await repository.list(privateSpace: true), isEmpty);
      expect(await repository.hasPrivateNotes(), isFalse);
    },
  );

  test('a new private draft remains private through ordinary edits', () {
    final note = Note.newDraft(
      isPrivate: true,
    ).copyWith(title: '私密草稿', isPinned: true);
    expect(note.isPrivate, isTrue);
    expect(Note.newDraft().isPrivate, isFalse);
  });

  test(
    'persists a complete Delta note graph without legacy body columns',
    () async {
      final fixture = _noteFixture();

      final created = await repository.create(fixture.note);
      final restored = await repository.get(created.id);

      expect(created.revision, 1);
      expect(restored?.revision, 1);
      expect(
        restored?.document.toDelta().toJson(),
        fixture.note.document.toDelta().toJson(),
      );
      expect(restored?.assets.single.id, fixture.asset.id);
      expect(restored?.coverAttachmentId, fixture.asset.id);
      expect(restored?.tags, ['设计', '离线']);
      expect(restored?.contentProjection.plainText, '正文\n【原图.png】');

      final columns = await database.rawQuery('PRAGMA table_info(notes)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names, containsAll(['document_json', 'search_text', 'revision']));
      expect(names, isNot(contains('content')));
      expect(names, isNot(contains('rich_content')));
      expect(names, isNot(contains('file_path')));
    },
  );

  test('searches projected text, tags and asset intelligence', () async {
    final created = await repository.create(_noteFixture().note);

    for (final query in ['正文', '设计', '原图', '手写会议纪要']) {
      expect((await repository.search(query)).map((note) => note.id), [
        created.id,
      ]);
    }
  });

  test('structured queries combine filters and return exact pages', () async {
    final fixture = _noteFixture();
    final matching = await repository.create(
      fixture.note.copyWith(
        title: '八月新闻日报',
        tags: const ['新闻', '重要'],
        isPinned: true,
      ),
    );
    final later = DateTime.utc(2026, 8, 24, 12);
    final other = await repository.create(
      Note.newDraft(now: later).copyWith(
        title: '八月行业观察',
        tags: const ['新闻'],
        document: NoteDocument.fromPlainText('行业新闻摘要'),
      ),
    );

    final filtered = await repository.queryPage(
      NoteQueryFilter(
        query: '正文',
        title: '新闻日报',
        tags: const ['新闻', '重要'],
        createdFrom: DateTime.utc(2026, 7, 1),
        createdTo: DateTime.utc(2026, 7, 31, 23, 59, 59, 999),
        isPinned: true,
        hasAttachments: true,
      ),
    );
    expect(filtered.total, 1);
    expect(filtered.notes.map((note) => note.id), [matching.id]);

    final firstPage = await repository.queryPage(
      const NoteQueryFilter(
        tags: ['不存在', '新闻'],
        matchAllTags: false,
        sort: NoteQuerySort.titleAsc,
      ),
      limit: 1,
    );
    final secondPage = await repository.queryPage(
      const NoteQueryFilter(
        tags: ['不存在', '新闻'],
        matchAllTags: false,
        sort: NoteQuerySort.titleAsc,
      ),
      offset: 1,
      limit: 1,
    );
    expect(firstPage.total, 2);
    expect(firstPage.notes.single.id, matching.id);
    expect(secondPage.total, 2);
    expect(secondPage.notes.single.id, other.id);
  });

  test(
    'OCR updates persist and refresh search without changing the body',
    () async {
      final fixture = _noteFixture();
      final original = await repository.create(
        fixture.note.copyWith(assets: [fixture.asset.copyWith(ocrText: null)]),
      );
      final recognized = await repository.update(
        original.copyWith(
          assets: [original.assets.single.copyWith(ocrText: '图内文字 OCR123')],
        ),
      );
      final restored = (await repository.get(recognized.id))!;
      expect(restored.assets.single.ocrText, '图内文字 OCR123');
      expect(
        restored.document.toDelta().toJson(),
        original.document.toDelta().toJson(),
      );
      expect((await repository.search('OCR123')).map((note) => note.id), [
        original.id,
      ]);
      await repository.update(
        restored.copyWith(
          assets: [
            restored.assets.single.copyWith(
              storageKey: 'notes/images/replaced.png',
              ocrText: null,
            ),
          ],
        ),
      );
      expect(await repository.search('OCR123'), isEmpty);
    },
  );

  test('uses revisions to reject stale automatic saves', () async {
    final original = await repository.create(_noteFixture().note);
    final updated = await repository.update(
      original.copyWith(
        title: '新标题',
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      ),
    );

    expect(updated.revision, 2);
    expect((await repository.get(original.id))?.title, '新标题');
    await expectLater(
      repository.update(original.copyWith(title: '过期写入')),
      throwsA(isA<NoteWriteConflict>()),
    );
    expect((await repository.get(original.id))?.title, '新标题');
  });

  test('permanent deletion cascades through the complete note graph', () async {
    final original = await repository.create(_noteFixture().note);
    expect(await repository.search('正文'), hasLength(1));

    await repository.deletePermanently(original.id);
    expect(await repository.get(original.id), isNull);
    expect(await database.query('note_assets'), isEmpty);
    expect(await database.query('note_tags'), isEmpty);
  });

  test('rejects missing and detached assets before persistence', () {
    final fixture = _noteFixture();

    expect(() => fixture.note.copyWith(assets: const []), throwsArgumentError);

    final detached = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.file,
      storageKey: 'notes/files/detached.pdf',
      originalName: 'detached.pdf',
      byteLength: 10,
      mimeType: 'application/pdf',
      createdAt: fixture.note.createdAt,
      updatedAt: fixture.note.updatedAt,
    );
    expect(
      () => fixture.note.copyWith(assets: [fixture.asset, detached]),
      throwsArgumentError,
    );
  });

  test('rejects absolute and traversing storage paths', () {
    final now = DateTime.utc(2026, 7, 23);

    for (final path in [
      '/data/image.png',
      '../image.png',
      'C:/image.png',
      'images/old.png',
      'notes/files/wrong-kind.png',
      'notes/images//duplicate.png',
    ]) {
      expect(
        () => NoteAsset(
          id: NoteAttachmentId.generate(),
          kind: NoteAssetKind.image,
          storageKey: path,
          originalName: 'image.png',
          byteLength: 1,
          mimeType: 'image/png',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => NoteAsset(
        id: NoteAttachmentId.generate(),
        kind: NoteAssetKind.image,
        storageKey: 'notes/images/image.png',
        previewStorageKey: 'thumbnails/old-preview.jpg',
        originalName: 'image.png',
        byteLength: 1,
        mimeType: 'image/png',
        createdAt: now,
        updatedAt: now,
      ),
      throwsArgumentError,
    );
  });
}

({Note note, NoteAsset asset}) _noteFixture() {
  final now = DateTime.utc(2026, 7, 23, 10);
  final attachmentId = NoteAttachmentId.parse(
    '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
  );
  final asset = NoteAsset(
    id: attachmentId,
    kind: NoteAssetKind.image,
    storageKey: 'notes/images/3d2be3d5.png',
    originalName: '原图.png',
    byteLength: 2048,
    mimeType: 'image/png',
    previewStorageKey: 'notes/thumbnails/3d2be3d5.webp',
    ocrText: '手写会议纪要',
    createdAt: now,
    updatedAt: now,
  );
  final document = NoteDocument.fromDelta(
    Delta()
      ..insert('正文\n', {'header': 1})
      ..insert(NoteEmbed.attachment(attachmentId).toDeltaData())
      ..insert('\n'),
  );
  return (
    note: Note(
      id: NoteId.parse('be0afe23-f682-4d98-a942-e6e010a45d07'),
      title: '项目记录',
      document: document,
      tags: const ['设计', ' 离线 ', '设计'],
      coverAttachmentId: attachmentId,
      assets: [asset],
      createdAt: now,
      updatedAt: now,
    ),
    asset: asset,
  );
}

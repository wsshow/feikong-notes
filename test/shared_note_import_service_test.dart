import 'dart:convert';
import 'dart:io';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/incoming_share_service.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:fknotes/services/shared_note_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late Directory inbox;
  late Database db;
  late NoteRepository repository;
  late SharedNoteImportService importer;
  late NoteId shareId;
  final time = DateTime.utc(2026, 8, 27, 9);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_share_test_');
    await FileStorageService.instance.init(
      baseDir: p.join(root.path, 'managed'),
    );
    shareId = NoteId.generate();
    inbox = await Directory(p.join(root.path, shareId.value)).create();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    repository = NoteRepository(db);
    await repository.initialize();
    importer = SharedNoteImportService(
      repositoryLoader: () async => repository,
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<SharedFile> file(
    String extension,
    List<int> bytes,
    String mime, {
    String? originalName,
  }) async {
    final name = '${NoteId.generate().value}$extension';
    await File(p.join(inbox.path, name)).writeAsBytes(bytes);
    return SharedFile(
      name: originalName ?? '分享$extension',
      fileName: name,
      mimeType: mime,
      byteLength: bytes.length,
    );
  }

  IncomingShare share({
    String text = '',
    String title = '',
    List<SharedFile> files = const [],
  }) => IncomingShare(
    id: shareId,
    directory: inbox.path,
    createdAt: time,
    text: text,
    title: title,
    files: files,
  );

  test(
    'text, subject and links become a separate saved regular note',
    () async {
      final current = await repository.create(
        Note.newDraft(isPrivate: true).copyWith(title: '正在编辑的笔记'),
      );
      final saved = await importer.import(
        share(title: '网页', text: '介绍\r\nhttps://example.org/article'),
      );
      expect(saved.id, shareId);
      expect(saved.title, '网页');
      expect(saved.isPrivate, isFalse);
      expect(saved.revision, 1);
      expect(saved.createdAt, time);
      expect(
        saved.document.toDelta().toJson(),
        contains(
          equals({
            'insert': 'https://example.org/article',
            'attributes': {'link': 'https://example.org/article'},
          }),
        ),
      );
      expect(
        (await repository.get(current.id, privateSpace: true))!.title,
        current.title,
      );
      expect(await repository.list(), hasLength(1));
    },
  );

  test('plain text files become editable text, not attachments', () async {
    final document = await file(
      '.txt',
      utf8.encode('\uFEFF中文笔记 🌱\r\n第二段\rhttps://example.org/note'),
      'text/plain',
    );
    final payload = share(files: [document]);
    final saved = await importer.import(payload);
    expect(saved.assets, isEmpty);
    expect(saved.document.toDelta().toJson(), [
      {'insert': '中文笔记 🌱\n第二段\n'},
      {
        'insert': 'https://example.org/note',
        'attributes': {'link': 'https://example.org/note'},
      },
      {'insert': '\n'},
    ]);
    await inbox.delete(recursive: true);
    expect((await repository.get(saved.id))!.document, saved.document);
    expect((await importer.import(payload)).id, saved.id);
    expect(await repository.list(), hasLength(1));
  });

  test(
    'shared Markdown renders its body and preserves YAML metadata',
    () async {
      final saved = await importer.import(
        share(text: _markdownWithFrontMatter),
      );
      final operations = saved.document.toDelta().operations;
      final metadata = NoteEmbed.parse(
        operations.firstWhere((operation) => operation.data is! String).data,
      );
      expect(saved.title, '儿童笔记 App 全局设计规范（晴空成长主题）');
      expect(metadata.kind, NoteEmbedKind.table);
      expect(metadata.table!.rows, [
        ['title', saved.title],
        ['version', '1.0.0'],
        ['status', 'Baseline'],
        ['updated', '2026-08-27'],
        ['platforms', '[iOS, Android]'],
        ['target_users', '7–12 岁儿童及辅助使用的家长/教师'],
      ]);
      expect(operations.any((op) => op.attributes?['header'] == 1), isTrue);
      expect(
        operations.any((op) => op.attributes?['blockquote'] == true),
        isTrue,
      );
      expect(operations.any((op) => op.attributes?['bold'] == true), isTrue);
      expect(
        operations.any((op) => op.attributes?['list'] == 'bullet'),
        isTrue,
      );
      expect(saved.document.project().plainText, isNot(contains('---')));
      expect((await repository.get(saved.id))!.document, saved.document);
    },
  );

  test(
    'Markdown files use the same renderer without overriding share titles',
    () async {
      final document = await file(
        '.bin',
        utf8.encode(
          '\uFEFF${_markdownWithFrontMatter.replaceAll('\n', '\r\n')}',
        ),
        'Text/Markdown; charset=utf-8',
        originalName: '设计规范.MARKDOWN',
      );
      final saved = await importer.import(
        share(title: '分享标题', files: [document]),
      );
      expect(saved.title, '分享标题');
      expect(saved.assets, isEmpty);
      expect(
        saved.document.toDelta().operations.any(
          (op) => op.attributes?['header'] == 1,
        ),
        isTrue,
      );
      expect(
        saved.document.project().plainText,
        contains('platforms\t[iOS, Android]'),
      );
    },
  );

  test(
    'Markdown image references remain links without fetching remote files',
    () async {
      final saved = await importer.import(
        share(
          text:
              '![示意图](https://example.org/image.png)\n\n![](https://example.org/other.png)',
        ),
      );
      expect(saved.assets, isEmpty);
      expect(
        saved.document
            .toDelta()
            .operations
            .where((op) => op.attributes?['link'] != null)
            .map((op) => op.attributes!['link']),
        ['https://example.org/image.png', 'https://example.org/other.png'],
      );
      expect(saved.document.project().plainText, contains('示意图'));
      expect(
        saved.document.project().plainText,
        contains('https://example.org/other.png'),
      );
    },
  );

  test(
    'text detection accepts MIME or original and staged extensions',
    () async {
      final namedText = await file(
        '.bin',
        utf8.encode('原文件名识别'),
        'application/octet-stream',
        originalName: '随手记.TXT',
      );
      final typedText = await file(
        '',
        utf8.encode('无扩展名文本'),
        'Text/Plain; charset=utf-8',
      );
      final markdown = await file(
        '.md',
        utf8.encode('# 渲染 Markdown 标题'),
        'application/octet-stream',
        originalName: '分享',
      );
      final saved = await importer.import(
        share(files: [namedText, typedText, markdown]),
      );
      expect(saved.assets, isEmpty);
      expect(
        saved.document.project().plainText,
        '原文件名识别\n无扩展名文本\n渲染 Markdown 标题',
      );
      expect(saved.document.toDelta().operations.last.attributes, {
        'header': 1,
      });
    },
  );

  test(
    'UTF-16 files with either BOM preserve Chinese and surrogate pairs',
    () async {
      final littleEndian = await file('.txt', [
        0xFF,
        0xFE,
        0x60,
        0x4F,
        0x7D,
        0x59,
        0x3C,
        0xD8,
        0x1F,
        0xDF,
        0x0D,
        0x00,
        0x0A,
        0x00,
      ], 'text/plain');
      final bigEndian = await file('.txt', [
        0xFE,
        0xFF,
        0x4F,
        0x60,
        0x59,
        0x7D,
        0xD8,
        0x3C,
        0xDF,
        0x1F,
      ], 'text/plain');
      final saved = await importer.import(
        share(files: [littleEndian, bigEndian]),
      );
      expect(saved.assets, isEmpty);
      expect(saved.document.project().plainText, '你好🌟\n你好🌟');
    },
  );

  test(
    'multiple media and documents keep their order and survive source cleanup',
    () async {
      final firstText = await file('.txt', utf8.encode('前文'), 'text/plain');
      final image = await file(
        '.png',
        img.encodePng(img.Image(width: 8, height: 8)),
        'image/png',
      );
      final audio = await file('.mp3', [1, 2, 3], 'audio/mpeg');
      final secondText = await file('.txt', utf8.encode('后文'), 'text/plain');
      final video = await file('.mp4', [4, 5, 6], 'video/mp4');
      final document = await file('.pdf', [7, 8, 9], 'application/pdf');
      final saved = await importer.import(
        share(
          text: '说明',
          files: [firstText, image, audio, secondText, video, document],
        ),
      );
      expect(saved.assets.map((asset) => asset.kind), [
        NoteAssetKind.image,
        NoteAssetKind.audio,
        NoteAssetKind.video,
        NoteAssetKind.file,
      ]);
      expect(saved.coverAttachmentId, saved.assets.first.id);
      expect(
        saved.document
            .project(
              resolveEmbedText: (embed) => saved.assets
                  .firstWhere((asset) => asset.id == embed.attachmentId)
                  .kind
                  .name,
            )
            .plainText,
        '说明\n前文\nimage\naudio\n后文\nvideo\nfile',
      );
      await inbox.delete(recursive: true);
      for (final asset in saved.assets) {
        expect(
          await FileStorageService.instance.fileExists(asset.storageKey),
          isTrue,
        );
      }
      expect((await repository.get(saved.id))!.assets, hasLength(4));
    },
  );

  test(
    'non-text and undecodable files are preserved without data loss',
    () async {
      final files = [
        await file('.pdf', utf8.encode('%PDF-1.7'), 'application/pdf'),
        await file('.txt', [0xC3, 0x28], 'text/plain'),
        await file('.txt', [0x00, 0x01, 0x41], 'text/plain'),
        await file('.txt', [0xFF, 0xFE, 0x41], 'text/plain'),
        await file('.txt', [0xFF, 0xFE, 0x00, 0xD8], 'text/plain'),
        await file('.txt', [0xFE, 0xFF, 0xDC, 0x00], 'text/plain'),
      ];
      final saved = await importer.import(share(files: files));
      expect(saved.assets, hasLength(files.length));
      for (var index = 0; index < files.length; index++) {
        final asset = saved.assets[index];
        expect(asset.kind, NoteAssetKind.file);
        expect(
          await File(
            FileStorageService.instance.absolutePath(asset.storageKey),
          ).readAsBytes(),
          await File(p.join(inbox.path, files[index].fileName)).readAsBytes(),
        );
      }
    },
  );

  test('text files share the inline limit and overflow stays whole', () async {
    final firstText = '文' * 99990;
    final first = await file('.txt', utf8.encode(firstText), 'text/plain');
    final overflow = await file(
      '.txt',
      utf8.encode('0123456789'),
      'text/plain',
    );
    final oversized = await file('.txt', List.filled(400004, 65), 'text/plain');
    final last = await file('.txt', utf8.encode('收尾'), 'text/plain');
    final saved = await importer.import(
      share(text: '说明', files: [first, overflow, oversized, last]),
    );
    expect(saved.assets.map((asset) => asset.byteLength), [10, 400004]);
    expect(saved.document.project().plainText, '说明\n$firstText\n\n\n收尾');
    expect(
      await File(
        FileStorageService.instance.absolutePath(saved.assets.first.storageKey),
      ).readAsString(),
      '0123456789',
    );
  });

  test(
    'unsupported images and zero-byte documents are preserved as files',
    () async {
      final heic = await file('.heic', [1, 2], 'image/heic');
      final empty = await file('.txt', [], 'text/plain');
      final saved = await importer.import(share(files: [heic, empty]));
      expect(saved.assets.map((asset) => asset.kind), [
        NoteAssetKind.file,
        NoteAssetKind.file,
      ]);
      expect(saved.assets.last.byteLength, 0);
    },
  );

  test(
    'retry after a committed save is idempotent even without staged files',
    () async {
      final attachment = await file('.pdf', [1], 'application/pdf');
      final payload = share(files: [attachment]);
      final first = await importer.import(payload);
      await inbox.delete(recursive: true);
      final retried = await importer.import(payload);
      expect(retried.id, first.id);
      expect(retried.assets.single.id, first.assets.single.id);
      expect(await repository.list(), hasLength(1));
    },
  );

  test(
    'an unreadable second attachment rolls back imported assets and note',
    () async {
      final a = await file('.pdf', [1], 'application/pdf');
      final text = await file('.txt', utf8.encode('不能部分保存'), 'text/plain');
      final b = await file('.pdf', [2], 'application/pdf');
      await File(p.join(inbox.path, b.fileName)).delete();
      await expectLater(
        importer.import(share(files: [a, text, b])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repository.list(), isEmpty);
      expect(
        await Directory(
          p.join(FileStorageService.instance.baseDir, 'notes/files'),
        ).list().toList(),
        isEmpty,
      );
      expect(await File(p.join(inbox.path, a.fileName)).exists(), isTrue);
    },
  );

  test(
    'symlinks outside the staged directory and empty shares are rejected',
    () async {
      final outside = await File(
        p.join(root.path, 'outside.txt'),
      ).writeAsString('secret');
      final name = '${NoteId.generate().value}.txt';
      await Link(p.join(inbox.path, name)).create(outside.path);
      await expectLater(
        importer.import(
          share(
            files: [
              SharedFile(
                name: 'file.txt',
                fileName: name,
                mimeType: 'text/plain',
                byteLength: 6,
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
      await expectLater(importer.import(share()), throwsFormatException);
      expect(await repository.list(), isEmpty);
    },
  );

  test('post-commit failure does not delete committed attachments', () async {
    final hooked = NoteRepository(
      db,
      onNoteChanged: (_) async => throw StateError('hook failed'),
    );
    final service = SharedNoteImportService(
      repositoryLoader: () async => hooked,
    );
    final attachment = await file('.pdf', [1], 'application/pdf');
    final saved = await service.import(share(files: [attachment]));
    expect(
      await FileStorageService.instance.fileExists(
        saved.assets.single.storageKey,
      ),
      isTrue,
    );
    expect(await repository.list(), hasLength(1));
  });

  test(
    'database transaction failure removes only newly imported assets',
    () async {
      await db.execute(
        "CREATE TRIGGER fail_shared_insert BEFORE INSERT ON notes BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      final attachment = await file('.pdf', [1, 2], 'application/pdf');
      await expectLater(
        importer.import(share(files: [attachment])),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repository.list(), isEmpty);
      expect(
        await Directory(
          p.join(FileStorageService.instance.baseDir, 'notes/files'),
        ).list().toList(),
        isEmpty,
      );
      expect(
        await File(p.join(inbox.path, attachment.fileName)).exists(),
        isTrue,
      );
    },
  );
}

const _markdownWithFrontMatter = '''
---
title: 儿童笔记 App 全局设计规范（晴空成长主题）
version: 1.0.0
status: Baseline
updated: 2026-08-27
platforms: [iOS, Android]
target_users: 7–12 岁儿童及辅助使用的家长/教师
---

# 儿童笔记 App 全局设计规范

> 视觉主题工作名：**晴空成长 / Sunny Growth**

- **必须**：保留元数据并渲染正文。
''';

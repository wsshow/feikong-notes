import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/providers/file_library_controller.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late FileLibraryStore store;
  XFile source(String name, [List<int> bytes = const [1, 2, 3]]) =>
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: name,
        path: '/source/$name',
      );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-library-test');
    store = FileLibraryStore(rootPath: p.join(root.path, 'library'));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'imports arbitrary formats, preserves bytes and resolves duplicate names',
    () async {
      final original = File(p.join(root.path, 'report.anything'));
      await original.writeAsBytes([0, 1, 128, 255]);
      final first = await store.importFile(XFile(original.path));
      final second = await store.importFile(XFile(original.path));
      expect(first.name, 'report.anything');
      expect(second.name, 'report (2).anything');
      expect(await store.fileFor(first).readAsBytes(), [0, 1, 128, 255]);
      expect(await original.readAsBytes(), [0, 1, 128, 255]);
      expect(first.size, 4);
      expect(
        (await FileLibraryStore(rootPath: store.rootPath).load()).length,
        2,
      );
      final empty = await store.importFile(source('empty.txt', []));
      expect(empty.size, 0);
    },
  );

  test(
    'concurrent store instances serialize commits without losing files',
    () async {
      await Future.wait([
        for (var i = 0; i < 8; i++)
          FileLibraryStore(
            rootPath: store.rootPath,
          ).importFile(source('same.txt')),
      ]);
      final entries = await store.load();
      expect(entries.length, 8);
      expect(entries.map((e) => e.name).toSet().length, 8);
    },
  );

  test(
    'nested folders move and copy atomically; prevents cycles and collisions',
    () async {
      final parent = await store.createFolder('Projects');
      final child = await store.createFolder('Reports', parentId: parent.id);
      final file = await store.importFile(
        source('budget.xlsx'),
        parentId: child.id,
      );
      await expectLater(
        store.transfer({parent.id}, child.id, copy: false),
        throwsA(
          isA<FileLibraryException>().having((e) => e.code, 'code', 'cycle'),
        ),
      );
      await expectLater(
        store.transfer({parent.id}, child.id, copy: true),
        throwsA(isA<FileLibraryException>()),
      );
      await expectLater(
        store.createFolder('projects'),
        throwsA(isA<FileLibraryException>()),
      );
      await store.transfer({parent.id, child.id}, null, copy: true);
      var entries = await store.load();
      expect(entries.length, 6);
      final copied = entries.singleWhere((e) => e.name == 'Projects (2)');
      final copiedChild = entries.singleWhere((e) => e.parentId == copied.id);
      final copiedFile = entries.singleWhere(
        (e) => e.parentId == copiedChild.id,
      );
      expect(
        await store.fileFor(copiedFile).readAsBytes(),
        await store.fileFor(file).readAsBytes(),
      );
      await store.transfer({child.id}, null, copy: false);
      entries = await store.load();
      expect(entries.singleWhere((e) => e.id == child.id).parentId, isNull);
      expect(entries.singleWhere((e) => e.id == file.id).parentId, child.id);
    },
  );

  test(
    'trash hides entire subtrees, restores on name collision, purges only trash',
    () async {
      final folder = await store.createFolder('Photos');
      final file = await store.importFile(
        source('image.png'),
        parentId: folder.id,
      );
      await expectLater(
        store.deletePermanently({file.id}),
        throwsA(isA<FileLibraryException>()),
      );
      await store.trash({folder.id, file.id});
      var entries = await store.load();
      expect(entries.where((e) => e.deletedAt != null).length, 1);
      final map = {for (final e in entries) e.id: e};
      expect(FileLibraryStore.isInTrash(map[file.id]!, map), true);
      await store.createFolder('Photos');
      await store.restore({folder.id});
      entries = await store.load();
      expect(entries.singleWhere((e) => e.id == folder.id).name, 'Photos (2)');
      expect(await store.fileFor(file).exists(), true);
      await store.trash({folder.id});
      await store.deletePermanently({folder.id});
      expect((await store.load()).length, 1);
      expect(await store.fileFor(file).exists(), false);
    },
  );

  test(
    'restores an individually deleted child to root when its parent is trashed',
    () async {
      final folder = await store.createFolder('Folder');
      final file = await store.importFile(
        source('readme.md'),
        parentId: folder.id,
      );
      await store.trash({file.id});
      await store.trash({folder.id});
      await store.restore({file.id});
      final restored = (await store.load()).singleWhere((e) => e.id == file.id);
      expect(restored.deletedAt, isNull);
      expect(restored.parentId, isNull);
    },
  );

  test(
    'cancelled and failed streams leave neither an index entry nor a partial blob',
    () async {
      await expectLater(
        store.importFile(source('cancelled.mp4'), isCancelled: () => true),
        throwsA(isA<FileLibraryException>()),
      );
      expect(await store.load(), isEmpty);
      final data = Directory(p.join(store.rootPath, 'data'));
      expect(await data.list().toList(), isEmpty);
    },
  );

  test(
    'validates names, blob paths and parent graphs before accepting an index',
    () async {
      for (final name in [
        '',
        '../oops',
        'a/b',
        r'a\b',
        '.',
        '..',
        'file:',
        'x\u0000',
      ]) {
        expect(
          () => FileLibraryStore.validateName(name),
          throwsA(isA<FileLibraryException>()),
        );
      }
      final entry = await store.importFile(source('safe.txt'));
      final index = File(p.join(store.rootPath, 'index.json'));
      final raw = jsonDecode(await index.readAsString()) as Map;
      (raw['entries'] as List).first['storageName'] = '../../outside';
      await index.writeAsString(jsonEncode(raw));
      await expectLater(store.load(), throwsA(isA<FileLibraryException>()));
      expect(await store.fileFor(entry).exists(), true);
    },
  );

  test(
    'backup snapshots include favorites and trash, exclude partial/unreferenced files',
    () async {
      final kept = await store.importFile(source('kept.pdf'));
      final deleted = await store.importFile(source('deleted.docx'));
      const linkedNoteId = '8d48ac02-23de-4d67-a55f-b687d8f9ff12';
      await store.linkNote(kept.id, linkedNoteId);
      await store.setFavorite({kept.id}, true);
      await store.trash({deleted.id});
      await File(
        p.join(store.rootPath, 'data', 'uncommitted.part'),
      ).writeAsString('partial');
      final staging = Directory(p.join(root.path, 'snapshot'));
      final files = await store.backupSnapshot(staging);
      expect(files.length, 3);
      final restored = FileLibraryStore(
        rootPath: p.join(staging.path, FileLibraryStore.relativeRoot),
      );
      expect(await restored.validateBackupFiles(), files.keys.toSet());
      final entries = await restored.load();
      expect(entries.singleWhere((e) => e.id == kept.id).favorite, true);
      expect(
        entries.singleWhere((e) => e.id == kept.id).linkedNoteId,
        linkedNoteId,
      );
      expect(
        entries.singleWhere((e) => e.id == deleted.id).deletedAt,
        isNotNull,
      );
      await restored.fileFor(kept).writeAsString('damaged');
      await expectLater(
        restored.validateBackupFiles(),
        throwsA(isA<FileLibraryException>()),
      );
    },
  );

  test(
    'search and categories span descendants; favorites and recent exclude trash',
    () async {
      final folder = await store.createFolder('Work');
      final image = await store.importFile(
        source('receipt.PNG'),
        parentId: folder.id,
      );
      final pdf = await store.importFile(source('reference.pdf'));
      await store.setFavorite({image.id}, true);
      await store.markOpened(image.id);
      final controller = FileLibraryController(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(
        controller.visible.map((e) => e.id),
        containsAll([folder.id, pdf.id]),
      );
      expect(controller.visible.map((e) => e.id), isNot(contains(image.id)));
      controller.search('RECEIPT');
      expect(controller.visible.single.id, image.id);
      controller.search('');
      controller.setFilter(LibraryFileKind.image);
      expect(controller.visible.single.id, image.id);
      controller.navigate(FileLibraryLocation.favorites);
      expect(controller.visible.single.id, image.id);
      controller.navigate(FileLibraryLocation.recent);
      expect(controller.visible.single.id, image.id);
      await controller.run(() => store.trash({folder.id}));
      expect(controller.visible, isEmpty);
      controller.navigate(FileLibraryLocation.trash);
      expect(controller.visible.single.id, folder.id);
      expect(controller.sizeOf(folder), 3);
    },
  );
}

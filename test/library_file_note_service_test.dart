import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/providers/editorial_material_controller.dart';
import 'package:fknotes/services/editorial_material_preferences.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/library_file_note_service.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _DelayedPreferences extends EditorialMaterialPreferences {
  final result = Completer<EditorialMaterialLayout>();
  @override
  Future<EditorialMaterialLayout> load() => result.future;
  @override
  Future<void> save(EditorialMaterialLayout layout) async {}
}

void main() {
  late Directory root;
  late FileLibraryStore store;
  late NoteRepository repository;
  late Database database;
  late LibraryFileNoteService service;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('material-note-service');
    await FileStorageService.instance.init(baseDir: root.path);
    store = FileLibraryStore.instance;
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    repository = NoteRepository(database);
    await repository.initialize();
    service = LibraryFileNoteService(
      store: store,
      repositoryLoader: () async => repository,
    );
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  Future<LibraryFile> source() async {
    final file = File(p.join(root.path, 'source.pdf'));
    await file.writeAsBytes([0, 1, 2, 255]);
    return store.importFile(XFile(file.path));
  }

  test(
    'creates a file reference without copying content and resumes the same note',
    () async {
      final file = await source();
      final notes = await Future.wait([
        service.openOrCreate(file),
        service.openOrCreate(file),
      ]);
      expect(notes[0].id, notes[1].id);
      final saved = notes.first;
      final linked = (await store.load()).single;
      expect(linked.linkedNoteId, saved.id.value);
      expect(saved.title, 'source');
      expect(saved.assets, isEmpty);
      final embed = NoteEmbed.parse(
        saved.document.toDelta().operations.first.data,
      );
      expect(embed.kind, NoteEmbedKind.fileReferences);
      expect(embed.fileReferences.single.fileId, file.id);
      expect(embed.fileReferences.single.name, file.name);
      expect(saved.searchText, contains('source.pdf'));
      final restored = await repository.get(saved.id);
      expect(restored!.document, saved.document);
      await store.trash({file.id});
      await store.deletePermanently({file.id});
      expect(await repository.get(saved.id), isNotNull);
    },
  );

  test(
    'groups mixed formats into one card and deduplicates concurrent batches',
    () async {
      final first = await source();
      final second = await store.importFile(
        XFile.fromData(
          Uint8List.fromList([1, 2]),
          name: 'archive.unknown',
          path: '/source/archive.unknown',
        ),
      );
      final notes = await Future.wait([
        service.openOrCreateMany([first, second, first]),
        service.openOrCreateMany([second, first]),
      ]);
      expect(notes.first.id, notes.last.id);
      expect(notes.first.assets, isEmpty);
      final embeds = notes.first.document
          .toDelta()
          .operations
          .where((op) => op.data is Map)
          .toList();
      expect(embeds, hasLength(1));
      final references = NoteEmbed.parse(embeds.single.data).fileReferences;
      expect(references.map((reference) => reference.fileId), [
        first.id,
        second.id,
      ]);
      expect(await repository.get(notes.first.id), isNotNull);
      expect(notes.first.searchText, contains('archive.unknown'));
    },
  );

  test('references resolve current metadata after rename and move', () async {
    final file = await source();
    final folder = await store.createFolder('资料');
    await store.rename(file.id, 'new-name.bin');
    await store.transfer({file.id}, folder.id, copy: false);
    final references = await service.referencesFor([file]);
    expect(references.single.fileId, file.id);
    expect(references.single.name, 'new-name.bin');
  });

  test('rejects empty, folder, trashed and missing file selections', () async {
    final file = await source();
    final folder = await store.createFolder('资料');
    await expectLater(service.openOrCreateMany([]), throwsFormatException);
    await expectLater(
      service.openOrCreate(folder),
      throwsA(isA<FileLibraryException>()),
    );
    await store.trash({file.id});
    await expectLater(
      service.openOrCreate(file),
      throwsA(isA<FileLibraryException>()),
    );
    await store.restore({file.id});
    await store.fileFor(file).delete();
    await expectLater(
      service.openOrCreate(file),
      throwsA(isA<FileLibraryException>()),
    );
  });

  test(
    'private and deleted linked notes are excluded and never reopened from public files',
    () async {
      final file = await source();
      final first = await service.openOrCreate(file);
      await repository.update(first.copyWith(isPrivate: true));
      var linked = (await store.load()).single;
      expect(await service.linkedNote(linked), isNull);
      final replacement = await service.openOrCreate(file);
      expect(replacement.isPrivate, false);
      expect(replacement.id, isNot(first.id));
      await repository.deletePermanently(replacement.id);
      final next = await service.openOrCreate(file);
      expect(next.id, isNot(replacement.id));
      linked = (await store.load()).single;
      final controller = EditorialMaterialController(
        store: store,
        notes: service,
      );
      await controller.refresh();
      expect(controller.continuing.single.id, file.id);
      expect(controller.linkedNotes[linked.id]!.id, next.id);
      controller.dispose();
    },
  );

  test(
    'last layout persists with stable names and rapid selections keep the last write',
    () async {
      final preferences = EditorialMaterialPreferences(
        file: File(p.join(root.path, 'preferences.json')),
      );
      await Future.wait([
        for (final layout in EditorialMaterialLayout.values)
          preferences.save(layout),
      ]);
      expect(await preferences.load(), EditorialMaterialLayout.categories);
      await File(
        p.join(root.path, 'preferences.json'),
      ).writeAsString('{"version":1,"layout":"future-layout"}');
      expect(await preferences.load(), EditorialMaterialLayout.recent);
    },
  );

  test(
    'late preference loading cannot override a new swipe selection',
    () async {
      final preferences = _DelayedPreferences();
      final controller = EditorialMaterialController(
        store: store,
        preferences: preferences,
        notes: service,
      );
      final initialization = controller.initialize();
      controller.select(EditorialMaterialLayout.images);
      preferences.result.complete(EditorialMaterialLayout.favorites);
      await initialization;
      expect(controller.layout, EditorialMaterialLayout.images);
      controller.dispose();
    },
  );
}

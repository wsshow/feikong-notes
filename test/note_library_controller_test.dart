import 'dart:async';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_constellation.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryLibraryStore store;
  late NoteLibraryController controller;

  setUp(() {
    store = _MemoryLibraryStore([
      _note('普通笔记', body: '正文', revision: 1),
      _note('另一篇笔记', revision: 2),
    ]);
    controller = NoteLibraryController(
      storeLoader: () async => store,
      now: () => DateTime.utc(2026, 7, 23, 18),
    );
    addTearDown(controller.dispose);
  });

  test('loads one unified note collection', () async {
    await controller.initialize();
    expect(controller.notes.map((note) => note.title), ['普通笔记', '另一篇笔记']);
    expect(store.constellationLoadCalls, 0);
  });

  test('public note size never includes private documents', () async {
    await controller.initialize();
    final size = controller.contentSizeBytes;
    store.notes.add(
      _note(
        'private size',
        body: 'secret ' * 1000,
        revision: 1,
      ).copyWith(isPrivate: true),
    );
    await controller.refresh();
    expect(controller.contentSizeBytes, size);
    final private = NoteLibraryController(
      privateSpace: true,
      storeLoader: () async => store,
    );
    addTearDown(private.dispose);
    await private.initialize();
    expect(private.contentSizeBytes, greaterThan(size));
  });

  test(
    'private libraries filter injected stores and moving notes preserves metadata',
    () async {
      await controller.initialize();
      final original = controller.notes.first;
      await controller.setPrivate([original], isPrivate: true);
      expect(controller.notes.any((note) => note.id == original.id), isFalse);
      final private = NoteLibraryController(
        privateSpace: true,
        storeLoader: () async => store,
      );
      addTearDown(private.dispose);
      await private.initialize();
      expect(private.notes.single.id, original.id);
      expect(private.notes.single.document, original.document);
      expect(private.notes.single.revision, original.revision + 1);
      await private.search('普通');
      expect(private.notes.single.isPrivate, isTrue);
      await private.setPrivate(private.notes, isPrivate: false);
      expect(private.notes, isEmpty);
      await controller.refresh();
      expect(controller.notes.any((note) => note.id == original.id), isTrue);
    },
  );

  test(
    'closing a private library discards an unfinished refresh safely',
    () async {
      final pending = Completer<NoteLibraryStore>();
      final private = NoteLibraryController(
        privateSpace: true,
        storeLoader: () => pending.future,
      );
      final loading = private.initialize();
      private.dispose();
      pending.complete(store);
      await loading;
      expect(private.notes, isEmpty);
    },
  );

  test('a late search response cannot replace a newer query', () async {
    final oldResponse = Completer<List<Note>>();
    final newResponse = Completer<List<Note>>();
    store.searchOverrides['旧'] = oldResponse.future;
    store.searchOverrides['新'] = newResponse.future;

    final oldSearch = controller.search('旧');
    final newSearch = controller.search('新');
    newResponse.complete([_note('新结果', revision: 1)]);
    await newSearch;
    oldResponse.complete([_note('旧结果', revision: 1)]);
    await oldSearch;

    expect(controller.query, '新');
    expect(controller.notes.map((note) => note.title), ['新结果']);
  });

  test('pinning preserves revisions and refreshes the collection', () async {
    await controller.initialize();
    final original = controller.notes.first;

    await controller.togglePinned(original);
    final pinned = controller.notes.singleWhere(
      (note) => note.id == original.id,
    );
    expect(pinned.isPinned, isTrue);
    expect(pinned.revision, 2);
    expect(pinned.updatedAt, DateTime.utc(2026, 7, 23, 18));
  });

  test(
    'write conflicts reload fresh state and remain visible as errors',
    () async {
      await controller.initialize();
      final original = controller.notes.first;
      store.updateError = NoteWriteConflict(original.id);

      await expectLater(
        controller.togglePinned(original),
        throwsA(isA<NoteWriteConflict>()),
      );

      expect(controller.error, isA<NoteWriteConflict>());
      expect(controller.isBusy(original.id), isFalse);
      expect(controller.notes.first.isPinned, isFalse);
    },
  );

  test('permanent deletion removes only the selected note', () async {
    await controller.initialize();
    final deleted = controller.notes.first;

    await controller.deletePermanently(deleted);

    expect(controller.notes, hasLength(1));
    expect(controller.notes.any((note) => note.id == deleted.id), isFalse);
    expect(store.deletedNotes, [deleted]);
    expect(store.notes.any((note) => note.id == deleted.id), isFalse);
  });

  test('optimistically saves star positions and region changes', () async {
    await controller.initialize();
    final note = controller.notes.first;
    final group = NoteConstellationGroup.create(
      name: '研究星云',
      kind: NoteConstellationGroupKind.nebula,
      colorIndex: 1,
      noteIds: [note.id],
      now: DateTime.utc(2026, 7, 23),
    );

    await controller.saveConstellationPosition(note.id, .31, .68);
    await controller.saveConstellationOverviewPosition(
      'time:2026-07',
      note.id,
      -.2,
      .4,
    );
    await controller.saveConstellationOverviewRegionPosition(
      'time:2026-07',
      48,
      -24,
    );
    await controller.saveConstellationGroup(group);

    expect(controller.constellationPositions[note.id]?.x, .31);
    expect(controller.constellationPositions[note.id]?.y, .68);
    expect(
      controller.constellationOverviewPositions['time:2026-07']?[note.id]?.x,
      -.2,
    );
    expect(
      controller.constellationOverviewRegionPositions['time:2026-07']?.x,
      48,
    );
    expect(controller.constellationGroups, [group]);
    expect(store.constellation.positions[note.id]?.x, .31);

    await controller.deleteConstellationGroup(group.id);
    expect(controller.constellationGroups, isEmpty);
    expect(store.constellation.groups, isEmpty);
  });
}

final class _MemoryLibraryStore
    implements NoteLibraryStore, NoteConstellationStore {
  _MemoryLibraryStore(this.notes);

  final List<Note> notes;
  final Map<String, Future<List<Note>>> searchOverrides = {};
  final List<Note> deletedNotes = [];
  Object? updateError;
  var searchCalls = 0;
  NoteConstellationSnapshot constellation =
      const NoteConstellationSnapshot.empty();
  var constellationLoadCalls = 0;

  Note note(NoteId id) => notes.singleWhere((candidate) => candidate.id == id);

  @override
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) {
    searchCalls++;
    final overridden = searchOverrides[query];
    if (overridden != null) return overridden;
    final normalized = query.toLowerCase();
    return Future.value(
      notes
          .where((note) => note.searchText.toLowerCase().contains(normalized))
          .toList(growable: false),
    );
  }

  @override
  Future<Note> update(Note note) async {
    final error = updateError;
    if (error != null) throw error;
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    deletedNotes.add(note);
    notes.removeWhere((candidate) => candidate.id == note.id);
  }

  @override
  Future<NoteConstellationSnapshot> loadConstellation() async {
    constellationLoadCalls += 1;
    return constellation;
  }

  @override
  Future<void> saveConstellationPosition(
    NoteId noteId,
    double x,
    double y,
  ) async {
    constellation = NoteConstellationSnapshot(
      positions: {
        ...constellation.positions,
        noteId: NoteConstellationPosition(
          noteId: noteId,
          x: x,
          y: y,
          updatedAt: DateTime.utc(2026, 7, 23, 18),
        ),
      },
      groups: constellation.groups,
      overviewPositions: constellation.overviewPositions,
      overviewRegionPositions: constellation.overviewRegionPositions,
    );
  }

  @override
  Future<void> saveConstellationOverviewPosition(
    String groupKey,
    NoteId noteId,
    double x,
    double y,
  ) async {
    constellation = NoteConstellationSnapshot(
      positions: constellation.positions,
      groups: constellation.groups,
      overviewPositions: {
        ...constellation.overviewPositions,
        groupKey: <NoteId, NoteConstellationOverviewPosition>{
          ...(constellation.overviewPositions[groupKey] ??
              const <NoteId, NoteConstellationOverviewPosition>{}),
          noteId: NoteConstellationOverviewPosition(
            groupKey: groupKey,
            noteId: noteId,
            x: x,
            y: y,
            updatedAt: DateTime.utc(2026, 7, 23, 18),
          ),
        },
      },
      overviewRegionPositions: constellation.overviewRegionPositions,
    );
  }

  @override
  Future<void> saveConstellationOverviewRegionPosition(
    String groupKey,
    double x,
    double y,
  ) async {
    constellation = NoteConstellationSnapshot(
      positions: constellation.positions,
      groups: constellation.groups,
      overviewPositions: constellation.overviewPositions,
      overviewRegionPositions: {
        ...constellation.overviewRegionPositions,
        groupKey: NoteConstellationOverviewRegionPosition(
          groupKey: groupKey,
          x: x,
          y: y,
          updatedAt: DateTime.utc(2026, 7, 23, 18),
        ),
      },
    );
  }

  @override
  Future<void> saveConstellationGroup(NoteConstellationGroup group) async {
    constellation = NoteConstellationSnapshot(
      positions: constellation.positions,
      groups: [
        group,
        ...constellation.groups.where((candidate) => candidate.id != group.id),
      ],
      overviewPositions: constellation.overviewPositions,
      overviewRegionPositions: constellation.overviewRegionPositions,
    );
  }

  @override
  Future<void> deleteConstellationGroup(String groupId) async {
    constellation = NoteConstellationSnapshot(
      positions: constellation.positions,
      groups: constellation.groups.where((group) => group.id != groupId),
      overviewPositions: constellation.overviewPositions,
      overviewRegionPositions: constellation.overviewRegionPositions,
    );
  }
}

Note _note(String title, {String body = '', int revision = 0}) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromPlainText(body),
    revision: revision,
    createdAt: now,
    updatedAt: now,
  );
}

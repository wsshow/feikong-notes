import 'package:flutter/foundation.dart';

import '../models/library_file.dart';
import '../models/note.dart';
import '../services/editorial_material_preferences.dart';
import '../services/file_library_store.dart';
import '../services/library_file_note_service.dart';

class EditorialMaterialController extends ChangeNotifier {
  EditorialMaterialController({
    FileLibraryStore? store,
    EditorialMaterialPreferences? preferences,
    LibraryFileNoteService? notes,
  }) : store = store ?? FileLibraryStore.instance,
       preferences = preferences ?? EditorialMaterialPreferences(),
       notes = notes ?? LibraryFileNoteService(store: store);
  final FileLibraryStore store;
  final EditorialMaterialPreferences preferences;
  final LibraryFileNoteService notes;
  List<LibraryFile> files = const [];
  Map<String, Note> linkedNotes = const {};
  EditorialMaterialLayout layout = EditorialMaterialLayout.recent;
  bool loading = true;
  bool failed = false;
  bool preferenceFailed = false;
  bool _disposed = false;
  bool _interacted = false;
  Future<void>? _initializing;
  Future<void>? _refreshing;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final saved = await preferences.load();
    if (!_interacted) layout = saved;
    await refresh();
  }

  Future<void> refresh() =>
      _refreshing ??= _read().whenComplete(() => _refreshing = null);
  Future<void> _read() async {
    try {
      final entries = await store.load();
      final byId = {for (final e in entries) e.id: e};
      final active = entries
          .where((e) => !e.isFolder && !FileLibraryStore.isInTrash(e, byId))
          .toList();
      final linked = <String, Note>{};
      for (final file in active.where((e) => e.linkedNoteId != null)) {
        final note = await notes.linkedNote(file);
        if (note != null) linked[file.id] = note;
      }
      files = List.unmodifiable(active);
      linkedNotes = Map.unmodifiable(linked);
      failed = false;
    } catch (_) {
      failed = true;
    }
    loading = false;
    _notify();
  }

  void select(EditorialMaterialLayout value) {
    _interacted = true;
    layout = value;
    preferenceFailed = false;
    _notify();
    preferences.save(value).catchError((Object _) {
      preferenceFailed = true;
      _notify();
    });
  }

  List<LibraryFile> get recent {
    final result = [...files]
      ..sort(
        (a, b) =>
            (b.openedAt ?? b.createdAt).compareTo(a.openedAt ?? a.createdAt),
      );
    return result;
  }

  List<LibraryFile> get favorites => recent.where((e) => e.favorite).toList();
  List<LibraryFile> get images =>
      recent.where((e) => e.kind == LibraryFileKind.image).toList();
  List<LibraryFile> get continuing {
    final result = files.where((e) => linkedNotes.containsKey(e.id)).toList()
      ..sort(
        (a, b) => linkedNotes[b.id]!.updatedAt.compareTo(
          linkedNotes[a.id]!.updatedAt,
        ),
      );
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

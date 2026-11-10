import '../models/note.dart';

/// Open editors own their document and undo stack. Background agent writes
/// must never bypass that owner, including the interval before autosave.
class NoteEditGuard {
  static final instance = NoteEditGuard();
  final _owners = <NoteId, Set<Object>>{};
  void register(NoteId id, Object owner) => (_owners[id] ??= {}).add(owner);
  void release(NoteId id, Object owner) {
    _owners[id]?.remove(owner);
    if (_owners[id]?.isEmpty == true) _owners.remove(id);
  }

  bool isOpen(NoteId id) => _owners[id]?.isNotEmpty == true;
}

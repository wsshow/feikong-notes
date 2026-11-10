import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_storage_service.dart';

enum EditorialMaterialLayout {
  recent,
  favorites,
  images,
  continueNotes,
  categories,
}

class EditorialMaterialPreferences {
  EditorialMaterialPreferences({this._file});
  final File? _file;
  Future<void> _writing = Future.value();

  File? get _destination {
    if (_file != null) return _file;
    final base = FileStorageService.instance.baseDirOrNull;
    return base == null
        ? null
        : File(p.join(base, 'settings', 'editorial-material-deck.json'));
  }

  Future<EditorialMaterialLayout> load() async {
    try {
      final file = _destination;
      if (file == null || !await file.exists()) {
        return EditorialMaterialLayout.recent;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['version'] != 1) {
        return EditorialMaterialLayout.recent;
      }
      return EditorialMaterialLayout.values.firstWhere(
        (e) => e.name == raw['layout'],
        orElse: () => EditorialMaterialLayout.recent,
      );
    } on FormatException {
      return EditorialMaterialLayout.recent;
    } on FileSystemException {
      return EditorialMaterialLayout.recent;
    }
  }

  Future<void> save(EditorialMaterialLayout layout) {
    final result = _writing.then((_) async {
      final file = _destination;
      if (file == null) return;
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.part');
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'layout': layout.name}),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _writing = result.catchError((Object _) {});
    return result;
  }
}

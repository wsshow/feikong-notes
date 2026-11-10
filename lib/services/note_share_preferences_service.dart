import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/note_share.dart';
import 'file_storage_service.dart';

class NoteSharePreferencesService {
  NoteSharePreferencesService._();
  static final NoteSharePreferencesService instance =
      NoteSharePreferencesService._();
  static const _defaults = NoteShareOptions(
    canvas: NoteShareCanvasSpec.singleLongUltra,
  );

  File? get _file {
    final baseDir = FileStorageService.instance.baseDirOrNull;
    return baseDir == null
        ? null
        : File(p.join(baseDir, 'note_share_preferences.json'));
  }

  Future<NoteShareOptions> load() async {
    try {
      final file = _file;
      if (file == null || !await file.exists()) {
        return _defaults;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _defaults;
      return NoteShareOptions.fromJson(
        Map<String, Object?>.from(decoded),
      ).copyWith(
        canvas: NoteShareCanvasSpec.singleLongUltra,
        density: NoteShareDensity.standard,
      );
    } catch (_) {
      return _defaults;
    }
  }

  Future<void> save(NoteShareOptions options) async {
    final file = _file;
    if (file == null) return;
    final temporary = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    final simplified = options.copyWith(
      canvas: NoteShareCanvasSpec.singleLongUltra,
      density: NoteShareDensity.standard,
    );
    await temporary.writeAsString(jsonEncode(simplified.toJson()), flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      await temporary.copy(file.path);
      await temporary.delete();
    }
  }
}

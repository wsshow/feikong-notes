import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_storage_service.dart';
import '../theme/app_theme.dart';

typedef AppThemePreferenceWriter =
    Future<void> Function(AppThemeStyle style, ThemeMode mode);

/// Appearance is stored independently of notes, filters and navigation state.
class AppThemeController extends ChangeNotifier {
  AppThemeController({String? settingsPath, this.preferenceWriter})
    : _settingsPathOverride = settingsPath;

  static final instance = AppThemeController();

  final String? _settingsPathOverride;
  final AppThemePreferenceWriter? preferenceWriter;
  AppThemeStyle _style = AppThemeCatalog.defaultStyle;
  ThemeMode _mode = ThemeMode.light;
  AppThemeStyle _savedStyle = AppThemeCatalog.defaultStyle;
  ThemeMode _savedMode = ThemeMode.light;
  Future<void> _writeQueue = Future.value();
  int _revision = 0;
  bool _disposed = false;

  AppThemeStyle get style => _style;
  ThemeMode get mode => _mode;
  ThemeMode get effectiveMode => _style.supportsDark ? _mode : ThemeMode.light;

  String get _settingsPath =>
      _settingsPathOverride ??
      p.join(FileStorageService.instance.baseDir, 'settings', 'app-theme.json');

  Future<void> initialize() async {
    final revision = _revision;
    try {
      final decoded = jsonDecode(await File(_settingsPath).readAsString());
      if (decoded is! Map || _disposed || revision != _revision) return;
      _style = AppThemeCatalog.styleFromStorage(decoded['style']);
      _mode = ThemeMode.values.firstWhere(
        (value) => value.name == decoded['mode'],
        orElse: () => ThemeMode.light,
      );
      _savedStyle = _style;
      _savedMode = _mode;
      notifyListeners();
    } on FormatException {
      // A damaged preference must never prevent access to the user's notes.
    } on FileSystemException {
      // First launch or an unavailable settings file uses the catalog default.
    }
  }

  Future<void> setStyle(AppThemeStyle style) => _save(style, _mode);
  Future<void> setMode(ThemeMode mode) => _save(_style, mode);

  Future<void> _save(AppThemeStyle style, ThemeMode mode) async {
    if (_style == style && _mode == mode) return;
    final revision = ++_revision;
    _style = style;
    _mode = mode;
    notifyListeners();
    final operation = _writeQueue.then((_) async {
      final writer = preferenceWriter;
      if (writer != null) {
        await writer(style, mode);
      } else {
        await _write(style, mode);
      }
      _savedStyle = style;
      _savedMode = mode;
    });
    _writeQueue = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (_) {
      if (!_disposed && revision == _revision) {
        _style = _savedStyle;
        _mode = _savedMode;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> _write(AppThemeStyle style, ThemeMode mode) async {
    final file = File(_settingsPath);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'style': style.storageId, 'mode': mode.name}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

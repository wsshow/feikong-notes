import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/note.dart';

final class SharedFile {
  const SharedFile({
    required this.name,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });
  final String name;
  final String fileName;
  final String mimeType;
  final int byteLength;
}

final class IncomingShare {
  const IncomingShare({
    required this.id,
    required this.directory,
    required this.createdAt,
    this.title = '',
    this.text = '',
    this.files = const [],
    this.error,
  });
  factory IncomingShare.fromMap(Map<Object?, Object?> map) {
    final id = NoteId.parse(map['id']! as String);
    final directory = map['directory']! as String;
    if (!p.isAbsolute(directory) || p.basename(directory) != id.value) {
      throw const FormatException('Invalid share directory');
    }
    final files = [for (final raw in map['files']! as List) _file(raw as Map)];
    final text = map['text']! as String;
    final title = map['title']! as String;
    if (files.length > 20 ||
        text.length > 100000 ||
        title.length > 500 ||
        files.fold<int>(0, (sum, file) => sum + file.byteLength) >
            200 * 1024 * 1024) {
      throw const FormatException('Share exceeds limits');
    }
    return IncomingShare(
      id: id,
      directory: directory,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt']! as int,
        isUtc: true,
      ),
      title: title,
      text: text,
      files: files,
      error: map['error'] as String?,
    );
  }

  static SharedFile _file(Map raw) {
    final fileName = raw['fileName']! as String;
    final bytes = raw['byteLength']! as int;
    if (!RegExp(r'^[0-9a-f-]{36}(\.[a-z0-9]{1,10})?$').hasMatch(fileName) ||
        bytes < 0 ||
        bytes > 100 * 1024 * 1024) {
      throw const FormatException('Invalid shared file');
    }
    return SharedFile(
      name: raw['name']! as String,
      fileName: fileName,
      mimeType: raw['mimeType']! as String,
      byteLength: bytes,
    );
  }

  final NoteId id;
  final String directory;
  final DateTime createdAt;
  final String title;
  final String text;
  final List<SharedFile> files;
  final String? error;
}

class IncomingShareService extends ChangeNotifier with WidgetsBindingObserver {
  IncomingShareService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('fknotes/incoming_share'),
      _supported =
          supported ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS));

  final MethodChannel _channel;
  final bool _supported;
  IncomingShare? get pending => _pending;
  IncomingShare? _pending;
  bool get receiving => _receiving;
  bool _receiving = false;
  bool get failed => _failed;
  bool _failed = false;
  bool _disposed = false;
  bool _initialized = false;
  Future<void>? _refreshing;
  bool _refreshAgain = false;

  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'receiving') {
        _receiving = true;
        notifyListeners();
      } else if (call.method == 'changed') {
        await refresh();
      } else if (call.method == 'receiveFailed') {
        _receiving = false;
        _failed = true;
        notifyListeners();
      }
    });
    await refresh();
  }

  Future<void> refresh() {
    if (!_supported || _disposed) return Future.value();
    if (_refreshing != null) {
      _refreshAgain = true;
      return _refreshing!;
    }
    return _refreshing = _read().whenComplete(() {
      _refreshing = null;
      if (_refreshAgain && !_disposed) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    });
  }

  Future<void> _read() async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('peek');
      if (_disposed) return;
      _pending = map == null ? null : IncomingShare.fromMap(map);
      _failed = false;
    } on MissingPluginException {
      // Non-Android hosts do not receive Android intents.
    } catch (_) {
      _failed = true;
    } finally {
      _receiving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> finish(NoteId id) async {
    await _channel.invokeMethod<void>('finish', {'id': id.value});
    if (_disposed) return;
    if (_pending?.id == id) _pending = null;
    notifyListeners();
  }

  void clearFailure() {
    _failed = false;
  }

  static Future<void> openAttachment(NoteAsset asset) =>
      const MethodChannel('fknotes/incoming_share').invokeMethod<void>(
        'openAttachment',
        {'storageKey': asset.storageKey, 'mimeType': asset.mimeType},
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}

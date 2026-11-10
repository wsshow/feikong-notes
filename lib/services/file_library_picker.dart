import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/library_file.dart';

/// Android's file_selector implementation materializes whole files in memory.
/// Keep content URIs native and copy them on a worker instead.
class FileLibraryPicker {
  FileLibraryPicker({MethodChannel? channel, bool? useAndroidPicker})
    : _channel = channel ?? const MethodChannel('fknotes/file_library'),
      _useAndroidPicker = useAndroidPicker ?? Platform.isAndroid;
  static final instance = FileLibraryPicker();
  final MethodChannel _channel;
  final bool _useAndroidPicker;
  final _progress = <String, void Function(int, int)>{};

  Future<List<XFile>> pickFiles() async {
    if (!_useAndroidPicker) return openFiles();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      _progress[args['token']]?.call(
        args['bytes'] as int,
        args['total'] as int,
      );
    });
    final files = await _channel.invokeListMethod<Object?>('pickFiles') ?? [];
    return files.map((raw) {
      final file = Map<Object?, Object?>.from(raw as Map);
      return AndroidLibraryFile(
        file['uri'] as String,
        file['name'] as String,
        file['size'] as int,
        this,
      );
    }).toList();
  }

  Future<int> _copy(
    AndroidLibraryFile source,
    String destination, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) {
      throw const FileLibraryException('cancelled');
    }
    final token = const Uuid().v4();
    var cancelled = false;
    _progress[token] = (bytes, total) {
      onProgress?.call(bytes, total);
      if (!cancelled && isCancelled?.call() == true) {
        cancelled = true;
        unawaited(_channel.invokeMethod<void>('cancel', {'token': token}));
      }
    };
    try {
      return await _channel.invokeMethod<int>('copyFile', {
            'uri': source.path,
            'destination': destination,
            'token': token,
          }) ??
          0;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        throw const FileLibraryException('cancelled');
      }
      rethrow;
    } finally {
      _progress.remove(token);
    }
  }
}

class AndroidLibraryFile extends XFile {
  AndroidLibraryFile(super.path, this._name, this._size, this._picker);
  final String _name;
  final int _size;
  final FileLibraryPicker _picker;
  @override
  String get name => _name;
  @override
  Future<int> length() async => _size;

  Future<int> copyTo(
    String destination, {
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  }) => _picker._copy(
    this,
    destination,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
}

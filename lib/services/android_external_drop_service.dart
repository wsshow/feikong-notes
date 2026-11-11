import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidExternalDropEventType { entered, updated, exited, done }

final class AndroidDroppedFile {
  const AndroidDroppedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.byteLength,
  });

  final String path;
  final String name;
  final String mimeType;
  final int byteLength;
}

final class AndroidExternalDropEvent {
  const AndroidExternalDropEvent({
    required this.type,
    required this.physicalPosition,
    this.files = const [],
    this.rejectedCount = 0,
  });

  final AndroidExternalDropEventType type;
  final Offset physicalPosition;
  final List<AndroidDroppedFile> files;
  final int rejectedCount;
}

typedef AndroidExternalDropListener =
    bool Function(AndroidExternalDropEvent event);

/// Historical Android name; iOS implements the same owned-file protocol.
final class AndroidExternalDropService {
  AndroidExternalDropService._();

  static final instance = AndroidExternalDropService._();
  static const _channel = MethodChannel('fknotes/external_image_drop');

  final Set<AndroidExternalDropListener> _listeners = {};
  var _initialized = false;

  void addListener(AndroidExternalDropListener listener) {
    _listeners.add(listener);
    _updateNativeEnabled();
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void removeListener(AndroidExternalDropListener listener) {
    _listeners.remove(listener);
    _updateNativeEnabled();
  }

  void _updateNativeEnabled() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    unawaited(_setEnabled());
  }

  Future<void> _setEnabled() async {
    try {
      await _channel.invokeMethod<void>('setEnabled', _listeners.isNotEmpty);
    } on MissingPluginException {
      // Widget tests and hosts without the optional native drop bridge.
    }
  }

  Future<void> deleteTemporaryFiles(Iterable<String> paths) async {
    final values = paths
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) return;
    await _channel.invokeMethod<void>('deleteTemporaryFiles', values);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final map = arguments.cast<Object?, Object?>();
    final position = _positionFrom(map['position']);
    final event = switch (call.method) {
      'entered' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.entered,
        physicalPosition: position,
      ),
      'updated' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.updated,
        physicalPosition: position,
      ),
      'exited' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.exited,
        physicalPosition: position,
      ),
      'done' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.done,
        physicalPosition: position,
        files: _filesFrom(map['files']),
        rejectedCount: (map['rejectedCount'] as num?)?.toInt() ?? 0,
      ),
      _ => null,
    };
    if (event == null) return;
    var claimed = false;
    for (final listener in List.of(_listeners).reversed) {
      if (listener(event)) {
        claimed = true;
        break;
      }
    }
    if (!claimed && event.type == AndroidExternalDropEventType.done) {
      await deleteTemporaryFiles(event.files.map((file) => file.path));
    }
  }

  static Offset _positionFrom(Object? value) {
    if (value is! List || value.length < 2) return Offset.zero;
    return Offset(
      (value[0] as num?)?.toDouble() ?? 0,
      (value[1] as num?)?.toDouble() ?? 0,
    );
  }

  static List<AndroidDroppedFile> _filesFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final map = raw.cast<Object?, Object?>();
          return AndroidDroppedFile(
            path: map['path'] as String? ?? '',
            name: map['name'] as String? ?? '',
            mimeType: map['mimeType'] as String? ?? '',
            byteLength: (map['byteLength'] as num?)?.toInt() ?? 0,
          );
        })
        .where((file) => file.path.isNotEmpty)
        .toList(growable: false);
  }
}

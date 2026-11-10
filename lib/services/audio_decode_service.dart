import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Keeps the original M4A (or imported audio) and prepares disposable PCM WAV
/// for offline recognition. Android and iOS implement the same channel.
class AudioDecodeService {
  AudioDecodeService({MethodChannel? channel, TargetPlatform? platform})
    : _channel = channel ?? const MethodChannel('fknotes/audio_decode'),
      _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final TargetPlatform _platform;

  Future<String> prepare(
    String source, {
    required String outputPath,
    bool Function()? isCancelled,
  }) async {
    if (p.extension(source).toLowerCase() == '.wav') return source;
    if (_platform != TargetPlatform.android &&
        _platform != TargetPlatform.iOS) {
      throw UnsupportedError('当前平台暂时只支持转写 WAV 音频');
    }
    if (p.equals(p.absolute(source), p.absolute(outputPath))) {
      throw ArgumentError('转写临时文件不能覆盖原音频');
    }
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    try {
      if (isCancelled?.call() == true) {
        throw PlatformException(code: 'cancelled');
      }
      final decoded = await _channel.invokeMethod<String>('decodeToWav', {
        'sourcePath': source,
        'outputPath': outputPath,
      });
      if (decoded != outputPath ||
          !await output.exists() ||
          await output.length() <= 44) {
        throw StateError('无法解码这个音频格式');
      }
      return outputPath;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  Future<void> cancel(String outputPath) async {
    // Android's existing decoder finishes in its worker; its caller discards
    // the result. iOS can also stop the AVAssetReader before decoding finishes.
    if (_platform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'outputPath': outputPath});
    } on PlatformException {
      // Completion may have won the race. The caller still discards its result.
    } on MissingPluginException {
      // Keep cancellation safe on hosts without the native bridge.
    }
  }
}

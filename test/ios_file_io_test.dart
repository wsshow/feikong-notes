import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:fknotes/services/backup_service.dart';
import 'package:fknotes/services/file_export_service.dart';
import 'package:fknotes/services/kokoro_tts_model_service.dart';
import 'package:fknotes/services/language_model_service.dart';
import 'package:fknotes/services/speaker_diarization_model_service.dart';
import 'package:fknotes/services/speech_denoiser_model_service.dart';
import 'package:fknotes/services/speech_model_service.dart';
import 'package:fknotes/services/streaming_speech_model_service.dart';
import 'package:fknotes/services/voice_activity_model_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/file_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'all backup and model import entrypoints supply iOS type identifiers',
    () async {
      final previous = FileSelectorPlatform.instance;
      final picker = _IosContractPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);

      expect(await BackupService.instance.chooseBackupFile(), isNull);
      expect(await SpeechModelService.instance.pickAndImport(), isNull);
      expect(await SpeechDenoiserModelService.instance.pickAndImport(), isNull);
      expect(await VoiceActivityModelService.instance.pickAndImport(), isNull);
      expect(await KokoroTtsModelService.instance.pickAndImport(), isNull);
      for (final id in StreamingSpeechModelService.supportedModelIds) {
        expect(
          await StreamingSpeechModelService.instance.pickAndImport(id),
          isNull,
        );
      }
      for (final id in LanguageModelService.supportedModelIds) {
        expect(await LanguageModelService.instance.pickAndImport(id), isNull);
      }
      picker.returnOneFile = true;
      expect(
        await SpeakerDiarizationModelService.instance.pickAndImport(),
        isNull,
      );
      expect(
        picker.labels,
        containsAll([
          'FK Notes Backup',
          'SenseVoice 模型文件',
          'DPDFNet 降噪模型',
          'Silero VAD 模型',
          'Kokoro TTS 模型归档',
          'Streaming Zipformer 模型文件',
          'MNN 语言模型文件',
          'LiteRT-LM 模型文件',
          'Pyannote 分段模型归档',
          '3D-Speaker 嵌入模型',
        ]),
      );
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform export reports native save/cancel and preserves original',
      () async {
        final root = await Directory.systemTemp.createTemp('file-export-test');
        addTearDown(() => root.delete(recursive: true));
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final source = await File(
          '${root.path}/source.zip',
        ).writeAsBytes([1, 2, 3]);
        final service = FileExportService(channel: channel, platform: platform);
        for (final saved in [true, false, null]) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'saveFile');
            expect(call.arguments, {
              'sourcePath': source.path,
              'suggestedName': 'backup.zip',
              'mimeType': 'application/zip',
            });
            return saved;
          });
          expect(
            await service.save(
              source: source,
              suggestedName: 'backup.zip',
              mimeType: 'application/zip',
            ),
            saved ?? false,
          );
          expect(await source.readAsBytes(), [1, 2, 3]);
        }
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'backup_export_failed');
        });
        await expectLater(
          service.save(
            source: source,
            suggestedName: 'backup.zip',
            mimeType: 'application/zip',
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(await source.readAsBytes(), [1, 2, 3]);
      },
    );
  }
}

class _IosContractPicker extends FileSelectorPlatform {
  final labels = <String>[];
  bool returnOneFile = false;

  void _validate(List<XTypeGroup>? groups) {
    expect(groups, isNotEmpty);
    for (final group in groups!) {
      // Match file_selector_ios's actual requirement before opening the picker.
      expect(
        group.allowsAny || (group.uniformTypeIdentifiers?.isNotEmpty ?? false),
        isTrue,
        reason: '${group.label} must be selectable on iOS',
      );
      labels.add(group.label ?? '');
    }
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    _validate(acceptedTypeGroups);
    if (returnOneFile) {
      returnOneFile = false;
      return XFile('/synthetic/model.tar.bz2');
    }
    return null;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    _validate(acceptedTypeGroups);
    return [];
  }
}

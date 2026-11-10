import 'dart:io';

import 'package:fknotes/app.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_model.dart';
import 'package:fknotes/pages/model_management_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/services/kokoro_tts_model_service.dart';
import 'package:fknotes/services/speech_model_service.dart';
import 'package:fknotes/services/speaker_diarization_model_service.dart';
import 'package:fknotes/services/speech_denoiser_model_service.dart';
import 'package:fknotes/services/voice_activity_model_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_model_management_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
    final partial = File(
      p.join(
        storageDirectory.path,
        'models',
        'asr',
        '.sensevoice-download',
        'model.int8.onnx.part',
      ),
    );
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(List<int>.filled(2048, 1));
    await File(
      p.join(partial.parent.path, 'tokens.txt.part'),
    ).writeAsBytes(List<int>.filled(512, 2));
    await File(
      p.join(partial.parent.path, 'MODEL_LICENSE.txt.part'),
    ).writeAsBytes(List<int>.filled(71, 3));
    final vadPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        'silero-vad-int8-16khz',
        '.download',
        '${VoiceActivityModelService.modelFileName}.part',
      ),
    );
    await vadPartial.parent.create(recursive: true);
    await vadPartial.writeAsBytes(List<int>.filled(123, 4));
    final denoiserPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        SpeechDenoiserModelService.modelId,
        '.download',
        '${SpeechDenoiserModelService.modelFileName}.part',
      ),
    );
    await denoiserPartial.parent.create(recursive: true);
    await denoiserPartial.writeAsBytes(List<int>.filled(456, 6));
    final speakerDownload = Directory(
      p.join(
        storageDirectory.path,
        'models',
        'audio',
        SpeakerDiarizationModelService.modelId,
        '.download',
      ),
    );
    await speakerDownload.create(recursive: true);
    await File(
      p.join(
        speakerDownload.path,
        '${SpeakerDiarizationModelService.segmentationArchiveName}.part',
      ),
    ).writeAsBytes(List<int>.filled(111, 7));
    await File(
      p.join(
        speakerDownload.path,
        '${SpeakerDiarizationModelService.embeddingFileName}.part',
      ),
    ).writeAsBytes(List<int>.filled(222, 8));
    final ttsPartial = File(
      p.join(
        storageDirectory.path,
        'models',
        'tts',
        KokoroTtsModelService.modelId,
        '.download',
        '${KokoroTtsModelService.archiveFileName}.part',
      ),
    );
    await ttsPartial.parent.create(recursive: true);
    await ttsPartial.writeAsBytes(List<int>.filled(321, 5));
    await LocalModelManager.instance.initialize(force: true);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test('partial size includes every resumable model file', () async {
    expect(await SpeechModelService.instance.partialDownloadBytes(), 2631);
    expect(
      await VoiceActivityModelService.instance.partialDownloadBytes(),
      123,
    );
    expect(await KokoroTtsModelService.instance.partialDownloadBytes(), 321);
    expect(
      await SpeechDenoiserModelService.instance.partialDownloadBytes(),
      456,
    );
    expect(
      await SpeakerDiarizationModelService.instance.partialDownloadBytes(),
      333,
    );
  });

  testWidgets('overview only shows active models and category navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
    await tester.pumpAndSettle();

    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('正在使用'), findsOneWidget);
    expect(find.text('分类管理'), findsOneWidget);
    expect(
      find.byKey(const Key('model-download-source-setting')),
      findsNothing,
    );
    expect(find.text('语言模型'), findsOneWidget);
    expect(find.text('语音模型'), findsOneWidget);
    expect(find.text('视觉模型'), findsOneWidget);
    expect(find.text('下载与待继续'), findsOneWidget);
    // All overview destinations fit a phone viewport without the old card gaps.
    expect(find.text('下载与存储').hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('local-model-summary'))).height,
      lessThan(68),
    );
    for (final category in ['language', 'speech', 'vision']) {
      final row = find.byKey(Key('model-category-$category'));
      expect(row.hitTestable(), findsOneWidget);
      expect(tester.getSize(row).height, inInclusiveRange(68, 72));
      expect(tester.getTopLeft(row).dx, 20);
    }
    const activeId = LocalModelManager.mlKitChineseOcrId;
    final active = find.byKey(const Key('active-model-$activeId'));
    expect(tester.getSize(active).height, inInclusiveRange(72, 96));
    expect(tester.widget<Material>(active).type, MaterialType.transparency);
    expect(
      tester.getSize(find.byKey(const Key('active-model-details-$activeId'))),
      const Size(48, 48),
    );
    final metadata = tester.widget<Text>(
      find.byKey(const Key('active-model-metadata-$activeId')),
    );
    expect(metadata.data, '文字识别 · Google ML Kit · 随应用提供');
    expect(metadata.maxLines, isNull);
    expect(find.text('ML Kit 中文文字识别'), findsOneWidget);
    expect(find.text('Qwen3.5 2B INT4'), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact model row keeps separate detail and management actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
      await tester.pumpAndSettle();

      const modelId = LocalModelManager.mlKitChineseOcrId;
      await tester.tap(find.byKey(const Key('active-model-details-$modelId')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.byKey(const Key('local-model-overview-list')),
        findsOneWidget,
      );
      expect(find.text('Google ML Kit'), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('ML Kit 中文文字识别'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.byKey(const Key('model-installation-filter')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('model-row-$modelId')), findsOneWidget);
      expect(find.text('正在使用'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact category rows retain each management destination', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
    await tester.pumpAndSettle();

    for (final category in ['language', 'speech', 'vision']) {
      await tester.tap(find.byKey(Key('model-category-$category')));
      await tester.pumpAndSettle();
      final page = tester.widget<ModelManagementPage>(
        find.byType(ModelManagementPage),
      );
      expect(page.category?.name, category);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('model-download-settings-link')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('model-download-source-setting')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'compact model overview wraps large ${locale.languageCode} text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const ModelManagementPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final downloads = find.byKey(const Key('model-download-settings-link'));
        await tester.scrollUntilVisible(
          downloads,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(downloads.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(downloads);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('model-download-source-setting')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('speech configuration owns live dictation settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.speech),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('语音模型'), findsOneWidget);
    expect(find.text('实时听写设置'), findsOneWidget);
    expect(find.text('热词增强'), findsNothing);

    await tester.tap(find.text('实时听写设置'));
    await tester.pumpAndSettle();
    expect(find.text('热词增强'), findsOneWidget);
    expect(find.text('结束后精修'), findsOneWidget);
    expect(find.text('实时降噪'), findsOneWidget);

    final hotwords = find.byKey(const Key('live-dictation-hotwords-card'));
    final titleLeft = tester.getTopLeft(find.text('热词增强')).dx;
    final switchRight = tester.getTopRight(hotwords).dx - 16;
    for (final (title, switchKey) in [
      ('结束后精修', 'live-dictation-two-pass-switch'),
      ('实时降噪', 'live-dictation-noise-suppression-switch'),
    ]) {
      expect(tester.getTopLeft(find.text(title)).dx, titleLeft);
      expect(tester.getTopRight(find.byKey(Key(switchKey))).dx, switchRight);
    }

    await tester.tap(hotwords);
    await tester.pumpAndSettle();
    expect(find.text('实时听写热词'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('category rows use the full list width and compact metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.language),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();

    const id = LocalModelManager.miniCpm5Id;
    final row = find.byKey(const Key('model-row-$id'));
    expect(tester.getTopLeft(row).dx, 20);
    expect(tester.getSize(row).width, 350);
    expect(tester.getSize(row).height, lessThan(170));
    expect(tester.widget<Material>(row).shape, isNull);
    expect(tester.widget<Material>(row).color, Colors.transparent);
    expect(
      tester.getSize(find.byKey(const Key('model-details-$id'))),
      const Size(48, 48),
    );
    for (final action in ['import', 'download']) {
      expect(
        tester.getSize(find.byKey(Key('model-$action-$id'))).height,
        greaterThanOrEqualTo(48),
      );
    }
    final metadata = tester.widget<Text>(
      find.byKey(const Key('model-metadata-$id')),
    );
    expect(metadata.data, contains('MNN'));
    expect(metadata.data, contains('中文、英语'));
    expect(metadata.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final category in LocalModelCategory.values) {
      testWidgets(
        'compact ${category.name} rows and details wrap large ${locale.languageCode} text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: ModelManagementPage(category: category),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(ModelManagementPage)),
          );
          if (category != LocalModelCategory.vision) {
            final filter = find.byKey(const Key('model-installation-filter'));
            await tester.scrollUntilVisible(
              filter,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(l10n.availableModels));
            await tester.pumpAndSettle();
          }
          final id = switch (category) {
            LocalModelCategory.language => LocalModelManager.miniCpm5Id,
            LocalModelCategory.speech => LocalModelManager.streamingChineseId,
            LocalModelCategory.vision => LocalModelManager.mlKitChineseOcrId,
          };
          final details = find.byKey(Key('model-details-$id'));
          await tester.scrollUntilVisible(
            details,
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(details.hitTestable(), findsOneWidget);
          expect(tester.getSize(details), const Size(48, 48));
          expect(tester.takeException(), isNull);
          await tester.tap(details);
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          final license = find.descendant(
            of: sheet,
            matching: find.text(LocalModelManager.instance.modelOf(id).license),
          );
          await tester.scrollUntilVisible(
            license,
            180,
            scrollable: find.descendant(
              of: sheet,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(license.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('compact settings wrap large ${locale.languageCode} text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ModelManagementPage(showDictationSettings: true),
        ),
      );
      await tester.pumpAndSettle();
      final denoiser = find.byKey(
        const Key('live-dictation-noise-suppression-switch'),
      );
      await tester.scrollUntilVisible(
        denoiser,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(denoiser.hitTestable(), findsOneWidget);
      expect(tester.widget<Switch>(denoiser).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('fresh download action is compact and visually secondary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.language),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();

    final modelId = LocalModelManager.qwen3Vl4BId;
    final importFinder = find.byKey(Key('model-import-$modelId'));
    await tester.scrollUntilVisible(
      importFinder,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(Key('model-row-$modelId')));
    final importButton = tester.getRect(importFinder);
    final downloadButton = tester.getRect(
      find.byKey(Key('model-download-$modelId')),
    );

    expect(importButton.left - card.left, closeTo(16, 1.1));
    expect(card.right - downloadButton.right, closeTo(16, 1.1));
    expect(downloadButton.width, lessThan(card.width * .5));
    expect(downloadButton.left - importButton.right, greaterThan(16));
    final button = tester.widget<FilledButton>(
      find.byKey(Key('model-download-$modelId')),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.softGreen,
    );
  });

  testWidgets('recommendation and metadata follow the model description', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.language),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();

    final card = find.byKey(
      const Key('model-row-${LocalModelManager.qwen3Vl4BId}'),
    );
    await tester.scrollUntilVisible(
      card,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final description = find.descendant(
      of: card,
      matching: find.text('均衡的多语言图文理解模型'),
    );
    final badge = find.descendant(
      of: card,
      matching: find.textContaining('推荐 · '),
    );
    expect(description, findsOneWidget);
    expect(badge, findsOneWidget);
    expect(
      tester.getTopLeft(description).dy,
      lessThan(tester.getTopLeft(badge).dy),
    );
  });

  testWidgets('resumable models are pinned once above regular filters', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 9000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(category: LocalModelCategory.speech),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(
      const Key('model-row-${LocalModelManager.voiceActivityId}'),
    );
    final filter = find.byKey(const Key('model-installation-filter'));
    expect(find.textContaining('下载与待继续（'), findsOneWidget);
    expect(card, findsOneWidget);
    expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(filter).dy));
    expect(
      find.descendant(of: card, matching: find.text('继续下载')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(
          const Key('model-partial-menu-${LocalModelManager.voiceActivityId}'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
  });

  testWidgets('overview transfer entry opens the unified task page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ModelManagementPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-transfer-tasks-link')));
    await tester.pumpAndSettle();

    expect(find.text('下载与待继续'), findsOneWidget);
    expect(find.textContaining('集中查看正在传输'), findsOneWidget);
    final resumableCard = find.byKey(
      const Key('model-row-${LocalModelManager.voiceActivityId}'),
    );
    await tester.scrollUntilVisible(
      resumableCard,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(resumableCard, findsOneWidget);
  });

  testWidgets('focused model entry opens its category and availability', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(focusModelId: LocalModelManager.qwen3Vl4BId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('语言模型'), findsOneWidget);
    expect(find.text('可获取'), findsOneWidget);
    expect(find.text('Qwen3-VL 4B Instruct INT4'), findsOneWidget);
    expect(find.text('正在使用'), findsNothing);
    final row = find.byKey(
      const Key('model-row-${LocalModelManager.qwen3Vl4BId}'),
    );
    expect(tester.widget<Material>(row).color, Colors.transparent);
    final filter = find.byKey(const Key('model-installation-filter'));
    await tester.tap(find.text('已安装'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {true});
    expect(find.text('Qwen3-VL 4B Instruct INT4'), findsNothing);
    await tester.runAsync(
      () => LocalModelManager.instance.initialize(force: true),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {true});
    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an installed focused model does not lock the availability tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ModelManagementPage(
          focusModelId: LocalModelManager.mlKitChineseOcrId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final filter = find.byKey(const Key('model-installation-filter'));
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {true});
    expect(
      tester.widget<SegmentedButton<bool>>(filter).onSelectionChanged,
      isNotNull,
    );
    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {false});
    await tester.runAsync(
      () => LocalModelManager.instance.initialize(force: true),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {false});
    await tester.tap(find.text('已安装'));
    await tester.pumpAndSettle();
    final row = find.byKey(
      const Key('model-row-${LocalModelManager.mlKitChineseOcrId}'),
    );
    expect(tester.widget<Material>(row).color, Colors.transparent);
  });

  testWidgets(
    'focused speech transfers retain actions without a row highlight',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: ModelManagementPage(
            focusModelId: LocalModelManager.senseVoiceId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const Key('model-row-${LocalModelManager.senseVoiceId}'),
      );
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(row).color, Colors.transparent);
      expect(tester.getTopLeft(row).dx, 20);
      expect(tester.getSize(row).width, 350);
      final details = find.byKey(
        const Key('model-details-${LocalModelManager.senseVoiceId}'),
      );
      expect(tester.getSize(details), const Size(48, 48));
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model catalog renders localized English metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ModelManagementPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local models'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Manage by category'), findsOneWidget);
    expect(find.text('Language models'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Downloads and storage'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Downloads and storage'), findsOneWidget);
    expect(find.text('Model download source'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discarding a partial download removes its transfer task', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 9000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: ModelManagementPage(showTransferTasks: true)),
    );
    await tester.pumpAndSettle();

    const modelId = LocalModelManager.voiceActivityId;
    final card = find.byKey(const Key('model-row-$modelId'));
    final menu = find.byKey(const Key('model-partial-menu-$modelId'));
    expect(card, findsOneWidget);
    expect(menu, findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除已下载部分'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('下次需要从头下载'), findsOneWidget);

    await tester.tap(find.text('删除已下载部分'));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 200; attempt++) {
      if (LocalModelManager.instance.installationOf(modelId).partialSizeBytes ==
          0) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      LocalModelManager.instance.installationOf(modelId).partialSizeBytes,
      0,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(card, findsNothing);
  });
}

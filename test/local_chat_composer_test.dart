import 'dart:io';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets(
    'editorial empty composer shares the canvas and centers actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            AppThemeStyle.editorialJournal,
            Brightness.light,
          ),
          home: Scaffold(
            body: LocalChatComposer(
              controller: controller,
              focusNode: focusNode,
              generating: false,
              pendingAttachments: const [],
              pendingNoteContexts: const [],
              imageInputAvailable: true,
              pickingImages: false,
              dictating: false,
              dictationPreparing: false,
              onTakePhoto: () {},
              onPickImages: () {},
              onRemoveAttachment: (_) {},
              onPickNoteContexts: () {},
              onRemoveNoteContext: (_) {},
              onToggleDictation: () {},
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      );

      final surface = find.byKey(const Key('local-chat-composer-surface'));
      final decoration =
          tester.widget<Container>(surface).decoration! as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(decoration.boxShadow, isNull);
      final centerY = tester.getCenter(surface).dy;
      for (final key in const [
        'local-chat-take-photo',
        'local-chat-input',
        'local-chat-voice-input',
        'local-chat-more-actions',
      ]) {
        expect(
          tester.getCenter(find.byKey(Key(key))).dy,
          closeTo(centerY, .01),
          reason: '$key should share the empty composer center line',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active dictation shows simple status and a clear finish action',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: '这是实时识别的文字');
      final focusNode = FocusNode();
      var finishCount = 0;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LocalChatComposer(
              controller: controller,
              focusNode: focusNode,
              generating: false,
              pendingAttachments: const [],
              pendingNoteContexts: const [],
              imageInputAvailable: true,
              pickingImages: false,
              dictating: true,
              dictationPreparing: false,
              onTakePhoto: () {},
              onPickImages: () {},
              onRemoveAttachment: (_) {},
              onPickNoteContexts: () {},
              onRemoveNoteContext: (_) {},
              onToggleDictation: () => finishCount++,
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('local-chat-dictation-state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('local-chat-dictation-text')),
        findsOneWidget,
      );
      expect(find.text('这是实时识别的文字'), findsOneWidget);
      expect(find.text('请自然说话，内容会实时显示'), findsOneWidget);
      expect(find.text('NNAPI'), findsNothing);
      expect(find.byKey(const Key('local-chat-take-photo')), findsNothing);
      expect(
        find.byKey(const Key('local-chat-finish-dictation')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('local-chat-finish-dictation')));
      expect(finishCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preparing dictation uses plain language and can be cancelled', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var cancelCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: true,
            dictationPreparing: true,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) {},
            onToggleDictation: () => cancelCount++,
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('正在准备语音输入…'), findsOneWidget);
    expect(find.textContaining('离线'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-chat-cancel-dictation')));
    expect(cancelCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer previews and removes multiple text quotes', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    ConversationQuote? removed;
    const quotes = [
      ConversationQuote(
        id: 'quote-a',
        sourceId: 'run:a',
        text: '第一处跨段引用内容',
        startOffset: 2,
        endOffset: 10,
        sourceLength: 50,
      ),
      ConversationQuote(
        id: 'quote-b',
        sourceId: 'run:b',
        text: '第二处引用内容',
        startOffset: 4,
        endOffset: 11,
        sourceLength: 20,
      ),
    ];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            pendingQuotes: quotes,
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) {},
            onRemoveQuote: (quote) => removed = quote,
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('第一处跨段引用内容'), findsOneWidget);
    expect(find.text('第二处引用内容'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('pending-chat-quote-remove-quote-a')),
    );
    expect(removed?.id, 'quote-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer exposes text, image and voice inputs on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var sendCount = 0;
    var notePickerCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: false,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () => notePickerCount++,
            onRemoveNoteContext: (_) {},
            onToggleDictation: () {},
            onSend: () => sendCount++,
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-chat-take-photo')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-add-note-context')), findsNothing);
    expect(find.byKey(const Key('local-chat-more-actions')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-input')), findsOneWidget);
    expect(find.byKey(const Key('send-local-chat')), findsNothing);

    final composerSurface = tester.widget<Container>(
      find.byKey(const Key('local-chat-composer-surface')),
    );
    final composerDecoration = composerSurface.decoration! as BoxDecoration;
    expect(composerDecoration.borderRadius, BorderRadius.circular(30));
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('local-chat-more-actions')),
              matching: find.byType(IconButton),
            ),
          )
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      Colors.transparent,
    );

    await tester.tap(find.byKey(const Key('local-chat-more-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-chat-add-menu-image')), findsOneWidget);
    expect(
      find.byKey(const Key('local-chat-add-menu-note-context')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('local-chat-add-menu-note-context')));
    await tester.pumpAndSettle();
    expect(notePickerCount, 1);

    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      '帮我整理这段内容',
    );
    await tester.pump();

    expect(find.byKey(const Key('send-local-chat')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsNothing);
    expect(find.byKey(const Key('local-chat-more-actions')), findsNothing);

    await tester.tap(find.byKey(const Key('send-local-chat')));
    expect(sendCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer renders English actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var imagePickerCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () => imagePickerCount++,
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) {},
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Take photo'), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Reference library notes'), findsOneWidget);
    expect(find.text('Add image'), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-chat-add-menu-image')));
    await tester.pumpAndSettle();
    expect(imagePickerCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generation can queue a focused draft without hiding stop', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var stops = 0;
    var sends = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: true,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) {},
            onToggleDictation: () {},
            onSend: () => sends++,
            onStop: () => stops++,
          ),
        ),
      ),
    );

    final input = find.byKey(const Key('local-chat-input'));
    expect(tester.widget<TextField>(input).enabled, isTrue);
    expect(find.byKey(const Key('stop-local-chat')), findsOneWidget);
    expect(find.byKey(const Key('send-local-chat')), findsNothing);
    await tester.tap(input);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(input, '下一条要求');
    await tester.pump();
    expect(controller.text, '下一条要求');
    expect(find.byKey(const Key('queue-local-chat')), findsOneWidget);
    expect(find.byKey(const Key('stop-local-chat')), findsOneWidget);
    await tester.tap(find.byKey(const Key('queue-local-chat')));
    expect(sends, 1);
    await tester.tap(find.byKey(const Key('stop-local-chat')));
    expect(stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer previews and removes pending note sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var removed = false;
    final note = LocalChatNoteContext(
      noteId: NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57'),
      title: '产品路线图',
      scope: LocalChatNoteScope.fullNote,
      content: '路线图正文',
      updatedAt: DateTime(2026),
    );
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: [note],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) => removed = true,
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('下一条消息将引用'), findsNothing);
    expect(find.text('产品路线图'), findsOneWidget);
    await tester.tap(find.byTooltip('移除笔记引用'));
    expect(removed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending images scroll horizontally and open a zoomable preview',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late final Directory root;
      late final List<LocalChatAttachment> attachments;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('fknotes-chat-images');
        await FileStorageService.instance.init(baseDir: root.path);
        final imageBytes = img.encodePng(img.Image(width: 2, height: 2));
        attachments = <LocalChatAttachment>[];
        for (var index = 0; index < 3; index++) {
          final relativePath = 'assistant/$index.png';
          await File(
            FileStorageService.instance.absolutePath(relativePath),
          ).writeAsBytes(imageBytes);
          attachments.add(
            LocalChatAttachment(
              id: 'image-$index',
              type: LocalChatAttachmentType.image,
              filePath: relativePath,
              fileName: '$index.png',
              mimeType: 'image/png',
              createdAt: DateTime(2026),
            ),
          );
        }
      });
      addTearDown(() async => root.delete(recursive: true));
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LocalChatComposer(
              controller: controller,
              focusNode: focusNode,
              generating: false,
              pendingAttachments: attachments,
              pendingNoteContexts: const [],
              imageInputAvailable: true,
              pickingImages: false,
              dictating: false,
              dictationPreparing: false,
              onTakePhoto: () {},
              onPickImages: () {},
              onRemoveAttachment: (_) {},
              onPickNoteContexts: () {},
              onRemoveNoteContext: (_) {},
              onToggleDictation: () {},
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final strip = tester.widget<ListView>(
        find.byKey(const Key('local-chat-image-strip')),
      );
      expect(strip.scrollDirection, Axis.horizontal);
      expect(
        find.byKey(const Key('local-chat-image-strip-add')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('send-local-chat')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending-chat-image-image-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('local-chat-image-preview')), findsOneWidget);
      expect(
        find.byKey(const Key('local-chat-image-preview-pages')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('local-chat-image-zoom-image-0')),
        findsOneWidget,
      );
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('local-chat-image-preview-pages')),
        const Offset(-280, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

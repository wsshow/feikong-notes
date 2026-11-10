import 'dart:io';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/local_model.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/pages/model_management_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_chat_database_service.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/chat_image_attachments.dart';
import 'package:fknotes/widgets/chat_reference_card_tokens.dart';
import 'package:fknotes/widgets/editorial_paper_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  // Keep the singleton's write queue outside any widget test's FakeAsync zone.
  final store = LocalChatStore.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_chat_models_');
    await FileStorageService.instance.init(baseDir: root.path);
    await LocalChatDatabaseService.instance.database;
    await LocalModelManager.instance.initialize(force: true);
  });

  tearDown(() async {
    await LocalChatDatabaseService.instance.close();
    await root.delete(recursive: true);
  });

  testWidgets(
    'empty chat sits slightly above center and adapts to the keyboard',
    (tester) async {
      await _openChat(tester);
      final empty = find.byKey(const Key('local-chat-empty-state'));
      final content = find.byKey(const Key('local-chat-empty-content'));
      double checkPosition() {
        final viewport = tester.getRect(empty);
        final group = tester.getRect(content);
        final spareHeight = viewport.height - 56 - group.height;
        expect(spareHeight, greaterThan(0));
        expect(group.center.dx, closeTo(viewport.center.dx, .1));
        expect(group.top - viewport.top, closeTo(28 + spareHeight * .4, .1));
        expect(group.center.dy, lessThan(viewport.center.dy));
        expect(group.bottom, lessThan(viewport.bottom - 28));
        return viewport.center.dy - group.center.dy;
      }

      final originalOffset = checkPosition();
      final originalGroup = tester.getRect(content);
      final input = find.byKey(const Key('local-chat-input'));
      final originalInput = tester.getRect(input);
      expect(originalOffset, inInclusiveRange(30, 60));
      await tester.tap(input);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(checkPosition(), lessThan(originalOffset));
      expect(tester.getRect(content).top, lessThan(originalGroup.top));
      expect(tester.getRect(input).top, closeTo(originalInput.top - 300, .1));
      expect(
        tester.getRect(content).bottom,
        lessThan(tester.getRect(input).top),
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.getRect(content), originalGroup);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('empty chat remains scrollable on a short keyboard viewport', (
    tester,
  ) async {
    await _openChat(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('local-chat-input')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();

    final empty = find.byKey(const Key('local-chat-empty-state'));
    final content = find.byKey(const Key('local-chat-empty-content'));
    final viewport = tester.getRect(empty);
    expect(tester.getRect(content).top, closeTo(viewport.top + 28, .1));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: empty, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(empty, const Offset(0, -400));
    await tester.pumpAndSettle();
    final description = tester.getRect(find.text('自由输入任何内容。消息和角色设定只保存在本机。'));
    expect(description.bottom, lessThanOrEqualTo(viewport.bottom - 28 + .1));
    expect(
      find.byKey(const Key('local-chat-input')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (kind, content, hasImage) in [
    ('text', '测试', false),
    ('image caption', '图片说明', true),
    ('image only', '', true),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        '$kind message time sits outside the card at ${textScale}x text',
        (tester) async {
          final attachments = <LocalChatAttachment>[];
          if (hasImage) {
            const relativePath = 'assistant/message-time.png';
            await tester.runAsync(() async {
              await File(
                FileStorageService.instance.absolutePath(relativePath),
              ).writeAsBytes(img.encodePng(img.Image(width: 4, height: 2)));
            });
            attachments.add(
              store.createImageAttachment(
                filePath: relativePath,
                fileName: 'message-time.png',
                mimeType: 'image/png',
              ),
            );
          }
          final message = LocalChatMessage(
            id: 'timestamp-test',
            role: LocalChatRole.user,
            content: content,
            attachments: attachments,
            createdAt: DateTime(2026, 8, 28, 21, 28),
          );
          await tester.runAsync(
            () => store.saveSession(
              store.createSession().copyWith(messages: [message]),
            ),
          );
          await _openChat(
            tester,
            size: const Size(320, 720),
            textScale: textScale,
          );
          if (hasImage) {
            final sentImage = find.byKey(
              ValueKey('sent-chat-image-${attachments.single.id}'),
            );
            await _pumpUntil(tester, sentImage.hitTestable());
            expect(
              tester.getSize(sentImage),
              const Size(
                ChatImageAttachments.singleImageWidth,
                ChatImageAttachments.singleImageHeight,
              ),
            );
          }
          final time = find.byKey(
            ValueKey('local-chat-user-message-time-${message.id}'),
          );
          final card = content.isEmpty
              ? find.byKey(ValueKey('sent-chat-image-${attachments.single.id}'))
              : find.byKey(
                  ValueKey('local-chat-user-message-card-${message.id}'),
                );
          expect(time, findsOneWidget);
          expect(tester.widget<Text>(time).data, '21:28');
          expect(find.descendant(of: card, matching: time), findsNothing);
          final cardRect = tester.getRect(card);
          final timeRect = tester.getRect(time);
          expect(timeRect.top - cardRect.bottom, closeTo(6, .1));
          expect(timeRect.right, closeTo(cardRect.right, .1));
          expect(cardRect.right, closeTo(320 - 16, .1));
          expect(
            timeRect.bottom,
            lessThan(tester.getRect(find.byType(LocalChatComposer)).top),
          );
          if (content.isNotEmpty) {
            expect(
              tester
                  .widget<SelectableText>(
                    find.descendant(
                      of: card,
                      matching: find.byType(SelectableText),
                    ),
                  )
                  .data,
              content,
              reason: 'only the message body belongs to selectable card text',
            );
          }
          if (hasImage) {
            await tester.tap(
              find.byKey(ValueKey('sent-chat-image-${attachments.single.id}')),
            );
            await tester.pumpAndSettle();
            final preview = find.byKey(const Key('local-chat-image-preview'));
            expect(preview, findsOneWidget);
            Navigator.of(tester.element(preview)).pop();
            await tester.pumpAndSettle();
            expect(time, findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final (messageCount, textScale) in [(2, 1.0), (16, 1.0), (16, 2.0)]) {
    testWidgets(
      '$messageCount chat messages follow keyboard and multiline composer at ${textScale}x text',
      (tester) async {
        final messages = await _seedConversation(tester, store, messageCount);
        await _openChat(
          tester,
          size: Size(textScale == 2 ? 320 : 390, 720),
          textScale: textScale,
        );
        final timeline = find.byKey(const Key('local-chat-timeline'));
        final scroll = tester.widget<ListView>(timeline).controller!;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, closeTo(0, .1));
        if (messageCount == 2) {
          expect(scroll.position.maxScrollExtent, 0);
        }
        final input = find.byKey(const Key('local-chat-input'));
        final originalInput = tester.getRect(input);
        await tester.tap(input);
        for (final inset in [100.0, 200.0, 300.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            scroll.position.extentAfter,
            closeTo(0, .1),
            reason: 'the latest message stays anchored during IME resizing',
          );
          expect(tester.getRect(input).bottom, lessThan(720 - inset));
        }
        expect(tester.getRect(input).top, closeTo(originalInput.top - 300, .1));
        expect(
          tester.getRect(find.text(messages.last.content)).bottom,
          lessThan(tester.getRect(timeline).bottom),
        );

        await tester.enterText(input, '草稿');
        await tester.pumpAndSettle();
        expect(
          tester.getRect(input).height,
          closeTo(originalInput.height, .1),
          reason: 'the empty hint must not occupy extra lines',
        );
        final draft = textScale == 2 ? '第一行\n第二行' : '第一行草稿\n第二行\n第三行\n第四行';
        await tester.enterText(input, draft);
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, closeTo(0, .1));
        expect(tester.getRect(input).height, greaterThan(originalInput.height));
        final latestText = tester.getRect(find.text(messages.last.content));
        expect(
          latestText.overlaps(tester.getRect(timeline)),
          isTrue,
          reason: 'bottom padding must not push the latest text out of view',
        );
        expect(
          tester.getRect(timeline).bottom,
          lessThan(tester.getRect(input).top),
        );
        tester.widget<TextField>(input).focusNode!.unfocus();
        for (final inset in [200.0, 100.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(scroll.position.extentAfter, closeTo(0, .1));
        }
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, draft);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'keyboard keeps history anchored and remains open while scrolling',
    (tester) async {
      await _seedConversation(tester, store, 16);
      await _openChat(tester, size: const Size(390, 720));
      final timeline = find.byType(ListView);
      final scroll = tester.widget<ListView>(timeline).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.drag(timeline, const Offset(0, 300));
      await tester.pumpAndSettle();
      final historyOffset = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(72));
      final jump = find.byKey(const Key('local-chat-jump-to-bottom'));
      expect(jump.hitTestable(), findsOneWidget);
      final input = find.byKey(const Key('local-chat-input'));
      final inputFocus = tester.widget<TextField>(input).focusNode!;
      final viewportBeforeKeyboard = scroll.position.viewportDimension;
      await tester.tap(input);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final viewportWithKeyboard = scroll.position.viewportDimension;
      expect(
        scroll.offset,
        closeTo(
          historyOffset + viewportBeforeKeyboard - viewportWithKeyboard,
          .1,
        ),
        reason: 'the content above the composer should move above the IME',
      );
      expect(inputFocus.hasFocus, isTrue);
      final offsetBeforeDrag = scroll.offset;
      await tester.drag(timeline, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(offsetBeforeDrag));
      expect(
        inputFocus.hasFocus,
        isTrue,
        reason: 'reading older messages must not dismiss the keyboard',
      );
      final offsetBeforeDraft = scroll.offset;
      final viewportBeforeDraft = scroll.position.viewportDimension;
      await tester.enterText(input, '保留草稿\n继续输入');
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        closeTo(
          offsetBeforeDraft +
              viewportBeforeDraft -
              scroll.position.viewportDimension,
          .1,
        ),
      );
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, .1));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('assistant model title opens the same category as settings', (
    tester,
  ) async {
    await _openChat(tester);
    await tester.enterText(find.byKey(const Key('local-chat-input')), '保留草稿');
    await tester.tap(find.byKey(const Key('local-chat-open-models')));
    await _pumpUntil(tester, find.byType(ModelManagementPage));
    await tester.pumpAndSettle();
    final page = tester.widget<ModelManagementPage>(
      find.byType(ModelManagementPage),
    );
    expect(page.category, LocalModelCategory.language);
    expect(page.focusModelId, isNull);
    final filter = find.byKey(const Key('model-installation-filter'));
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {true});
    expect(
      tester.widget<SegmentedButton<bool>>(filter).onSelectionChanged,
      isNotNull,
    );
    await tester.tap(find.text('可获取'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(filter).selected, {false});
    final row = find.byKey(
      const Key('model-row-${LocalModelManager.miniCpm5Id}'),
    );
    expect(tester.widget<Material>(row).color, Colors.transparent);
    expect(
      find.byKey(const Key('model-download-${LocalModelManager.miniCpm5Id}')),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-chat-open-models')), findsOneWidget);
    expect(find.text('保留草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'missing-model guidance opens availability without locking tabs',
    (tester) async {
      await _openChat(tester);
      await tester.enterText(find.byKey(const Key('local-chat-input')), '你好');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-local-chat')));
      await _pumpUntil(tester, find.byType(AlertDialog));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.widget<ModelManagementPage>(
        find.byType(ModelManagementPage),
      );
      expect(page.category, LocalModelCategory.language);
      expect(page.focusModelId, isNotNull);
      final filter = find.byKey(const Key('model-installation-filter'));
      expect(tester.widget<SegmentedButton<bool>>(filter).selected, {false});
      await tester.tap(find.text('已安装'));
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<bool>>(filter).selected, {true});
      await tester.tap(find.text('可获取'));
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<bool>>(filter).selected, {false});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('user note references render as compact cards and open notes', (
    tester,
  ) async {
    final reference = LocalChatNoteContext(
      noteId: NoteId.parse('7be74db5-e23d-4f5f-9226-86072142be77'),
      title: '项目路线图',
      scope: LocalChatNoteScope.fullNote,
      content: '路线图正文',
      updatedAt: DateTime(2026, 8, 30),
    );
    final message = store.createMessage(
      role: LocalChatRole.user,
      content: '帮我检查一下',
      noteContexts: [reference],
    );
    await tester.runAsync(
      () => store.saveSession(
        store.createSession().copyWith(messages: [message]),
      ),
    );
    LocalChatNoteContext? opened;
    await _openChat(tester, onOpenNote: (note) async => opened = note);

    final card = find.byKey(
      ValueKey('local-chat-user-note-${message.id}-${reference.noteId.value}'),
    );
    expect(card, findsOneWidget);
    expect(find.text('项目路线图'), findsOneWidget);
    expect(
      tester.getSize(card),
      const Size(ChatReferenceCardTokens.width, ChatReferenceCardTokens.height),
    );
    await tester.tap(card);
    await tester.pump();
    expect(opened?.noteId, reference.noteId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial assistant turns replies into paper cards', (
    tester,
  ) async {
    final message = store.createMessage(
      role: LocalChatRole.assistant,
      content: '我把这段想法整理成了一张纸页。',
    );
    await tester.runAsync(
      () => store.saveSession(
        store.createSession().copyWith(messages: [message]),
      ),
    );
    await _openChat(
      tester,
      theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
    );

    final card = tester.widget<Container>(
      find.byKey(ValueKey('local-chat-assistant-message-card-${message.id}')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.editorialJournalLight.surface);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(AppRadii.editorial.large),
    );
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
    final composer = tester.widget<Container>(
      find.byKey(const Key('local-chat-composer-surface')),
    );
    final composerDecoration = composer.decoration! as BoxDecoration;
    expect(
      tester
          .widget<Material>(find.byKey(const Key('local-chat-composer-region')))
          .type,
      MaterialType.transparency,
    );
    expect(
      composerDecoration.borderRadius,
      BorderRadius.circular(AppRadii.editorial.extraLarge),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial user messages use the shared cobalt paper surface', (
    tester,
  ) async {
    final message = store.createMessage(
      role: LocalChatRole.user,
      content: '把今天的灵感记下来',
    );
    await tester.runAsync(
      () => store.saveSession(
        store.createSession().copyWith(messages: [message]),
      ),
    );
    await _openChat(
      tester,
      theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
    );

    final card = tester.widget<EditorialPaperSurface>(
      find.descendant(
        of: find.byKey(ValueKey('local-chat-user-message-card-${message.id}')),
        matching: find.byType(EditorialPaperSurface),
      ),
    );
    expect(card.color, EditorialJournalTokens.colorCobalt);
    expect(card.borderColor, isNull);
    expect(card.radius, AppRadii.editorial.large);
    expect(card.depth, EditorialSurfaceDepth.lifted);
    expect(card.textureOpacity, .06);
    final text = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(ValueKey('local-chat-user-message-card-${message.id}')),
        matching: find.byType(SelectableText),
      ),
    );
    expect(text.style?.color, AppPalette.editorialJournalLight.onAccent);
    expect(tester.takeException(), isNull);
  });
}

Future<List<LocalChatMessage>> _seedConversation(
  WidgetTester tester,
  LocalChatStore store,
  int count,
) async {
  final messages = List.generate(
    count,
    (index) => store.createMessage(
      role: LocalChatRole.user,
      content: '第 ${index + 1} 条消息\n这段聊天内容需要保持可见。\n可以继续输入新的问题。',
    ),
  );
  await tester.runAsync(
    () => store.saveSession(store.createSession().copyWith(messages: messages)),
  );
  return messages;
}

Future<void> _openChat(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  double textScale = 1,
  LocalChatNoteOpener? onOpenNote,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      theme: theme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LocalChatPage(onOpenNote: onOpenNote),
    ),
  );
  await _pumpUntil(tester, find.byKey(const Key('local-chat-open-models')));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  // The real test database and model manifests use filesystem I/O, so allow
  // those futures to finish outside FakeAsync before advancing Flutter frames.
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}

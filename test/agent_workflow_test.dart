import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fknotes/agent/agent_service.dart';
import 'package:fknotes/agent/agent_run_timing.dart';
import 'package:fknotes/agent/editor_agent_driver.dart';
import 'package:fknotes/agent/model_profile.dart';
import 'package:fknotes/agent/model_catalog.dart';
import 'package:fknotes/agent/note_tools.dart'
    show taskCreatedNoteIds, taskNoteChanges;
import 'package:fknotes/pages/agent_model_editor_page.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/agent_tasks_page.dart';
import 'package:fknotes/pages/agent_settings_page.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/providers/private_notes_controller.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_chat_database_service.dart';
import 'package:fknotes/services/local_chat_note_context_builder.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/agent_permission_sheet.dart';
import 'package:fknotes/widgets/agent_task_card.dart';
import 'package:fknotes/widgets/local_chat_note_picker.dart';
import 'package:fknotes/widgets/app_icon.dart';
import 'package:fknotes/widgets/app_popup_menu.dart';
import 'package:fknotes/widgets/chat_image_attachments.dart';
import 'package:fknotes/widgets/chat_reference_card_tokens.dart';
import 'package:fknotes/widgets/editorial_paper_surface.dart';
import 'package:fknotes/widgets/fk_markdown_view.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'agent_model_adapter_test.dart' show TestVault;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final chats = LocalChatStore.instance;
  late Directory directory;
  late Database db;
  late NoteRepository repo;
  late AgentService service;
  late PrivateNotesController privacy;
  late Note note;
  late _Model model;
  late List<http.Request> catalogRequests;
  late Future<http.Response> Function(http.Request) catalogResponse;
  const profile = ModelProfile(
    id: 'test',
    name: 'Test provider',
    protocol: ModelProtocol.responses,
    endpoint: 'https://example.test/v1',
    model: 'test',
  );
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const fontPath = String.fromEnvironment('FKNOTES_QA_FONT');
    if (fontPath.isNotEmpty) {
      final data = File(
        fontPath,
      ).readAsBytes().then((b) => ByteData.sublistView(b));
      await (FontLoader('Roboto')..addFont(data)).load();
      await (FontLoader('Source Han Serif CN')..addFont(data)).load();
    }
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_workflow_');
    await FileStorageService.instance.init(baseDir: directory.path);
    await LocalChatDatabaseService.instance.database;
    await LocalModelManager.instance.initialize(force: true);
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    repo = NoteRepository(db);
    await repo.initialize();
    note = await repo.create(
      Note.newDraft().copyWith(
        title: 'Project',
        document: NoteDocument.fromPlainText('Original text'),
      ),
    );
    privacy = PrivateNotesController(
      authenticator: _Unlock(),
      observeLifecycle: false,
    );
    model = _Model();
    final vault = TestVault();
    catalogRequests = [];
    catalogResponse = (_) async => http.Response('unavailable', 404);
    service = AgentService(
      storage: FileStorageService.instance,
      vault: vault,
      modelCatalog: ModelCatalog(
        vault,
        clientFactory: () => MockClient((request) {
          catalogRequests.add(request);
          return catalogResponse(request);
        }),
      ),
      privateNotes: privacy,
      repository: () async => repo,
      runStore: MemoryRunStore(),
      modelResolver: (_) async => model,
    );
    await service.profiles.save(profile);
    await service.profiles.select(profile.id);
    await service.initialize();
  });
  tearDown(() async {
    await service.close();
    privacy.dispose();
    await db.close();
    await LocalChatDatabaseService.instance.close();
    await directory.delete(recursive: true);
  });

  testWidgets('configured model starts directly; workflow survives navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => service.profiles.setDefaultRequireApproval(true),
    );
    final finish = Completer<void>();
    model.respond = (request, cancel) async* {
      switch (model.requests.length) {
        case 1:
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'search',
                  name: 'search_notes',
                  arguments: {'query': 'Project'},
                ),
              ],
            ),
          );
        case 2:
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'read',
                  name: 'read_notes',
                  arguments: {
                    'ids': [note.id.value],
                  },
                ),
              ],
            ),
          );
        case 3:
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'write',
                  name: 'propose_note_changes',
                  arguments: {
                    'changes': [
                      {
                        'kind': 'append',
                        'noteId': note.id.value,
                        'baseRevision': note.revision,
                        'text': 'Approved addition',
                      },
                    ],
                  },
                ),
              ],
            ),
          );
        default:
          yield const ModelReasoning('先核对已读取的笔记和修改结果。');
          await finish.future;
          yield const ModelText('Workflow complete');
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              text: 'Workflow complete',
            ),
          );
      }
    };
    await tester.pumpWidget(
      _app(
        LocalChatPage(
          agentService: service,
          initialNoteContext: LocalChatNoteContextBuilder.fromNote(
            note,
            untitledLabel: 'Untitled',
          ),
        ),
      ),
    );
    await _until(
      tester,
      () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      'Summarize and append the result',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-local-chat')));
    await _until(
      tester,
      () => service.runs.any((r) => r.status == RunStatus.waitingApproval),
    );
    expect(find.byKey(const Key('agent-start-task')), findsNothing);
    expect(model.requests, hasLength(3));
    expect(
      await tester.runAsync(() => repo.get(note.id)),
      isA<Note>().having(
        (n) => n.revision,
        'not written before approval',
        note.revision,
      ),
    );
    final run = service.runs.single;
    expect(run.scope.online, isTrue);
    expect(run.scope.readNotes, isTrue);
    expect(run.scope.allNotes, isTrue);
    expect(run.scope.writeNotes, isTrue);
    expect(run.scope.networkTools, isTrue);
    expect(
      model.requests.first.tools.map((tool) => tool.name),
      contains('web_fetch'),
    );
    expect(run.scope.requireApproval, isTrue);
    final writeOperationId = run.pending.single.operationId;
    final review = find.byKey(ValueKey('agent-review-$writeOperationId'));
    await tester.scrollUntilVisible(
      review,
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('local-chat-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(review);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Original text'), findsWidgets);
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-approve-proposal'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    await _capture(tester, '02-proposal');
    await tester.tap(find.byKey(const Key('agent-approve-proposal')));
    await _until(tester, () => model.requests.length == 4);
    await _until(tester, () => service.runs.single.reasoning.isNotEmpty);
    final process = find.byKey(
      ValueKey('agent-process-${run.id}-${service.runs.single.status.name}'),
    );
    expect(process, findsOneWidget);
    expect(find.text('先核对已读取的笔记和修改结果。'), findsOneWidget);
    expect(
      find.byKey(ValueKey('agent-reasoning-details-${run.id}-4')),
      findsNothing,
    );
    expect(
      find.descendant(of: process, matching: find.text('笔记修改')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: process, matching: find.text('调用参数')),
      findsNothing,
    );
    await tester.tap(find.byKey(ValueKey('agent-reasoning-${run.id}-4')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(ValueKey('agent-reasoning-details-${run.id}-4')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('agent-tool-$writeOperationId')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.descendant(of: process, matching: find.text('调用参数')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stop-local-chat')), findsOneWidget);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('补充要求'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('local-chat-input')))
          .enabled,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      '完成后继续整理标题',
    );
    expect(find.byKey(ValueKey('agent-reply-actions-${run.id}')), findsNothing);
    // Closing the chat only removes the subscriber. The application owns the run.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.runs.single.status, RunStatus.running);
    finish.complete();
    await _until(
      tester,
      () => service.runs.single.status == RunStatus.completed,
    );
    final stored = await tester.runAsync(() => chats.loadSessions());
    expect(
      stored!.single.messages,
      isEmpty,
      reason: 'Task bodies are not mirrored into plaintext chat history',
    );
    await tester.pumpWidget(_app(AgentStatisticsPage(service: service)));
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-statistics-overview'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const Key('agent-task-details-page')), findsNothing);
    expect(find.byType(FkMarkdownView), findsNothing);
    expect(find.byKey(const Key('agent-statistics-recent')), findsOneWidget);
    expect(find.byKey(const Key('agent-statistics-tokens')), findsOneWidget);
    expect(
      find.byKey(const Key('agent-statistics-local-runs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-statistics-online-runs')),
      findsOneWidget,
    );
    expect(find.text('智能体统计'), findsOneWidget);
    expect(find.text('近 7 天使用'), findsOneWidget);
    expect(find.text('累计 Token'), findsOneWidget);
    expect(find.text('本地推理'), findsOneWidget);
    expect(find.text('在线推理'), findsOneWidget);
    expect(find.text('完成率'), findsNothing);
    expect(find.text('智能体轮次'), findsNothing);
    expect(find.text('工具调用'), findsNothing);
    expect(find.text(run.goal), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('test · Test provider'), findsOneWidget);
    await _capture(tester, '03-task');
    await tester.runAsync(() => service.undo(run.id, writeOperationId));
    await _until(
      tester,
      () => service.runs.single.actions.single['undone'] == true,
    );
    final restored = await tester.runAsync(() => repo.get(note.id));
    expect(
      restored!.document.toQuillDocument().toPlainText(),
      'Original text\n',
    );
    expect(stored.single.title, isNot(contains('Summarize')));
    await tester.runAsync(
      () => chats.saveSession(
        stored.single.copyWith(
          messages: [
            chats.createMessage(
              role: LocalChatRole.assistant,
              content: 'Archived reply with a violet-orchid keyword.',
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(_app(LocalChatPage(agentService: service)));
    await _until(
      tester,
      () => find
          .byKey(ValueKey('agent-reply-actions-${run.id}'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byKey(ValueKey('agent-user-message-${run.id}')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('agent-user-time-${run.id}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('agent-run-finished-${run.id}')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('agent-copy-${run.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('agent-regenerate-${run.id}')), findsOneWidget);
    expect(find.text('先核对已读取的笔记和修改结果。'), findsNothing);
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();
    expect(find.text('先核对已读取的笔记和修改结果。'), findsOneWidget);
    expect(
      find.byKey(ValueKey('agent-reasoning-details-${run.id}-4')),
      findsNothing,
    );
    await tester.tap(find.byKey(ValueKey('agent-reasoning-${run.id}-4')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('agent-reasoning-details-${run.id}-4')),
      findsOneWidget,
    );
    final newConversation = find.byKey(
      const Key('local-chat-new-conversation'),
    );
    await _until(
      tester,
      () =>
          newConversation.evaluate().isNotEmpty &&
          tester.widget<IconButton>(newConversation).onPressed != null,
    );
    final newConversationIcon = find.descendant(
      of: newConversation,
      matching: find.byType(AppIcon),
    );
    expect(
      tester.widget<AppIcon>(newConversationIcon).icon,
      Icons.add_comment_outlined,
    );
    expect(find.byKey(const Key('chat-agent-settings')), findsNothing);
    expect(find.byKey(const Key('chat-agent-history')), findsNothing);
    expect(find.byKey(const Key('local-chat-persona-switcher')), findsNothing);
    final actionsMenu = find.byKey(const Key('local-chat-actions-menu'));
    expect(
      tester.widget<AppAnchoredMenuButton<String>>(actionsMenu).actions.length,
      5,
    );
    await tester.tap(actionsMenu);
    final historyAction = find.widgetWithText(MenuItemButton, '对话记录');
    await _until(tester, () => historyAction.evaluate().isNotEmpty);
    final personaAction = find.widgetWithText(MenuItemButton, '切换角色');
    expect(personaAction, findsOneWidget);
    final personaActionIcon = find.descendant(
      of: personaAction,
      matching: find.byType(AppIcon),
    );
    expect(
      tester.widget<AppIcon>(personaActionIcon).icon,
      Icons.groups_2_outlined,
    );
    expect(find.widgetWithText(MenuItemButton, '智能体设置'), findsOneWidget);
    await tester.tap(historyAction);
    final row = find.byKey(ValueKey('agent-session-${run.sessionId}'));
    await _until(tester, () => row.evaluate().isNotEmpty);
    expect(find.byKey(const Key('chat-history-sheet')), findsOneWidget);
    expect(find.byKey(const Key('chat-history-hint')), findsOneWidget);
    expect(find.byKey(const Key('chat-history-list')), findsOneWidget);
    final historySearch = find.byKey(const Key('chat-history-search'));
    expect(historySearch, findsOneWidget);
    expect(
      find.byKey(const Key('chat-history-new-conversation')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text('Summarize and append the result'),
      ),
      findsOneWidget,
    );
    await tester.enterText(historySearch, 'violet orchid');
    await tester.pump();
    expect(row, findsOneWidget, reason: 'message bodies are searchable');
    await tester.enterText(historySearch, 'definitely-not-in-history');
    await tester.pump();
    expect(row, findsNothing);
    expect(find.text('没有找到匹配的对话'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('没有找到匹配的对话')).dy,
      lessThan(632),
      reason: 'the search state stays above the keyboard',
    );
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-history-clear-search')));
    await tester.pump();
    expect(row, findsOneWidget);
    await tester.runAsync(
      () => repo.update(restored.copyWith(isPrivate: true)),
    );
    await _until(tester, () => service.runs.single.requiresPrivateAccess);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Summarize and append the result'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text('隐私空间已锁定')),
      findsOneWidget,
    );
    await tester.enterText(historySearch, 'violet orchid');
    await tester.pump();
    expect(
      row,
      findsNothing,
      reason: 'locked conversations do not expose content through search',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'streamed text stays in the process timeline until the final reply completes',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      const stageText = '我先确认资料，再继续整理。';
      const finalText = '这是最终回答。';
      model.respond = (request, cancel) async* {
        if (model.requests.length == 1) {
          yield const ModelText(stageText);
          await release.future;
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              text: stageText,
              calls: [
                ToolCall(
                  id: 'search-stage',
                  name: 'search_notes',
                  arguments: {'query': 'Project'},
                ),
              ],
            ),
          );
        } else {
          yield ModelCompleted(
            AgentMessage(role: MessageRole.assistant, text: finalText),
          );
        }
      };
      final id = await tester.runAsync(() async {
        final scope = await service.grant(
          profileId: profile.id,
          online: true,
          readNotes: true,
          noteIds: {note.id.value},
        );
        return service.start(
          sessionId: 'stream-stage',
          input: '整理 Project 笔记',
          profileId: profile.id,
          scope: scope,
        );
      });
      late AgentRun activeRun;
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          activeRun = (await service.runtime.get(id!))!;
          if (activeRun.draft == stageText) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('The streamed stage text was not persisted.');
      });

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: AgentTaskCard(
                service: service,
                run: activeRun,
                conversation: true,
              ),
            ),
          ),
          themed: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final timeline = find.byKey(
        ValueKey('agent-process-timeline-${activeRun.id}'),
      );
      final stage = find.byKey(
        ValueKey('agent-stage-${activeRun.id}-live-stage'),
      );
      expect(timeline, findsOneWidget);
      expect(find.descendant(of: timeline, matching: stage), findsOneWidget);
      expect(
        find.descendant(of: timeline, matching: find.text(stageText)),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is FkMarkdownView && widget.data == stageText,
        ),
        findsNothing,
      );

      release.complete();
      await tester.runAsync(() => service.runtime.settle(activeRun.id));
      final completed = (await tester.runAsync(
        () => service.runtime.get(activeRun.id),
      ))!;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: AgentTaskCard(
                service: service,
                run: completed,
                conversation: true,
              ),
            ),
          ),
          themed: true,
        ),
      );
      await tester.pumpAndSettle();

      final finalMarkdown = find.byWidgetPredicate(
        (widget) => widget is FkMarkdownView && widget.data == finalText,
      );
      expect(finalMarkdown, findsOneWidget);
      expect(
        find.ancestor(
          of: finalMarkdown,
          matching: find.byKey(
            ValueKey('agent-process-timeline-${completed.id}'),
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'streaming keeps the next draft editable and respects a history drag',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final appendMore = Completer<void>();
      final finish = Completer<void>();
      addTearDown(() {
        if (!appendMore.isCompleted) appendMore.complete();
        if (!finish.isCompleted) finish.complete();
      });
      final first = List.generate(
        34,
        (index) => '正在整理第 ${index + 1} 条内容。',
      ).join('\n');
      final second = List.generate(
        18,
        (index) => '继续补充第 ${index + 1} 条内容。',
      ).join('\n');
      model.respond = (request, cancel) async* {
        yield ModelText(first);
        await appendMore.future;
        yield ModelText(second);
        await finish.future;
        yield ModelCompleted(
          AgentMessage(role: MessageRole.assistant, text: '$first\n$second'),
        );
      };
      final session = chats.createSession().copyWith(
        messages: [
          for (var index = 0; index < 12; index++)
            chats.createMessage(
              role: LocalChatRole.user,
              content: '历史消息 ${index + 1}\n用于验证流式输出时仍可向上阅读。',
            ),
        ],
      );
      late String runId;
      await tester.runAsync(() async {
        await _insertChatSession(session);
        final scope = await service.grant(profileId: profile.id, online: true);
        runId = (await service.start(
          sessionId: session.id,
          input: '持续整理内容',
          profileId: profile.id,
          scope: scope,
        ));
      });
      await _until(
        tester,
        () => service.runs.any(
          (run) => run.id == runId && run.draft.contains('第 34 条'),
        ),
      );
      await tester.pumpWidget(
        _app(
          LocalChatPage(agentService: service, initialSessionId: session.id),
        ),
      );
      final timeline = find.byKey(const Key('local-chat-timeline'));
      await _until(tester, () => timeline.evaluate().isNotEmpty);
      final scroll = tester.widget<ListView>(timeline).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
      expect(scroll.position.extentAfter, closeTo(0, .1));

      final input = find.byKey(const Key('local-chat-input'));
      final focus = tester.widget<TextField>(input).focusNode!;
      await tester.tap(input);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(focus.hasFocus, isTrue);
      await tester.enterText(input, '模型完成后执行这条指令');
      await tester.pump();
      await tester.tap(find.byKey(const Key('queue-local-chat')));
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        isEmpty,
        reason: '排队操作不应等待加密持久化后才清空输入框',
      );
      await _until(
        tester,
        () => service.queuedSessionRuns(session.id).length == 1,
      );
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.byKey(const Key('local-chat-queued-inputs')), findsOneWidget);
      final firstQueueId = service.queuedSessionRuns(session.id).single.id;
      expect(
        find.byKey(ValueKey('promote-queued-input-$firstQueueId')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('edit-queued-input-$firstQueueId')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      final editor = find.byKey(ValueKey('queued-input-editor-$firstQueueId'));
      await tester.enterText(editor, '编辑后的下一条指令');
      await tester.tap(find.byKey(ValueKey('save-queued-input-$firstQueueId')));
      await _until(
        tester,
        () => service.queuedSessionRuns(session.id).single.goal == '编辑后的下一条指令',
      );

      await tester.tap(input);
      await tester.enterText(input, '需要取消的消息');
      await tester.pump();
      await tester.tap(find.byKey(const Key('queue-local-chat')));
      await _until(
        tester,
        () => service.queuedSessionRuns(session.id).length == 2,
      );
      final secondQueueId = service.queuedSessionRuns(session.id).last.id;
      expect(
        tester
            .getSize(find.byKey(ValueKey('queued-input-row-$secondQueueId')))
            .height,
        34,
      );
      expect(
        tester.getSize(
          find.byKey(ValueKey('edit-queued-input-$secondQueueId')),
        ),
        const Size(40, 34),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('local-chat-queued-inputs')))
            .height,
        lessThanOrEqualTo(100),
      );
      await tester.tap(
        find.byKey(ValueKey('cancel-queued-input-$secondQueueId')),
      );
      await _until(
        tester,
        () => service.queuedSessionRuns(session.id).length == 1,
      );

      final gesture = await tester.startGesture(tester.getCenter(timeline));
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();
      final readingOffset = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(8));
      expect(scroll.position.extentAfter, lessThanOrEqualTo(72));
      appendMore.complete();
      await _until(
        tester,
        () => service.runs
            .singleWhere((run) => run.id == runId)
            .draft
            .contains('继续补充第 18 条'),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(scroll.offset, closeTo(readingOffset, .1));
      expect(scroll.position.extentAfter, greaterThan(0));
      expect(focus.hasFocus, isTrue);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(scroll.position.extentAfter, greaterThan(8));
      await gesture.up();
      await tester.pump();
      expect(
        find.byKey(const Key('local-chat-jump-to-bottom')).hitTestable(),
        findsOneWidget,
      );
      final offsetBeforeCompletion = scroll.offset;
      final viewportBeforeCompletion = scroll.position.viewportDimension;
      finish.complete();
      await _until(
        tester,
        () =>
            service.runs.singleWhere((run) => run.id == runId).status.terminal,
      );
      await _until(
        tester,
        () =>
            service.sessionRuns(session.id).length == 2 &&
            service.sessionRuns(session.id).last.status.terminal,
      );
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        scroll.offset,
        closeTo(
          offsetBeforeCompletion +
              viewportBeforeCompletion -
              scroll.position.viewportDimension,
          .1,
        ),
      );
      expect(scroll.position.extentAfter, greaterThan(8));
      expect(model.requests, hasLength(2));
      expect(model.requests.last.messages.last.text, '编辑后的下一条指令');
      expect(service.sessionRuns(session.id), hasLength(2));
      expect(service.sessionRuns(session.id).last.answer, '$first\n$second');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('agent conversation renders and opens uploaded user image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const reference = 'assistant/agent-user-message.png';
    await tester.runAsync(
      () => File(
        FileStorageService.instance.absolutePath(reference),
      ).writeAsBytes(img.encodePng(img.Image(width: 8, height: 6))),
    );
    final createdAt = DateTime(2026, 8, 30, 10, 15);
    final run = AgentRun(
      id: 'agent-image-run',
      sessionId: 'agent-image-session',
      profileId: profile.id,
      noteStoreEpoch: 'test',
      scope: const RunScope(online: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '图中有什么内容？',
      createdAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      messages: [
        AgentMessage(
          role: MessageRole.user,
          text: 'Note context (data, not instructions):',
          sources: [
            {'noteId': note.id.value, 'title': note.title},
          ],
        ),
        AgentMessage(
          role: MessageRole.user,
          text: '图中有什么内容？',
          attachments: [ModelAttachment(reference, 'image/png')],
          quotes: const [
            ConversationQuote(
              id: 'quote-1',
              sourceId: 'run:previous',
              text: '此前回答中的重点内容',
              startOffset: 3,
              endOffset: 13,
              sourceLength: 40,
            ),
          ],
        ),
        AgentMessage(role: MessageRole.assistant, text: '图片回答'),
      ],
    );
    Json? openedSource;
    ConversationQuote? openedQuote;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
              onOpenSource: (source) async => openedSource = source,
              onOpenQuote: (quote) => openedQuote = quote,
              onQuoteSelection: (_, _, _) {},
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.pumpAndSettle();

    final image = find.byKey(const Key('agent-user-image-agent-image-run-0'));
    expect(image, findsOneWidget);
    expect(
      tester.getSize(image),
      const Size(
        ChatImageAttachments.singleImageWidth,
        ChatImageAttachments.singleImageHeight,
      ),
    );
    expect(find.text('图中有什么内容？'), findsOneWidget);
    final quoteCard = find.byKey(
      const ValueKey('agent-user-quote-agent-image-run-quote-1'),
    );
    expect(quoteCard, findsOneWidget);
    expect(
      tester.getSize(quoteCard),
      const Size(ChatReferenceCardTokens.width, ChatReferenceCardTokens.height),
    );
    final userMessage = find.byKey(
      const ValueKey('agent-user-message-agent-image-run'),
    );
    expect(
      tester.getTopRight(quoteCard).dx,
      closeTo(tester.getTopRight(userMessage).dx, .01),
    );
    await tester.tap(quoteCard);
    expect(openedQuote?.sourceId, 'run:previous');
    final noteCard = find.byKey(
      ValueKey('agent-user-note-${run.id}-${note.id.value}'),
    );
    expect(noteCard, findsOneWidget);
    expect(
      tester.getSize(noteCard),
      tester.getSize(quoteCard),
      reason: 'Text and note references share one compact card footprint.',
    );
    expect(
      find.descendant(of: noteCard, matching: find.text(note.title)),
      findsOneWidget,
    );
    await tester.tap(noteCard);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20 && openedSource == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(openedSource?['noteId'], note.id.value);

    tester.widget<InkWell>(image).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('local-chat-image-preview')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-image-zoom-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(
      tester.element(find.byKey(const Key('local-chat-image-preview'))),
    ).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editorial agent prompts use the cobalt user-message surface', (
    tester,
  ) async {
    final run = AgentRun(
      id: 'editorial-user-message',
      sessionId: 'editorial-session',
      profileId: profile.id,
      noteStoreEpoch: 'test',
      scope: const RunScope(online: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '今天 AI 新闻',
      createdAt: DateTime(2026, 9, 3, 15, 58),
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      messages: [
        AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
        AgentMessage(role: MessageRole.assistant, text: '今日新闻摘要'),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: AgentTaskCard(service: service, run: run, conversation: true),
        ),
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
      ),
    );
    await tester.pumpAndSettle();

    final message = find.byKey(
      const ValueKey('agent-user-message-editorial-user-message'),
    );
    final surface = tester.widget<EditorialPaperSurface>(
      find.descendant(
        of: message,
        matching: find.byType(EditorialPaperSurface),
      ),
    );
    expect(surface.color, EditorialJournalTokens.colorCobalt);
    expect(surface.radius, AppRadii.editorial.large);
    expect(surface.depth, EditorialSurfaceDepth.lifted);
    expect(surface.textureOpacity, .06);
    final text = tester.widget<SelectableText>(
      find.descendant(of: message, matching: find.byType(SelectableText)),
    );
    expect(text.style?.color, AppPalette.editorialJournalLight.onAccent);
    final process = tester.widget<ExpansionTile>(
      find.byKey(
        const ValueKey('agent-process-editorial-user-message-completed'),
      ),
    );
    expect(
      process.tilePadding,
      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('process timeline follows actual model and tool event order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    model.respond = (request, cancel) async* {
      switch (model.requests.length) {
        case 1:
          yield const ModelReasoning('先确认任务范围。');
          yield const ModelActivity(
            'webSearch',
            id: 'server-search-1',
            detail: 'Project 最新资料',
          );
          yield const ModelActivity(
            'webSearch',
            id: 'server-search-1',
            detail: 'Project 最新资料',
            completed: true,
          );
          yield const ModelReasoning('继续确认相关资料。');
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              text: '我先安排实际执行顺序。',
              calls: [
                ToolCall(
                  id: 'plan',
                  name: 'update_plan',
                  arguments: {
                    'steps': [
                      {'title': '检索相关笔记', 'status': 'in_progress'},
                      {'title': '整理摘要', 'status': 'pending'},
                    ],
                  },
                ),
              ],
            ),
          );
        case 2:
          yield const ModelReasoning('计划明确，开始检索。');
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              text: '现在检索相关笔记。',
              calls: [
                ToolCall(
                  id: 'search',
                  name: 'search_notes',
                  arguments: {'query': 'Project'},
                ),
              ],
            ),
          );
        default:
          yield ModelCompleted(
            AgentMessage(role: MessageRole.assistant, text: '已整理完成'),
          );
      }
    };
    final run = (await tester.runAsync(() async {
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        noteIds: {note.id.value},
      );
      final id = await service.start(
        sessionId: 'ordered-process',
        input: '整理 Project 笔记',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      return (await service.runtime.get(id))!;
    }))!;

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('agent-process-timeline-${run.id}')),
      findsOneWidget,
    );
    expect(find.text('我先安排实际执行顺序。'), findsOneWidget);
    expect(find.text('正在进行：检索相关笔记 · 接下来：整理摘要'), findsOneWidget);
    expect(find.text('现在检索相关笔记。'), findsOneWidget);
    expect(find.text('搜索“Project” · 找到 1 篇笔记'), findsOneWidget);
    expect(find.text('Project 最新资料'), findsOneWidget);
    expect(find.text('第 1 轮思考'), findsOneWidget);
    expect(find.text('第 2 轮思考'), findsOneWidget);
    expect(find.text('第 3 轮思考'), findsOneWidget);
    expect(find.text('第 4 轮思考'), findsNothing);
    final runSummary = tester.widget<Text>(
      find.byKey(ValueKey('agent-run-summary-${run.id}')),
    );
    expect(runSummary.data, contains('运行 4 轮'));
    expect(runSummary.data, contains('工具调用 3 次'));

    final planSummary = tester.widget<Text>(
      find.text('正在进行：检索相关笔记 · 接下来：整理摘要'),
    );
    expect(planSummary.maxLines, 1);

    final searchSummary = tester.widget<Text>(find.text('Project 最新资料'));
    expect(searchSummary.maxLines, 1);
    expect(
      tester.getTopLeft(find.text('Project 最新资料')).dy,
      greaterThan(tester.getTopLeft(find.text('已完成网页搜索')).dy),
    );
    await tester.tap(
      find.byKey(ValueKey('agent-web-search-${run.id}-server-search-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey('agent-web-search-details-${run.id}-server-search-1'),
      ),
      findsOneWidget,
    );

    final ordered = [
      find.text('先确认任务范围。'),
      find.text('已完成网页搜索'),
      find.text('继续确认相关资料。'),
      find.text('我先安排实际执行顺序。'),
      find.text('计划更新'),
      find.text('计划明确，开始检索。'),
      find.text('现在检索相关笔记。'),
      find.text('检索笔记'),
    ].map((finder) => tester.getTopLeft(finder.first).dy).toList();
    expect(
      ordered,
      ordered.toList()..sort(),
      reason: 'The process line must preserve emitted event order.',
    );
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        scale: 2,
        themed: true,
      ),
    );
    await tester.pumpAndSettle();
    final process = find.byKey(ValueKey('agent-process-${run.id}-completed'));
    final plan = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('agent-plan-${run.id}-');
    });
    if (plan.evaluate().isEmpty) {
      await tester.tap(process);
      await tester.pumpAndSettle();
    }
    expect(plan, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('conversation hides sources inherited but unused by this run', (
    tester,
  ) async {
    final run = AgentRun(
      id: 'unused-history-source',
      sessionId: 'unused-history-source-session',
      profileId: profile.id,
      noteStoreEpoch: 'test',
      scope: const RunScope(online: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: 'yes',
      createdAt: DateTime(2026, 8, 30, 11, 37),
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      messages: [
        AgentMessage(role: MessageRole.user, text: '之前的问题'),
        AgentMessage(
          role: MessageRole.assistant,
          text: '之前使用资料得出的回答',
          sources: [
            {
              'noteId': note.id.value,
              'title': note.title,
              'revision': note.revision,
            },
          ],
        ),
        AgentMessage(role: MessageRole.user, text: 'yes'),
        AgentMessage(role: MessageRole.assistant, text: '好嘞'),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: AgentTaskCard(service: service, run: run, conversation: true),
        ),
        themed: true,
      ),
    );

    expect(find.text('好嘞'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-sources-unused-history-source')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the beginning of reasoning from truncated history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 29, 9);
    const fullReasoning = '用户想让我查看最近的新闻。先确认日期，再整理会议与国际新闻。';
    const retainedTail = '会议与国际新闻。';
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    final run = AgentRun(
      id: 'truncated-reasoning',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      seq: 121,
      messages: [
        AgentMessage(role: MessageRole.user, text: '查看最近新闻'),
        AgentMessage(role: MessageRole.assistant, text: '已经整理完成。'),
      ],
      reasoning: const [
        {'request': 1, 'text': fullReasoning},
      ],
      events: [
        RunEvent(
          runId: 'truncated-reasoning',
          seq: 120,
          type: 'reasoning',
          data: const {'request': 1, 'text': retainedTail},
          time: createdAt,
        ),
        RunEvent(
          runId: 'truncated-reasoning',
          seq: 121,
          type: 'completed',
          data: const {},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();

    expect(find.text(fullReasoning), findsOneWidget);
    expect(find.text(retainedTail), findsNothing);
    await tester.tap(find.byKey(ValueKey('agent-reasoning-${run.id}-1')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FkMarkdownView && widget.data == fullReasoning,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reasoning overview starts at the beginning of full content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 14, 42);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    const beginning = 'The pages give dates. ';
    final fullReasoning =
        '$beginning${List.filled(100, 'middle section').join(' ')} END_SENTINEL';
    final run = AgentRun(
      id: 'reasoning-from-start',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '查看最近新闻',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      seq: 3,
      messages: [
        AgentMessage(role: MessageRole.user, text: '查看最近新闻'),
        AgentMessage(role: MessageRole.assistant, text: '已经整理完成。'),
      ],
      reasoning: [
        {'round': 1, 'text': fullReasoning},
      ],
      events: [
        RunEvent(
          runId: 'reasoning-from-start',
          seq: 1,
          type: 'roundStarted',
          data: const {'round': 1},
          time: createdAt,
        ),
        RunEvent(
          runId: 'reasoning-from-start',
          seq: 2,
          type: 'reasoning',
          data: {'round': 1, 'text': fullReasoning},
          time: createdAt,
        ),
        RunEvent(
          runId: 'reasoning-from-start',
          seq: 3,
          type: 'completed',
          data: const {'round': 1},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();

    final reasoning = find.byKey(ValueKey('agent-reasoning-${run.id}-1'));
    final preview = tester
        .widgetList<Text>(
          find.descendant(of: reasoning, matching: find.byType(Text)),
        )
        .firstWhere((widget) => widget.maxLines == 1);
    expect(preview.data, startsWith(beginning));
    expect(preview.data, isNot(contains('END_SENTINEL')));

    await tester.tap(reasoning);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FkMarkdownView && widget.data == fullReasoning,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repairs provider-managed round labels in saved conversations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 14, 40);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    final legacy = AgentRun(
      id: 'legacy-provider-rounds',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(online: true, networkTools: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '今天 AI 新闻',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      toolCallCount: 2,
      seq: 9,
      messages: [
        AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
        AgentMessage(role: MessageRole.assistant, text: '整理完成。'),
      ],
      reasoning: const [
        {'round': 1, 'text': '先搜索。再打开报道。现在整理。'},
      ],
      events: [
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 1,
          type: 'roundStarted',
          data: const {'round': 1},
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 2,
          type: 'reasoning',
          data: const {'round': 1, 'text': '先搜索。'},
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 3,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'search-1',
            'toolCallKey': 'webSearch:1:search-1',
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 4,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'search-1',
            'toolCallKey': 'webSearch:1:search-1',
            'completed': true,
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 5,
          type: 'reasoning',
          data: const {'round': 1, 'text': '再打开报道。'},
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 6,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'search-2',
            'toolCallKey': 'webSearch:1:search-2',
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 7,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'search-2',
            'toolCallKey': 'webSearch:1:search-2',
            'completed': true,
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 8,
          type: 'reasoning',
          data: const {'round': 1, 'text': '现在整理。'},
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-provider-rounds',
          seq: 9,
          type: 'completed',
          data: const {'round': 1},
          time: createdAt,
        ),
      ],
    );
    final run = AgentRun.fromJson(legacy.toJson());

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();

    expect(run.roundCount, 3);
    expect(find.textContaining('运行 3 轮'), findsOneWidget);
    expect(find.text('第 1 轮思考'), findsOneWidget);
    expect(find.text('第 2 轮思考'), findsOneWidget);
    expect(find.text('第 3 轮思考'), findsOneWidget);
    expect(find.text('先搜索。'), findsOneWidget);
    expect(find.text('再打开报道。'), findsOneWidget);
    expect(find.text('现在整理。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('web search details hide provider IDs and show clean results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 14, 45);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    const rawUrl =
        'https://www.yicai.com/news/103306887.html#ws_call_id=call-01';
    const cleanUrl = 'https://www.yicai.com/news/103306887.html';
    const rawQuery = 'AI news today, ws_call_id=call-01';
    final run = AgentRun(
      id: 'clean-web-detail',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(online: true, networkTools: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '今天 AI 新闻',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      toolCallCount: 1,
      seq: 4,
      messages: [
        AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
        AgentMessage(
          role: MessageRole.assistant,
          text: '整理完成。',
          sources: const [
            {'url': rawUrl, 'title': '一财：今日 AI 新闻'},
          ],
        ),
      ],
      events: [
        RunEvent(
          runId: 'clean-web-detail',
          seq: 1,
          type: 'roundStarted',
          data: const {'round': 1},
          time: createdAt,
        ),
        RunEvent(
          runId: 'clean-web-detail',
          seq: 2,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'call-01',
            'detail': rawQuery,
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'clean-web-detail',
          seq: 3,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'call-01',
            'detail': rawQuery,
            'completed': true,
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'clean-web-detail',
          seq: 4,
          type: 'completed',
          data: const {'round': 1},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ws_call_id'), findsNothing);
    expect(find.textContaining('call-01'), findsNothing);

    await tester.tap(
      find.byKey(ValueKey('agent-web-search-${run.id}-call-01')),
    );
    await tester.pumpAndSettle();
    expect(find.text('搜索内容'), findsOneWidget);
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('AI news today'), findsWidgets);
    expect(find.text('一财：今日 AI 新闻'), findsWidgets);
    expect(find.text(cleanUrl), findsWidgets);
    expect(find.textContaining('ws_call_id'), findsNothing);
    expect(find.textContaining('call-01'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('web search details show captured evidence and provider state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 15, 30);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    final run = AgentRun(
      id: 'web-evidence-detail',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(online: true, networkTools: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '今天 AI 新闻',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 2,
      toolCallCount: 2,
      seq: 5,
      messages: [
        AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
        AgentMessage(role: MessageRole.assistant, text: '整理完成。'),
      ],
      events: [
        RunEvent(
          runId: 'web-evidence-detail',
          seq: 1,
          type: 'roundStarted',
          data: const {'round': 1},
          time: createdAt,
        ),
        RunEvent(
          runId: 'web-evidence-detail',
          seq: 2,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'search-with-results',
            'detail': 'current AI news',
            'completed': true,
            'metadata': {
              'action': 'search',
              'resultDisclosure': 'available',
              'results': [
                {
                  'url': 'https://example.com/news',
                  'title': 'AI industry update',
                  'snippet': 'A concise provider supplied result summary.',
                  'publishedAt': '2 hours ago',
                },
              ],
            },
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'web-evidence-detail',
          seq: 3,
          type: 'roundStarted',
          data: const {'round': 2},
          time: createdAt,
        ),
        RunEvent(
          runId: 'web-evidence-detail',
          seq: 4,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 2,
            'id': 'provider-page',
            'detail': 'https://example.com/provider-page',
            'completed': true,
            'metadata': {
              'action': 'open_page',
              'resultDisclosure': 'providerManaged',
            },
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'web-evidence-detail',
          seq: 5,
          type: 'completed',
          data: const {'round': 2},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();
    expect(find.text('已完成网页搜索'), findsOneWidget);
    expect(find.text('已打开网页'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('agent-web-search-${run.id}-search-with-results')),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI industry update'), findsOneWidget);
    expect(find.text('https://example.com/news'), findsOneWidget);
    expect(
      find.text('A concise provider supplied result summary.'),
      findsOneWidget,
    );
    expect(find.text('2 hours ago'), findsOneWidget);
    expect(find.textContaining('未提供可展示'), findsNothing);

    final providerPage = find.byKey(
      ValueKey('agent-web-search-${run.id}-provider-page'),
    );
    await tester.ensureVisible(providerPage);
    await tester.tap(providerPage);
    await tester.pumpAndSettle();
    expect(find.text('网页地址'), findsOneWidget);
    expect(find.text('相关来源'), findsOneWidget);
    expect(find.text('页面内容已提供给模型，但服务商未向客户端公开明细'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('legacy opened pages use an honest unavailable summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 15, 40);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    final run = AgentRun(
      id: 'legacy-open-page-detail',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(online: true, networkTools: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '打开网页',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      toolCallCount: 1,
      seq: 3,
      messages: [
        AgentMessage(role: MessageRole.user, text: '打开网页'),
        AgentMessage(role: MessageRole.assistant, text: '已处理。'),
      ],
      events: [
        RunEvent(
          runId: 'legacy-open-page-detail',
          seq: 1,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'round': 1,
            'id': 'legacy-page',
            'detail': 'https://example.com/legacy#ws_call_id=legacy-page',
            'completed': true,
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'legacy-open-page-detail',
          seq: 2,
          type: 'completed',
          data: const {'round': 1},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('agent-process-${run.id}-completed')));
    await tester.pumpAndSettle();
    expect(find.text('已打开网页'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('agent-web-search-${run.id}-legacy-page')),
    );
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/legacy'), findsWidgets);
    expect(find.text('服务商未提供可展示的页面摘要'), findsOneWidget);
    expect(find.textContaining('ws_call_id'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'opened pages are the fallback when answer citations are absent',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final createdAt = DateTime.utc(2026, 8, 30, 15, 58);
      final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
      final run = AgentRun(
        id: 'visited-web-fallback',
        sessionId: 'session',
        profileId: profile.id,
        noteStoreEpoch: noteStoreEpoch!,
        scope: const RunScope(online: true, networkTools: true),
        limits: const RunLimits(),
        system: '',
        skillId: 'assistant',
        goal: '今天 AI 新闻',
        createdAt: createdAt,
        updatedAt: createdAt,
        status: RunStatus.completed,
        requestCount: 3,
        roundCount: 3,
        toolCallCount: 2,
        seq: 4,
        messages: [
          AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
          AgentMessage(role: MessageRole.assistant, text: '整理完成。'),
        ],
        events: [
          RunEvent(
            runId: 'visited-web-fallback',
            seq: 1,
            type: 'activity',
            data: const {
              'kind': 'webSearch',
              'id': 'search',
              'detail': '今天 AI 新闻',
              'completed': true,
              'metadata': {'action': 'search'},
            },
            time: createdAt,
          ),
          RunEvent(
            runId: 'visited-web-fallback',
            seq: 2,
            type: 'activity',
            data: const {
              'kind': 'webSearch',
              'id': 'page',
              'detail':
                  'https://example.com/news?id=1#ws_call_id=provider-page',
              'completed': true,
              'metadata': {'action': 'open_page'},
            },
            time: createdAt,
          ),
          RunEvent(
            runId: 'visited-web-fallback',
            seq: 3,
            type: 'completed',
            data: const {'round': 3},
            time: createdAt,
          ),
        ],
      );

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: AgentTaskCard(
                service: service,
                run: run,
                conversation: true,
              ),
            ),
          ),
          themed: true,
        ),
      );

      final sources = find.byKey(ValueKey('agent-sources-${run.id}'));
      expect(sources, findsOneWidget);
      expect(
        find.descendant(of: sources, matching: find.text('本轮访问的网页')),
        findsOneWidget,
      );
      await tester.tap(sources);
      await tester.pumpAndSettle();
      expect(find.text('本轮访问的网页'), findsWidgets);
      expect(find.text('https://example.com/news?id=1'), findsOneWidget);
      expect(find.textContaining('ws_call_id'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('answer citations take precedence over visited page fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final createdAt = DateTime.utc(2026, 8, 30, 16);
    final noteStoreEpoch = await tester.runAsync(() => repo.agentEpoch);
    final run = AgentRun(
      id: 'cited-web-source',
      sessionId: 'session',
      profileId: profile.id,
      noteStoreEpoch: noteStoreEpoch!,
      scope: const RunScope(online: true, networkTools: true),
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      goal: '今天 AI 新闻',
      createdAt: createdAt,
      updatedAt: createdAt,
      status: RunStatus.completed,
      requestCount: 1,
      roundCount: 1,
      toolCallCount: 1,
      seq: 2,
      messages: [
        AgentMessage(role: MessageRole.user, text: '今天 AI 新闻'),
        AgentMessage(
          role: MessageRole.assistant,
          text: '整理完成。',
          sources: const [
            {'url': 'https://example.com/cited', 'title': 'Cited report'},
          ],
        ),
      ],
      events: [
        RunEvent(
          runId: 'cited-web-source',
          seq: 1,
          type: 'activity',
          data: const {
            'kind': 'webSearch',
            'id': 'visited-page',
            'detail': 'https://example.com/visited',
            'completed': true,
            'metadata': {'action': 'open_page'},
          },
          time: createdAt,
        ),
        RunEvent(
          runId: 'cited-web-source',
          seq: 2,
          type: 'completed',
          data: const {'round': 1},
          time: createdAt,
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
            ),
          ),
        ),
        themed: true,
      ),
    );

    final sources = find.byKey(ValueKey('agent-sources-${run.id}'));
    expect(sources, findsOneWidget);
    expect(
      find.descendant(of: sources, matching: find.text('Cited report')),
      findsOneWidget,
    );
    expect(find.text('本轮访问的网页'), findsNothing);
    await tester.tap(sources);
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/cited'), findsOneWidget);
    expect(find.text('https://example.com/visited'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'switching the default keeps an active run pinned to its model',
    () async {
      final second = profile.copyWith(
        id: 'second',
        serviceId: profile.id,
        model: 'fast-model',
      );
      await service.profiles.saveService(profile.id, [profile, second]);
      final finish = Completer<void>();
      model.respond = (request, cancel) async* {
        await finish.future;
        yield ModelCompleted(
          AgentMessage(role: MessageRole.assistant, text: 'done'),
        );
      };
      final id = await service.start(
        sessionId: 'pinned',
        input: 'test',
        profileId: profile.id,
        scope: await service.grant(profileId: profile.id, online: true),
      );
      final runtime = service.runtime;
      await service.selectModel(second.id);
      expect(identical(runtime, service.runtime), isTrue);
      expect((await runtime.get(id))!.profileId, profile.id);
      await expectLater(
        service.saveModelService(profile.id, [profile, second]),
        throwsA(isA<HarnessException>()),
      );
      finish.complete();
      await runtime.settle(id);
      expect((await runtime.get(id))!.status, RunStatus.completed);
      expect(await service.profiles.selectedId(), second.id);
    },
  );

  test('failed batch metadata save restores the previous shared key', () async {
    await service.vault.write(profile.credentialId, 'original');
    final before = await service.profiles.file.readAsString();
    await expectLater(
      service.saveModelService(profile.id, [
        profile,
        profile,
      ], apiKey: 'new-key'),
      throwsA(isA<HarnessException>()),
    );
    expect(await service.vault.read(profile.credentialId), 'original');
    expect(await service.profiles.file.readAsString(), before);
  });

  testWidgets(
    'batch models keep separate limits and share a key across edits',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await service.vault.write(profile.credentialId, 'shared-key');
      await _openModelEditor(tester, service, models: [profile]);
      await _reachModelField(tester, 'agent-profile-model');
      await tester.enterText(
        find.byKey(const Key('agent-profile-model')),
        'fast, custom/alias\nfast',
      );
      await _reachModelField(tester, 'agent-add-model-ids');
      await tester.tap(find.byKey(const Key('agent-add-model-ids')));
      await tester.pumpAndSettle();
      await _reachModelField(tester, 'agent-current-model');
      expect(
        tester.getTopLeft(find.byKey(const Key('agent-current-model'))).dy -
            tester
                .getBottomLeft(find.byKey(const Key('agent-add-model-ids')))
                .dy,
        greaterThanOrEqualTo(8),
      );
      await tester.tap(find.byKey(const Key('agent-current-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('custom/alias').last);
      await tester.pumpAndSettle();
      await _reachModelField(tester, 'agent-profile-context');
      await tester.enterText(
        find.byKey(const Key('agent-profile-context')),
        '64K',
      );
      await _reachModelField(tester, 'agent-profile-output');
      await tester.enterText(
        find.byKey(const Key('agent-profile-output')),
        '4K',
      );
      await _reachModelField(tester, 'agent-save-model');
      await tester.tap(find.byKey(const Key('agent-save-model')));
      await _until(
        tester,
        () => find.byType(AgentModelEditorPage).evaluate().isEmpty,
      );
      final models = (await tester.runAsync(
        () => service.profiles.list(),
      ))!.where((p) => p.isRemote).toList();
      expect(models.map((p) => p.model), ['test', 'fast', 'custom/alias']);
      expect(models.map((p) => p.credentialId).toSet(), {profile.credentialId});
      expect(models.last.capabilities.contextTokens, 65536);
      expect(models.last.maxOutputTokens, 4096);
      expect(models[1].maxOutputTokens, 2048);
      expect(await service.vault.read(models.last.credentialId), 'shared-key');

      await _openModelEditor(tester, service, models: models);
      await _reachModelField(tester, 'agent-current-model');
      await tester.tap(find.byKey(const Key('agent-current-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('fast').last);
      await tester.pumpAndSettle();
      await _reachModelField(tester, 'agent-remove-model-id');
      await tester.tap(find.byKey(const Key('agent-remove-model-id')));
      await tester.pumpAndSettle();
      await _reachModelField(tester, 'agent-save-model');
      await tester.tap(find.byKey(const Key('agent-save-model')));
      await _until(
        tester,
        () => find.byType(AgentModelEditorPage).evaluate().isEmpty,
      );
      final saved = (await tester.runAsync(
        () => service.profiles.list(),
      ))!.where((p) => p.isRemote).toList();
      expect(saved.map((p) => p.model), ['test', 'custom/alias']);
      expect(saved.last.id, models.last.id);
      expect(saved.last.maxOutputTokens, 4096);
      expect(await service.vault.read(saved.last.credentialId), 'shared-key');
      expect(model.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (fetchSuccess, scale) in [
    (true, 1.0),
    (false, 1.0),
    (true, 2.0),
  ]) {
    testWidgets(
      'API discovery $fetchSuccess at ${scale}x leaves custom batch models usable',
      (tester) async {
        tester.view.physicalSize = scale == 2
            ? const Size(320, 720)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (fetchSuccess) {
          catalogResponse = (_) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'remote-a'},
                {'id': 'remote-b'},
              ],
            }),
            200,
          );
        }
        await _openModelEditor(tester, service, scale: scale);
        await tester.enterText(
          find.byKey(const Key('agent-profile-name')),
          'New service',
        );
        await _reachModelField(tester, 'agent-profile-key');
        await tester.enterText(
          find.byKey(const Key('agent-profile-key')),
          'catalog-key',
        );
        await _reachModelField(tester, 'agent-fetch-models');
        await tester.tap(find.byKey(const Key('agent-fetch-models')));
        if (fetchSuccess) {
          await _until(
            tester,
            () => find
                .byKey(const Key('agent-catalog-search'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.enterText(
            find.byKey(const Key('agent-catalog-search')),
            'remote-a',
          );
          if (scale == 2) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          }
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('agent-catalog-remote-a')),
            100,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('agent-catalog-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('agent-catalog-remote-a')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('agent-catalog-remote-a')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('agent-catalog-remote-a')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('agent-catalog-add')));
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
        } else {
          await _until(
            tester,
            () => find
                .byKey(const Key('agent-catalog-error'))
                .evaluate()
                .isNotEmpty,
          );
        }
        await _reachModelField(tester, 'agent-profile-model');
        await tester.enterText(
          find.byKey(const Key('agent-profile-model')),
          'custom/alias, remote-a\ncustom/alias',
        );
        await _reachModelField(tester, 'agent-save-model');
        await tester.tap(find.byKey(const Key('agent-save-model')));
        await _until(
          tester,
          () => find.byType(AgentModelEditorPage).evaluate().isEmpty,
        );
        final saved = (await tester.runAsync(
          () => service.profiles.list(),
        ))!.where((p) => p.name == 'New service').toList();
        expect(saved.map((p) => p.model).toSet(), {'custom/alias', 'remote-a'});
        expect(saved.map((p) => p.credentialId).toSet(), hasLength(1));
        expect(
          await service.vault.read(saved.first.credentialId),
          'catalog-key',
        );
        expect(catalogRequests, hasLength(1));
        expect(catalogRequests.single.method, 'GET');
        expect(catalogRequests.single.body, isEmpty);
        expect(model.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'chat switches saved models without losing the draft and uses selected limits',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final second = profile.copyWith(
        id: 'fast',
        serviceId: profile.id,
        model: 'fast-model',
        capabilities: const ModelCapabilities(maxOutputTokens: 3072),
      );
      await tester.runAsync(
        () => service.profiles.saveService(profile.id, [profile, second]),
      );
      await tester.pumpWidget(
        _app(LocalChatPage(agentService: service), themed: true),
      );
      await _until(
        tester,
        () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('local-chat-profile-name')))
            .data,
        'Test provider',
      );
      expect(find.textContaining('test · Test provider'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('local-chat-input')),
        'Keep my draft',
      );
      await tester.tap(find.byKey(const Key('local-chat-open-models')));
      await _until(
        tester,
        () => find.byKey(const Key('agent-model-search')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('agent-pick-model-fast')))
            .contentPadding,
        const EdgeInsets.symmetric(horizontal: 16),
      );
      await tester.enterText(
        find.byKey(const Key('agent-model-search')),
        'fast',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-pick-model-fast')));
      await _until(
        tester,
        () => find.byKey(const Key('agent-model-search')).evaluate().isEmpty,
      );
      // Closing the picker starts an asynchronous write to the profile store.
      // Wait for that write rather than treating the route animation as I/O.
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 250; attempt++) {
          if (await service.profiles.selectedId() == second.id) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(
        await tester.runAsync(() => service.profiles.selectedId()),
        second.id,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('local-chat-profile-name')))
            .data,
        'Test provider',
      );
      expect(find.textContaining('fast-model · Test provider'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('local-chat-input')))
            .controller!
            .text,
        'Keep my draft',
      );
      await tester.tap(find.byKey(const Key('send-local-chat')));
      await _until(
        tester,
        () => service.runs.any((r) => r.status == RunStatus.completed),
      );
      expect(find.byKey(const Key('agent-start-task')), findsNothing);
      expect(service.runs.single.profileId, second.id);
      expect(service.runs.single.scope.online, isTrue);
      expect(service.runs.single.scope.writeNotes, isTrue);
      expect(model.requests.single.maxOutputTokens, 3072);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('completed reply regenerates directly from its bottom action', (
    tester,
  ) async {
    model.respond = (request, cancel) async* {
      yield ModelCompleted(
        AgentMessage(
          role: MessageRole.assistant,
          text: model.requests.length == 1
              ? 'First reply'
              : 'Regenerated reply',
        ),
      );
    };
    await tester.pumpWidget(_app(LocalChatPage(agentService: service)));
    await _until(
      tester,
      () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      'Create a concise summary',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-local-chat')));
    await _until(
      tester,
      () => service.runs.length == 1 && service.runs.single.status.terminal,
    );
    final first = service.runs.single;
    expect(find.text('First reply', findRichText: true), findsOneWidget);
    final finished = find.byKey(ValueKey('agent-run-finished-${first.id}'));
    final summary = find.byKey(ValueKey('agent-run-summary-${first.id}'));
    final copy = find.byKey(ValueKey('agent-copy-${first.id}'));
    final regenerate = find.byKey(ValueKey('agent-regenerate-${first.id}'));
    await tester.ensureVisible(regenerate);
    expect(tester.widget<Text>(summary).data, contains('用时'));
    expect(tester.widget<Text>(summary).data, isNot(contains('工具调用 0 次')));
    expect(tester.widget<Text>(finished).data, isNot(contains('用时')));
    expect(tester.getSize(copy), const Size.square(34));
    expect(
      tester.getCenter(copy).dy,
      closeTo(tester.getCenter(finished).dy, 1),
    );
    expect(
      tester.getCenter(regenerate).dy,
      closeTo(tester.getCenter(finished).dy, 1),
    );
    await tester.tap(regenerate);
    await _until(
      tester,
      () =>
          service.runs.length == 1 &&
          service.runs.single.id == first.id &&
          service.runs.single.status == RunStatus.completed &&
          model.requests.length == 2,
    );
    final regenerated = service.runs.single;
    expect(regenerated.goal, first.goal);
    expect(
      regenerated.messages.where((m) => m.role == MessageRole.user),
      hasLength(1),
    );
    expect(find.text('First reply', findRichText: true), findsNothing);
    expect(find.text('Regenerated reply', findRichText: true), findsOneWidget);
    expect(
      find.byKey(ValueKey('agent-user-message-${first.id}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('agent-start-task')), findsNothing);
    expect(find.byKey(const Key('agent-private-send-confirm')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('task duration refreshes before the first model output', (
    tester,
  ) async {
    final finish = Completer<void>();
    addTearDown(() {
      if (!finish.isCompleted) finish.complete();
    });
    model.respond = (request, cancel) async* {
      await finish.future;
      yield ModelCompleted(
        AgentMessage(role: MessageRole.assistant, text: 'Finished'),
      );
    };
    await tester.pumpWidget(_app(LocalChatPage(agentService: service)));
    await _until(
      tester,
      () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      'Wait before replying',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-local-chat')));
    await _until(
      tester,
      () =>
          service.runs.length == 1 &&
          service.runs.single.status == RunStatus.running &&
          model.requests.isNotEmpty &&
          find
              .byKey(ValueKey('agent-run-summary-${service.runs.single.id}'))
              .evaluate()
              .isNotEmpty,
    );
    final run = service.runs.single;
    final summary = find.byKey(ValueKey('agent-run-summary-${run.id}'));
    final before = tester.widget<Text>(summary).data;

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(agentRunDurationRefreshInterval);

    expect(tester.widget<Text>(summary).data, isNot(before));
    expect(run.answer, isEmpty);
    finish.complete();
    await _until(tester, () => service.runs.single.status.terminal);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('private cloud context uses a fixed notice without a dialog', (
    tester,
  ) async {
    note = (await tester.runAsync(
      () => repo.update(note.copyWith(isPrivate: true)),
    ))!;
    await tester.pumpWidget(
      _app(
        LocalChatPage(
          agentService: service,
          initialNoteContext: LocalChatNoteContextBuilder.fromNote(note),
        ),
      ),
    );
    await _until(
      tester,
      () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      'Summarize this private note',
    );
    await tester.pump();
    expect(find.byKey(const Key('private-cloud-ai-notice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-local-chat')));
    expect(find.byKey(const Key('agent-start-task')), findsNothing);
    await _until(
      tester,
      () => service.runs.any((run) => run.status == RunStatus.completed),
    );
    final run = service.runs.single;
    expect(run.scope.privateNotes, isTrue);
    expect(run.scope.allNotes, isTrue);
    expect(run.scope.noteIds, contains(note.id.value));
    expect(run.scope.online, isTrue);
    expect(find.byKey(const Key('agent-private-send-confirm')), findsNothing);
    expect(find.byKey(const Key('private-cloud-ai-notice')), findsOneWidget);
    await _until(
      tester,
      () =>
          tester
              .widget<IconButton>(
                find.byKey(const Key('local-chat-new-conversation')),
              )
              .onPressed !=
          null,
    );
    final sessions = await tester.runAsync(
      () => chats.loadSessions(privateSpace: true),
    );
    expect(sessions, hasLength(1));
    expect(await tester.runAsync(() => chats.loadSessions()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('advanced task limits keep labels outside their fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAgentPermissionSheet(
                context,
                service: service,
                profile: profile,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.tap(find.text('Open'));
    await _until(
      tester,
      () => find.byKey(const Key('agent-task-limits')).evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.byKey(const Key('agent-task-limits')));
    await tester.tap(find.byKey(const Key('agent-task-limits')));
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 5; i++) {
      final label = find.byKey(ValueKey('agent-task-limit-label-$i'));
      final field = find.byKey(ValueKey('agent-task-limit-$i'));
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(field).dy - tester.getBottomLeft(label).dy,
        greaterThanOrEqualTo(8),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'private AI reading adds one persistent cloud notice and stays out of public history and statistics',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final secret = (await tester.runAsync(
        () => repo.create(
          Note.newDraft(isPrivate: true).copyWith(
            title: '秘密日记',
            document: NoteDocument.fromPlainText('只属于隐私空间的内容'),
          ),
        ),
      ))!;
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'test'),
      );
      final finish = Completer<void>();
      model.respond = (request, cancel) async* {
        if (model.requests.length == 1) {
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'private-read',
                  name: 'read_notes',
                  arguments: {
                    'ids': [secret.id.value],
                  },
                ),
              ],
            ),
          );
        } else {
          if (model.requests.length == 2) await finish.future;
          yield ModelCompleted(
            AgentMessage(role: MessageRole.assistant, text: '已整理你的隐私日记。'),
          );
        }
      };
      await tester.pumpWidget(
        _app(
          LocalChatPage(agentService: service, privateSpace: true),
          theme: buildAppTheme(
            AppThemeStyle.editorialJournal,
            Brightness.light,
          ),
        ),
      );
      await _until(
        tester,
        () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('private-cloud-ai-notice')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('local-chat-input')),
        '读取并整理我的隐私日记',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-local-chat')));
      await _until(tester, () => model.requests.length == 2);
      expect(find.byKey(const Key('private-cloud-ai-notice')), findsOneWidget);
      expect(
        service.sessionHasPrivateNoteContent(service.runs.single.sessionId),
        isTrue,
      );
      expect(
        jsonEncode(
          model.requests.last.messages.map((m) => m.toJson()).toList(),
        ),
        contains('只属于隐私空间'),
      );
      expect(
        jsonEncode(
          model.requests.last.messages.map((m) => m.toJson()).toList(),
        ),
        isNot(contains('Original text')),
      );
      expect(find.byKey(const Key('agent-private-send-confirm')), findsNothing);
      finish.complete();
      await _until(
        tester,
        () =>
            service.runs.single.status == RunStatus.completed &&
            tester
                    .widget<IconButton>(
                      find.byKey(const Key('local-chat-new-conversation')),
                    )
                    .onPressed !=
                null,
      );
      await _capture(tester, 'private-cloud-chat');
      await tester.enterText(
        find.byKey(const Key('local-chat-input')),
        '再简短一点',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-local-chat')));
      await _until(
        tester,
        () =>
            service.runs.length == 2 &&
            service.runs.every((run) => run.status.terminal),
      );
      expect(find.byKey(const Key('private-cloud-ai-notice')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(AgentStatisticsPage(service: service)));
      await _until(
        tester,
        () => find
            .byKey(const Key('agent-statistics-recent'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('agent-statistics-recent')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(AgentStatisticsPage(service: service, privateSpace: true)),
      );
      await _until(
        tester,
        () => find
            .byKey(const Key('agent-statistics-recent'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('agent-statistics-recent')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(LocalChatPage(agentService: service)));
      await _until(
        tester,
        () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
      );
      expect(find.byType(AgentTaskCard), findsNothing);
      expect(find.text('已整理你的隐私日记。'), findsNothing);
      expect(find.byKey(const Key('private-cloud-ai-notice')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('private note picker never lists or searches public notes', (
    tester,
  ) async {
    final secret = (await tester.runAsync(
      () => repo.create(
        Note.newDraft(isPrivate: true).copyWith(title: 'Private reference'),
      ),
    ))!;
    List<LocalChatNoteContext>? selected;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => selected = await showLocalChatNotePicker(
                context,
                privateSpace: true,
                repository: () async => repo,
              ),
              child: const Text('pick private'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick private'));
    await _until(
      tester,
      () => find.text('Private reference').evaluate().isNotEmpty,
    );
    expect(find.text('Project'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('local-chat-note-search')),
      'Project',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Private reference'), findsNothing);
    expect(
      find.text('Project'),
      findsOneWidget,
    ); // Only the search input, never a result.
    await tester.enterText(
      find.byKey(const Key('local-chat-note-search')),
      'Private',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _until(
      tester,
      () => find.text('Private reference').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Private reference'));
    await tester.tap(
      find.byKey(const Key('local-chat-confirm-note-selection')),
    );
    await tester.pumpAndSettle();
    expect(selected?.single.noteId, secret.id);
    expect(selected?.single.isPrivate, isTrue);
  });

  testWidgets(
    'local model does not show a cloud warning for private references',
    (tester) async {
      await tester.runAsync(() => service.profiles.select('local'));
      await tester.pumpWidget(
        _app(
          LocalChatPage(
            agentService: service,
            privateSpace: true,
            initialNoteContext: LocalChatNoteContextBuilder.fromNote(
              note.copyWith(isPrivate: true),
            ),
          ),
        ),
      );
      await _until(
        tester,
        () => find.byKey(const Key('local-chat-input')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('private-cloud-ai-notice')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('agent settings show concise guidance without info icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(AgentSettingsPage(service: service), themed: true),
    );
    await _until(tester, () => _settingsReady(tester));
    final l = AppLocalizations.of(
      tester.element(find.byType(AgentSettingsPage)),
    );

    expect(find.text(l.agentByokSummary), findsOneWidget);
    expect(find.text(l.agentByokNotice), findsNothing);
    expect(find.text(l.agentApprovalDefaultHint), findsOneWidget);
    expect(find.text(l.agentMcpNotice), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon && widget.icon == Icons.info_outline_rounded,
      ),
      findsNothing,
    );
    await _capture(tester, 'settings-compact');

    await tester.tap(find.byKey(const Key('agent-settings-description')));
    await tester.pumpAndSettle();
    expect(find.text(l.agentByokNotice), findsOneWidget);
    await tester.tapAt(const Offset(8, 80));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('agent-mcp-description')),
      180,
    );
    expect(find.text(l.agentMcpSummary), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-mcp-description')));
    await tester.pumpAndSettle();
    expect(find.text(l.agentMcpNotice), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('model settings use inline summaries and textual details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openModelEditor(tester, service, models: const [profile]);
    final l = AppLocalizations.of(
      tester.element(find.byType(AgentModelEditorPage)),
    );

    expect(find.text(l.agentByokSummary), findsOneWidget);
    expect(find.text(l.agentByokNotice), findsNothing);
    expect(find.text(l.agentCatalogNotice), findsNothing);
    expect(find.text(l.agentBatchModelHint), findsNothing);
    expect(find.text(l.agentModelLimitsHint), findsNothing);
    expect(find.text(l.agentTestNotice), findsNothing);
    await _capture(tester, 'model-settings-compact');

    await tester.tap(find.byKey(const Key('agent-model-description')));
    await tester.pumpAndSettle();
    expect(find.text(l.agentByokNotice), findsOneWidget);
    await tester.tapAt(const Offset(8, 80));
    await tester.pumpAndSettle();

    await _reachModelField(tester, 'agent-service-models-description');
    expect(find.text(l.agentServiceModelsSummary), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-service-models-description')));
    await tester.pumpAndSettle();
    expect(find.textContaining(l.agentCatalogNotice), findsOneWidget);
    expect(find.textContaining(l.agentBatchModelHint), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('model management card separates actions at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openModelEditor(tester, service, models: const [profile], scale: 2);
    await _reachModelField(tester, 'agent-current-model');

    expect(
      tester.getTopLeft(find.byKey(const Key('agent-current-model'))).dy -
          tester.getBottomLeft(find.byKey(const Key('agent-add-model-ids'))).dy,
      greaterThanOrEqualTo(8),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'model settings keep keys out of profile JSON and support large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(AgentSettingsPage(service: service), scale: 2, themed: true),
      );
      await _until(tester, () => _settingsReady(tester));
      await _reachAgentSettingsRow(tester, 'agent-profile-test');
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('agent-profile-test')))
            .contentPadding,
        const EdgeInsets.symmetric(horizontal: 16),
      );
      await _capture(tester, '04-settings-large');
      final add = find.byKey(const Key('agent-add-model'));
      await _reachAgentSettingsRow(tester, 'agent-add-model');
      await tester.tap(add);
      await _until(
        tester,
        () => find
            .byKey(const Key('agent-profile-name'))
            .hitTestable()
            .evaluate()
            .isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('agent-profile-name')),
        'Other provider',
      );
      final formScroll = find
          .descendant(
            of: find.byKey(const Key('agent-model-form')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('agent-profile-key')),
        180,
        scrollable: formScroll,
      );
      await tester.enterText(
        find.byKey(const Key('agent-profile-key')),
        'synthetic-key',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('agent-profile-model')),
        180,
        scrollable: formScroll,
      );
      await tester.enterText(
        find.byKey(const Key('agent-profile-model')),
        'model',
      );
      final contextField = find.byKey(const Key('agent-profile-context'));
      final outputField = find.byKey(const Key('agent-profile-output'));
      await tester.scrollUntilVisible(
        contextField,
        180,
        scrollable: formScroll,
      );
      await tester.enterText(contextField, '1M');
      await tester.scrollUntilVisible(outputField, 180, scrollable: formScroll);
      expect(
        tester.getTopLeft(outputField).dy -
            tester.getBottomLeft(contextField).dy,
        greaterThanOrEqualTo(16),
      );
      await tester.enterText(outputField, '384K');
      await _capture(tester, '06-model-lengths-large');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('agent-save-model'));
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(save).dy, lessThan(100));
      await tester.tap(save);
      await _until(
        tester,
        () => find.byType(AgentModelEditorPage).evaluate().isEmpty,
      );
      final saved = await tester.runAsync(
        () async => service.profiles.get(await service.profiles.selectedId()),
      );
      expect(saved!.name, 'Other provider');
      expect(saved.capabilities.contextTokens, 1048576);
      expect(saved.maxOutputTokens, 393216);
      expect(saved.defaultRunLimits.maxOutputTokens, 393216);
      expect(await service.vault.read(saved.credentialId), 'synthetic-key');
      expect(
        await tester.runAsync(() => service.profiles.file.readAsString()),
        isNot(contains('synthetic-key')),
      );
      expect(model.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('model connection result stays beside the test action', (
    tester,
  ) async {
    await _openModelEditor(tester, service, models: const [profile]);
    await _reachModelField(tester, 'agent-test-model');

    expect(
      tester.getCenter(find.byKey(const Key('agent-test-model'))).dx,
      closeTo(tester.getCenter(find.byType(Scaffold).last).dx, 1),
    );
    await _capture(tester, 'model-test-centered');

    await tester.tap(find.byKey(const Key('agent-test-model')));
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-connection-result'))
          .evaluate()
          .isNotEmpty,
    );

    expect(find.textContaining('连接成功'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(model.requests, hasLength(1));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('MCP form has separated fields and actions at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(AgentSettingsPage(service: service), scale: scale, themed: true),
      );
      await _until(tester, () => _settingsReady(tester));
      await _reachAgentSettingsRow(tester, 'agent-add-mcp');
      await tester.tap(find.byKey(const Key('agent-add-mcp')));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byKey(const Key('agent-mcp-form'))),
      );
      expect(find.text(l.agentMcpSummary), findsOneWidget);
      expect(find.text(l.agentMcpNotice), findsNothing);
      await tester.tap(find.byKey(const Key('agent-mcp-form-description')));
      await tester.pumpAndSettle();
      expect(find.text(l.agentMcpNotice), findsOneWidget);
      await tester.tapAt(const Offset(8, 80));
      await tester.pumpAndSettle();
      final form = find
          .descendant(
            of: find.byKey(const Key('agent-mcp-form')),
            matching: find.byType(Scrollable),
          )
          .first;
      final endpoint = find.byKey(const Key('agent-mcp-endpoint'));
      await tester.scrollUntilVisible(endpoint, 180, scrollable: form);
      expect(
        tester.getTopLeft(endpoint).dy -
            tester.getBottomLeft(find.byKey(const Key('agent-mcp-name'))).dy,
        greaterThanOrEqualTo(16),
      );
      await tester.enterText(endpoint, 'https://example.test/mcp');
      final token = find.byKey(const Key('agent-mcp-token'));
      await tester.scrollUntilVisible(token, 180, scrollable: form);
      expect(
        tester.getTopLeft(token).dy - tester.getBottomLeft(endpoint).dy,
        greaterThanOrEqualTo(16),
      );
      final save = find.byKey(const Key('agent-save-mcp'));
      await tester.scrollUntilVisible(save, 180, scrollable: form);
      expect(
        tester.getTopLeft(save).dy -
            tester
                .getBottomLeft(find.byKey(const Key('agent-mcp-discover')))
                .dy,
        greaterThanOrEqualTo(12),
      );
      await _capture(tester, '05-mcp-form-$scale');
      expect(tester.takeException(), isNull);
      expect(model.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('approval preference persists and grants pin the chosen mode', (
    tester,
  ) async {
    final grant = (await tester.runAsync(
      () => service.grant(profileId: profile.id),
    ))!;
    expect(grant.requireApproval, isFalse);
    expect(grant.writeNotes, isFalse);
    expect(grant.networkTools, isFalse);
    await tester.pumpWidget(_app(AgentSettingsPage(service: service)));
    await _until(tester, () => _settingsReady(tester));
    final toggle = find.byKey(const Key('agent-default-skip-approval'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await _until(tester, () => !tester.widget<SwitchListTile>(toggle).value);
    expect(
      await tester.runAsync(
        () => ModelProfileStore(service.profiles.file).defaultRequireApproval(),
      ),
      isTrue,
    );
    final next = await tester.runAsync(
      () => service.grant(profileId: profile.id),
    );
    expect(next!.requireApproval, isTrue);
    expect(
      grant.requireApproval,
      isFalse,
      reason: 'Changing defaults cannot modify an existing grant',
    );
    expect(model.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'model length settings supply the task budget and actual output request',
    () async {
      final configured = ModelProfile(
        id: profile.id,
        name: profile.name,
        protocol: profile.protocol,
        endpoint: profile.endpoint,
        model: profile.model,
        capabilities: const ModelCapabilities(
          contextTokens: 1048576,
          maxOutputTokens: 393216,
        ),
      );
      await service.profiles.save(configured);
      model.capabilities = configured.capabilities;
      model.respond = (request, cancel) async* {
        yield ModelCompleted(
          AgentMessage(role: MessageRole.assistant, text: 'Done'),
        );
      };
      final scope = await service.grant(profileId: configured.id, online: true);
      final id = await service.start(
        sessionId: 'model-limits',
        input: 'Test',
        profileId: configured.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      final run = (await service.runtime.get(id))!;
      expect(run.status, RunStatus.completed);
      expect(run.limits.maxTokens, configured.defaultRunLimits.maxTokens);
      expect(model.requests.single.maxOutputTokens, 393216);
    },
  );

  test(
    'default automatic note writes retain receipts, sources and undo',
    () async {
      model.respond = (request, cancel) async* {
        yield ModelCompleted(
          model.requests.length == 1
              ? AgentMessage(
                  role: MessageRole.assistant,
                  calls: [
                    ToolCall(
                      id: 'automatic-write',
                      name: 'propose_note_changes',
                      arguments: {
                        'changes': [
                          {
                            'kind': 'append',
                            'noteId': note.id.value,
                            'baseRevision': note.revision,
                            'text': 'Automatic addition',
                          },
                        ],
                      },
                    ),
                  ],
                )
              : AgentMessage(role: MessageRole.assistant, text: 'Saved'),
        );
      };
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        writeNotes: true,
        noteIds: {note.id.value},
      );
      final id = await service.start(
        sessionId: 'automatic',
        input: 'Append',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      await _refresh(service, id);
      final run = (await service.runtime.get(id))!;
      expect(run.status, RunStatus.completed);
      expect(run.events.where((e) => e.type == 'approvalRequired'), isEmpty);
      expect(run.actions.single['approvalMode'], 'automatic');
      expect(
        (await repo.get(note.id))!.document.toQuillDocument().toPlainText(),
        contains('Automatic addition'),
      );
      expect(
        run.messages
            .expand((m) => m.sources)
            .any((s) => s['noteId'] == note.id.value),
        isTrue,
      );
      await service.undo(id, run.actions.single['operationId'] as String);
      expect(
        (await repo.get(note.id))!.document.toQuillDocument().toPlainText(),
        'Original text\n',
      );
    },
  );

  testWidgets('sources and note changes open compact metadata sheets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sourceNote = (await tester.runAsync(
      () => repo.update(note.copyWith(tags: const ['参考资料'])),
    ))!;
    final deletedNote = (await tester.runAsync(
      () => repo.create(
        Note.newDraft().copyWith(title: '临时笔记', tags: const ['旧']),
      ),
    ))!;
    model.respond = (request, cancel) async* {
      yield ModelCompleted(switch (model.requests.length) {
        1 => AgentMessage(
          role: MessageRole.assistant,
          calls: [
            ToolCall(
              id: 'read-source',
              name: 'read_notes',
              arguments: {
                'ids': [sourceNote.id.value],
              },
            ),
          ],
        ),
        2 => AgentMessage(
          role: MessageRole.assistant,
          calls: [
            ToolCall(
              id: 'create-notes',
              name: 'propose_note_changes',
              arguments: {
                'changes': [
                  {
                    'kind': 'create',
                    'title': '会议摘要',
                    'text': '会议内容',
                    'tags': ['输出'],
                  },
                  {
                    'kind': 'create',
                    'title': '行动清单',
                    'text': '下一步',
                    'tags': ['待办'],
                  },
                  {
                    'kind': 'metadata',
                    'noteId': sourceNote.id.value,
                    'baseRevision': sourceNote.revision,
                    'tags': ['参考资料', '已整理'],
                  },
                  {
                    'kind': 'delete',
                    'noteId': deletedNote.id.value,
                    'baseRevision': deletedNote.revision,
                  },
                ],
              },
            ),
          ],
        ),
        _ => AgentMessage(role: MessageRole.assistant, text: '已完成'),
      });
    };
    final run = (await tester.runAsync(() async {
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        writeNotes: true,
        requireApproval: false,
        noteIds: {sourceNote.id.value, deletedNote.id.value},
      );
      final id = await service.start(
        sessionId: 'note-collections',
        input: '根据资料新建两篇笔记',
        profileId: profile.id,
        scope: scope,
        history: [
          AgentMessage(
            role: MessageRole.user,
            text: '参考资料',
            sources: [
              {
                'noteId': sourceNote.id.value,
                'title': sourceNote.title,
                'revision': sourceNote.revision,
              },
            ],
          ),
        ],
      );
      await service.runtime.settle(id);
      final approvalRun = (await service.runtime.get(id))!;
      expect(approvalRun.status, RunStatus.waitingApproval);
      final pending = approvalRun.pending.single;
      expect(pending.preview!.requiresApproval, isTrue);
      await service.runtime.approve(
        pending.approvalId!,
        accept: true,
        expectedDigest: pending.preview!.digest,
      );
      await service.runtime.settle(id);
      return (await service.runtime.get(id))!;
    }))!;
    final createdIds = taskCreatedNoteIds(run);
    expect(createdIds, hasLength(2));
    expect(taskNoteChanges(run), hasLength(4));
    expect(await tester.runAsync(() => repo.get(deletedNote.id)), isNull);
    Json? opened;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(
              service: service,
              run: run,
              conversation: true,
              onOpenSource: (source) async => opened = source,
            ),
          ),
        ),
        themed: true,
      ),
    );
    final sources = find.byKey(ValueKey('agent-sources-${run.id}'));
    final changes = find.byKey(ValueKey('agent-note-changes-${run.id}'));
    expect(sources, findsOneWidget);
    expect(changes, findsOneWidget);
    expect(
      find.descendant(of: sources, matching: find.text('Project')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: changes, matching: find.textContaining('会议摘要')),
      findsOneWidget,
    );

    await tester.tap(sources);
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-note-collection-sheet'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byKey(const Key('agent-note-collection-sheet')),
      findsOneWidget,
    );
    expect(find.text('参考资料'), findsOneWidget);
    expect(find.text('引用后已更新'), findsNothing);
    expect(find.textContaining('引用版本'), findsNothing);
    expect(find.textContaining('更新'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('agent-source-note-${sourceNote.id.value}')),
    );
    await _until(tester, () => opened != null);
    expect(opened?['noteId'], sourceNote.id.value);

    opened = null;
    await tester.tap(changes);
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-note-collection-sheet'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('会议摘要'), findsWidgets);
    expect(find.text('行动清单'), findsWidgets);
    expect(find.text('临时笔记'), findsOneWidget);
    expect(find.text('输出'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('已整理'), findsOneWidget);
    expect(find.text('已新建'), findsNWidgets(2));
    expect(find.text('已更新信息'), findsOneWidget);
    expect(find.text('已删除'), findsWidgets);
    expect(find.textContaining('创建时间'), findsNWidgets(2));
    final firstCreatedId = createdIds.first;
    await tester.tap(find.byKey(ValueKey('agent-source-note-$firstCreatedId')));
    await _until(tester, () => opened != null);
    expect(opened?['noteId'], firstCreatedId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locking private access also hides an open approval sheet', (
    tester,
  ) async {
    note = (await tester.runAsync(
      () => repo.update(note.copyWith(isPrivate: true)),
    ))!;
    await privacy.unlock(
      prompt: const DeviceAuthenticationPrompt(reason: 'test'),
    );
    model.respond = (request, cancel) async* {
      yield ModelCompleted(
        AgentMessage(
          role: MessageRole.assistant,
          calls: [
            ToolCall(
              id: 'private-write',
              name: 'propose_note_changes',
              arguments: {
                'changes': [
                  {
                    'kind': 'append',
                    'noteId': note.id.value,
                    'baseRevision': note.revision,
                    'text': 'Sensitive proposal',
                  },
                ],
              },
            ),
          ],
        ),
      );
    };
    await tester.runAsync(() async {
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        privateAccess: true,
        readNotes: true,
        writeNotes: true,
        requireApproval: true,
        noteIds: {note.id.value},
      );
      final id = await service.start(
        sessionId: 'private-sheet',
        input: 'Edit',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
    });
    await tester.pumpWidget(_app(AgentStatisticsPage(service: service)));
    final privateRun = service.runs.single;
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-statistics-overview'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text(privateRun.goal), findsNothing);
    expect(find.text('审核修改'), findsNothing);
    expect(find.byKey(const Key('agent-task-details-page')), findsNothing);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: AgentTaskCard(service: service, run: privateRun),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () => find.text('审核修改').hitTestable().evaluate().isNotEmpty,
    );
    await tester.tap(find.text('审核修改'));
    await _until(
      tester,
      () => find
          .byKey(const Key('agent-approve-proposal'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    expect(find.textContaining('Sensitive proposal'), findsOneWidget);
    privacy.lock();
    await tester.pump();
    expect(find.textContaining('Sensitive proposal'), findsNothing);
    expect(
      (await tester.runAsync(
        () => repo.get(note.id, privateSpace: true),
      ))!.revision,
      note.revision,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('editor uses the same runtime and cannot invoke note tools', () async {
    model.respond = (request, cancel) async* {
      expect(request.tools, isEmpty);
      if (model.requests.length == 1) {
        yield ModelCompleted(
          AgentMessage(
            role: MessageRole.assistant,
            calls: [
              ToolCall(
                id: 'denied',
                name: 'propose_note_changes',
                arguments: {
                  'changes': [
                    {
                      'kind': 'append',
                      'noteId': note.id.value,
                      'baseRevision': note.revision,
                      'text': 'Forbidden',
                    },
                  ],
                },
              ),
            ],
          ),
        );
      } else {
        expect(
          request.messages.where((m) => m.role == MessageRole.tool).last.text,
          contains('skillToolDenied'),
        );
        yield const ModelText('Editor suggestion');
        yield ModelCompleted(
          AgentMessage(role: MessageRole.assistant, text: 'Editor suggestion'),
        );
      }
    };
    final driver = HarnessEditorDriver(service: service);
    driver.configure(
      profile: profile,
      scope: await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        noteIds: {note.id.value},
        writeNotes: true,
      ),
      limits: const RunLimits(),
      note: note,
      instruction: 'Rewrite',
    );
    await driver.load();
    final output = await driver
        .generate(
          NoteAssistantPromptBuilder.build(
            action: NoteAssistantAction.custom('Rewrite'),
            title: note.title,
            content: note.document.toQuillDocument().toPlainText(),
            onDevice: false,
          ),
        )
        .toList();
    expect(
      output.whereType<LocalLlmTextDelta>().last.text,
      'Editor suggestion',
    );
    expect(output.last, isA<LocalLlmGenerationCompleted>());
    expect(service.runs.single.skillId, 'editor');
    expect((await repo.get(note.id))!.revision, note.revision);
  });

  test(
    'a changed note returns an observation and requires a new approval',
    () async {
      model.respond = (request, cancel) async* {
        if (model.requests.length <= 2) {
          if (model.requests.length == 2) {
            expect(
              request.messages
                  .where((m) => m.role == MessageRole.tool)
                  .last
                  .text,
              contains('noteChanged'),
            );
          }
          final current = (await repo.get(note.id))!;
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'proposal-${model.requests.length}',
                  name: 'propose_note_changes',
                  arguments: {
                    'changes': [
                      {
                        'kind': 'append',
                        'noteId': note.id.value,
                        'baseRevision': current.revision,
                        'text': 'Agent addition',
                      },
                    ],
                  },
                ),
              ],
            ),
          );
        } else {
          yield ModelCompleted(
            AgentMessage(role: MessageRole.assistant, text: 'Done'),
          );
        }
      };
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        writeNotes: true,
        requireApproval: true,
        noteIds: {note.id.value},
      );
      final id = await service.start(
        sessionId: 'conflict',
        input: 'Append',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      final old = (await service.runtime.get(id))!.pending.single;
      await repo.update(
        note.copyWith(
          document: NoteDocument.fromPlainText('User changed this'),
        ),
      );
      await service.runtime.approve(
        old.approvalId!,
        accept: true,
        expectedDigest: old.preview!.digest,
      );
      await service.runtime.settle(id);
      final refreshed = (await service.runtime.get(id))!;
      expect(refreshed.status, RunStatus.waitingApproval);
      final next = refreshed.pending.single;
      expect(next.approvalId, isNot(old.approvalId));
      expect(
        (await repo.get(note.id))!.contentProjection.plainText,
        'User changed this',
      );
      await expectLater(
        service.runtime.approve(
          old.approvalId!,
          accept: true,
          expectedDigest: old.preview!.digest,
        ),
        throwsA(isA<HarnessException>()),
      );
      await service.runtime.approve(
        next.approvalId!,
        accept: true,
        expectedDigest: next.preview!.digest,
      );
      await service.runtime.settle(id);
      expect(
        (await repo.get(note.id))!.contentProjection.plainText,
        'User changed this\nAgent addition',
      );
      expect((await service.runtime.get(id))!.status, RunStatus.completed);
    },
  );

  test(
    'private history requires a new grant after locking and does not rerun',
    () async {
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'test'),
      );
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        privateAccess: true,
      );
      final id = await service.start(
        sessionId: 'private',
        input: 'Private input',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      await _refresh(service, id);
      expect(service.canDisplay(service.runs.single), isTrue);
      privacy.lock();
      expect(service.canDisplay(service.runs.single), isFalse);
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'test'),
      );
      expect(service.canDisplay(service.runs.single), isFalse);
      final grant = await service.grant(
        profileId: profile.id,
        online: true,
        privateAccess: true,
      );
      await service.renewViewGrant(id, grant);
      expect(service.canDisplay(service.runs.single), isTrue);
      expect(model.requests, hasLength(1));
    },
  );

  test(
    'reentering an authenticated workspace reveals history without resuming old work',
    () async {
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'first visit'),
      );
      final scope = await service.grant(
        profileId: profile.id,
        privateAccess: true,
        online: true,
      );
      final id = await service.start(
        sessionId: 'private-history',
        input: 'Private conversation',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      final run = (await service.runtime.get(id))!;
      privacy.lock();
      expect(service.canDisplay(run), isFalse);
      final visit = PrivateNotesController(
        authenticator: _Unlock(),
        observeLifecycle: false,
      );
      await visit.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'next visit'),
      );
      privacy.followSession(visit);
      expect(service.canDisplay(run), isTrue);
      expect(
        () => service.policy.validateScope(run.scope),
        throwsA(isA<HarnessException>()),
      );
      expect(model.requests, hasLength(1));
      visit.dispose();
      expect(service.canDisplay(run), isFalse);
    },
  );

  test(
    'a task can read its approved new note without gaining access to other notes',
    () async {
      String? createdId;
      model.respond = (request, cancel) async* {
        if (model.requests.length == 1) {
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'create',
                  name: 'propose_note_changes',
                  arguments: {
                    'changes': [
                      {
                        'kind': 'create',
                        'title': 'Created by task',
                        'text': 'New content',
                      },
                    ],
                  },
                ),
              ],
            ),
          );
        } else if (model.requests.length == 2) {
          createdId =
              request.messages
                      .where((m) => m.role == MessageRole.tool)
                      .last
                      .sources
                      .single['noteId']
                  as String;
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                ToolCall(
                  id: 'read-created',
                  name: 'read_notes',
                  arguments: {
                    'ids': [createdId, note.id.value],
                  },
                ),
              ],
            ),
          );
        } else {
          expect(
            request.messages
                .where((m) => m.role == MessageRole.tool)
                .last
                .isError,
            model.requests.length == 3,
            reason: 'An unrelated existing note is still outside the grant',
          );
          yield ModelCompleted(
            AgentMessage(
              role: MessageRole.assistant,
              calls: [
                if (model.requests.length == 3)
                  ToolCall(
                    id: 'read-own',
                    name: 'read_notes',
                    arguments: {
                      'ids': [createdId],
                    },
                  ),
              ],
              text: model.requests.length == 3 ? '' : 'Done',
            ),
          );
        }
      };
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        writeNotes: true,
        requireApproval: true,
      );
      final id = await service.start(
        sessionId: 'create',
        input: 'Create',
        profileId: profile.id,
        scope: scope,
      );
      await service.runtime.settle(id);
      final pending = (await service.runtime.get(id))!.pending.single;
      await service.runtime.approve(
        pending.approvalId!,
        accept: true,
        expectedDigest: pending.preview!.digest,
      );
      await service.runtime.settle(id);
      final run = (await service.runtime.get(id))!;
      expect(run.status, RunStatus.completed);
      expect(
        (await repo.get(NoteId.parse(createdId!)))!.title,
        'Created by task',
      );
      expect(
        run.messages.where((m) => m.toolCallId == 'read-own').single.isError,
        isFalse,
      );
      expect(run.scope.noteIds, isEmpty);
    },
  );

  test(
    'moving a source into private space protects persisted history even after deletion',
    () async {
      final scope = await service.grant(
        profileId: profile.id,
        online: true,
        readNotes: true,
        noteIds: {note.id.value},
      );
      final id = await service.start(
        sessionId: 'reclassify',
        input: 'Summarize',
        profileId: profile.id,
        scope: scope,
        history: [
          AgentMessage(
            role: MessageRole.user,
            text: 'Source body',
            sources: [
              {'noteId': note.id.value},
            ],
          ),
        ],
      );
      await service.runtime.settle(id);
      await _refresh(service, id);
      expect(service.canDisplay(service.runs.single), isTrue);
      await repo.update(note.copyWith(isPrivate: true));
      expect(service.canDisplay(service.runs.single), isFalse);
      for (
        var i = 0;
        i < 100 && !(await service.runtime.get(id))!.requiresPrivateAccess;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect((await service.runtime.get(id))!.requiresPrivateAccess, isTrue);
      await repo.deletePermanently(note.id);
      expect(service.canDisplay((await service.runtime.get(id))!), isFalse);
    },
  );
}

final _captureKey = GlobalKey();
bool _settingsReady(WidgetTester tester) {
  final toggle = find.byKey(const Key('agent-default-skip-approval'));
  return toggle.evaluate().isNotEmpty &&
      tester.widget<SwitchListTile>(toggle).onChanged != null;
}

Widget _app(
  Widget page, {
  double scale = 1,
  bool themed = false,
  ThemeData? theme,
}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme:
        theme ??
        (themed ? buildAppTheme(AppThemeStyle.paper, Brightness.light) : null),
    locale: const Locale('zh'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: page,
  ),
);

Future<void> _openModelEditor(
  WidgetTester tester,
  AgentService service, {
  List<ModelProfile> models = const [],
  double scale = 1,
}) async {
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open-model-editor'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AgentModelEditorPage(service: service, models: models),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      themed: true,
      scale: scale,
    ),
  );
  await tester.tap(find.byKey(const Key('open-model-editor')));
  await tester.pumpAndSettle();
}

Future<void> _reachModelField(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final scroll = find
      .descendant(
        of: find.byKey(const Key('agent-model-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    220,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
}

Future<void> _reachAgentSettingsRow(WidgetTester tester, String key) async {
  final scroll = find
      .descendant(
        of: find.byKey(const Key('agent-settings-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    220,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('FKNOTES_QA_SCREENSHOTS');
  if (directory.isEmpty) return;
  await tester.pump();
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final frame = await boundary.toImage();
    final bytes = (await frame.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes);
    frame.dispose();
  });
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _refresh(AgentService service, String id) async {
  for (var i = 0; i < 100 && !service.runs.single.status.terminal; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<void> _insertChatSession(LocalChatSession session) async {
  final database = await LocalChatDatabaseService.instance.database;
  await database.transaction((transaction) async {
    await transaction.insert('chat_sessions', {
      'id': session.id,
      'title': session.title,
      'persona_id': session.personaId,
      'system_prompt': session.systemPrompt,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': session.updatedAt.toIso8601String(),
    });
    final batch = transaction.batch();
    for (var index = 0; index < session.messages.length; index++) {
      final message = session.messages[index];
      batch.insert('chat_messages', {
        'id': message.id,
        'session_id': session.id,
        'role': message.role.name,
        'content': message.content,
        'attachments_json': jsonEncode([
          for (final attachment in message.attachments) attachment.toJson(),
        ]),
        'note_contexts_json': jsonEncode([
          for (final context in message.noteContexts) context.toJson(),
        ]),
        'tool_calls_json': jsonEncode([
          for (final call in message.toolCalls) call.toJson(),
        ]),
        'status': message.status.name,
        'created_at': message.createdAt.toIso8601String(),
        'sort_order': index,
      });
    }
    await batch.commit(noResult: true);
  });
}

class _Model implements ModelPort {
  @override
  String get id => 'test';
  @override
  bool get isRemote => true;
  @override
  ModelCapabilities capabilities = const ModelCapabilities(
    contextTokens: 32000,
  );
  final requests = <ModelRequest>[];
  Stream<ModelEvent> Function(ModelRequest, CancellationToken)? respond;
  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    requests.add(request);
    if (respond != null) {
      yield* respond!(request, cancel);
    } else {
      yield ModelCompleted(
        AgentMessage(role: MessageRole.assistant, text: 'Done'),
      );
    }
  }
}

class _Unlock implements DeviceAuthenticator {
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<DeviceAuthenticationResult> authenticate({
    required DeviceAuthenticationPrompt prompt,
  }) async => const DeviceAuthenticationResult(
    DeviceAuthenticationStatus.authenticated,
    'test',
  );
}

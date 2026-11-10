import 'dart:convert';
import 'dart:io';

import 'package:fknotes/agent/encrypted_run_store.dart';
import 'package:fknotes/agent/agent_policy.dart';
import 'package:fknotes/agent/model_profile.dart';
import 'package:fknotes/agent/note_tools.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_edit_guard.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:fknotes/providers/private_notes_controller.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'agent_model_adapter_test.dart' show TestVault;

void main() {
  late Database db;
  late NoteRepository repo;
  late NoteToolAccess access;
  late ProposeNoteChangesTool writes;
  late String epoch;
  var privateGranted = true;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    repo = NoteRepository(db);
    await repo.initialize();
    epoch = await repo.agentEpoch;
    privateGranted = true;
    access = NoteToolAccess(
      repository: () async => repo,
      editors: NoteEditGuard(),
      validateScope: (scope) {
        if (scope.privateNotes && !privateGranted) {
          throw const HarnessException(
            'privateLocked',
            'Private space locked.',
          );
        }
      },
    );
    writes = ProposeNoteChangesTool(access);
  });
  tearDown(() => db.close());

  AgentRun run({
    RunScope scope = const RunScope(
      readNotes: true,
      writeNotes: true,
      allNotes: true,
      requireApproval: true,
    ),
  }) => AgentRun(
    id: 'run',
    sessionId: 'session',
    profileId: 'local',
    noteStoreEpoch: epoch,
    scope: scope,
    limits: const RunLimits(),
    system: '',
    skillId: 'assistant',
    createdAt: DateTime.utc(2026),
  );
  ToolContext context(AgentRun run, Json args, {String operation = 'op'}) =>
      ToolContext(
        run: run,
        operationId: operation,
        argumentsDigest: contentDigest(args),
        cancel: CancellationToken(),
        ensureActive: () async {
          access.validateScope(run.scope);
          if (await repo.agentEpoch != run.noteStoreEpoch) {
            throw const HarnessException('libraryChanged', 'Library changed.');
          }
        },
      );

  test(
    'online grants bind endpoints and private grants expire across locks',
    () async {
      final privacy = PrivateNotesController(
        authenticator: _Unlock(),
        observeLifecycle: false,
      );
      addTearDown(privacy.dispose);
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'test'),
      );
      var model = ModelProfile(
        id: 'remote',
        name: 'Remote',
        protocol: ModelProtocol.responses,
        endpoint: 'https://first.example/v1',
        model: 'm',
      );
      final policy = AgentPolicy(
        privateNotes: privacy,
        repository: () async => repo,
        profile: (_) async => model,
      );
      final granted = run(
        scope: RunScope(
          online: true,
          modelBinding: model.binding,
          readNotes: true,
          allNotes: true,
          privateNotes: true,
          privateGeneration: privacy.authorizationGeneration,
        ),
      );
      await policy.authorize(granted, sendingToModel: true);
      model = ModelProfile(
        id: 'remote',
        name: 'Remote',
        protocol: ModelProtocol.responses,
        endpoint: 'https://other.example/v1',
        model: 'm',
      );
      await expectLater(
        policy.authorize(granted, sendingToModel: true),
        throwsA(
          isA<HarnessException>().having(
            (e) => e.code,
            'code',
            'modelPermission',
          ),
        ),
      );
      privacy.lock();
      await privacy.unlock(
        prompt: const DeviceAuthenticationPrompt(reason: 'test'),
      );
      expect(
        () => policy.validateScope(granted.scope),
        throwsA(
          isA<HarnessException>().having(
            (e) => e.code,
            'code',
            'privateLocked',
          ),
        ),
      );
    },
  );

  test(
    'selection scope and private notes never leak through search or read',
    () async {
      final selected = await repo.create(
        Note.newDraft().copyWith(
          title: 'selected',
          document: NoteDocument.fromPlainText('hello'),
        ),
      );
      final other = await repo.create(Note.newDraft().copyWith(title: 'other'));
      final secret = await repo.create(
        Note.newDraft(isPrivate: true).copyWith(title: 'secret'),
      );
      final args = <String, dynamic>{'browseAll': true};
      final scoped = run(
        scope: RunScope(readNotes: true, noteIds: {selected.id.value}),
      );
      final found = await SearchNotesTool(
        access,
      ).execute(context(scoped, args), args, ToolPreview(data: {}));
      expect((found.data['notes'] as List).single['noteId'], selected.id.value);
      expect(jsonEncode(found.toJson()), isNot(contains('secret')));
      await expectLater(
        access.read(context(scoped, args), other.id.value),
        throwsA(isA<HarnessException>()),
      );
      await expectLater(
        access.read(context(run(), args), secret.id.value),
        throwsA(isA<HarnessException>()),
      );
      final readArgs = <String, dynamic>{
        'ids': [selected.id.value],
        'start': 1,
        'length': 2,
      };
      final read = await ReadNotesTool(
        access,
      ).execute(context(scoped, readArgs), readArgs, ToolPreview(data: {}));
      expect(read.data['notes'].single['text'], 'el');
      expect(read.sources.single['revision'], selected.revision);
    },
  );

  test(
    'search notes requires intent and browses the scope only when explicit',
    () async {
      final first = await repo.create(Note.newDraft().copyWith(title: 'first'));
      final second = await repo.create(
        Note.newDraft().copyWith(title: 'second'),
      );
      final tool = SearchNotesTool(access);
      final model = _SearchModel();
      final runtime = HarnessRuntime(
        store: MemoryRunStore(),
        resolveModel: (_) async => model,
        authorize: (run, {tool, sendingToModel = false}) async {},
        tools: [tool],
      );
      addTearDown(runtime.close);
      final id = await runtime.start(
        TaskRequest(
          sessionId: 'search',
          input: '列出笔记',
          profileId: 'local',
          noteStoreEpoch: epoch,
          scope: const RunScope(readNotes: true, allNotes: true),
        ),
      );
      await runtime.settle(id);
      final completed = (await runtime.get(id))!;
      final observation =
          jsonDecode(
                completed.messages
                    .singleWhere((message) => message.role == MessageRole.tool)
                    .text,
              )
              as Map<String, dynamic>;
      final notes = (observation['notes'] as List)
          .map((note) => (note as Map)['noteId'])
          .toSet();

      expect(
        (tool.spec.schema['anyOf'] as List).whereType<Map>(),
        contains(containsPair('required', ['browseAll'])),
      );
      expect(completed.status, RunStatus.completed);
      expect(completed.errorCode, isNull);
      expect(model.requests, 2);
      expect(notes, {first.id.value, second.id.value});
    },
  );

  test(
    'private tools search, read, create and undo only inside private space',
    () async {
      final public = await repo.create(
        Note.newDraft().copyWith(title: 'public-only'),
      );
      final secret = await repo.create(
        Note.newDraft(isPrivate: true).copyWith(title: 'private-only'),
      );
      final scoped = run(
        scope: const RunScope(
          readNotes: true,
          writeNotes: true,
          allNotes: true,
          privateNotes: true,
        ),
      );
      final args = <String, dynamic>{'browseAll': true};
      final found = await SearchNotesTool(
        access,
      ).execute(context(scoped, args), args, ToolPreview(data: {}));
      expect(found.data['total'], 1);
      expect(found.sources.single['noteId'], secret.id.value);
      expect(jsonEncode(found.toJson()), isNot(contains('public-only')));
      await expectLater(
        access.read(context(scoped, args), public.id.value),
        throwsA(isA<HarnessException>()),
      );
      expect(
        (await access.read(context(scoped, args), secret.id.value)).isPrivate,
        isTrue,
      );
      final changes = <String, dynamic>{
        'changes': [
          {
            'kind': 'create',
            'title': 'AI private draft',
            'text': 'private content',
          },
        ],
      };
      final ctx = context(scoped, changes);
      final preview = await writes.prepare(ctx, changes);
      final result = await writes.execute(ctx, changes, preview);
      final id = NoteId.parse(
        result.data['results'].single['noteId'] as String,
      );
      expect(await repo.get(id), isNull);
      expect(
        (await repo.get(id, privateSpace: true))?.title,
        'AI private draft',
      );
      expect((await repo.list()).single.id, public.id);
      await writes.undo(ctx, {
        'operationId': ctx.operationId,
        'preview': preview.toJson(),
        'result': result.toJson(),
      });
      expect(await repo.get(id, privateSpace: true), isNull);
      expect((await repo.list(privateSpace: true)).single.id, secret.id);
    },
  );

  test('search notes rejects an omitted query before reading notes', () async {
    await repo.create(Note.newDraft().copyWith(title: 'must stay hidden'));
    final model = _SearchModel(arguments: const {});
    final runtime = HarnessRuntime(
      store: MemoryRunStore(),
      resolveModel: (_) async => model,
      authorize: (run, {tool, sendingToModel = false}) async {},
      tools: [SearchNotesTool(access)],
    );
    addTearDown(runtime.close);
    final id = await runtime.start(
      TaskRequest(
        sessionId: 'invalid-search',
        input: '记录一条新信息',
        profileId: 'local',
        noteStoreEpoch: epoch,
        scope: const RunScope(readNotes: true, allNotes: true),
      ),
    );
    await runtime.settle(id);
    final completed = (await runtime.get(id))!;
    final toolMessage = completed.messages.singleWhere(
      (message) => message.role == MessageRole.tool,
    );
    final observation = jsonDecode(toolMessage.text) as Map<String, dynamic>;

    expect(observation, {'error': 'invalidArguments'});
    expect(toolMessage.sources, isEmpty);
  });

  test(
    'search notes returns metadata and explains query-centered truncation',
    () async {
      final saved = await repo.create(
        Note.newDraft(now: DateTime.utc(2026, 8, 29)).copyWith(
          title: '长笔记',
          tags: ['新闻', '归档'],
          isPinned: true,
          document: NoteDocument.fromPlainText(
            '${List.filled(700, '前').join()}关键命中${List.filled(700, '后').join()}',
          ),
        ),
      );
      final args = <String, dynamic>{'query': '关键命中'};
      final result = await SearchNotesTool(
        access,
      ).execute(context(run(), args), args, ToolPreview(data: args));
      final found = (result.data['notes'] as List).single as Json;

      expect(found['noteId'], saved.id.value);
      expect(found['tags'], ['新闻', '归档']);
      expect(found['createdAt'], isA<String>());
      expect(found['updatedAt'], isA<String>());
      expect(found['isPinned'], isTrue);
      expect(found['attachmentCount'], 0);
      expect(found['excerpt'], contains('关键命中'));
      expect(found['offsetUnit'], 'utf16');
      expect(found['excerptStart'], greaterThan(0));
      expect(found['excerptEnd'], lessThan(found['contentLength'] as int));
      expect(
        found['excerptLength'],
        (found['excerptEnd'] as int) - (found['excerptStart'] as int),
      );
      expect(
        found['omittedCharacters'],
        (found['omittedBefore'] as int) + (found['omittedAfter'] as int),
      );
      expect(found['truncated'], isTrue);
    },
  );

  test('search notes combines title tags dates and state filters', () async {
    Note draft(
      String title,
      DateTime date, {
      List<String> tags = const [],
      bool pinned = false,
    }) => Note.newDraft(now: date).copyWith(
      title: title,
      tags: tags,
      isPinned: pinned,
      document: NoteDocument.fromPlainText('正文'),
    );

    final matching = await repo.create(
      draft(
        '八月新闻日报',
        DateTime.utc(2026, 8, 20),
        tags: ['新闻', '重要'],
        pinned: true,
      ),
    );
    await repo.create(
      draft('八月新闻日报', DateTime.utc(2026, 8, 21), tags: ['新闻'], pinned: true),
    );
    await repo.create(
      draft(
        '七月新闻日报',
        DateTime.utc(2026, 7, 20),
        tags: ['新闻', '重要'],
        pinned: true,
      ),
    );
    final args = <String, dynamic>{
      'title': '新闻日报',
      'tags': ['新闻', '重要'],
      'tagMode': 'all',
      'createdFrom': '2026-08-01',
      'createdTo': '2026-08-31',
      'isPinned': true,
    };
    final result = await SearchNotesTool(
      access,
    ).execute(context(run(), args), args, ToolPreview(data: args));
    final notes = (result.data['notes'] as List).cast<Json>();

    expect(notes.map((note) => note['noteId']), [matching.id.value]);
    expect(result.data['total'], 1);
    expect(result.data['nextCursor'], isNull);
  });

  test(
    'approved range edits preserve unrelated formatting, embeds, cover and undo',
    () async {
      final original = await repo.create(_richNote());
      final args = <String, dynamic>{
        'changes': [
          {
            'kind': 'replace_range',
            'noteId': original.id.value,
            'baseRevision': original.revision,
            'start': 0,
            'end': 2,
            'text': 'Hi',
            'tags': ['new'],
          },
        ],
      };
      final ctx = context(run(), args);
      final preview = await writes.prepare(ctx, args);
      expect(
        (await repo.get(original.id))!.revision,
        1,
      ); // preview has no effect
      final result = await writes.execute(ctx, args, preview);
      final edited = (await repo.get(original.id))!;
      expect(edited.revision, 2);
      expect(edited.assets.single.id, original.assets.single.id);
      expect(edited.coverAttachmentId, original.coverAttachmentId);
      expect(
        edited.document.toDelta().toJson().last,
        original.document.toDelta().toJson().last,
      );
      expect(
        edited.document.toDelta().slice(2, 5).toJson(),
        original.document.toDelta().slice(2, 5).toJson(),
      );
      expect(edited.tags, ['new']);
      final recovered = await writes.recover(ctx, args);
      expect(recovered!.data, result.data);
      expect((await repo.get(original.id))!.revision, 2);
      final action = <String, dynamic>{
        'operationId': 'op',
        'preview': preview.toJson(),
        'result': result.toJson(),
      };
      await writes.undo(ctx, action);
      final undone = (await repo.get(original.id))!;
      expect(undone.document.toJsonString(), original.document.toJsonString());
      expect(undone.tags, original.tags);
      expect(undone.revision, 3);
      await writes.undo(ctx, action);
      expect((await repo.get(original.id))!.revision, 3);
      final receiptRows = await db.query('agent_operation_receipts');
      expect(jsonEncode(receiptRows), isNot(contains('Hello')));
    },
  );

  test('append decodes Markdown into native note formatting', () async {
    final original = await repo.create(
      Note.newDraft().copyWith(
        title: '早春诗',
        document: NoteDocument.fromPlainText('原诗正文'),
      ),
    );
    final args = <String, dynamic>{
      'changes': [
        {
          'kind': 'append',
          'noteId': original.id.value,
          'baseRevision': original.revision,
          'text': '## 春雪\n\n**韩愈（唐代）**\n\n新年都未有芳华。',
        },
      ],
    };
    final ctx = context(run(), args);
    final preview = await writes.prepare(ctx, args);
    await writes.execute(ctx, args, preview);

    final edited = (await repo.get(original.id))!;
    final delta = edited.document.toDelta();
    expect(edited.contentProjection.plainText, contains('原诗正文\n春雪'));
    expect(edited.contentProjection.plainText, isNot(contains('##')));
    expect(edited.contentProjection.plainText, isNot(contains('**')));
    expect(
      delta.operations.any((operation) => operation.attributes?['header'] == 2),
      isTrue,
    );
    expect(
      delta.operations.any(
        (operation) =>
            operation.data == '韩愈（唐代）' && operation.attributes?['bold'] == true,
      ),
      isTrue,
    );
  });

  test(
    'range replacement decodes Markdown without leaving raw markers',
    () async {
      final original = await repo.create(
        Note.newDraft().copyWith(
          title: '草稿',
          document: NoteDocument.fromPlainText('旧标题'),
        ),
      );
      final args = <String, dynamic>{
        'changes': [
          {
            'kind': 'replace_range',
            'noteId': original.id.value,
            'baseRevision': original.revision,
            'start': 0,
            'end': 3,
            'text': '## 新标题',
          },
        ],
      };
      final ctx = context(run(), args);
      final preview = await writes.prepare(ctx, args);
      await writes.execute(ctx, args, preview);

      final edited = (await repo.get(original.id))!;
      expect(edited.contentProjection.plainText, '新标题');
      expect(edited.document.toDelta().toJson(), [
        {'insert': '新标题'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
      ]);
    },
  );

  test(
    'delete receipts are visible and undo restores the complete note',
    () async {
      final reminder = DateTime.utc(2026, 9, 1, 8);
      final original = await repo.create(
        _richNote().copyWith(isPinned: true, reminderAt: reminder),
      );
      final args = <String, dynamic>{
        'changes': [
          {
            'kind': 'delete',
            'noteId': original.id.value,
            'baseRevision': original.revision,
          },
        ],
      };
      final trackedRun = run();
      final ctx = context(trackedRun, args);
      final preview = await writes.prepare(ctx, args);

      expect(preview.requiresApproval, isTrue);
      expect(preview.data['changes'].single['after'], isNull);
      expect(preview.data['changes'].single['before']['assets'], hasLength(1));
      final result = await writes.execute(ctx, args, preview);
      expect(result.data['results'].single['deleted'], isTrue);
      expect(result.sources, isEmpty);
      expect(await repo.get(original.id), isNull);

      final action = <String, dynamic>{
        'operationId': 'op',
        'name': 'propose_note_changes',
        'preview': preview.toJson(),
        'result': result.toJson(),
      };
      trackedRun.actions.add(action);
      final change = taskNoteChanges(trackedRun)[original.id.value]!;
      expect(change['kind'], 'delete');
      expect(change['deleted'], isTrue);
      expect(change['title'], original.title);

      await writes.undo(ctx, action);
      final restored = (await repo.get(original.id))!;
      expect(restored.title, original.title);
      expect(
        restored.document.toJsonString(),
        original.document.toJsonString(),
      );
      expect(restored.tags, original.tags);
      expect(restored.isPinned, isTrue);
      expect(restored.reminderAt, reminder);
      expect(
        restored.assets.single.storageKey,
        original.assets.single.storageKey,
      );
      expect(restored.coverAttachmentId, original.coverAttachmentId);
      expect(restored.createdAt, original.createdAt);
      expect(restored.revision, original.revision + 1);
    },
  );

  test('embeds and open editor ownership block background edits', () async {
    final note = await repo.create(_richNote());
    final embedArgs = <String, dynamic>{
      'changes': [
        {
          'kind': 'replace_range',
          'noteId': note.id.value,
          'baseRevision': 1,
          'start': 6,
          'end': 7,
          'text': 'oops',
        },
      ],
    };
    await expectLater(
      writes.prepare(context(run(), embedArgs), embedArgs),
      throwsA(
        isA<HarnessException>().having((e) => e.code, 'code', 'embedProtected'),
      ),
    );
    final args = <String, dynamic>{
      'changes': [
        {
          'kind': 'append',
          'noteId': note.id.value,
          'baseRevision': 1,
          'text': 'extra',
        },
      ],
    };
    final ctx = context(run(), args);
    final preview = await writes.prepare(ctx, args);
    final owner = Object();
    access.editors.register(note.id, owner);
    await expectLater(
      writes.execute(ctx, args, preview),
      throwsA(
        isA<HarnessException>().having((e) => e.code, 'code', 'editorOpen'),
      ),
    );
    expect((await repo.get(note.id))!.revision, 1);
    access.editors.release(note.id, owner);
    await writes.execute(ctx, args, preview);
    expect((await repo.get(note.id))!.revision, 2);
  });

  test(
    'private locking, cancellation and library replacement revoke pending access',
    () async {
      final note = await repo.create(
        Note.newDraft(isPrivate: true).copyWith(title: 'secret'),
      );
      final args = <String, dynamic>{
        'changes': [
          {
            'kind': 'metadata',
            'noteId': note.id.value,
            'baseRevision': 1,
            'title': 'changed',
          },
        ],
      };
      final ctx = context(
        run(
          scope: const RunScope(
            readNotes: true,
            writeNotes: true,
            allNotes: true,
            privateNotes: true,
          ),
        ),
        args,
      );
      final preview = await writes.prepare(ctx, args);
      privateGranted = false;
      await expectLater(
        writes.execute(ctx, args, preview),
        throwsA(isA<HarnessException>()),
      );
      privateGranted = true;
      ctx.cancel.cancel();
      await expectLater(
        writes.execute(ctx, args, preview),
        throwsA(isA<HarnessException>()),
      );
      expect((await repo.get(note.id, privateSpace: true))!.revision, 1);
      await repo.clearAgentMetadata(restoring: true);
      await expectLater(
        writes.recover(context(run(), args), args),
        throwsA(
          isA<HarnessException>().having(
            (e) => e.code,
            'code',
            'libraryChanged',
          ),
        ),
      );
    },
  );

  test(
    'batch transaction rolls back every edit and receipt on a stale revision',
    () async {
      final first = await repo.create(Note.newDraft().copyWith(title: 'first'));
      final second = await repo.create(
        Note.newDraft().copyWith(title: 'second'),
      );
      await expectLater(
        repo.applyAgentMutations(
          operationId: 'batch',
          argumentsDigest: 'hash',
          epoch: epoch,
          mutations: [
            AgentNoteMutation(
              id: first.id,
              expectedRevision: 1,
              replacement: first.copyWith(title: 'changed'),
            ),
            AgentNoteMutation(
              id: second.id,
              expectedRevision: 5,
              replacement: second,
            ),
          ],
          validateAccess: () {},
        ),
        throwsA(isA<NoteWriteConflict>()),
      );
      expect((await repo.get(first.id))!.title, 'first');
      expect(await db.query('agent_operation_receipts'), isEmpty);
    },
  );

  test(
    'write receipts reject operation collisions and undo preserves newer edits',
    () async {
      final args = <String, dynamic>{
        'changes': [
          {'kind': 'create', 'title': 'created', 'text': 'new note'},
        ],
      };
      final ctx = context(run(), args);
      final preview = await writes.prepare(ctx, args);
      final result = await writes.execute(ctx, args, preview);
      final id = NoteId.parse(
        result.data['results'].single['noteId'] as String,
      );
      await expectLater(
        repo.agentReceipt(
          operationId: 'op',
          argumentsDigest: 'different',
          epoch: epoch,
        ),
        throwsA(isA<NoteAgentConflict>()),
      );
      await repo.update((await repo.get(id))!.copyWith(title: 'user edit'));
      await expectLater(
        writes.undo(ctx, {
          'operationId': 'op',
          'preview': preview.toJson(),
          'result': result.toJson(),
        }),
        throwsA(
          isA<HarnessException>().having((e) => e.code, 'code', 'undoConflict'),
        ),
      );
      expect((await repo.get(id))!.title, 'user edit');
    },
  );

  test(
    'created notes convert Markdown into native editor formatting',
    () async {
      const markdown = '''# 新闻速览

> 整理时间：2026-08-29

## 国内要闻

- 第一条
- 第二条''';
      final args = <String, dynamic>{
        'changes': [
          {'kind': 'create', 'title': '新闻速览', 'text': markdown},
        ],
      };
      final ctx = context(run(), args);
      final preview = await writes.prepare(ctx, args);
      final result = await writes.execute(ctx, args, preview);
      final id = NoteId.parse(
        result.data['results'].single['noteId'] as String,
      );
      final created = (await repo.get(id))!;
      final plainText = created.contentProjection.plainText;
      final delta = created.document.toDelta().toJson();

      expect(plainText, contains('新闻速览'));
      expect(plainText, isNot(contains('# 新闻速览')));
      expect(plainText, isNot(contains('> 整理时间')));
      expect(plainText, isNot(contains('- 第一条')));
      expect(
        delta,
        contains(
          predicate<Map<String, dynamic>>(
            (operation) =>
                operation['insert'] == '\n' &&
                (operation['attributes'] as Map?)?['header'] == 1,
          ),
        ),
      );
      expect(
        delta,
        contains(
          predicate<Map<String, dynamic>>(
            (operation) =>
                operation['insert'] == '\n' &&
                (operation['attributes'] as Map?)?['blockquote'] == true,
          ),
        ),
      );
      expect(
        delta.where(
          (operation) =>
              operation['insert'] == '\n' &&
              (operation['attributes'] as Map?)?['list'] == 'bullet',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'encrypted approval survives restart; subset adjustment invalidates old approval',
    () async {
      final dir = await Directory.systemTemp.createTemp('fknotes-run-store');
      addTearDown(() => dir.delete(recursive: true));
      final vault = TestVault();
      final path = '${dir.path}/tasks.db';
      var store = await EncryptedRunStore.open(
        path,
        vault,
        factory: databaseFactoryFfi,
      );
      final args = <String, dynamic>{
        'changes': [
          {'kind': 'create', 'title': 'one', 'text': 'PRIVATE_SENTINEL'},
          {'kind': 'create', 'title': 'two', 'text': 'other'},
        ],
      };
      final model = _NoteModel(args);
      HarnessRuntime runtime() => HarnessRuntime(
        store: store,
        resolveModel: (_) async => model,
        authorize: (r, {tool, sendingToModel = false}) async {},
        tools: [writes],
      );
      var harness = runtime();
      final id = await harness.start(
        TaskRequest(
          sessionId: 's',
          input: 'create notes',
          profileId: 'local',
          noteStoreEpoch: epoch,
          scope: run().scope,
        ),
      );
      await harness.settle(id);
      final pending = (await harness.get(id))!.pending.single;
      expect((await harness.get(id))!.status, RunStatus.waitingApproval);
      expect(await repo.list(), isEmpty);
      expect(
        jsonEncode(await store.database.query('runs')),
        isNot(contains('PRIVATE_SENTINEL')),
      );
      await harness.close();
      await store.close();
      store = await EncryptedRunStore.open(
        path,
        vault,
        factory: databaseFactoryFfi,
      );
      harness = runtime();
      await harness.recover();
      await harness.amendApproval(
        pending.approvalId!,
        expectedDigest: pending.preview!.digest,
        arguments: {
          'changes': [args['changes'][0]],
        },
      );
      await harness.settle(id);
      final amended = (await harness.get(id))!.pending.single;
      expect(amended.operationId, isNot(pending.operationId));
      await expectLater(
        harness.approve(
          pending.approvalId!,
          accept: true,
          expectedDigest: pending.preview!.digest,
        ),
        throwsA(isA<HarnessException>()),
      );
      await harness.approve(
        amended.approvalId!,
        accept: true,
        expectedDigest: amended.preview!.digest,
      );
      await harness.settle(id);
      expect((await harness.get(id))!.status, RunStatus.completed);
      expect((await repo.list()).single.title, 'one');
      expect(
        (await harness.get(
          id,
        ))!.actions.single['result']['data']['results'].length,
        1,
      );
      final saved = (await harness.get(id))!;
      await expectLater(
        store.save(saved, expectedRevision: 0),
        throwsA(isA<HarnessException>()),
      );
      await store.database.update(
        'runs',
        {'revision': saved.revision + 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await expectLater(
        store.get(id),
        throwsA(
          isA<HarnessException>().having((e) => e.code, 'code', 'taskCorrupt'),
        ),
      );
      await harness.close();
      await store.close();
      await vault.delete(EncryptedRunStore.keyId);
      await expectLater(
        EncryptedRunStore.open(path, vault, factory: databaseFactoryFfi),
        throwsA(
          isA<HarnessException>().having(
            (e) => e.code,
            'code',
            'taskKeyMissing',
          ),
        ),
      );
    },
  );
}

Note _richNote() {
  final now = DateTime.utc(2026);
  final id = NoteAttachmentId.generate();
  final asset = NoteAsset(
    id: id,
    kind: NoteAssetKind.image,
    storageKey: 'notes/images/test.png',
    originalName: 'test.png',
    byteLength: 1,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
  final delta = Delta()
    ..insert('Hello', {'bold': true})
    ..insert('\n')
    ..insert(NoteEmbed.attachment(id).toDeltaData())
    ..insert('\n');
  return Note.newDraft(now: now).copyWith(
    title: 'rich',
    document: NoteDocument.fromDelta(delta),
    assets: [asset],
    coverAttachmentId: id,
    tags: ['original'],
  );
}

class _NoteModel implements ModelPort {
  final Json args;
  _NoteModel(this.args);
  @override
  String get id => 'local';
  @override
  bool get isRemote => false;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    if (request.messages.any((m) => m.role == MessageRole.tool)) {
      yield ModelCompleted(
        AgentMessage(role: MessageRole.assistant, text: 'Saved.'),
      );
    } else {
      yield ModelCompleted(
        AgentMessage(
          role: MessageRole.assistant,
          calls: [
            ToolCall(id: 'call', name: 'propose_note_changes', arguments: args),
          ],
        ),
      );
    }
  }
}

class _SearchModel implements ModelPort {
  final Json arguments;
  int requests = 0;
  _SearchModel({this.arguments = const {'browseAll': true}});
  @override
  String get id => 'local';
  @override
  bool get isRemote => false;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    requests++;
    if (request.messages.any((message) => message.role == MessageRole.tool)) {
      yield ModelCompleted(
        AgentMessage(role: MessageRole.assistant, text: '完成'),
      );
      return;
    }
    yield ModelCompleted(
      AgentMessage(
        role: MessageRole.assistant,
        calls: [
          ToolCall(id: 'search', name: 'search_notes', arguments: arguments),
        ],
      ),
    );
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
    '',
  );
}

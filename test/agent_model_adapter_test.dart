import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fknotes/agent/agent_http_client.dart';
import 'package:fknotes/agent/credential_vault.dart';
import 'package:fknotes/agent/local_model_adapter.dart';
import 'package:fknotes/agent/model_profile.dart';
import 'package:fknotes/agent/model_catalog.dart';
import 'package:fknotes/agent/online_model_adapter.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestVault implements CredentialVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String id) async => values[id];
  @override
  Future<void> write(String id, String value) async {
    values[id] = value;
  }

  @override
  Future<void> delete(String id) async {
    values.remove(id);
  }
}

class WireClient extends http.BaseClient {
  final Stream<List<int>> stream;
  final int status;
  final void Function()? onClose;
  http.BaseRequest? request;
  Json? body;
  bool closed = false;
  WireClient(this.stream, {this.status = 200, this.onClose});
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    body = jsonDecode(await request.finalize().bytesToString()) as Json;
    return http.StreamedResponse(
      stream,
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
    onClose?.call();
  }
}

Stream<List<int>> sse(List<Json> events) => Stream.fromIterable([
  for (final j in events)
    utf8.encode(
      '${j['type'] != null ? 'event: ${j['type']}\n' : ''}data: ${jsonEncode(j)}\n\n',
    ),
  utf8.encode('data: [DONE]\n\n'),
]);

List<Json> chat({
  bool complete = true,
  String arguments = '{"query":"工作"}',
  String finish = 'tool_calls',
}) => [
  {
    'choices': [
      {
        'index': 0,
        'delta': {'reasoning_content': 'private reasoning'},
      },
    ],
  },
  {
    'choices': [
      {
        'index': 0,
        'delta': {'content': '查找'},
      },
    ],
  },
  {
    'choices': [
      {
        'index': 0,
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'id': 'call1',
              'type': 'function',
              'function': {
                'name': 'search_notes',
                'arguments': arguments.substring(0, 3),
              },
            },
          ],
        },
      },
    ],
  },
  {
    'choices': [
      {
        'index': 0,
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': arguments.substring(3)},
            },
          ],
        },
        if (complete) 'finish_reason': finish,
      },
    ],
  },
  {
    'choices': [],
    'usage': {'prompt_tokens': 20, 'completion_tokens': 8, 'total_tokens': 28},
  },
];

List<Json> responses() => [
  {
    'type': 'response.reasoning_summary_text.delta',
    'sequence_number': 0,
    'item_id': 'rs1',
    'output_index': 0,
    'summary_index': 0,
    'delta': 'private reasoning',
  },
  {
    'type': 'response.output_text.delta',
    'sequence_number': 1,
    'item_id': 'msg1',
    'output_index': 0,
    'content_index': 0,
    'delta': '查找',
  },
  {
    'type': 'response.completed',
    'sequence_number': 2,
    'response': {
      'id': 'resp1',
      'object': 'response',
      'created_at': 1,
      'model': 'test-model',
      'status': 'completed',
      'output': [
        {
          'id': 'rs1',
          'type': 'reasoning',
          'summary': [],
          'encrypted_content': 'opaque-encrypted',
        },
        {
          'id': 'fc1',
          'type': 'function_call',
          'call_id': 'call1',
          'name': 'search_notes',
          'arguments': '{"query":"工作"}',
          'status': 'completed',
        },
        {
          'id': 'msg1',
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {
              'type': 'output_text',
              'text': '查找',
              'annotations': [
                {
                  'type': 'url_citation',
                  'url': 'https://example.com/source',
                  'title': 'Source',
                  'start_index': 0,
                  'end_index': 2,
                },
              ],
            },
          ],
        },
      ],
      'usage': {'input_tokens': 20, 'output_tokens': 8, 'total_tokens': 28},
    },
  },
];

List<Json> deepSeekResponses() => [
  {
    'type': 'response.reasoning_text.delta',
    'sequence_number': 0,
    'item_id': 'rs-deepseek',
    'output_index': 0,
    'content_index': 0,
    'delta': '先检索并读取来源。',
  },
  {
    'type': 'response.output_item.added',
    'sequence_number': 1,
    'output_index': 1,
    'item': {
      'id': 'ws-deepseek',
      'type': 'web_search_call',
      'status': 'in_progress',
    },
  },
  {
    'type': 'response.web_search_call.searching',
    'sequence_number': 2,
    'output_index': 1,
    'item_id': 'ws-deepseek',
  },
  {
    'type': 'response.output_item.done',
    'sequence_number': 3,
    'output_index': 1,
    'item': {
      'id': 'ws-deepseek',
      'type': 'web_search_call',
      'status': 'completed',
      'action': {
        'type': 'search',
        'queries': ['近期新闻', '今日重点新闻, ws_call_id=ws-deepseek'],
      },
    },
  },
  {
    'type': 'response.output_text.delta',
    'sequence_number': 4,
    'item_id': 'msg-deepseek',
    'output_index': 2,
    'content_index': 0,
    'delta': '正在整理。',
  },
  {
    'type': 'response.completed',
    'sequence_number': 5,
    'response': {
      'id': 'resp-deepseek',
      'object': 'response',
      'created_at': 1,
      'model': 'deepseek-v4-flash',
      'status': 'completed',
      'output': [
        {
          'id': 'rs-deepseek',
          'type': 'reasoning',
          'content': [
            {'type': 'reasoning_text', 'text': '先检索并读取来源。'},
          ],
          'summary': [],
        },
        {'id': 'ws-deepseek', 'type': 'web_search_call', 'status': 'completed'},
        {
          'id': 'msg-deepseek',
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {
              'type': 'output_text',
              'text': '正在整理。',
              'annotations': [
                {
                  'type': 'url_citation',
                  'url': 'https://example.com/news#ws_call_id=ws-deepseek',
                  'title': 'News',
                  'start_index': 0,
                  'end_index': 4,
                },
              ],
            },
          ],
        },
        {
          'id': 'fc-deepseek-1',
          'type': 'function_call',
          'call_id': 'fetch-1',
          'name': 'web_fetch',
          'arguments': '{"url":"https://example.com/one"}',
          'status': 'completed',
        },
        {
          'id': 'fc-deepseek-2',
          'type': 'function_call',
          'call_id': 'fetch-2',
          'name': 'web_fetch',
          'arguments': '{"url":"https://example.com/two"}',
          'status': 'completed',
        },
      ],
      'usage': {'input_tokens': 30, 'output_tokens': 12, 'total_tokens': 42},
    },
  },
];

List<Json> responsesWithWebSearchResults() => [
  {
    'type': 'response.output_item.done',
    'sequence_number': 0,
    'output_index': 0,
    'item': {
      'id': 'ws-results',
      'type': 'web_search_call',
      'status': 'completed',
      'action': {
        'type': 'search',
        'query': 'current AI news',
        'sources': [
          {'url': 'https://example.com/one', 'title': 'Source one'},
          {'url': 'javascript:alert(1)', 'title': 'Unsafe'},
        ],
      },
      'results': {
        'data': [
          {
            'url': 'https://example.com/one#ws_call_id=ws-results',
            'title': 'Result one',
            'snippet': 'First result summary',
            'published_at': '2026-08-30',
          },
          {
            'url': 'https://example.com/two',
            'title': 'Result two',
            'content': List.filled(900, 'x').join(),
          },
        ],
      },
    },
  },
  {
    'type': 'response.completed',
    'sequence_number': 1,
    'response': {
      'id': 'resp-results',
      'object': 'response',
      'created_at': 1,
      'model': 'test-model',
      'status': 'completed',
      'output': [
        {'id': 'ws-results', 'type': 'web_search_call', 'status': 'completed'},
        {
          'id': 'msg-results',
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {'type': 'output_text', 'text': 'Done', 'annotations': []},
          ],
        },
      ],
      'usage': {'input_tokens': 10, 'output_tokens': 2, 'total_tokens': 12},
    },
  },
];

List<Json> anthropicWebSearchResults() => [
  {
    'type': 'message_start',
    'message': {
      'id': 'msg-search',
      'type': 'message',
      'role': 'assistant',
      'model': 'test-model',
      'content': [],
      'stop_reason': null,
      'stop_sequence': null,
      'usage': {'input_tokens': 10, 'output_tokens': 0},
    },
  },
  {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {
      'type': 'server_tool_use',
      'id': 'search-1',
      'name': 'web_search',
      'input': {'query': 'current AI news'},
    },
  },
  {'type': 'content_block_stop', 'index': 0},
  {
    'type': 'content_block_start',
    'index': 1,
    'content_block': {
      'type': 'web_search_tool_result',
      'tool_use_id': 'search-1',
      'content': [
        {
          'type': 'web_search_result',
          'url': 'https://example.com/anthropic',
          'title': 'Anthropic result',
          'encrypted_content': 'must-not-be-persisted-as-evidence',
          'page_age': '2 hours ago',
        },
      ],
    },
  },
  {'type': 'content_block_stop', 'index': 1},
  {
    'type': 'content_block_start',
    'index': 2,
    'content_block': {'type': 'text', 'text': ''},
  },
  {
    'type': 'content_block_delta',
    'index': 2,
    'delta': {'type': 'text_delta', 'text': 'Done'},
  },
  {'type': 'content_block_stop', 'index': 2},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
    'usage': {'output_tokens': 2},
  },
  {'type': 'message_stop'},
];

List<Json> anthropic() => [
  {
    'type': 'message_start',
    'message': {
      'id': 'msg1',
      'type': 'message',
      'role': 'assistant',
      'model': 'test-model',
      'content': [],
      'stop_reason': null,
      'stop_sequence': null,
      'usage': {'input_tokens': 20, 'output_tokens': 0},
    },
  },
  {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''},
  },
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'thinking_delta', 'thinking': 'private reasoning'},
  },
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'signature_delta', 'signature': 'opaque-signature'},
  },
  {'type': 'content_block_stop', 'index': 0},
  {
    'type': 'content_block_start',
    'index': 1,
    'content_block': {'type': 'text', 'text': ''},
  },
  {
    'type': 'content_block_delta',
    'index': 1,
    'delta': {'type': 'text_delta', 'text': '查找'},
  },
  {'type': 'content_block_stop', 'index': 1},
  {
    'type': 'content_block_start',
    'index': 2,
    'content_block': {
      'type': 'tool_use',
      'id': 'call1',
      'name': 'search_notes',
      'input': {},
    },
  },
  {
    'type': 'content_block_delta',
    'index': 2,
    'delta': {'type': 'input_json_delta', 'partial_json': '{"query":'},
  },
  {
    'type': 'content_block_delta',
    'index': 2,
    'delta': {'type': 'input_json_delta', 'partial_json': '"工作"}'},
  },
  {'type': 'content_block_stop', 'index': 2},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
    'usage': {'output_tokens': 8},
  },
  {'type': 'message_stop'},
];

List<Json> _roundFixture(ModelProtocol protocol, int round) {
  var encoded = jsonEncode(switch (protocol) {
    ModelProtocol.chatCompletions => chat(),
    ModelProtocol.responses => responses(),
    ModelProtocol.anthropic => anthropic(),
    ModelProtocol.local => throw ArgumentError.value(protocol),
  });
  for (final entry in {
    'call1': 'call$round',
    'resp1': 'resp$round',
    'rs1': 'rs$round',
    'msg1': 'msg$round',
    'fc1': 'fc$round',
  }.entries) {
    encoded = encoded.replaceAll('"${entry.key}"', '"${entry.value}"');
  }
  return (jsonDecode(encoded) as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

List<Json> _finalFixture(ModelProtocol protocol) => switch (protocol) {
  ModelProtocol.chatCompletions => [
    {
      'choices': [
        {
          'index': 0,
          'delta': {'content': '任务完成'},
          'finish_reason': 'stop',
        },
      ],
    },
    {
      'choices': [],
      'usage': {
        'prompt_tokens': 36,
        'completion_tokens': 4,
        'total_tokens': 40,
      },
    },
  ],
  ModelProtocol.responses => [
    {
      'type': 'response.output_text.delta',
      'sequence_number': 0,
      'item_id': 'msg-final',
      'output_index': 0,
      'content_index': 0,
      'delta': '任务完成',
    },
    {
      'type': 'response.completed',
      'sequence_number': 1,
      'response': {
        'id': 'resp-final',
        'object': 'response',
        'created_at': 1,
        'model': 'test-model',
        'status': 'completed',
        'output': [
          {
            'id': 'msg-final',
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': [
              {'type': 'output_text', 'text': '任务完成', 'annotations': []},
            ],
          },
        ],
        'usage': {'input_tokens': 36, 'output_tokens': 4, 'total_tokens': 40},
      },
    },
  ],
  ModelProtocol.anthropic => [
    {
      'type': 'message_start',
      'message': {
        'id': 'msg-final',
        'type': 'message',
        'role': 'assistant',
        'model': 'test-model',
        'content': [],
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {'input_tokens': 36, 'output_tokens': 0},
      },
    },
    {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    },
    {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': '任务完成'},
    },
    {'type': 'content_block_stop', 'index': 0},
    {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
      'usage': {'output_tokens': 4},
    },
    {'type': 'message_stop'},
  ],
  ModelProtocol.local => throw ArgumentError.value(protocol),
};

class _SearchNotesTool extends AgentTool {
  int calls = 0;

  @override
  ToolSpec get spec => const ToolSpec(
    name: 'search_notes',
    description: 'Search notes',
    schema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string'},
      },
      'required': ['query'],
      'additionalProperties': false,
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  ) async {
    await context.ensureActive();
    calls++;
    return ToolResult({'notes': [], 'query': arguments['query']});
  }
}

void main() {
  test('legacy profiles grow into a shared-key service atomically', () async {
    final directory = await Directory.systemTemp.createTemp('fknotes_models_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/profiles.json');
    const first = ModelProfile(
      id: 'old',
      name: 'Gateway',
      protocol: ModelProtocol.responses,
      endpoint: 'https://example.test/v1',
      model: 'old-model',
    );
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'selected': 'old',
        'requireApproval': true,
        'profiles': [first.toJson()],
      }),
    );
    final store = ModelProfileStore(file);
    final vault = TestVault();
    await vault.write(first.credentialId, 'shared-secret');
    final second = first.copyWith(
      id: 'new',
      serviceId: 'old',
      model: 'custom/not-in-catalog',
      capabilities: const ModelCapabilities(
        contextTokens: 1048576,
        maxOutputTokens: 393216,
      ),
    );
    await store.saveService('old', [first, second]);
    final reopened = ModelProfileStore(file);
    expect(await reopened.selectedId(), 'old');
    expect(await reopened.defaultRequireApproval(), isTrue);
    expect((await reopened.get('old')).binding, first.binding);
    final saved = await reopened.get('new');
    expect(saved.credentialId, first.credentialId);
    expect(await vault.read(saved.credentialId), 'shared-secret');
    expect(saved.defaultRunLimits.maxOutputTokens, 393216);
    expect((await reopened.get('old')).maxOutputTokens, 2048);
    final before = await file.readAsString();
    expect(before, isNot(contains('shared-secret')));
    await expectLater(
      store.saveService('old', [
        first,
        second.copyWith(endpoint: 'https://other.test'),
      ]),
      throwsA(isA<HarnessException>()),
    );
    expect(await file.readAsString(), before);
    await expectLater(
      store.saveService('old', [first, first]),
      throwsA(isA<HarnessException>()),
    );
    expect(await file.readAsString(), before);
    await store.select('new');
    await store.saveService('old', [first]);
    expect(await store.selectedId(), 'old');
    await store.deleteService('old');
    expect(await store.selectedId(), 'local');
    expect(await store.list(), hasLength(1));
  });

  test('batch model identifiers preserve aliases and remove duplicates', () {
    expect(
      ModelProfile.parseModelIds(
        ' model-a, provider/model-b\nmodel-a；custom:latest，alias-v2 ',
      ),
      ['model-a', 'provider/model-b', 'custom:latest', 'alias-v2'],
    );
    for (final value in [
      'invalid model',
      'a\u0000b',
      List.generate(101, (i) => 'm$i').join('\n'),
    ]) {
      expect(
        () => ModelProfile.parseModelIds(value),
        throwsA(isA<HarnessException>()),
      );
    }
  });

  for (final protocol in ModelProtocol.values.where(
    (p) => p != ModelProtocol.local,
  )) {
    test(
      '$protocol discovers IDs without inference and follows bounded cursors',
      () async {
        final vault = TestVault();
        final connection = ModelProfile(
          id: 'model',
          serviceId: 'service',
          name: '',
          protocol: protocol,
          endpoint: 'https://example.test/gateway/v1',
        );
        await vault.write(connection.credentialId, 'saved-key');
        final requests = <http.Request>[];
        final catalog = ModelCatalog(
          vault,
          clientFactory: () => MockClient((request) async {
            requests.add(request);
            expect(request.method, 'GET');
            expect(request.url.path, '/gateway/v1/models');
            expect(request.body, isEmpty);
            expect(request.followRedirects, isFalse);
            if (protocol == ModelProtocol.anthropic) {
              expect(request.headers['x-api-key'], 'draft-key');
              expect(request.headers['anthropic-version'], '2023-06-01');
              expect(request.headers.containsKey('authorization'), isFalse);
            } else {
              expect(request.headers['authorization'], 'Bearer draft-key');
            }
            return http.Response(
              jsonEncode(
                requests.length == 1
                    ? {
                        'data': [
                          {'id': 'a', 'display_name': 'Model A'},
                          {'id': 'a'},
                          {'id': 'b'},
                        ],
                        'has_more': true,
                        'last_id': 'b',
                      }
                    : {
                        'data': [
                          {'id': 'custom/alias'},
                          {'id': 'invalid id'},
                          {},
                        ],
                        'has_more': false,
                      },
              ),
              200,
            );
          }),
        );
        final models = await catalog.fetch(
          connection,
          CancellationToken(),
          apiKey: 'draft-key',
        );
        expect(models.map((m) => m.id), ['a', 'b', 'custom/alias']);
        expect(models.first.name, 'Model A');
        expect(requests.last.url.queryParameters['after_id'], 'b');
        expect(await vault.read(connection.credentialId), 'saved-key');
      },
    );
  }

  test(
    'catalog failures are safe and never expose response bodies or keys',
    () async {
      const connection = ModelProfile(
        id: 'p',
        name: '',
        protocol: ModelProtocol.chatCompletions,
        endpoint: 'https://example.test',
      );
      for (final status in [401, 404, 429, 302]) {
        final catalog = ModelCatalog(
          TestVault(),
          clientFactory: () => MockClient(
            (r) async => http.Response(
              'secret echoed by server',
              status,
              headers: {'location': 'https://other.test/models'},
            ),
          ),
        );
        await expectLater(
          catalog.fetch(connection, CancellationToken(), apiKey: 'secret'),
          throwsA(
            isA<HarnessException>()
                .having(
                  (e) => e.code,
                  'code',
                  {
                    401: 'authentication',
                    404: 'endpointNotFound',
                    429: 'rateLimited',
                    302: 'redirectDenied',
                  }[status],
                )
                .having((e) => e.message, 'message', isNot(contains('secret'))),
          ),
        );
      }
      for (final body in [
        'not-json',
        '{"data":{}}',
        '{"data":[{"id":"a"}],"has_more":true,"last_id":"a"}',
      ]) {
        var calls = 0;
        final catalog = ModelCatalog(
          TestVault(),
          clientFactory: () => MockClient((r) async {
            calls++;
            return http.Response(body, 200);
          }),
        );
        await expectLater(
          catalog.fetch(connection, CancellationToken(), apiKey: 'secret'),
          throwsA(
            isA<HarnessException>().having(
              (e) => e.code,
              'code',
              'modelCatalogFormat',
            ),
          ),
        );
        expect(calls, lessThanOrEqualTo(2));
      }
    },
  );

  test(
    'catalog cancellation and timeout finish even when a client hangs',
    () async {
      const connection = ModelProfile(
        id: 'p',
        name: '',
        protocol: ModelProtocol.responses,
        endpoint: 'https://example.test/v1',
      );
      for (final timeout in [false, true]) {
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        final catalog = ModelCatalog(
          TestVault(),
          timeout: timeout
              ? const Duration(milliseconds: 20)
              : const Duration(seconds: 5),
          clientFactory: () => MockClient((r) {
            entered.complete();
            return response.future;
          }),
        );
        final cancel = CancellationToken();
        final result = catalog.fetch(connection, cancel, apiKey: 'test');
        final check = expectLater(
          result,
          throwsA(
            isA<HarnessException>().having(
              (e) => e.code,
              'code',
              timeout ? 'requestTimeout' : 'cancelled',
            ),
          ),
        );
        await entered.future;
        if (!timeout) cancel.cancel();
        await check;
        response.complete(http.Response('{"data":[]}', 200));
      }
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test('keystore errors surface without resetting credentials', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'KeyStoreUnavailable');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await expectLater(
      const SystemCredentialVault().read('synthetic-task-key'),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.map((c) => c.method), ['read']);
    expect(calls.single.arguments['options']['resetOnError'], 'false');
  });
  final request = ModelRequest(
    messages: [AgentMessage(role: MessageRole.user, text: 'find notes')],
    tools: [],
    maxOutputTokens: 2000,
  );
  for (final protocol in [
    ModelProtocol.chatCompletions,
    ModelProtocol.responses,
    ModelProtocol.anthropic,
  ]) {
    test('${protocol.name} sends quoted conversation context', () async {
      final profile = ModelProfile(
        id: 'quoted-${protocol.name}',
        name: 'Quoted',
        protocol: protocol,
        endpoint: 'https://model.example/v1',
        model: 'test-model',
      );
      final vault = TestVault();
      await vault.write(profile.credentialId, 'secret');
      final fixture = switch (protocol) {
        ModelProtocol.chatCompletions => chat(),
        ModelProtocol.responses => responses(),
        ModelProtocol.anthropic => anthropic(),
        ModelProtocol.local => throw StateError('unreachable'),
      };
      final client = WireClient(sse(fixture));
      final adapter = OnlineModelAdapter(
        profile: profile,
        vault: vault,
        clientFactory: () => client,
      );
      await adapter
          .generate(
            ModelRequest(
              messages: [
                AgentMessage(
                  role: MessageRole.user,
                  text: '继续说明',
                  quotes: [
                    ConversationQuote(
                      id: 'quote-1',
                      sourceId: 'run:previous',
                      text: '被引用的跨段内容',
                      startOffset: 1,
                      endOffset: 9,
                      sourceLength: 30,
                    ),
                  ],
                ),
              ],
              tools: const [],
              maxOutputTokens: 2000,
            ),
            CancellationToken(),
          )
          .toList();

      final encoded = jsonEncode(client.body);
      expect(encoded, contains('被引用的跨段内容'));
      expect(encoded, contains('继续说明'));
    });
  }
  test('missing keys and unsupported search fail before HTTP', () async {
    var opened = 0;
    final profile = ModelProfile(
      id: 'no-key',
      name: 'No key',
      protocol: ModelProtocol.chatCompletions,
      endpoint: 'https://example.com/v1',
      model: 'm',
    );
    final adapter = OnlineModelAdapter(
      profile: profile,
      vault: TestVault(),
      clientFactory: () {
        opened++;
        return WireClient(sse(chat()));
      },
    );
    await expectLater(
      adapter.generate(request, CancellationToken()).toList(),
      throwsA(
        isA<HarnessException>().having(
          (e) => e.code,
          'code',
          'missingCredential',
        ),
      ),
    );
    await expectLater(
      adapter
          .generate(
            ModelRequest(
              messages: request.messages,
              tools: [],
              maxOutputTokens: 100,
              webSearch: true,
            ),
            CancellationToken(),
          )
          .toList(),
      throwsA(
        isA<HarnessException>().having(
          (e) => e.code,
          'code',
          'searchUnsupported',
        ),
      ),
    );
    expect(opened, 0);
  });

  for (final protocol in [ModelProtocol.responses, ModelProtocol.anthropic]) {
    test(
      '${protocol.name}: explicit server search and custom tools coexist',
      () async {
        final p = ModelProfile(
          id: 'search',
          name: 'Search',
          protocol: protocol,
          endpoint: 'https://example.com/v1',
          model: 'm',
          capabilities: const ModelCapabilities(webSearch: true),
        );
        final vault = TestVault();
        await vault.write(p.credentialId, 'test');
        final client = WireClient(
          sse(protocol == ModelProtocol.responses ? responses() : anthropic()),
        );
        await OnlineModelAdapter(
              profile: p,
              vault: vault,
              clientFactory: () => client,
            )
            .generate(
              ModelRequest(
                messages: request.messages,
                tools: [
                  ToolSpec(
                    name: 'search_notes',
                    description: 'Search',
                    schema: {
                      'type': 'object',
                      'properties': {
                        'query': {'type': 'string'},
                      },
                      'required': ['query'],
                    },
                  ),
                ],
                maxOutputTokens: 2000,
                webSearch: true,
              ),
              CancellationToken(),
            )
            .drain<void>();
        expect((client.body!['tools'] as List).length, 2);
        expect(client.body!['tools'].first['name'], 'search_notes');
        expect(client.body!['tools'].last['type'], startsWith('web_search'));
      },
    );
  }

  test(
    'DeepSeek Responses replays only supported output fields after tools',
    () async {
      final profile = ModelProfile(
        id: 'deepseek',
        name: 'DeepSeek',
        protocol: ModelProtocol.responses,
        endpoint: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        capabilities: const ModelCapabilities(webSearch: true),
        thinking: true,
        statelessResponses: false,
      );
      final vault = TestVault();
      await vault.write(profile.credentialId, 'test-key');
      final clients = <WireClient>[];
      final adapter = OnlineModelAdapter(
        profile: profile,
        vault: vault,
        clientFactory: () {
          final client = WireClient(sse(deepSeekResponses()));
          clients.add(client);
          return client;
        },
      );
      final firstEvents = await adapter
          .generate(
            ModelRequest(
              messages: request.messages,
              tools: request.tools,
              maxOutputTokens: 4096,
              webSearch: true,
            ),
            CancellationToken(),
          )
          .toList();
      expect(
        firstEvents.whereType<ModelReasoning>().map((e) => e.text).join(),
        '先检索并读取来源。',
      );
      final searchActivities = firstEvents
          .whereType<ModelActivity>()
          .where((event) => event.kind == 'webSearch')
          .toList();
      expect(searchActivities.last.detail, '近期新闻、今日重点新闻');
      expect(searchActivities.last.completed, isTrue);
      expect(searchActivities.last.data, {
        'action': 'search',
        'resultDisclosure': 'providerManaged',
      });
      expect(clients.single.body!['include'], [
        'web_search_call.results',
        'web_search_call.action.sources',
      ]);
      final done = firstEvents.whereType<ModelCompleted>().single;
      expect(done.message.calls.map((call) => call.id), ['fetch-1', 'fetch-2']);
      expect(done.message.sources.single['url'], 'https://example.com/news');
      expect(done.message.sources.single['providerCallId'], 'ws-deepseek');
      expect(done.message.sources.single['url'], isNot(contains('ws_call_id')));

      await adapter
          .generate(
            ModelRequest(
              messages: [
                ...request.messages,
                done.message,
                AgentMessage(
                  role: MessageRole.tool,
                  toolCallId: 'fetch-1',
                  toolName: 'web_fetch',
                  text: '{"content":"one"}',
                ),
                AgentMessage(
                  role: MessageRole.tool,
                  toolCallId: 'fetch-2',
                  toolName: 'web_fetch',
                  text: '{"content":"two"}',
                ),
              ],
              tools: request.tools,
              maxOutputTokens: 4096,
              webSearch: true,
            ),
            CancellationToken(),
          )
          .drain<void>();

      final body = clients.last.body!;
      final input = (body['input'] as List).cast<Json>();
      expect(input.where((item) => item['type'] == 'reasoning').single, {
        'type': 'reasoning',
        'content': [
          {'type': 'reasoning_text', 'text': '先检索并读取来源。'},
        ],
      });
      expect(input.where((item) => item['type'] == 'web_search_call').single, {
        'type': 'web_search_call',
        'id': 'ws-deepseek',
        'status': 'completed',
        'action': {
          'type': 'search',
          'queries': ['近期新闻', '今日重点新闻, ws_call_id=ws-deepseek'],
        },
      });
      expect(input.where((item) => item['type'] == 'message').last, {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': '正在整理。'},
        ],
      });
      final calls = input
          .where((item) => item['type'] == 'function_call')
          .toList();
      expect(calls, hasLength(2));
      expect(calls.every((call) => !call.containsKey('id')), isTrue);
      expect(calls.every((call) => !call.containsKey('status')), isTrue);
      expect(
        input
            .where((item) => item['type'] == 'function_call_output')
            .map((item) => item['call_id']),
        ['fetch-1', 'fetch-2'],
      );
      expect(
        (body['tools'] as List).every(
          (tool) => !(tool as Map).containsKey('strict'),
        ),
        isTrue,
      );
    },
  );

  test('Responses requests, bounds and exposes web search evidence', () async {
    final profile = ModelProfile(
      id: 'responses-search-results',
      name: 'Responses search results',
      protocol: ModelProtocol.responses,
      endpoint: 'https://example.com/v1',
      model: 'test-model',
      statelessResponses: true,
      capabilities: const ModelCapabilities(webSearch: true),
    );
    final vault = TestVault();
    await vault.write(profile.credentialId, 'test-key');
    final client = WireClient(sse(responsesWithWebSearchResults()));
    final events =
        await OnlineModelAdapter(
              profile: profile,
              vault: vault,
              clientFactory: () => client,
            )
            .generate(
              ModelRequest(
                messages: request.messages,
                tools: const [],
                maxOutputTokens: 4096,
                webSearch: true,
              ),
              CancellationToken(),
            )
            .toList();

    expect(client.body!['include'], [
      'reasoning.encrypted_content',
      'web_search_call.results',
      'web_search_call.action.sources',
    ]);
    final activity = events
        .whereType<ModelActivity>()
        .where((event) => event.kind == 'webSearch')
        .last;
    expect(activity.detail, 'current AI news');
    expect(activity.completed, isTrue);
    expect(activity.data['action'], 'search');
    expect(activity.data['resultDisclosure'], 'available');
    final results = (activity.data['results'] as List).cast<Json>();
    expect(results, hasLength(2));
    expect(results.first, {
      'url': 'https://example.com/one',
      'title': 'Result one',
      'snippet': 'First result summary',
      'publishedAt': '2026-08-30',
    });
    expect(results.last['url'], 'https://example.com/two');
    expect((results.last['snippet'] as String).runes.length, 801);
    expect(jsonEncode(activity.data), isNot(contains('ws_call_id')));
    expect(jsonEncode(activity.data), isNot(contains('javascript:')));
  });

  test('Anthropic exposes lightweight web search result blocks', () async {
    final profile = ModelProfile(
      id: 'anthropic-search-results',
      name: 'Anthropic search results',
      protocol: ModelProtocol.anthropic,
      endpoint: 'https://example.com/anthropic',
      model: 'test-model',
      capabilities: const ModelCapabilities(webSearch: true),
    );
    final vault = TestVault();
    await vault.write(profile.credentialId, 'test-key');
    final client = WireClient(sse(anthropicWebSearchResults()));
    final events =
        await OnlineModelAdapter(
              profile: profile,
              vault: vault,
              clientFactory: () => client,
            )
            .generate(
              ModelRequest(
                messages: request.messages,
                tools: const [],
                maxOutputTokens: 4096,
                webSearch: true,
              ),
              CancellationToken(),
            )
            .toList();

    final activity = events
        .whereType<ModelActivity>()
        .where((event) => event.kind == 'webSearch')
        .last;
    expect(activity.completed, isTrue);
    expect(activity.data['action'], 'search');
    expect(activity.data['resultDisclosure'], 'available');
    expect(activity.data['results'], [
      {
        'url': 'https://example.com/anthropic',
        'title': 'Anthropic result',
        'publishedAt': '2 hours ago',
      },
    ]);
    expect(
      jsonEncode(activity.data),
      isNot(contains('must-not-be-persisted-as-evidence')),
    );
  });

  for (final protocol in [
    ModelProtocol.chatCompletions,
    ModelProtocol.responses,
    ModelProtocol.anthropic,
  ]) {
    final fixture = switch (protocol) {
      ModelProtocol.chatCompletions => chat(),
      ModelProtocol.responses => responses(),
      _ => anthropic(),
    };
    test(
      '${protocol.name}: full tools, usage, hidden protocol and stateless continuation',
      () async {
        final profile = ModelProfile(
          id: 'test',
          name: 'Test',
          protocol: protocol,
          endpoint: 'https://model.example/v1',
          model: 'test-model',
          capabilities: const ModelCapabilities(
            contextTokens: 1048576,
            maxOutputTokens: 393216,
          ),
        );
        final vault = TestVault();
        await vault.write(profile.credentialId, 'secret-for-test');
        final clients = <WireClient>[];
        final adapter = OnlineModelAdapter(
          profile: profile,
          vault: vault,
          clientFactory: () {
            final c = WireClient(sse(fixture));
            clients.add(c);
            return c;
          },
        );
        final events = await adapter
            .generate(
              ModelRequest(
                messages: request.messages,
                tools: request.tools,
                maxOutputTokens: profile.maxOutputTokens,
              ),
              CancellationToken(),
            )
            .toList();
        final outputField = switch (protocol) {
          ModelProtocol.chatCompletions => 'max_completion_tokens',
          ModelProtocol.responses => 'max_output_tokens',
          _ => 'max_tokens',
        };
        expect(clients.single.body![outputField], 393216);
        final done = events.whereType<ModelCompleted>().single;
        expect(events.whereType<ModelText>().map((e) => e.text).join(), '查找');
        expect(
          events.whereType<ModelReasoning>().map((e) => e.text).join(),
          'private reasoning',
        );
        expect(done.message.calls.single.arguments, {'query': '工作'});
        expect(done.message.calls.single.id, 'call1');
        expect(done.inputTokens, 20);
        expect(done.outputTokens, 8);
        expect(done.message.text, '查找');
        expect(clients.single.closed, isTrue);
        expect(clients.single.request!.followRedirects, isFalse);
        expect(
          jsonEncode(done.message.toJson()),
          isNot(contains('secret-for-test')),
        );
        await adapter
            .generate(
              ModelRequest(
                messages: [
                  ...request.messages,
                  done.message,
                  AgentMessage(
                    role: MessageRole.tool,
                    toolCallId: 'call1',
                    toolName: 'search_notes',
                    text: '{"notes":[]}',
                  ),
                ],
                tools: [],
                maxOutputTokens: 1000,
              ),
              CancellationToken(),
            )
            .drain<void>();
        final body = clients.last.body!;
        switch (protocol) {
          case ModelProtocol.chatCompletions:
            expect(
              body['messages'][1]['reasoning_content'],
              'private reasoning',
            );
            expect(body['messages'][2]['tool_call_id'], 'call1');
          case ModelProtocol.responses:
            expect(body['store'], false);
            expect(body.containsKey('previous_response_id'), false);
            expect(body['input'][1]['encrypted_content'], 'opaque-encrypted');
            expect(body['input'].last['call_id'], 'call1');
            expect(
              done.message.sources.single['url'],
              'https://example.com/source',
            );
          case ModelProtocol.anthropic:
            expect(
              body['messages'][1]['content'][0]['signature'],
              'opaque-signature',
            );
            expect(body['messages'].last['content'][0]['tool_use_id'], 'call1');
          case ModelProtocol.local:
            break;
        }
        // A changed provider/model must never receive opaque continuation fields.
        final other = ModelProfile(
          id: 'test',
          name: 'Test',
          protocol: protocol,
          endpoint: 'https://model.example/v1',
          model: 'other',
        );
        final capture = WireClient(sse(fixture));
        await OnlineModelAdapter(
              profile: other,
              vault: vault,
              clientFactory: () => capture,
            )
            .generate(
              ModelRequest(
                messages: [...request.messages, done.message],
                tools: [],
                maxOutputTokens: 1000,
              ),
              CancellationToken(),
            )
            .drain<void>();
        expect(jsonEncode(capture.body), isNot(contains('private reasoning')));
        expect(jsonEncode(capture.body), isNot(contains('opaque-')));
      },
    );

    test(
      '${protocol.name}: cancellation closes an idle HTTP transport',
      () async {
        final controller = StreamController<List<int>>();
        final client = WireClient(
          controller.stream,
          onClose: () {
            unawaited(controller.close());
          },
        );
        final profile = ModelProfile(
          id: 'cancel',
          name: 'Cancel',
          protocol: protocol,
          endpoint: 'https://model.example/v1',
          model: 'test',
        );
        final vault = TestVault();
        await vault.write(profile.credentialId, 'test');
        final token = CancellationToken();
        final result = OnlineModelAdapter(
          profile: profile,
          vault: vault,
          clientFactory: () => client,
        ).generate(request, token).toList();
        final expectation = expectLater(
          result,
          throwsA(
            isA<HarnessException>().having((e) => e.code, 'code', 'cancelled'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        token.cancel();
        await expectation;
        expect(client.closed, true);
      },
    );

    test(
      '${protocol.name}: harness preserves two tool exchanges and retries a transient round',
      () async {
        final profile = ModelProfile(
          id: 'react-${protocol.name}',
          name: 'ReAct',
          protocol: protocol,
          endpoint: 'https://model.example/v1',
          model: 'test-model',
          capabilities: const ModelCapabilities(
            contextTokens: 65536,
            maxOutputTokens: 1024,
          ),
        );
        final vault = TestVault();
        await vault.write(profile.credentialId, 'test-key');
        final clients = <WireClient>[];
        final adapter = OnlineModelAdapter(
          profile: profile,
          vault: vault,
          clientFactory: () {
            final index = clients.length;
            final client = switch (index) {
              0 => WireClient(sse(_roundFixture(protocol, 1))),
              1 => WireClient(
                Stream.value(utf8.encode('temporary provider failure')),
                status: 503,
              ),
              2 => WireClient(sse(_roundFixture(protocol, 2))),
              3 => WireClient(sse(_finalFixture(protocol))),
              _ => throw StateError('Unexpected model request $index'),
            };
            clients.add(client);
            return client;
          },
        );
        final tool = _SearchNotesTool();
        final store = MemoryRunStore();
        final harness = HarnessRuntime(
          store: store,
          resolveModel: (_) async => adapter,
          authorize: (run, {tool, sendingToModel = false}) async {},
          tools: [tool],
          retrySleep: (duration, token) async => token.check(),
        );
        addTearDown(harness.close);

        final id = await harness.start(
          TaskRequest(
            sessionId: 'session-${protocol.name}',
            input: '连续查找两次再回答',
            profileId: profile.id,
            noteStoreEpoch: 'db-1',
            scope: const RunScope(online: true, readNotes: true),
            limits: const RunLimits(
              maxRequests: 6,
              maxTokens: 65536,
              maxOutputTokens: 1024,
              maxRetries: 1,
            ),
          ),
        );
        await harness.settle(id);
        final run = (await harness.get(id))!;

        expect(run.status, RunStatus.completed);
        expect(run.answer, '任务完成');
        expect(run.requestCount, 4);
        expect(run.roundCount, 3);
        expect(run.toolCallCount, 2);
        expect(tool.calls, 2);
        expect(run.messages.map((message) => message.role), [
          MessageRole.user,
          MessageRole.assistant,
          MessageRole.tool,
          MessageRole.assistant,
          MessageRole.tool,
          MessageRole.assistant,
        ]);
        expect(
          run.messages
              .where((message) => message.role == MessageRole.assistant)
              .expand((message) => message.calls)
              .map((call) => call.id),
          ['call1', 'call2'],
        );
        expect(
          run.messages
              .where((message) => message.role == MessageRole.tool)
              .map((message) => message.toolCallId),
          ['call1', 'call2'],
        );
        expect(
          run.events
              .where((event) => event.type == 'retry')
              .map((event) => event.data),
          [
            {'attempt': 1, 'delayMs': 250, 'code': 'serviceUnavailable'},
          ],
        );

        final body = clients.last.body!;
        switch (protocol) {
          case ModelProtocol.chatCompletions:
            final messages = (body['messages'] as List).cast<Json>();
            expect(
              messages
                  .expand((message) => message['tool_calls'] as List? ?? [])
                  .map((call) => (call as Map)['id']),
              ['call1', 'call2'],
            );
            expect(
              messages
                  .where((message) => message['role'] == 'tool')
                  .map((message) => message['tool_call_id']),
              ['call1', 'call2'],
            );
          case ModelProtocol.responses:
            final input = (body['input'] as List).cast<Json>();
            expect(
              input
                  .where((item) => item['type'] == 'function_call')
                  .map((item) => item['call_id']),
              ['call1', 'call2'],
            );
            expect(
              input
                  .where((item) => item['type'] == 'function_call_output')
                  .map((item) => item['call_id']),
              ['call1', 'call2'],
            );
          case ModelProtocol.anthropic:
            final messages = (body['messages'] as List).cast<Json>();
            final blocks = messages
                .expand((message) => message['content'] as List)
                .cast<Json>();
            expect(
              blocks
                  .where((block) => block['type'] == 'tool_use')
                  .map((block) => block['id']),
              ['call1', 'call2'],
            );
            expect(
              blocks
                  .where((block) => block['type'] == 'tool_result')
                  .map((block) => block['tool_use_id']),
              ['call1', 'call2'],
            );
          case ModelProtocol.local:
            fail('Local protocol is not part of this matrix.');
        }
      },
    );
  }

  test('Chat output limit parameter is selected automatically', () async {
    for (final entry in [
      (
        endpoint: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
        field: 'max_tokens',
      ),
      (
        endpoint: 'https://gateway.example/v1',
        model: 'deepseek-reasoner',
        field: 'max_tokens',
      ),
      (
        endpoint: 'https://api.openai.com/v1',
        model: 'gpt-5',
        field: 'max_completion_tokens',
      ),
    ]) {
      final profile = ModelProfile(
        id: 'automatic',
        name: 'Automatic',
        protocol: ModelProtocol.chatCompletions,
        endpoint: entry.endpoint,
        model: entry.model,
      );
      final vault = TestVault();
      await vault.write(profile.credentialId, 'test');
      final client = WireClient(sse(chat(finish: 'stop')));
      await OnlineModelAdapter(
        profile: profile,
        vault: vault,
        clientFactory: () => client,
      ).generate(request, CancellationToken()).drain<void>();
      expect(client.body![entry.field], request.maxOutputTokens);
      expect(
        client.body!.containsKey(
          entry.field == 'max_tokens' ? 'max_completion_tokens' : 'max_tokens',
        ),
        isFalse,
      );
    }
  });

  test(
    'incomplete and malformed calls never become executable tools',
    () async {
      final p = ModelProfile(
        id: 'test',
        name: 'Test',
        protocol: ModelProtocol.chatCompletions,
        endpoint: 'https://model.example/v1',
        model: 'm',
      );
      final vault = TestVault();
      await vault.write(p.credentialId, 'test');
      for (final fixture in [
        chat(complete: false),
        chat(arguments: '{"bad":'),
      ]) {
        await expectLater(
          OnlineModelAdapter(
            profile: p,
            vault: vault,
            clientFactory: () => WireClient(sse(fixture)),
          ).generate(request, CancellationToken()).toList(),
          throwsA(isA<HarnessException>()),
        );
      }
      final events = await OnlineModelAdapter(
        profile: p,
        vault: vault,
        clientFactory: () =>
            WireClient(sse(chat(arguments: '{"bad":', finish: 'length'))),
      ).generate(request, CancellationToken()).toList();
      expect(events.whereType<ModelCompleted>().single.message.calls, isEmpty);
      expect(events.whereType<ModelCompleted>().single.finishReason, 'length');
    },
  );

  test(
    'HTTP errors are redacted, classified, not retried; redirects rejected',
    () async {
      final p = ModelProfile(
        id: 'test',
        name: 'Test',
        protocol: ModelProtocol.chatCompletions,
        endpoint: 'https://model.example/v1',
        model: 'm',
      );
      final vault = TestVault();
      await vault.write(p.credentialId, 'secret-key');
      const classifications = {
        302: ('redirectDenied', false),
        400: ('invalidRequest', false),
        401: ('authentication', false),
        404: ('endpointNotFound', false),
        408: ('requestTimeout', true),
        413: ('contextOverflow', false),
        429: ('rateLimited', true),
        500: ('serviceUnavailable', true),
        504: ('requestTimeout', true),
      };
      for (final MapEntry(key: status, value: expected)
          in classifications.entries) {
        var requests = 0;
        final adapter = OnlineModelAdapter(
          profile: p,
          vault: vault,
          clientFactory: () {
            requests++;
            return WireClient(
              Stream.value(utf8.encode('secret-key private note')),
              status: status,
            );
          },
        );
        await expectLater(
          adapter.generate(request, CancellationToken()).toList(),
          throwsA(
            isA<HarnessException>()
                .having((e) => e.message, 'redacted', isNot(contains('secret')))
                .having((e) => e.code, 'code', expected.$1)
                .having((e) => e.retryable, 'retryable', expected.$2),
          ),
        );
        expect(requests, 1);
      }
      final client = WireClient(const Stream.empty());
      final guarded = AgentHttpClient(
        client,
        Uri.parse('https://model.example'),
      );
      await expectLater(
        guarded.send(http.Request('POST', Uri.parse('https://other.example'))),
        throwsA(isA<HarnessException>()),
      );
      expect(client.request, isNull);
    },
  );

  test(
    'profile settings persist without credentials and reject unsafe endpoints',
    () async {
      final dir = await Directory.systemTemp.createTemp('fknotes-profiles');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/profiles.json');
      final store = ModelProfileStore(file);
      expect(await store.defaultRequireApproval(), isFalse);
      await store.setDefaultRequireApproval(true);
      final p = ModelProfile(
        id: 'mine',
        name: 'My model',
        protocol: ModelProtocol.responses,
        endpoint: 'https://example.com/v1/responses/',
        model: 'm',
        capabilities: const ModelCapabilities(
          contextTokens: 1048576,
          maxOutputTokens: 393216,
        ),
      );
      await store.save(p);
      await store.select(p.id);
      expect(
        (await ModelProfileStore(file).get('mine')).baseUri.toString(),
        'https://example.com/v1',
      );
      expect(await store.selectedId(), 'mine');
      final reloaded = await ModelProfileStore(file).get('mine');
      expect(reloaded.capabilities.contextTokens, 1048576);
      expect(reloaded.maxOutputTokens, 393216);
      expect(reloaded.defaultRunLimits.maxTokens, greaterThan(393216));
      expect(await ModelProfileStore(file).defaultRequireApproval(), isTrue);
      expect(await file.readAsString(), isNot(contains('apiKey')));
      await store.delete('mine');
      expect(await store.selectedId(), 'local');
      expect(await store.defaultRequireApproval(), isTrue);
      for (final endpoint in [
        'http://public.example',
        'https://user:key@example.com',
        'https://example.com?key=secret',
      ]) {
        expect(
          () => ModelProfile(
            id: 'x',
            name: 'X',
            protocol: ModelProtocol.responses,
            endpoint: endpoint,
            model: 'm',
          ).validate(),
          throwsA(isA<HarnessException>()),
        );
      }
    },
  );

  test(
    'long output gets a bounded SSE allowance above the normal 16MB limit',
    () async {
      const profile = ModelProfile(
        id: 'long',
        name: 'Long',
        protocol: ModelProtocol.chatCompletions,
        endpoint: 'https://example.test/v1',
        model: 'long',
        capabilities: ModelCapabilities(
          contextTokens: 1048576,
          maxOutputTokens: 393216,
        ),
      );
      final vault = TestVault();
      await vault.write(profile.credentialId, 'synthetic-key');
      Stream<List<int>> wire() async* {
        final comment = utf8.encode(':${' ' * 16384}\n\n');
        for (var i = 0; i < 1100; i++) {
          yield comment;
        }
        yield* sse(chat());
      }

      for (final output in [2000, 393216]) {
        final adapter = OnlineModelAdapter(
          profile: profile,
          vault: vault,
          clientFactory: () => WireClient(wire()),
        );
        final result = adapter
            .generate(
              ModelRequest(
                messages: request.messages,
                tools: [],
                maxOutputTokens: output,
              ),
              CancellationToken(),
            )
            .toList();
        if (output == 2000) {
          await expectLater(
            result,
            throwsA(
              isA<HarnessException>().having(
                (e) => e.code,
                'code',
                'responseSize',
              ),
            ),
          );
        } else {
          expect((await result).whereType<ModelCompleted>(), hasLength(1));
        }
      }
    },
  );

  test(
    'token lengths accept explicit K/M units and reject invalid windows',
    () {
      for (final entry in {
        '1M': 1048576,
        '384k': 393216,
        '1.5K': 1536,
        '1,048,576': 1048576,
      }.entries) {
        expect(ModelProfile.parseTokenCount(entry.key), entry.value);
      }
      for (final invalid in ['0', '-1', 'NaN', '1e9', '0.1', '3M']) {
        expect(ModelProfile.parseTokenCount(invalid), isNull);
      }
      for (final output in [0, 16384, 32768]) {
        expect(
          () => ModelProfile(
            id: 'invalid',
            name: 'Invalid',
            protocol: ModelProtocol.responses,
            endpoint: 'https://example.test/v1',
            model: 'test',
            capabilities: ModelCapabilities(maxOutputTokens: output),
          ).validate(),
          throwsA(
            isA<HarnessException>().having(
              (e) => e.code,
              'code',
              'invalidModelLimits',
            ),
          ),
        );
      }
    },
  );

  test(
    'local template accepts complete JSON only and does not execute ordinary text',
    () {
      expect(
        LocalModelAdapter.parseToolCalls('I might search_notes later'),
        isEmpty,
      );
      expect(
        LocalModelAdapter.parseToolCalls(
          '<fknotes_tool>{"name":"search_notes","arguments":{"query":"x"}}</fknotes_tool>',
        ).single.arguments,
        {'query': 'x'},
      );
      for (final raw in [
        '<fknotes_tool>{',
        '<fknotes_tool>{"name":"search_notes","arguments":[]}</fknotes_tool>',
      ]) {
        expect(
          () => LocalModelAdapter.parseToolCalls(raw),
          throwsA(isA<HarnessException>()),
        );
      }
    },
  );
}

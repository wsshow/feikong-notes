import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fknotes/agent/mcp_tools.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'agent_model_adapter_test.dart' show TestVault;

void main() {
  test(
    'HTTP MCP discovery, approval, scope and uncertain external result share the harness',
    () async {
      var effects = 0;
      var failAfterEffect = false;
      final server = mcp.StreamableMcpServer(
        host: '127.0.0.1',
        port: 0,
        path: '/mcp',
        serverFactory: (_) {
          final instance = mcp.McpServer(
            const mcp.Implementation(name: 'test-server', version: '1.0.0'),
          );
          instance.registerTool(
            'change_external',
            description: 'External action',
            annotations: const mcp.ToolAnnotations(readOnlyHint: true),
            inputSchema: mcp.JsonSchema.object(
              properties: {'value': mcp.JsonSchema.string()},
              required: ['value'],
            ),
            callback: (args, _) async {
              effects++;
              if (failAfterEffect) throw StateError('server-private-error');
              return mcp.CallToolResult.fromContent([
                mcp.TextContent(text: 'saved ${args['value']}'),
              ]);
            },
          );
          return instance;
        },
      );
      await server.start();
      addTearDown(server.stop);
      final vault = TestVault();
      final gateway = McpGateway(vault);
      var config = McpServerConfig(
        id: 'local_test',
        name: 'Test server',
        endpoint: 'http://127.0.0.1:${server.boundPort}/mcp',
      );
      final definitions = await gateway.discover(config, CancellationToken());
      expect(definitions.single.name, 'change_external');
      expect(
        definitions.single.trustedReadOnly,
        false,
      ); // remote hints are not grants
      expect(effects, 0);
      config = McpServerConfig(
        id: config.id,
        name: config.name,
        endpoint: config.endpoint,
        tools: definitions,
      );
      final tool = RemoteMcpTool(
        server: config,
        definition: definitions.single,
        gateway: gateway,
        currentConfig: (_) async => config,
      );
      final store = MemoryRunStore();
      final runtime = HarnessRuntime(
        store: store,
        resolveModel: (_) async => _McpModel(tool.spec.name),
        authorize: (r, {tool, sendingToModel = false}) async {},
        tools: [tool],
      );
      addTearDown(runtime.close);
      final scope = RunScope(
        requireApproval: true,
        networkTools: true,
        externalWrites: true,
        networkBindings: {config.binding},
      );
      Future<String> start(RunScope s) async {
        final id = await runtime.start(
          TaskRequest(
            sessionId: 's',
            input: 'run tool',
            profileId: 'local',
            noteStoreEpoch: 'e',
            scope: s,
          ),
        );
        await runtime.settle(id);
        return id;
      }

      await start(const RunScope());
      expect(effects, 0);
      final id = await start(scope);
      final pending = (await runtime.get(id))!.pending.single;
      expect((await runtime.get(id))!.status, RunStatus.waitingApproval);
      expect(effects, 0);
      await runtime.approve(
        pending.approvalId!,
        accept: true,
        expectedDigest: pending.preview!.digest,
      );
      await runtime.settle(id);
      expect((await runtime.get(id))!.status, RunStatus.completed);
      expect(effects, 1);
      expect(scope.readOnly().externalWrites, false);
      final automaticScope = RunScope.fromJson({
        ...scope.toJson(),
        'requireApproval': false,
      });
      final automatic = await start(automaticScope);
      expect((await runtime.get(automatic))!.status, RunStatus.completed);
      expect(
        (await runtime.get(automatic))!.actions.single['approvalMode'],
        'automatic',
      );
      expect(effects, 2);
      failAfterEffect = true;
      final uncertain = await start(automaticScope);
      expect(
        effects,
        3,
      ); // no SDK/client replay after an unknown external effect
      final unknown = (await runtime.get(uncertain))!;
      expect(unknown.status, RunStatus.needsReconciliation);
      expect(unknown.errorMessage, isNot(contains('server-private-error')));
      // Changing endpoint/tool trust invalidates an already granted binding.
      config = McpServerConfig(
        id: config.id,
        name: 'Changed',
        endpoint: config.endpoint,
        tools: definitions,
      );
      await expectLater(
        tool.prepare(
          ToolContext(
            run: unknown,
            operationId: 'p',
            argumentsDigest: 'd',
            cancel: CancellationToken(),
            ensureActive: () async {},
          ),
          {'value': 'x'},
        ),
        throwsA(
          isA<HarnessException>().having(
            (e) => e.code,
            'code',
            'mcpPermission',
          ),
        ),
      );
    },
  );

  test(
    'MCP configuration excludes secrets and refuses unsafe schemas/endpoints',
    () async {
      final directory = await Directory.systemTemp.createTemp('fknotes-mcp');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/mcp.json');
      final store = McpConfigStore(file);
      final config = McpServerConfig(
        id: 'one',
        name: 'Server',
        endpoint: 'https://example.com/mcp',
        tools: [
          McpToolDefinition(
            name: 'read',
            description: 'Read',
            schema: {'type': 'object', 'properties': {}},
            trustedReadOnly: true,
          ),
        ],
      );
      await store.save(config);
      expect((await store.get('one'))!.binding, config.binding);
      expect(
        jsonDecode(
          await file.readAsString(),
        )['servers'][0].containsKey('token'),
        false,
      );
      expect(
        () => McpToolDefinition(
          name: 'bad',
          description: '',
          schema: {'type': 'object', r'$ref': 'https://other.example/schema'},
        ).validate(),
        throwsA(isA<HarnessException>()),
      );
      expect(
        () => const McpServerConfig(
          id: 'bad',
          name: 'Bad',
          endpoint: 'http://public.example/mcp',
        ).validate(),
        throwsA(isA<HarnessException>()),
      );
      await store.delete('one');
      expect(await store.list(), isEmpty);
    },
  );

  test('cancelling MCP discovery closes idle transport', () async {
    final waiting = StreamController<List<int>>();
    final client = _IdleClient(waiting);
    final gateway = McpGateway(TestVault(), clientFactory: () => client);
    final cancel = CancellationToken();
    final result = gateway.discover(
      const McpServerConfig(
        id: 'one',
        name: 'One',
        endpoint: 'https://example.com/mcp',
      ),
      cancel,
    );
    final expectation = expectLater(
      result,
      throwsA(
        isA<HarnessException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    await client.started.future;
    cancel.cancel();
    await expectation;
    expect(client.closed, true);
  });
}

class _McpModel implements ModelPort {
  final String name;
  _McpModel(this.name);
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
    yield ModelCompleted(
      AgentMessage(
        role: MessageRole.assistant,
        text: 'result',
        calls: request.messages.any((m) => m.role == MessageRole.tool)
            ? []
            : [
                ToolCall(id: 'one', name: name, arguments: {'value': 'test'}),
              ],
      ),
    );
  }
}

class _IdleClient extends http.BaseClient {
  final StreamController<List<int>> waiting;
  _IdleClient(this.waiting);
  final started = Completer<void>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    if (!started.isCompleted) started.complete();
    return http.StreamedResponse(
      waiting.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
    unawaited(waiting.close());
  }
}

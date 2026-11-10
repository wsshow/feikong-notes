import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import 'agent_http_client.dart';
import 'credential_vault.dart';
import 'model_profile.dart';

class McpToolDefinition {
  final String name;
  final String description;
  final Json schema;

  /// Explicit user trust, never inferred from server annotations.
  final bool trustedReadOnly;
  McpToolDefinition({
    required this.name,
    required this.description,
    required this.schema,
    this.trustedReadOnly = false,
  });
  Json toJson() => {
    'name': name,
    'description': description,
    'schema': schema,
    'trustedReadOnly': trustedReadOnly,
  };
  factory McpToolDefinition.fromJson(Json j) => McpToolDefinition(
    name: j['name'] as String,
    description: j['description'] as String,
    schema: Map<String, dynamic>.from(j['schema'] as Map),
    trustedReadOnly: j['trustedReadOnly'] == true,
  );
  void validate() {
    if (name.isEmpty ||
        name.length > 128 ||
        description.length > 4000 ||
        schema['type'] != 'object' ||
        jsonEncode(schema).length > 32000) {
      throw const HarnessException(
        'mcpSchema',
        'Unsupported or oversized MCP tool schema.',
      );
    }
    void visit(dynamic value, int depth) {
      if (depth > 24) {
        throw const HarnessException(
          'mcpSchema',
          'MCP schema nesting is too deep.',
        );
      }
      if (value is Map) {
        if (value.containsKey(r'$ref') || value.containsKey(r'$dynamicRef')) {
          throw const HarnessException(
            'mcpSchema',
            'MCP schemas must be self-contained without references.',
          );
        }
        for (final child in value.values) {
          visit(child, depth + 1);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child, depth + 1);
        }
      }
    }

    visit(schema, 0);
  }
}

class McpServerConfig {
  final String id;
  final String name;
  final String endpoint;
  final List<McpToolDefinition> tools;
  final bool enabled;
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    this.tools = const [],
    this.enabled = true,
  });
  String get credentialId => 'fknotes.agent.mcp.$id';
  String get binding => contentDigest(toJson());
  Uri get uri {
    // Share the TLS/loopback and credential-free URL policy, preserving the
    // exact MCP path rather than treating it as an inference base path.
    ModelProfile(
      id: id,
      name: name,
      protocol: ModelProtocol.responses,
      endpoint: endpoint,
      model: 'mcp',
    ).baseUri;
    return Uri.parse(endpoint.trim());
  }

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 120 ||
        tools.length > 32 ||
        tools.map((t) => t.name).toSet().length != tools.length) {
      throw const HarnessException('mcpConfig', 'Invalid MCP configuration.');
    }
    uri;
    for (final tool in tools) {
      tool.validate();
    }
  }

  Json toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'tools': tools.map((t) => t.toJson()).toList(),
    'enabled': enabled,
  };
  factory McpServerConfig.fromJson(Json j) => McpServerConfig(
    id: j['id'] as String,
    name: j['name'] as String,
    endpoint: j['endpoint'] as String,
    enabled: j['enabled'] != false,
    tools: (j['tools'] as List)
        .map(
          (t) =>
              McpToolDefinition.fromJson(Map<String, dynamic>.from(t as Map)),
        )
        .toList(),
  );
}

class McpConfigStore {
  final File file;
  Future<void> _tail = Future.value();
  McpConfigStore(this.file);
  Future<List<McpServerConfig>> list() async {
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as Json;
    if (data['version'] != 1) {
      throw const HarnessException(
        'mcpConfig',
        'Unsupported MCP settings version.',
      );
    }
    return (data['servers'] as List)
        .map(
          (s) => McpServerConfig.fromJson(Map<String, dynamic>.from(s as Map)),
        )
        .toList();
  }

  Future<McpServerConfig?> get(String id) async =>
      (await list()).where((s) => s.id == id).firstOrNull;
  Future<void> save(McpServerConfig server) {
    server.validate();
    return _edit((servers) {
      servers.removeWhere((s) => s.id == server.id);
      servers.add(server);
    });
  }

  Future<void> delete(String id) =>
      _edit((servers) => servers.removeWhere((s) => s.id == id));
  Future<void> _edit(void Function(List<McpServerConfig>) edit) {
    final next = _tail.then((_) async {
      final servers = await list();
      edit(servers);
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsString(
        jsonEncode({
          'version': 1,
          'servers': servers.map((s) => s.toJson()).toList(),
        }),
        flush: true,
      );
      await part.rename(file.path);
    });
    _tail = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

/// SDK owns MCP negotiation and envelopes. No sampling, roots, elicitation,
/// resource fetching, OAuth redirects or local processes are advertised.
class McpGateway {
  final CredentialVault vault;
  final http.Client Function() clientFactory;
  McpGateway(this.vault, {http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  Future<T> _use<T>(
    McpServerConfig config,
    CancellationToken cancel,
    Future<T> Function(mcp.McpClient) work,
  ) async {
    config.validate();
    cancel.check();
    final token = await vault.read(config.credentialId);
    mcp.silenceMcpLogs();
    final transport = AgentHttpClient(
      clientFactory(),
      config.uri,
      maxResponseBytes: 1024 * 1024,
    );
    final client = mcp.McpClient(
      const mcp.Implementation(name: 'fknotes-harness', version: '1.0.0'),
      options: const mcp.McpClientOptions(
        capabilities: mcp.ClientCapabilities(),
        gracefulShutdownTimeout: Duration(milliseconds: 500),
      ),
    );
    final unregister = cancel.onCancel(() {
      transport.close();
      unawaited(client.close().catchError((Object _) {}));
    });
    try {
      return await http.runWithClient(() async {
        cancel.check();
        await client
            .connect(
              mcp.StreamableHttpClientTransport(
                config.uri,
                opts: mcp.StreamableHttpClientTransportOptions(
                  requestInit: {
                    'headers': {
                      if (token?.isNotEmpty == true)
                        'Authorization': 'Bearer $token',
                    },
                  },
                ),
              ),
            )
            .timeout(const Duration(seconds: 20));
        cancel.check();
        return await work(client).timeout(const Duration(seconds: 45));
      }, () => transport);
    } catch (_) {
      cancel.check();
      if (transport.failure != null) throw transport.failure!;
      throw const HarnessException(
        'mcpFailed',
        'The MCP request failed. Check this server and its access token. An external action may require verification before retrying.',
      );
    } finally {
      unregister();
      transport.close();
      try {
        await client.close();
      } catch (_) {
        /* transport already aborted */
      }
    }
  }

  Future<List<McpToolDefinition>> discover(
    McpServerConfig config,
    CancellationToken cancel,
  ) => _use(config, cancel, (client) async {
    final tools = <McpToolDefinition>[];
    String? cursor;
    final seen = <String>{};
    do {
      cancel.check();
      final page = await client.listTools(
        params: cursor == null ? null : mcp.ListToolsRequest(cursor: cursor),
      );
      for (final tool in page.tools) {
        final definition = McpToolDefinition(
          name: tool.name,
          description: tool.description ?? '',
          schema: tool.inputSchema.toJson(),
        );
        definition.validate();
        tools.add(definition);
      }
      cursor = page.nextCursor;
      if (tools.length > 32 || cursor != null && !seen.add(cursor)) {
        throw const HarnessException(
          'mcpToolLimit',
          'The server returned too many tools or a repeated cursor.',
        );
      }
    } while (cursor != null);
    return tools;
  });

  Future<ToolResult> call(
    McpServerConfig config,
    McpToolDefinition tool,
    Json args,
    CancellationToken cancel,
  ) => _use(config, cancel, (client) async {
    // No blind network retry: each call is a single external operation.
    final result = await client.callTool(
      mcp.CallToolRequest(name: tool.name, arguments: args),
      options: const mcp.RequestOptions(
        timeout: Duration(seconds: 45),
        resetTimeoutOnProgress: false,
      ),
    );
    cancel.check();
    if (result.isError && !tool.trustedReadOnly) {
      throw const HarnessException(
        'mcpExternalUncertain',
        'The external tool reported an error. Verify its effects before continuing.',
      );
    }
    final data = result.toJson();
    if (jsonEncode(data).length > 64000) {
      // A definite response is still a result, not an unknown external effect.
      return const ToolResult({
        'status': 'resultTooLarge',
        'message': 'The server completed but its response exceeded the limit.',
      }, isError: true);
    }
    return ToolResult({
      'server': config.name,
      'result': data,
    }, isError: result.isError);
  });
}

class RemoteMcpTool extends AgentTool {
  final McpServerConfig server;
  final McpToolDefinition definition;
  final McpGateway gateway;
  final Future<McpServerConfig?> Function(String id) currentConfig;
  RemoteMcpTool({
    required this.server,
    required this.definition,
    required this.gateway,
    required this.currentConfig,
  }) {
    server.validate();
    definition.validate();
  }
  @override
  ToolSpec get spec => ToolSpec(
    name:
        'mcp_${contentDigest({'server': server.id, 'tool': definition.name}).substring(0, 24)}',
    description:
        '[${server.name}] ${definition.name}: ${definition.description}',
    schema: definition.schema,
    network: true,
    risk: definition.trustedReadOnly ? ToolRisk.read : ToolRisk.write,
    idempotency: definition.trustedReadOnly
        ? ToolIdempotency.readOnly
        : ToolIdempotency.external,
  );
  Future<void> _check(ToolContext context) async {
    await context.ensureActive();
    if (!context.run.scope.networkTools ||
        !context.run.scope.networkBindings.contains(server.binding) ||
        (await currentConfig(server.id))?.binding != server.binding ||
        !server.enabled) {
      throw const HarnessException(
        'mcpPermission',
        'This MCP server or tool configuration is not authorized for the task.',
      );
    }
  }

  @override
  Future<ToolPreview> prepare(ToolContext context, Json arguments) async {
    await _check(context);
    return ToolPreview(
      data: {
        'server': server.name,
        'endpoint': server.endpoint,
        'tool': definition.name,
        'arguments': arguments,
        'external': true,
        'warning':
            'This operation runs on the configured server and cannot be undone by FKNotes.',
      },
      versions: {'binding': server.binding},
    );
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  ) async {
    await _check(context);
    return gateway.call(server, definition, arguments, context.cancel);
  }
}

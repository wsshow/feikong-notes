import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as ant;
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:openai_dart/openai_dart.dart' as oai;

import 'agent_http_client.dart';
import 'credential_vault.dart';
import 'model_profile.dart';

typedef AttachmentBytes =
    Future<Uint8List> Function(ModelAttachment attachment);

class OnlineModelAdapter implements ModelPort {
  final ModelProfile profile;
  final CredentialVault vault;
  final http.Client Function() clientFactory;
  final AttachmentBytes? attachmentBytes;
  OnlineModelAdapter({
    required this.profile,
    required this.vault,
    http.Client Function()? clientFactory,
    this.attachmentBytes,
  }) : clientFactory = clientFactory ?? http.Client.new;
  @override
  String get id => profile.id;
  @override
  bool get isRemote => true;
  @override
  ModelCapabilities get capabilities => profile.capabilities;

  bool get _isDeepSeek {
    final host = profile.baseUri.host.toLowerCase();
    final model = profile.model.toLowerCase();
    return host == 'api.deepseek.com' ||
        host.endsWith('.deepseek.com') ||
        model.startsWith('deepseek-');
  }

  String get _chatOutputLimitField {
    // DeepSeek's OpenAI-compatible Chat API keeps the original max_tokens
    // field. Select it automatically so users do not need a protocol quirk in
    // the model form. Keep the persisted flag as a migration escape hatch for
    // profiles created before this behavior became automatic.
    return profile.legacyMaxTokens || _isDeepSeek
        ? 'max_tokens'
        : 'max_completion_tokens';
  }

  @override
  Stream<ModelEvent> generate(
    ModelRequest request,
    CancellationToken cancel,
  ) async* {
    profile.validate();
    // SDK named loggers need hierarchy enabled before setting Level.OFF.
    hierarchicalLoggingEnabled = true;
    Logger('OpenAIClient').level = Level.OFF;
    Logger('AnthropicClient').level = Level.OFF;
    cancel.check();
    if (request.webSearch && !capabilities.webSearch) {
      throw const HarnessException(
        'searchUnsupported',
        'This model configuration does not support server search.',
      );
    }
    final key = await vault.read(profile.credentialId);
    if (key == null || key.trim().isEmpty) {
      throw const HarnessException(
        'missingCredential',
        'Add an API key in model settings.',
      );
    }
    final additions = <String, dynamic>{};
    if (profile.protocol == ModelProtocol.chatCompletions && profile.thinking) {
      additions['thinking'] = {'type': 'enabled'};
    }
    final transport = AgentHttpClient(
      clientFactory(),
      profile.baseUri,
      additions: additions,
      // SSE framing can be much larger than the generated text. Scale the
      // bounded wire allowance for explicitly requested long responses.
      maxResponseBytes: (request.maxOutputTokens * 512).clamp(
        16 * 1024 * 1024,
        128 * 1024 * 1024,
      ),
    );
    final unregister = cancel.onCancel(transport.close);
    try {
      cancel.check();
      final wire = await _request(request);
      if (profile.protocol == ModelProtocol.responses) {
        // SDK 8.1.0's input union excludes reasoning/search output items even
        // though the API requires their replay. Preserve the complete input
        // at our transport boundary instead of losing opaque continuations.
        additions['input'] = wire['input'];
        final include = <String>[
          if (profile.statelessResponses) 'reasoning.encrypted_content',
          if (request.webSearch) ...[
            'web_search_call.results',
            'web_search_call.action.sources',
          ],
        ];
        if (include.isNotEmpty) additions['include'] = include;
      }
      cancel.check();
      if (profile.protocol == ModelProtocol.anthropic) {
        final client = ant.AnthropicClient(
          config: ant.AnthropicConfig(
            baseUrl: profile.baseUri.toString(),
            authProvider: ant.ApiKeyProvider(key),
            retryPolicy: const ant.RetryPolicy(maxRetries: 0),
            logLevel: Level.OFF,
          ),
          httpClient: transport,
        );
        try {
          await for (final event in _anthropic(client, wire, cancel)) {
            yield event;
          }
        } finally {
          client.close();
        }
      } else {
        final responsesCapture = profile.protocol == ModelProtocol.responses
            ? _ResponsesSseCaptureClient(transport)
            : null;
        final client = oai.OpenAIClient(
          config: oai.OpenAIConfig(
            baseUrl: profile.baseUri.toString(),
            authProvider: oai.ApiKeyProvider(key),
            retryPolicy: const oai.RetryPolicy(maxRetries: 0),
            logLevel: Level.OFF,
          ),
          httpClient: responsesCapture ?? transport,
        );
        try {
          if (profile.protocol == ModelProtocol.responses) {
            await for (final event in _responses(
              client,
              wire,
              cancel,
              responsesCapture!,
            )) {
              yield event;
            }
          } else {
            await for (final event in _chat(client, wire, cancel)) {
              yield event;
            }
          }
        } finally {
          client.close();
        }
      }
    } on HarnessException {
      rethrow;
    } on TimeoutException {
      throw const HarnessException(
        'requestTimeout',
        'The model request timed out.',
        retryable: true,
      );
    } catch (_) {
      cancel.check();
      if (transport.failure != null) throw transport.failure!;
      // Exception messages from SDKs may include complete HTTP payloads.
      throw const HarnessException(
        'modelTransport',
        'The model response could not be read. Check the endpoint, model and network.',
      );
    } finally {
      unregister();
      transport.close();
    }
  }

  Json? _saved(AgentMessage m) => m.protocol['binding'] == profile.binding
      ? m.protocol['wire'] as Json?
      : null;
  Json _protocol(Json wire) => {'binding': profile.binding, 'wire': wire};

  Iterable<Json> _responsesReplay(List<dynamic> output) sync* {
    if (!_isDeepSeek) {
      for (final item in output) {
        if (item is Map) yield Map<String, dynamic>.from(item);
      }
      return;
    }
    // DeepSeek accepts only its documented response item shapes as input.
    // Strip response-only metadata (id/status/annotations) while preserving
    // reasoning and built-in web search items needed for stateless replay.
    for (final raw in output) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      switch (item['type']) {
        case 'reasoning':
          final content = <Json>[
            for (final rawBlock in item['content'] as List? ?? const [])
              if (rawBlock is Map &&
                  rawBlock['type'] == 'reasoning_text' &&
                  rawBlock['text'] is String)
                {'type': 'reasoning_text', 'text': rawBlock['text'] as String},
          ];
          if (content.isNotEmpty) {
            yield {'type': 'reasoning', 'content': content};
          }
        case 'web_search_call':
          // Built-in calls are replayed as returned so DeepSeek can associate
          // the search with the following assistant message.
          yield item;
        case 'function_call':
          if (item['call_id'] is String &&
              item['name'] is String &&
              item['arguments'] is String) {
            yield {
              'type': 'function_call',
              'call_id': item['call_id'],
              'name': item['name'],
              'arguments': item['arguments'],
            };
          }
        case 'message':
          final content = <Json>[
            for (final rawBlock in item['content'] as List? ?? const [])
              if (rawBlock is Map &&
                  rawBlock['type'] == 'output_text' &&
                  rawBlock['text'] is String)
                {'type': 'output_text', 'text': rawBlock['text'] as String}
              else if (rawBlock is Map &&
                  rawBlock['type'] == 'refusal' &&
                  rawBlock['refusal'] is String)
                {'type': 'refusal', 'refusal': rawBlock['refusal'] as String},
          ];
          if (content.isNotEmpty) {
            yield {'type': 'message', 'role': 'assistant', 'content': content};
          }
      }
    }
  }

  Future<List<Json>> _images(AgentMessage m, String format) async {
    final out = <Json>[];
    if (m.attachments.length > 4) {
      throw const HarnessException(
        'attachmentCount',
        'Use at most four images in one message.',
      );
    }
    for (final a in m.attachments) {
      if (!capabilities.images ||
          !a.mimeType.startsWith('image/') ||
          attachmentBytes == null) {
        throw const HarnessException(
          'attachmentUnsupported',
          'This model does not support the attached media.',
        );
      }
      final bytes = await attachmentBytes!(a);
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const HarnessException(
          'attachmentSize',
          'The image exceeds the upload limit.',
        );
      }
      final encoded = base64Encode(bytes);
      out.add(switch (format) {
        'anthropic' => {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': a.mimeType,
            'data': encoded,
          },
        },
        'responses' => {
          'type': 'input_image',
          'image_url': 'data:${a.mimeType};base64,$encoded',
        },
        _ => {
          'type': 'image_url',
          'image_url': {'url': 'data:${a.mimeType};base64,$encoded'},
        },
      });
    }
    return out;
  }

  Future<Json> _request(ModelRequest request) async {
    final messages = <Json>[];
    final tools = request.tools;
    switch (profile.protocol) {
      case ModelProtocol.chatCompletions:
        for (final m in request.messages) {
          final saved = _saved(m);
          if (m.role == MessageRole.assistant && saved != null) {
            messages.add(saved);
            continue;
          }
          messages.add({
            'role': m.role.name,
            'content': m.attachments.isEmpty
                ? m.modelText
                : [
                    {'type': 'text', 'text': m.modelText},
                    ...await _images(m, 'chat'),
                  ],
            if (m.role == MessageRole.tool) 'tool_call_id': m.toolCallId,
            if (m.calls.isNotEmpty)
              'tool_calls': [
                for (final c in m.calls)
                  {
                    'id': c.id,
                    'type': 'function',
                    'function': {
                      'name': c.name,
                      'arguments': jsonEncode(c.arguments),
                    },
                  },
              ],
          });
        }
        return {
          'model': profile.model,
          'messages': messages,
          if (tools.isNotEmpty)
            'tools': [
              for (final t in tools)
                {'type': 'function', 'function': t.toJson()},
            ],
          _chatOutputLimitField: request.maxOutputTokens,
          if (profile.includeUsage) 'stream_options': {'include_usage': true},
        };
      case ModelProtocol.responses:
        for (final m in request.messages) {
          final saved = _saved(m);
          if (m.role == MessageRole.assistant && saved?['output'] is List) {
            messages.addAll(_responsesReplay(saved!['output'] as List));
            continue;
          }
          if (m.role == MessageRole.tool) {
            messages.add({
              'type': 'function_call_output',
              'call_id': m.toolCallId,
              'output': m.modelText,
            });
            continue;
          }
          if (m.modelText.isNotEmpty || m.attachments.isNotEmpty) {
            messages.add({
              'type': 'message',
              'role': m.role.name,
              'content': [
                {
                  'type': m.role == MessageRole.assistant
                      ? 'output_text'
                      : 'input_text',
                  'text': m.modelText,
                },
                ...await _images(m, 'responses'),
              ],
            });
          }
          messages.addAll([
            for (final c in m.calls)
              {
                'type': 'function_call',
                'call_id': c.id,
                'name': c.name,
                'arguments': jsonEncode(c.arguments),
              },
          ]);
        }
        return {
          'model': profile.model,
          'input': messages,
          'max_output_tokens': request.maxOutputTokens,
          if (profile.statelessResponses) 'store': false,
          if (profile.thinking) 'reasoning': {'effort': 'medium'},
          if (tools.isNotEmpty || request.webSearch)
            'tools': [
              for (final t in tools) {'type': 'function', ...t.toJson()},
              if (request.webSearch) {'type': 'web_search'},
            ],
        };
      case ModelProtocol.anthropic:
        for (final m in request.messages.where(
          (m) => m.role != MessageRole.system,
        )) {
          final saved = _saved(m);
          final List<dynamic> content;
          if (m.role == MessageRole.tool) {
            content = [
              {
                'type': 'tool_result',
                'tool_use_id': m.toolCallId,
                'content': [
                  {'type': 'text', 'text': m.modelText},
                ],
                'is_error': m.isError,
              },
            ];
          } else if (m.role == MessageRole.assistant &&
              saved?['content'] is List) {
            content = saved!['content'] as List;
          } else {
            content = [
              if (m.modelText.isNotEmpty) {'type': 'text', 'text': m.modelText},
              ...await _images(m, 'anthropic'),
              for (final c in m.calls)
                {
                  'type': 'tool_use',
                  'id': c.id,
                  'name': c.name,
                  'input': c.arguments,
                },
            ];
          }
          final role = m.role == MessageRole.assistant ? 'assistant' : 'user';
          if (messages.isNotEmpty && messages.last['role'] == role) {
            (messages.last['content'] as List).addAll(content);
          } else {
            messages.add({'role': role, 'content': List.of(content)});
          }
        }
        return {
          'model': profile.model,
          'messages': messages,
          'max_tokens': request.maxOutputTokens,
          'system': request.messages
              .where((m) => m.role == MessageRole.system)
              .map((m) => m.modelText)
              .join('\n\n'),
          if (profile.thinking && request.maxOutputTokens > 2048)
            'thinking': {
              'type': 'enabled',
              'budget_tokens': request.maxOutputTokens ~/ 2,
            },
          if (tools.isNotEmpty || request.webSearch)
            'tools': [
              for (final t in tools)
                {
                  'name': t.name,
                  'description': t.description,
                  'input_schema': t.schema,
                },
              if (request.webSearch)
                {
                  'type': 'web_search_20250305',
                  'name': 'web_search',
                  'max_uses': 3,
                },
            ],
        };
      case ModelProtocol.local:
        throw StateError('Use LocalModelAdapter');
    }
  }

  Stream<ModelEvent> _chat(
    oai.OpenAIClient client,
    Json wire,
    CancellationToken cancel,
  ) async* {
    final accumulator = oai.ChatStreamAccumulator();
    var size = 0;
    var finished = false;
    await for (final event in client.chat.completions.createStream(
      oai.ChatCompletionCreateRequest.fromJson(wire),
    )) {
      cancel.check();
      _checkSize(size += jsonEncode(event.toJson()).length);
      accumulator.add(event);
      for (final choice in event.toJson()['choices'] as List? ?? []) {
        if (choice['index'] != 0) continue;
        final delta = choice['delta'] as Json;
        if (delta['content'] case final String text) yield ModelText(text);
        final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
        if (reasoning is String && reasoning.isNotEmpty) {
          yield ModelReasoning(reasoning);
        }
        finished |= choice['finish_reason'] != null;
      }
    }
    cancel.check();
    if (!finished) {
      throw const HarnessException(
        'incompleteStream',
        'The model stream ended before completion.',
      );
    }
    final result = accumulator.toChatCompletion().toJson();
    final choice = (result['choices'] as List).first as Json;
    final message = choice['message'] as Json;
    final usage = result['usage'] as Json?;
    final finish = choice['finish_reason'] as String? ?? 'stop';
    final calls = <ToolCall>[];
    if (finish != 'length') {
      for (final c in message['tool_calls'] as List? ?? []) {
        calls.add(
          _call(c['id'], c['function']['name'], c['function']['arguments']),
        );
      }
    }
    _unique(calls);
    yield ModelCompleted(
      AgentMessage(
        role: MessageRole.assistant,
        text:
            message['content'] as String? ??
            message['refusal'] as String? ??
            '',
        calls: calls,
        protocol: _protocol(message),
      ),
      inputTokens: usage?['prompt_tokens'] as int?,
      outputTokens: usage?['completion_tokens'] as int?,
      finishReason: finish,
    );
  }

  Stream<ModelEvent> _responses(
    oai.OpenAIClient client,
    Json wire,
    CancellationToken cancel,
    _ResponsesSseCaptureClient capture,
  ) async* {
    Json? response;
    var size = 0;
    final startedSearches = <String>{};
    await for (final event in client.responses.createStream(
      oai.CreateResponseRequest.fromJson({...wire, 'input': ''}),
    )) {
      cancel.check();
      final j = event.toJson();
      _checkSize(size += jsonEncode(j).length);
      switch (j['type']) {
        case 'response.output_text.delta':
          yield ModelText(j['delta'] as String);
        case 'response.output_item.added' || 'response.output_item.done':
          final item = j['item'] as Json?;
          final itemId = item?['id'];
          if (item?['type'] == 'web_search_call' && itemId is String) {
            final rawItem = capture.outputItem(itemId) ?? item!;
            final detail = _webSearchDetail(rawItem);
            final data = _webSearchData(rawItem);
            if (startedSearches.add(itemId)) {
              yield ModelActivity(
                'webSearch',
                id: itemId,
                detail: detail,
                data: data,
              );
            }
            if (j['type'] == 'response.output_item.done' ||
                rawItem['status'] == 'completed') {
              yield ModelActivity(
                'webSearch',
                id: itemId,
                detail: detail,
                data: data,
                completed: true,
              );
            }
          }
        case 'response.web_search_call.in_progress' ||
            'response.web_search_call.searching':
          if (j['item_id'] case final String itemId) {
            final detail = _webSearchDetail(capture.outputItem(itemId));
            final data = _webSearchData(capture.outputItem(itemId));
            if (startedSearches.add(itemId) || detail != null) {
              yield ModelActivity(
                'webSearch',
                id: itemId,
                detail: detail,
                data: data,
              );
            }
          }
        case 'response.web_search_call.completed':
          if (j['item_id'] case final String itemId) {
            startedSearches.add(itemId);
            yield ModelActivity(
              'webSearch',
              id: itemId,
              detail: _webSearchDetail(capture.outputItem(itemId)),
              data: _webSearchData(capture.outputItem(itemId)),
              completed: true,
            );
          }
        case 'response.reasoning_summary_text.delta' ||
            'response.reasoning_text.delta':
          if (j['delta'] case final String text when text.isNotEmpty) {
            yield ModelReasoning(text);
          }
        case 'response.completed' || 'response.incomplete':
          response = capture.responseWithCapturedItems(j['response'] as Json);
          for (final item in response['output'] as List? ?? const []) {
            if (item is! Map || item['type'] != 'web_search_call') continue;
            final rawItem = Map<String, dynamic>.from(item);
            final itemId = rawItem['id'] as String?;
            if (itemId == null || itemId.isEmpty) continue;
            if (startedSearches.add(itemId)) {
              yield ModelActivity(
                'webSearch',
                id: itemId,
                detail: _webSearchDetail(rawItem),
                data: _webSearchData(rawItem),
              );
            }
            yield ModelActivity(
              'webSearch',
              id: itemId,
              detail: _webSearchDetail(rawItem),
              data: _webSearchData(rawItem),
              completed: true,
            );
          }
        case 'response.failed' || 'error':
          throw const HarnessException(
            'modelFailed',
            'The provider could not finish this response.',
          );
      }
    }
    cancel.check();
    if (response == null) {
      throw const HarnessException(
        'incompleteStream',
        'The model stream ended before completion.',
      );
    }
    final output = (response['output'] as List? ?? []).cast<Json>();
    final text = StringBuffer();
    final sources = <Json>[];
    final calls = <ToolCall>[];
    for (final item in output) {
      if (item['type'] == 'function_call' &&
          response['status'] != 'incomplete') {
        calls.add(_call(item['call_id'], item['name'], item['arguments']));
      }
      if (item['type'] == 'message') {
        for (final block in item['content'] as List? ?? []) {
          if (block['type'] == 'output_text') {
            text.write(block['text']);
            for (final citation in block['annotations'] as List? ?? []) {
              if (citation['type'] == 'url_citation') {
                sources.add(_cleanWebSource(citation));
              }
            }
          } else if (block['type'] == 'refusal') {
            text.write(block['refusal']);
          }
        }
      }
    }
    _unique(calls);
    final usage = response['usage'] as Json?;
    yield ModelCompleted(
      AgentMessage(
        role: MessageRole.assistant,
        text: text.toString(),
        calls: calls,
        sources: sources,
        protocol: _protocol({'output': output}),
      ),
      inputTokens: usage?['input_tokens'] as int?,
      outputTokens: usage?['output_tokens'] as int?,
      finishReason: response['status'] == 'incomplete' ? 'incomplete' : 'stop',
    );
  }

  String? _webSearchDetail(Json? item) {
    final action = item?['action'];
    if (action is! Map) return null;
    final query = action['query'];
    if (query is String && query.trim().isNotEmpty) {
      return _cleanProviderSearchDetail(query);
    }
    final queries = (action['queries'] as List? ?? const [])
        .whereType<String>()
        .map(_cleanProviderSearchDetail)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (queries.isNotEmpty) return queries.join('、');
    for (final key in const ['url', 'pattern']) {
      final value = action[key];
      if (value is String && value.trim().isNotEmpty) {
        return _cleanProviderSearchDetail(value);
      }
    }
    return null;
  }

  Json _webSearchData(Json? item) {
    final action = item?['action'];
    final actionMap = action is Map
        ? Map<String, dynamic>.from(action)
        : const <String, dynamic>{};
    final results = _webSearchEvidence(item, actionMap);
    final hasExplicitResults =
        item?.containsKey('results') == true ||
        actionMap.containsKey('sources');
    final actionType = actionMap['type'];
    return {
      if (actionType is String && actionType.isNotEmpty) 'action': actionType,
      if (results.isNotEmpty) 'results': results,
      'resultDisclosure': results.isNotEmpty
          ? 'available'
          : hasExplicitResults
          ? 'empty'
          : _isDeepSeek
          ? 'providerManaged'
          : 'notProvided',
    };
  }

  List<Json> _webSearchEvidence(Json? item, Json action) {
    final candidates = <Object?>[
      ..._webSearchEvidenceList(item?['results']),
      ..._webSearchEvidenceList(action['sources']),
    ];
    final results = <Json>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final result = _cleanWebSearchEvidence(candidate);
      if (result == null) continue;
      final key = result['url'] as String;
      if (!seen.add(key)) continue;
      results.add(result);
      if (results.length == 10) break;
    }
    return results;
  }

  Iterable<Object?> _webSearchEvidenceList(Object? value) sync* {
    if (value is List) {
      yield* value;
      return;
    }
    if (value is Map) {
      for (final key in const ['data', 'results', 'sources']) {
        final nested = value[key];
        if (nested is List) {
          yield* nested;
          return;
        }
      }
    }
  }

  Json? _cleanWebSearchEvidence(Object? raw) {
    final Json source;
    if (raw is String) {
      source = {'url': raw};
    } else if (raw is Map) {
      source = Map<String, dynamic>.from(raw);
    } else {
      return null;
    }
    final rawUrl = source['url'] ?? source['link'];
    if (rawUrl is! String) return null;
    final url = _cleanProviderWebUrl(rawUrl);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    String? firstText(Iterable<String> keys, int maxRunes) {
      for (final key in keys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          return _boundedText(value, maxRunes);
        }
      }
      return null;
    }

    final title = firstText(const ['title', 'name'], 240);
    final snippet = firstText(const [
      'snippet',
      'description',
      'text',
      'content',
    ], 800);
    final publishedAt = firstText(const [
      'published_at',
      'publishedAt',
      'page_age',
      'date',
    ], 80);
    return {
      'url': _boundedText(url, 2048),
      'title': ?title,
      'snippet': ?snippet,
      'publishedAt': ?publishedAt,
    };
  }

  String _boundedText(String value, int maxRunes) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final runes = normalized.runes;
    if (runes.length <= maxRunes) return normalized;
    return '${String.fromCharCodes(runes.take(maxRunes))}…';
  }

  Json _cleanWebSource(Object? raw) {
    final source = Map<String, dynamic>.from(raw as Map);
    if (source['url'] case final String url) {
      if (_providerWebCallId(url) case final callId?) {
        source['providerCallId'] = callId;
      }
      source['url'] = _cleanProviderWebUrl(url);
    }
    return source;
  }

  String? _providerWebCallId(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.fragment.isEmpty) return null;
    for (final part in uri.fragment.split('&')) {
      final separator = part.indexOf('=');
      final rawKey = separator < 0 ? part : part.substring(0, separator);
      final rawValue = separator < 0 ? '' : part.substring(separator + 1);
      try {
        if (Uri.decodeQueryComponent(rawKey) == 'ws_call_id') {
          return Uri.decodeQueryComponent(rawValue);
        }
      } on FormatException {
        if (rawKey == 'ws_call_id') return rawValue;
      }
    }
    return null;
  }

  String _cleanProviderWebUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.fragment.isEmpty) return value.trim();
    final retained = uri.fragment
        .split('&')
        .where((part) {
          final separator = part.indexOf('=');
          final rawKey = separator < 0 ? part : part.substring(0, separator);
          try {
            return Uri.decodeQueryComponent(rawKey) != 'ws_call_id';
          } on FormatException {
            return rawKey != 'ws_call_id';
          }
        })
        .toList(growable: false);
    if (retained.length == uri.fragment.split('&').length) {
      return value.trim();
    }
    if (retained.isEmpty) {
      return value.trim().substring(0, value.trim().lastIndexOf('#'));
    }
    return uri.replace(fragment: retained.join('&')).toString();
  }

  String _cleanProviderSearchDetail(String value) {
    final cleanedUrl = _cleanProviderWebUrl(value);
    return cleanedUrl
        .replaceAll(
          RegExp(
            r'(?:\s*[,，;；]\s*)?[#?&]?ws_call_id\s*=\s*[^&\s,，;；]+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'\s*[,，;；]\s*$'), '')
        .trim();
  }

  Stream<ModelEvent> _anthropic(
    ant.AnthropicClient client,
    Json wire,
    CancellationToken cancel,
  ) async* {
    final accumulator = ant.MessageStreamAccumulator();
    var finished = false;
    var size = 0;
    final webSearches = <String, String?>{};
    final webSearchData = <String, Json>{};
    final completedWebSearches = <String>{};
    await for (final event in client.messages.createStream(
      ant.MessageCreateRequest.fromJson(wire),
    )) {
      cancel.check();
      final j = event.toJson();
      _checkSize(size += jsonEncode(j).length);
      if (j['type'] == 'error') {
        throw const HarnessException(
          'modelFailed',
          'The provider could not finish this response.',
        );
      }
      accumulator.add(event);
      if (j['type'] == 'message_stop') finished = true;
      if (j['type'] == 'content_block_delta') {
        final delta = j['delta'] as Json;
        if (delta['type'] == 'text_delta') {
          yield ModelText(delta['text'] as String);
        }
        if (delta['type'] == 'thinking_delta') {
          if (delta['thinking'] case final String text when text.isNotEmpty) {
            yield ModelReasoning(text);
          }
        }
      }
      final rawBlock = j['content_block'];
      if (j['type'] == 'content_block_start' && rawBlock is Map) {
        final block = Map<String, dynamic>.from(rawBlock);
        final blockId = block['id'];
        final toolUseId = block['tool_use_id'];
        if (block['type'] == 'server_tool_use' &&
            block['name'] == 'web_search' &&
            blockId is String) {
          final input = block['input'];
          final query = input is Map ? input['query'] as String? : null;
          webSearches[blockId] = query;
          webSearchData[blockId] = const {
            'action': 'search',
            'resultDisclosure': 'pending',
          };
          yield ModelActivity(
            'webSearch',
            id: blockId,
            detail: query,
            data: webSearchData[blockId]!,
          );
        } else if (block['type'] == 'web_search_tool_result' &&
            toolUseId is String) {
          completedWebSearches.add(toolUseId);
          final results = _webSearchEvidence({
            'results': block['content'],
          }, const {});
          final data = {
            ...?webSearchData[toolUseId],
            if (results.isNotEmpty) 'results': results,
            'resultDisclosure': results.isEmpty ? 'empty' : 'available',
          };
          webSearchData[toolUseId] = data;
          yield ModelActivity(
            'webSearch',
            id: toolUseId,
            detail: webSearches[toolUseId],
            data: data,
            completed: true,
          );
        }
      }
    }
    cancel.check();
    if (!finished) {
      throw const HarnessException(
        'incompleteStream',
        'The model stream ended before completion.',
      );
    }
    for (final entry in webSearches.entries) {
      if (completedWebSearches.add(entry.key)) {
        yield ModelActivity(
          'webSearch',
          id: entry.key,
          detail: entry.value,
          data: webSearchData[entry.key] ?? const {},
          completed: true,
        );
      }
    }
    final result = accumulator.toMessage().toJson();
    final content = result['content'] as List;
    final finish = result['stop_reason'] as String? ?? 'end_turn';
    final calls = <ToolCall>[];
    final sources = <Json>[];
    final text = StringBuffer();
    for (final block in content) {
      if (block['type'] == 'tool_use' && finish != 'max_tokens') {
        calls.add(_call(block['id'], block['name'], block['input']));
      } else if (block['type'] == 'text') {
        text.write(block['text']);
        for (final citation in block['citations'] as List? ?? []) {
          sources.add(_cleanWebSource(citation));
        }
      }
    }
    _unique(calls);
    final usage = result['usage'] as Json;
    yield ModelCompleted(
      AgentMessage(
        role: MessageRole.assistant,
        text: text.toString(),
        calls: calls,
        sources: sources,
        protocol: _protocol({'content': content}),
      ),
      inputTokens:
          (usage['input_tokens'] as int? ?? 0) +
          (usage['cache_creation_input_tokens'] as int? ?? 0) +
          (usage['cache_read_input_tokens'] as int? ?? 0),
      outputTokens: usage['output_tokens'] as int?,
      finishReason: finish,
    );
  }

  static ToolCall _call(dynamic id, dynamic name, dynamic input) {
    try {
      final parsed = input is String ? jsonDecode(input) : input;
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.isEmpty ||
          parsed is! Map) {
        throw const FormatException();
      }
      return ToolCall(
        id: id,
        name: name,
        arguments: Map<String, dynamic>.from(parsed),
      );
    } catch (_) {
      throw const HarnessException(
        'invalidToolCall',
        'The model returned an invalid tool call.',
      );
    }
  }

  static void _unique(List<ToolCall> calls) {
    if (calls.length > 32 ||
        calls.map((c) => c.id).toSet().length != calls.length) {
      throw const HarnessException(
        'invalidToolCall',
        'The model returned duplicate or excessive tool calls.',
      );
    }
  }

  static void _checkSize(int size) {
    if (size > 8 * 1024 * 1024) {
      throw const HarnessException(
        'responseSize',
        'The model response exceeds the limit.',
      );
    }
  }
}

/// Keeps the provider's raw Responses items alongside the typed SDK stream.
/// The current SDK intentionally omits vendor fields such as DeepSeek's web
/// search `action`; those fields are required for faithful stateless replay
/// and also contain the concrete search query shown in the task timeline.
class _ResponsesSseCaptureClient extends http.BaseClient {
  final http.Client inner;
  final List<int> _pending = [];
  final Map<String, Json> _outputItems = {};
  Json? finalResponse;

  _ResponsesSseCaptureClient(this.inner);

  Json? outputItem(String id) => _outputItems[id];

  Json responseWithCapturedItems(Json fallback) {
    final response = finalResponse ?? fallback;
    final output = <Json>[
      for (final rawItem in response['output'] as List? ?? const [])
        if (rawItem is Map)
          outputItem(rawItem['id'] as String? ?? '') ??
              Map<String, dynamic>.from(rawItem),
    ];
    return {...response, 'output': output};
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    final stream = response.stream.map((chunk) {
      _capture(chunk);
      return chunk;
    });
    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  void _capture(List<int> chunk) {
    _pending.addAll(chunk);
    while (true) {
      final boundary = _eventBoundary(_pending);
      if (boundary == null) return;
      final frame = _pending.sublist(0, boundary.$1);
      _pending.removeRange(0, boundary.$1 + boundary.$2);
      _captureFrame(frame);
    }
  }

  (int, int)? _eventBoundary(List<int> bytes) {
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 10 && bytes[i + 1] == 10) return (i, 2);
      if (i < bytes.length - 3 &&
          bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return (i, 4);
      }
    }
    return null;
  }

  void _captureFrame(List<int> frame) {
    try {
      final data = utf8
          .decode(frame)
          .split(RegExp(r'\r?\n'))
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring(5).trimLeft())
          .join('\n');
      if (data.isEmpty || data == '[DONE]') return;
      final event = jsonDecode(data);
      if (event is! Map) return;
      final json = Map<String, dynamic>.from(event);
      if (json['item'] case final Map item) {
        _rememberItem(Map<String, dynamic>.from(item));
      }
      if (json['response'] case final Map response) {
        final rawResponse = Map<String, dynamic>.from(response);
        finalResponse = rawResponse;
        for (final item in rawResponse['output'] as List? ?? const []) {
          if (item is Map) _rememberItem(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {
      // The SDK remains the source of validation. A partial/non-JSON SSE
      // frame simply provides no optional vendor metadata.
    }
  }

  void _rememberItem(Json item) {
    final id = item['id'];
    if (id is! String || id.isEmpty) return;
    // Providers may send richer fields in output_item.done than in the final
    // response snapshot. Merge later snapshots instead of allowing them to
    // erase continuation data such as DeepSeek's web search action.
    _outputItems[id] = {...?_outputItems[id], ...item};
  }

  @override
  void close() => inner.close();
}

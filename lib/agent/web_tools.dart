import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef WebHostLookup = Future<List<InternetAddress>> Function(String host);

/// Reads a known public web URL. Search discovery remains the provider's
/// `web_search` tool; page finding and pagination stay inside this one tool.
final class WebFetchTool extends AgentTool {
  static const _maxDownloadBytes = 2 * 1024 * 1024;
  static const _maxRedirects = 4;
  static const _cacheLifetime = Duration(minutes: 10);
  static const _cacheEntries = 8;

  final http.Client Function()? clientFactory;
  final WebHostLookup lookup;
  final DateTime Function() now;
  final LinkedHashMap<String, _CachedWebPage> _cache = LinkedHashMap();

  WebFetchTool({
    this.clientFactory,
    WebHostLookup? lookup,
    DateTime Function()? now,
  }) : lookup = lookup ?? InternetAddress.lookup,
       now = now ?? DateTime.now;

  @override
  ToolSpec get spec => const ToolSpec(
    name: 'web_fetch',
    description:
        'Read one known public HTTP(S) URL as clean text. query optionally returns matching passages; cursor and max_chars paginate the cached page.',
    network: true,
    timeout: Duration(seconds: 30),
    schema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'minLength': 1, 'maxLength': 2048},
        'query': {'type': 'string', 'maxLength': 200},
        'cursor': {'type': 'integer', 'minimum': 0},
        'max_chars': {'type': 'integer', 'minimum': 500, 'maximum': 20000},
      },
      'required': ['url'],
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
    if (!context.run.scope.networkTools) {
      throw const HarnessException(
        'networkDenied',
        'Web tools are not authorized for this task.',
      );
    }
    final uri = _parseUrl(arguments['url'] as String);
    final page = await _page(uri, context.cancel);
    await context.ensureActive();
    final query = (arguments['query'] as String? ?? '').trim();
    final cursor = arguments['cursor'] as int? ?? 0;
    final maxChars = arguments['max_chars'] as int? ?? 8000;
    final slice = query.isEmpty
        ? _pageSlice(page.text, cursor, maxChars)
        : _querySlice(page.text, query, cursor, maxChars);
    final excerpt = slice.content.length > 500
        ? slice.content.substring(0, 500)
        : slice.content;
    final source = {
      'url': page.url.toString(),
      'title': page.title,
      'excerpt': excerpt,
    };
    return ToolResult(
      {
        'url': page.url.toString(),
        'title': page.title,
        'content': slice.content,
        'query': query.isEmpty ? null : query,
        'cursor': cursor,
        'nextCursor': slice.nextCursor,
        'totalCharacters': page.text.length,
        'matchCount': slice.matchCount,
        'truncated': slice.nextCursor != null,
      },
      sources: [source],
    );
  }

  Uri _parseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      throw const HarnessException(
        'webFetchUrl',
        'web_fetch requires a public HTTP(S) URL without embedded credentials.',
        toolObservation: true,
      );
    }
    return uri.removeFragment();
  }

  Future<_CachedWebPage> _page(Uri uri, CancellationToken cancel) async {
    final key = uri.toString();
    final cached = _cache.remove(key);
    if (cached != null && now().difference(cached.fetchedAt) < _cacheLifetime) {
      _cache[key] = cached;
      return cached;
    }
    final page = await _download(uri, cancel);
    _cache[key] = page;
    while (_cache.length > _cacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return page;
  }

  Future<_CachedWebPage> _download(
    Uri initial,
    CancellationToken cancel,
  ) async {
    final client = clientFactory?.call() ?? _guardedClient();
    final unregister = cancel.onCancel(client.close);
    var current = initial;
    try {
      for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
        cancel.check();
        await _validatePublic(current);
        cancel.check();
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(const {
            'accept':
                'text/html,application/xhtml+xml,text/plain,application/json,text/markdown;q=0.9,*/*;q=0.1',
            'user-agent': 'FKNotes-WebFetch/1.0',
          });
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          if (redirect == _maxRedirects) {
            throw const HarnessException(
              'webFetchRedirect',
              'The page redirected too many times.',
              toolObservation: true,
            );
          }
          final location = response.headers['location'];
          if (location == null || location.trim().isEmpty) {
            throw const HarnessException(
              'webFetchRedirect',
              'The page returned an invalid redirect.',
              toolObservation: true,
            );
          }
          current = _parseUrl(current.resolve(location).toString());
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HarnessException(
            'webFetchHttp',
            'The page returned HTTP ${response.statusCode}.',
            toolObservation: true,
          );
        }
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';
        if (!_isTextContent(contentType)) {
          throw const HarnessException(
            'webFetchContent',
            'web_fetch can only read text and HTML pages.',
            toolObservation: true,
          );
        }
        final declared = response.contentLength;
        if (declared != null && declared > _maxDownloadBytes) {
          throw const HarnessException(
            'webFetchSize',
            'The page exceeds the web_fetch download limit.',
            toolObservation: true,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          cancel.check();
          if (bytes.length + chunk.length > _maxDownloadBytes) {
            throw const HarnessException(
              'webFetchSize',
              'The page exceeds the web_fetch download limit.',
              toolObservation: true,
            );
          }
          bytes.addAll(chunk);
        }
        final decoded = utf8.decode(bytes, allowMalformed: true);
        final extracted = _extract(decoded, contentType, current);
        return _CachedWebPage(
          url: current,
          title: extracted.title,
          text: extracted.text,
          fetchedAt: now(),
        );
      }
      throw StateError('unreachable');
    } on TimeoutException {
      throw const HarnessException(
        'webFetchTimeout',
        'The page did not respond in time.',
        retryable: true,
        toolObservation: true,
      );
    } on SocketException {
      cancel.check();
      throw const HarnessException(
        'webFetchNetwork',
        'The public web page could not be reached.',
        retryable: true,
        toolObservation: true,
      );
    } on http.ClientException {
      cancel.check();
      throw const HarnessException(
        'webFetchNetwork',
        'The public web page could not be reached.',
        retryable: true,
        toolObservation: true,
      );
    } finally {
      unregister();
      client.close();
    }
  }

  Future<void> _validatePublic(Uri uri) async {
    await _publicAddresses(uri.host);
  }

  Future<List<InternetAddress>> _publicAddresses(String value) async {
    final host = value.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.home.arpa')) {
      throw const HarnessException(
        'webFetchPrivate',
        'web_fetch cannot access local or private network addresses.',
        toolObservation: true,
      );
    }
    final literal = InternetAddress.tryParse(host);
    final addresses = literal == null ? await lookup(host) : [literal];
    if (addresses.isEmpty || addresses.any((address) => !_isPublic(address))) {
      throw const HarnessException(
        'webFetchPrivate',
        'web_fetch cannot access local or private network addresses.',
        toolObservation: true,
      );
    }
    return addresses;
  }

  http.Client _guardedClient() {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 10);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null || proxyPort != null) {
        throw const SocketException('Proxies are disabled for web_fetch.');
      }
      final addresses = await _publicAddresses(uri.host);
      final port = uri.hasPort
          ? uri.port
          : uri.scheme.toLowerCase() == 'https'
          ? 443
          : 80;
      final task = await Socket.startConnect(addresses.first, port);
      if (uri.scheme.toLowerCase() != 'https') return task;
      final socket = task.socket.then(
        (plain) => SecureSocket.secure(
          plain,
          host: uri.host,
          supportedProtocols: const ['http/1.1'],
        ),
      );
      return ConnectionTask.fromSocket(socket, task.cancel);
    };
    return IOClient(client);
  }

  static bool _isPublic(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      final c = bytes[2];
      return !(a == 0 ||
          a == 10 ||
          a == 100 && b >= 64 && b <= 127 ||
          a == 127 ||
          a == 169 && b == 254 ||
          a == 172 && b >= 16 && b <= 31 ||
          a == 192 && b == 0 && c == 0 ||
          a == 192 && b == 0 && c == 2 ||
          a == 192 && b == 168 ||
          a == 198 && (b == 18 || b == 19) ||
          a == 198 && b == 51 && c == 100 ||
          a == 203 && b == 0 && c == 113 ||
          a >= 224);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final globalUnicast = bytes[0] >= 0x20 && bytes[0] <= 0x3f;
      final documentation =
          bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8;
      final sixToFour = bytes[0] == 0x20 && bytes[1] == 0x02;
      final nat64 =
          bytes.take(12).toList().join(',') == '0,100,255,155,0,0,0,0,0,0,0,0';
      return globalUnicast && !documentation && !sixToFour && !nat64;
    }
    return false;
  }

  static bool _isTextContent(String value) {
    if (value.isEmpty) return true;
    final type = value.split(';').first.trim();
    return type.startsWith('text/') ||
        type == 'application/json' ||
        type == 'application/xhtml+xml' ||
        type == 'application/xml' ||
        type.endsWith('+xml');
  }

  static _ExtractedPage _extract(String source, String contentType, Uri uri) {
    if (!contentType.contains('html') &&
        !source.trimLeft().toLowerCase().startsWith('<!doctype html') &&
        !source.trimLeft().toLowerCase().startsWith('<html')) {
      return _ExtractedPage(title: uri.host, text: _normalizeText(source));
    }
    final document = html_parser.parse(source);
    final title = _normalizeText(document.querySelector('title')?.text ?? '');
    for (final element in document.querySelectorAll(
      'script,style,noscript,svg,canvas,template,form',
    )) {
      element.remove();
    }
    final root =
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.body ??
        document.documentElement;
    if (root == null) {
      return _ExtractedPage(title: title.isEmpty ? uri.host : title, text: '');
    }
    for (final element in root.querySelectorAll(
      'p,div,section,article,h1,h2,h3,h4,h5,h6,li,tr,blockquote,pre,br',
    )) {
      element.append(dom.Text('\n'));
    }
    return _ExtractedPage(
      title: title.isEmpty ? uri.host : title,
      text: _normalizeText(root.text),
    );
  }

  static String _normalizeText(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[\t ]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();

  static _WebSlice _pageSlice(String text, int cursor, int maxChars) {
    final start = cursor.clamp(0, text.length);
    final end = math.min(start + maxChars, text.length);
    return _WebSlice(
      text.substring(start, end),
      nextCursor: end < text.length ? end : null,
    );
  }

  static _WebSlice _querySlice(
    String text,
    String query,
    int cursor,
    int maxChars,
  ) {
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    var searchAt = cursor.clamp(0, text.length);
    final passages = <String>[];
    var used = 0;
    var matches = 0;
    int? nextCursor;
    while (searchAt < text.length) {
      final match = lower.indexOf(needle, searchAt);
      if (match < 0) break;
      final start = math.max(0, match - 240);
      final end = math.min(text.length, match + needle.length + 500);
      final passage = text.substring(start, end).trim();
      final addition = (passages.isEmpty ? 0 : 5) + passage.length;
      if (passages.isNotEmpty && used + addition > maxChars) {
        nextCursor = match;
        break;
      }
      final remaining = maxChars - used - (passages.isEmpty ? 0 : 5);
      passages.add(
        passage.length > remaining ? passage.substring(0, remaining) : passage,
      );
      used += addition.clamp(0, maxChars);
      matches++;
      searchAt = match + math.max(needle.length, 1);
      if (used >= maxChars) {
        nextCursor = searchAt < text.length ? searchAt : null;
        break;
      }
    }
    return _WebSlice(
      passages.join('\n...\n'),
      nextCursor: nextCursor,
      matchCount: matches,
    );
  }
}

final class _CachedWebPage {
  final Uri url;
  final String title;
  final String text;
  final DateTime fetchedAt;
  const _CachedWebPage({
    required this.url,
    required this.title,
    required this.text,
    required this.fetchedAt,
  });
}

final class _ExtractedPage {
  final String title;
  final String text;
  const _ExtractedPage({required this.title, required this.text});
}

final class _WebSlice {
  final String content;
  final int? nextCursor;
  final int matchCount;
  const _WebSlice(this.content, {this.nextCursor, this.matchCount = 0});
}

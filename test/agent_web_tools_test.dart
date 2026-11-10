import 'dart:io';

import 'package:fknotes/agent/web_tools.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ToolContext context({
    RunScope scope = const RunScope(online: true, networkTools: true),
  }) {
    final run = AgentRun(
      id: 'run',
      sessionId: 'session',
      profileId: 'remote',
      noteStoreEpoch: 'notes',
      scope: scope,
      limits: const RunLimits(),
      system: '',
      skillId: 'assistant',
      createdAt: DateTime(2026),
    );
    return ToolContext(
      run: run,
      operationId: 'operation',
      argumentsDigest: 'arguments',
      cancel: CancellationToken(),
      ensureActive: () async {},
    );
  }

  Future<List<InternetAddress>> publicLookup(String _) async => [
    InternetAddress('8.8.8.8'),
  ];

  test('fetches, cleans, searches and reuses one cached public page', () async {
    var requests = 0;
    final body =
        '''
      <!doctype html><html><head><title>示例页面</title>
      <style>.hidden { display:none }</style></head><body>
      <main><h1>网页标题</h1><p>${List.filled(80, '第一段正文').join(' ')}</p>
      <p>这里包含需要定位的精确内容，后面还有说明。</p>
      <script>不要交给模型</script></main></body></html>
    ''';
    final tool = WebFetchTool(
      lookup: publicLookup,
      clientFactory: () => MockClient((request) async {
        requests++;
        return http.Response(
          body,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

    final first = await tool.execute(context(), {
      'url': 'https://example.com/article#section',
      'max_chars': 500,
    }, const ToolPreview(data: {}));
    expect(first.data['title'], '示例页面');
    expect(first.data['content'], contains('网页标题'));
    expect(first.data['content'], isNot(contains('不要交给模型')));
    expect(first.data['nextCursor'], isA<int>());
    expect(first.sources.single['url'], 'https://example.com/article');

    final found = await tool.execute(context(), {
      'url': 'https://example.com/article',
      'query': '精确内容',
      'max_chars': 1000,
    }, const ToolPreview(data: {}));
    expect(found.data['content'], contains('精确内容'));
    expect(found.data['matchCount'], 1);
    expect(requests, 1, reason: 'querying the page should reuse its cache');
  });

  test('blocks local and private addresses before sending HTTP', () async {
    var requests = 0;
    final tool = WebFetchTool(
      lookup: (host) async => [InternetAddress('192.168.1.4')],
      clientFactory: () => MockClient((request) async {
        requests++;
        return http.Response('private', 200);
      }),
    );

    for (final url in [
      'http://127.0.0.1/admin',
      'https://router.example/admin',
      'https://device.local/status',
    ]) {
      await expectLater(
        tool.execute(context(), {'url': url}, const ToolPreview(data: {})),
        throwsA(
          isA<HarnessException>().having(
            (error) => error.code,
            'code',
            'webFetchPrivate',
          ),
        ),
      );
    }
    expect(requests, 0);
  });

  test('validates every redirect before following it', () async {
    var requests = 0;
    final tool = WebFetchTool(
      lookup: publicLookup,
      clientFactory: () => MockClient((request) async {
        requests++;
        return http.Response('', 302, headers: {'location': 'http://[::1]/'});
      }),
    );

    await expectLater(
      tool.execute(context(), {
        'url': 'https://example.com/start',
      }, const ToolPreview(data: {})),
      throwsA(
        isA<HarnessException>().having(
          (error) => error.code,
          'code',
          'webFetchPrivate',
        ),
      ),
    );
    expect(requests, 1);
  });

  test('does not expose web_fetch outside a network grant', () async {
    final tool = WebFetchTool(
      lookup: publicLookup,
      clientFactory: () => MockClient((_) async => http.Response('ok', 200)),
    );
    final denied = context(scope: const RunScope());

    await expectLater(
      tool.execute(denied, {
        'url': 'https://example.com',
      }, const ToolPreview(data: {})),
      throwsA(
        isA<HarnessException>().having(
          (error) => error.code,
          'code',
          'networkDenied',
        ),
      ),
    );
  });
}

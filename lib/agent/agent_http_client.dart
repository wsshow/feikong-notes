import 'dart:convert';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:http/http.dart' as http;

/// One transport per inference. No redirects, hidden retries or raw error logs.
/// The SDK handles SSE; this boundary only enforces network policy and adds
/// explicitly supported vendor fields the typed SDK does not serialize.
class AgentHttpClient extends http.BaseClient {
  final http.Client inner;
  final Uri origin;
  final Json additions;
  final int maxResponseBytes;
  bool _closed = false;
  HarnessException? failure;
  AgentHttpClient(
    this.inner,
    this.origin, {
    this.additions = const {},
    this.maxResponseBytes = 16 * 1024 * 1024,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw const HarnessException('cancelled', 'Request cancelled.');
    }
    if (request.url.origin != origin.origin) {
      throw const HarnessException(
        'redirectDenied',
        'Credentials cannot be sent to another origin.',
      );
    }
    final bytes = await request.finalize().toBytes();
    final outgoing = http.Request(request.method, request.url)
      ..followRedirects = false
      ..headers.addAll(request.headers);
    if (additions.isNotEmpty) {
      final body = jsonDecode(utf8.decode(bytes)) as Json;
      body.addAll(additions);
      outgoing.body = jsonEncode(body);
    } else {
      outgoing.bodyBytes = bytes;
    }
    if (_closed) {
      throw const HarnessException('cancelled', 'Request cancelled.');
    }
    final response = await inner.send(outgoing);
    if (response.statusCode >= 300) {
      // Do not expose a provider's response body (it can echo prompts/keys).
      final status = response.statusCode;
      close();
      failure = HarnessException(
        switch (status) {
          401 || 403 => 'authentication',
          404 => 'endpointNotFound',
          408 || 504 => 'requestTimeout',
          400 || 409 || 422 => 'invalidRequest',
          413 => 'contextOverflow',
          429 => 'rateLimited',
          >= 300 && < 400 => 'redirectDenied',
          >= 500 => 'serviceUnavailable',
          _ => 'httpError',
        },
        'Model endpoint returned HTTP $status.',
        retryable: status == 408 || status == 429 || status >= 500,
      );
      throw failure!;
    }
    var received = 0;
    final stream = response.stream.map((bytes) {
      received += bytes.length;
      if (received > maxResponseBytes) {
        failure = const HarnessException(
          'responseSize',
          'The endpoint response exceeded the safety limit.',
        );
        close();
        throw failure!;
      }
      return bytes;
    });
    return http.StreamedResponse(
      stream,
      response.statusCode,
      headers: response.headers,
      contentLength: response.contentLength,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    inner.close();
  }
}

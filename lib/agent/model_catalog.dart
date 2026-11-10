import 'dart:async';
import 'dart:convert';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:http/http.dart' as http;

import 'agent_http_client.dart';
import 'credential_vault.dart';
import 'model_profile.dart';

class CatalogModel {
  final String id;
  final String? name;
  const CatalogModel(this.id, {this.name});
}

/// Catalog discovery is an explicit, credentialed GET, never an inference.
/// Parse the common ID subset so compatible gateways need not return every
/// vendor-specific model field. A listed ID does not imply chat/tool support.
class ModelCatalog {
  final CredentialVault vault;
  final http.Client Function() clientFactory;
  final Duration timeout;
  ModelCatalog(
    this.vault, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 20),
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<List<CatalogModel>> fetch(
    ModelProfile connection,
    CancellationToken cancel, {
    String? apiKey,
  }) async {
    cancel.check();
    if (!connection.isRemote) {
      throw const HarnessException(
        'invalidProfile',
        'Select an online service.',
      );
    }
    final base = connection.baseUri;
    final transport = AgentHttpClient(
      clientFactory(),
      base,
      maxResponseBytes: 2 * 1024 * 1024,
    );
    final stopped = Completer<List<CatalogModel>>();
    final unregister = cancel.onCancel(() {
      transport.close();
      if (!stopped.isCompleted) {
        stopped.completeError(
          const HarnessException('cancelled', 'Model discovery cancelled.'),
        );
      }
    });
    Future<List<CatalogModel>> read() async {
      final key = apiKey?.trim().isNotEmpty == true
          ? apiKey!.trim()
          : await vault.read(connection.credentialId);
      cancel.check();
      if (key == null || key.trim().isEmpty) {
        throw const HarnessException('missingCredential', 'Enter an API key.');
      }
      final anthropic = connection.protocol == ModelProtocol.anthropic;
      final endpoint = base.replace(
        path: '${base.path}${anthropic ? '/v1' : ''}/models',
      );
      final result = <String, CatalogModel>{};
      final cursors = <String>{};
      String? after;
      for (var page = 0; page < 20; page++) {
        cancel.check();
        final uri = endpoint.replace(
          queryParameters: anthropic || after != null
              ? {'limit': '1000', 'after_id': ?after}
              : null,
        );
        final response = await transport.get(
          uri,
          headers: {
            'accept': 'application/json',
            if (anthropic) ...{
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            } else
              'authorization': 'Bearer $key',
          },
        );
        cancel.check();
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is! Map || json['data'] is! List) {
          throw const HarnessException(
            'modelCatalogFormat',
            'Invalid catalog.',
          );
        }
        final data = json['data'] as List;
        if (data.length > 5000) {
          throw const HarnessException(
            'modelCatalogLimit',
            'Catalog too large.',
          );
        }
        for (final item in data) {
          if (item is! Map || item['id'] is! String) continue;
          final id = item['id'] as String;
          if (!ModelProfile.validModelId(id)) continue;
          final name = item['display_name'] ?? item['name'];
          result.putIfAbsent(
            id,
            () => CatalogModel(
              id,
              name: name is String && name.length <= 160
                  ? name.replaceAll(RegExp(r'\s+'), ' ').trim()
                  : null,
            ),
          );
        }
        if (result.length > 5000) {
          throw const HarnessException(
            'modelCatalogLimit',
            'Catalog too large.',
          );
        }
        if (json['has_more'] != true) return result.values.toList();
        final next = json['last_id'];
        if (next is! String ||
            !ModelProfile.validModelId(next) ||
            !cursors.add(next) ||
            data.isEmpty) {
          throw const HarnessException('modelCatalogFormat', 'Invalid cursor.');
        }
        after = next;
      }
      throw const HarnessException(
        'modelCatalogLimit',
        'Too many catalog pages.',
      );
    }

    try {
      return await Future.any([read(), stopped.future]).timeout(timeout);
    } on HarnessException {
      rethrow;
    } on TimeoutException {
      throw const HarnessException(
        'requestTimeout',
        'Model discovery timed out.',
      );
    } catch (_) {
      cancel.check();
      if (transport.failure != null) throw transport.failure!;
      // Never expose response bodies, credentials or SDK/client exception text.
      throw const HarnessException(
        'modelCatalogFormat',
        'Cannot read catalog.',
      );
    } finally {
      unregister();
      transport.close();
      cancel.cancel();
    }
  }
}

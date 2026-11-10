import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fknotes_harness/fknotes_harness.dart';

enum ModelProtocol { local, chatCompletions, responses, anthropic }

/// Credentials are never part of a profile, URL, diagnostic or task snapshot.
class ModelProfile {
  final String id;
  final String name;
  final ModelProtocol protocol;
  final String endpoint;
  final String model;

  /// Models in one service share credentials, but retain stable task IDs.
  /// Legacy profiles use their original ID, without moving any saved key.
  final String? serviceId;
  final ModelCapabilities capabilities;
  final bool thinking;
  final bool includeUsage;
  final bool statelessResponses;
  final bool legacyMaxTokens;

  const ModelProfile({
    required this.id,
    required this.name,
    required this.protocol,
    this.endpoint = '',
    this.model = '',
    this.serviceId,
    this.capabilities = const ModelCapabilities(),
    this.thinking = false,
    this.includeUsage = true,
    this.statelessResponses = true,
    this.legacyMaxTokens = false,
  });

  static const local = ModelProfile(
    id: 'local',
    name: 'Local',
    protocol: ModelProtocol.local,
  );
  bool get isRemote => protocol != ModelProtocol.local;
  int get maxOutputTokens =>
      capabilities.maxOutputTokens ??
      math.min(2048, capabilities.contextTokens ~/ 4);
  RunLimits get defaultRunLimits => !isRemote
      ? const RunLimits()
      : RunLimits(
          maxOutputTokens: maxOutputTokens,
          // A large configured output must fit the initial task budget too.
          maxTokens: math.max(
            64000,
            capabilities.contextTokens + maxOutputTokens,
          ),
        );

  /// Token shorthand uses binary units, shown explicitly beside the fields.
  static int? parseTokenCount(String value) {
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*([kKmM]?)$',
    ).firstMatch(value.trim().replaceAll(',', ''));
    if (match == null) return null;
    final amount = double.tryParse(match[1]!);
    if (amount == null) return null;
    final multiplier = switch (match[2]!.toUpperCase()) {
      'K' => 1024,
      'M' => 1024 * 1024,
      _ => 1,
    };
    final tokens = amount * multiplier;
    if (!tokens.isFinite ||
        tokens < 1 ||
        tokens > 2 * 1024 * 1024 ||
        tokens != tokens.roundToDouble()) {
      return null;
    }
    return tokens.toInt();
  }

  String get connectionId => serviceId ?? id;
  String get credentialId => 'fknotes.agent.key.$connectionId';
  String get displayName => isRemote ? '$model · $name' : name;

  ModelProfile copyWith({
    String? id,
    String? name,
    ModelProtocol? protocol,
    String? endpoint,
    String? model,
    String? serviceId,
    ModelCapabilities? capabilities,
    bool? thinking,
    bool? includeUsage,
    bool? statelessResponses,
    bool? legacyMaxTokens,
  }) => ModelProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    serviceId: serviceId ?? this.serviceId,
    capabilities: capabilities ?? this.capabilities,
    thinking: thinking ?? this.thinking,
    includeUsage: includeUsage ?? this.includeUsage,
    statelessResponses: statelessResponses ?? this.statelessResponses,
    legacyMaxTokens: legacyMaxTokens ?? this.legacyMaxTokens,
  );

  static bool validModelId(String value) =>
      value.isNotEmpty &&
      value.length <= 200 &&
      !RegExp(r'[\s,，;；\x00-\x1f\x7f]').hasMatch(value);

  static List<String> parseModelIds(String value) {
    if (value.length > 24000) {
      throw const HarnessException('invalidModelList', 'Too many models.');
    }
    final models = value
        .split(RegExp(r'[,，;；\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (models.length > 100 || models.any((s) => !validModelId(s))) {
      throw const HarnessException('invalidModelList', 'Invalid model list.');
    }
    return models;
  }

  String get binding => contentDigest({
    'id': id,
    'protocol': protocol.name,
    'endpoint': endpoint,
    'model': model,
  });

  /// A base URL, not a full completion URL. Explicit loopback HTTP is useful
  /// for a user's local gateway; all other endpoints must use TLS.
  Uri get baseUri {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            uri.scheme == 'http' &&
                {'localhost', '127.0.0.1', '::1'}.contains(uri.host))) {
      throw const HarnessException(
        'invalidEndpoint',
        'Use an HTTPS base URL without credentials, query or fragment.',
      );
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    for (final suffix in ['/chat/completions', '/responses', '/messages']) {
      if (path.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
      }
    }
    if (protocol == ModelProtocol.anthropic && path.endsWith('/v1')) {
      path = path.substring(0, path.length - 3);
    }
    return uri.replace(path: path);
  }

  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(connectionId) ||
        name.trim().isEmpty ||
        name.length > 120) {
      throw const HarnessException(
        'invalidProfile',
        'Invalid model configuration.',
      );
    }
    if (capabilities.contextTokens < 1024 ||
        capabilities.contextTokens > 2 * 1024 * 1024 ||
        maxOutputTokens < 1 ||
        maxOutputTokens >= capabilities.contextTokens) {
      throw const HarnessException(
        'invalidModelLimits',
        'Output tokens must be positive and smaller than the context window.',
      );
    }
    if (isRemote) {
      baseUri;
      if (!validModelId(model)) {
        throw const HarnessException(
          'invalidModel',
          'Enter the provider model identifier.',
        );
      }
      if (capabilities.audio ||
          capabilities.webSearch && protocol == ModelProtocol.chatCompletions) {
        throw const HarnessException(
          'unsupportedCapability',
          'This protocol adapter does not support the selected capability.',
        );
      }
    }
  }

  Json toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'endpoint': endpoint,
    'model': model,
    if (serviceId != null) 'serviceId': serviceId,
    'capabilities': capabilities.toJson(),
    'thinking': thinking,
    'includeUsage': includeUsage,
    'statelessResponses': statelessResponses,
    'legacyMaxTokens': legacyMaxTokens,
  };
  factory ModelProfile.fromJson(Json j) => ModelProfile(
    id: j['id'] as String,
    name: j['name'] as String,
    protocol: ModelProtocol.values.byName(j['protocol'] as String),
    endpoint: j['endpoint'] as String? ?? '',
    model: j['model'] as String? ?? '',
    serviceId: j['serviceId'] as String?,
    capabilities: ModelCapabilities.fromJson(
      Map<String, dynamic>.from(j['capabilities'] as Map),
    ),
    thinking: j['thinking'] == true,
    includeUsage: j['includeUsage'] != false,
    statelessResponses: j['statelessResponses'] != false,
    legacyMaxTokens: j['legacyMaxTokens'] == true,
  );
}

class ModelProfileStore {
  final File file;
  Future<void> _queue = Future.value();
  ModelProfileStore(this.file);

  Future<Json> _read() async {
    if (!await file.exists()) {
      return {'version': 1, 'selected': 'local', 'profiles': []};
    }
    final data = jsonDecode(await file.readAsString()) as Json;
    if (data['version'] != 1 && data['version'] != 2) {
      throw const HarnessException(
        'profileVersion',
        'Unsupported model settings version.',
      );
    }
    return data;
  }

  Future<List<ModelProfile>> list() async => [
    ModelProfile.local,
    for (final j in (await _read())['profiles'] as List)
      ModelProfile.fromJson(Map<String, dynamic>.from(j as Map)),
  ];
  Future<String> selectedId() async => (await _read())['selected'] as String;
  // Application default for new grants, independent of the selected provider.
  // Existing tasks carry their own immutable choice until explicitly resumed.
  Future<bool> defaultRequireApproval() async =>
      (await _read())['requireApproval'] == true;
  Future<void> setDefaultRequireApproval(bool value) =>
      _edit((j) => j['requireApproval'] = value);
  Future<ModelProfile> get(String id) async => (await list()).firstWhere(
    (p) => p.id == id,
    orElse: () => throw const HarnessException(
      'profileMissing',
      'Select an available model configuration.',
    ),
  );
  Future<void> save(ModelProfile profile) {
    profile.validate();
    if (!profile.isRemote || profile.id == 'local') {
      throw ArgumentError('Reserved local profile');
    }
    return _edit((j) {
      (j['profiles'] as List).removeWhere((p) => p['id'] == profile.id);
      (j['profiles'] as List).add(profile.toJson());
    });
  }

  /// Atomically replace one service's models. No partial batch writes and no
  /// automatic merging by hostname (two accounts may use the same endpoint).
  Future<void> saveService(
    String serviceId,
    List<ModelProfile> profiles, {
    String? selectedId,
  }) {
    if (profiles.isEmpty || profiles.length > 100) {
      throw const HarnessException('invalidModelList', 'Select 1–100 models.');
    }
    for (final profile in profiles) {
      profile.validate();
      if (!profile.isRemote ||
          profile.id == 'local' ||
          profile.connectionId != serviceId) {
        throw const HarnessException('invalidProfile', 'Invalid service.');
      }
    }
    return _edit((j) {
      final items = j['profiles'] as List;
      final previousIds = items
          .where((p) => (p['serviceId'] ?? p['id']) == serviceId)
          .map((p) => p['id'])
          .toSet();
      items.removeWhere((p) => (p['serviceId'] ?? p['id']) == serviceId);
      if (items.any((p) => profiles.any((n) => n.id == p['id']))) {
        throw const HarnessException('invalidProfile', 'Duplicate model ID.');
      }
      items.addAll(profiles.map((p) => p.toJson()));
      if (selectedId != null) {
        if (!profiles.any((p) => p.id == selectedId)) {
          throw const HarnessException(
            'profileMissing',
            'Select a saved model.',
          );
        }
        j['selected'] = selectedId;
      } else if (previousIds.contains(j['selected']) &&
          !profiles.any((p) => p.id == j['selected'])) {
        j['selected'] = profiles.first.id;
      }
    });
  }

  Future<void> deleteService(String serviceId) => _edit((j) {
    final items = j['profiles'] as List;
    final removed = items
        .where((p) => (p['serviceId'] ?? p['id']) == serviceId)
        .map((p) => p['id'])
        .toSet();
    items.removeWhere((p) => (p['serviceId'] ?? p['id']) == serviceId);
    if (removed.contains(j['selected'])) j['selected'] = 'local';
  });

  Future<void> select(String id) => _edit((j) {
    if (id != 'local' && !(j['profiles'] as List).any((p) => p['id'] == id)) {
      throw const HarnessException(
        'profileMissing',
        'Select an available model configuration.',
      );
    }
    j['selected'] = id;
  });
  Future<void> delete(String id) => _edit((j) {
    (j['profiles'] as List).removeWhere((p) => p['id'] == id);
    if (j['selected'] == id) j['selected'] = 'local';
  });
  Future<void> _edit(void Function(Json) edit) {
    final next = _queue.then((_) async {
      final data = await _read();
      edit(data);
      final ids = <String>{};
      final groups = <String, ModelProfile>{};
      final models = <String, Set<String>>{};
      for (final json in data['profiles'] as List) {
        final p = ModelProfile.fromJson(Map<String, dynamic>.from(json as Map));
        p.validate();
        final first = groups.putIfAbsent(p.connectionId, () => p);
        if (!p.isRemote ||
            p.id == 'local' ||
            !ids.add(p.id) ||
            !(models[p.connectionId] ??= {}).add(p.model) ||
            p.name != first.name ||
            p.protocol != first.protocol ||
            p.endpoint != first.endpoint) {
          throw const HarnessException(
            'invalidProfile',
            'Inconsistent service.',
          );
        }
      }
      data['version'] = 2;
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.part');
      await temporary.writeAsString(jsonEncode(data), flush: true);
      await temporary.rename(file.path);
    });
    _queue = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:uuid/uuid.dart';

import '../editor/note_markdown_mutation.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../services/note_edit_guard.dart';
import '../services/note_repository.dart';

/// Only successful, locally recorded creation receipts extend a task's read
/// scope. A model-supplied ID or an unsuccessful proposal cannot do so.
Set<String> taskCreatedNoteIds(AgentRun run) => {
  for (final action in run.actions)
    if (action['name'] == 'propose_note_changes' && action['undone'] != true)
      for (final change
          in (((action['preview'] as Json?)?['data'] as Json?)?['changes']
                  as List? ??
              []))
        if (change['before'] == null) change['noteId'] as String,
};

/// Successful note mutations produced by this task, grouped by note.
///
/// A note can be changed more than once during a run. The latest receipt owns
/// its visible state while [created] records whether the task created it at any
/// point. Failed tool calls and explicitly undone actions never appear here.
Map<String, Json> taskNoteChanges(AgentRun run) {
  final result = <String, Json>{};
  for (final action in run.actions) {
    if (action['name'] != 'propose_note_changes' || action['undone'] == true) {
      continue;
    }
    final changes =
        (((action['preview'] as Json?)?['data'] as Json?)?['changes']
                    as List? ??
                const [])
            .cast<Json>();
    final receipts = <String, Json>{
      for (final receipt
          in ((((action['result'] as Json?)?['data'] as Json?)?['results']
                      as List? ??
                  const []))
              .cast<Json>())
        if (receipt['noteId'] case final String id) id: receipt,
    };
    for (final change in changes) {
      final id = change['noteId'] as String?;
      final receipt = id == null ? null : receipts[id];
      if (id == null || receipt == null) continue;
      final before = change['before'] as Json?;
      final after = change['after'] as Json?;
      final previous = result.remove(id);
      result[id] = {
        'noteId': id,
        'kind': change['kind'],
        'created': previous?['created'] == true || before == null,
        'deleted': receipt['deleted'] == true,
        'revision': receipt['revision'],
        'previousRevision': change['baseRevision'],
        'title':
            after?['title'] ?? before?['title'] ?? previous?['title'] ?? '',
        'tags':
            after?['tags'] ?? before?['tags'] ?? previous?['tags'] ?? const [],
      };
    }
  }
  return Map.unmodifiable(result);
}

class NoteToolAccess {
  final Future<NoteRepository> Function() repository;
  final void Function(RunScope scope) validateScope;
  final NoteEditGuard editors;
  NoteToolAccess({
    required this.repository,
    required this.validateScope,
    NoteEditGuard? editors,
  }) : editors = editors ?? NoteEditGuard.instance;

  Future<Note> read(ToolContext context, String id) async {
    await context.ensureActive();
    validateScope(context.run.scope);
    if (!context.run.scope.permitsNote(id) &&
        !taskCreatedNoteIds(context.run).contains(id)) {
      throw const HarnessException(
        'noteScope',
        'This note is outside the granted data scope.',
        toolObservation: true,
      );
    }
    final repo = await repository();
    final key = NoteId.parse(id);
    final note = await repo.get(
      key,
      privateSpace: context.run.scope.privateNotes,
    );
    if (note == null) {
      throw const HarnessException(
        'noteMissing',
        'The note is unavailable in this data scope.',
        toolObservation: true,
      );
    }
    return note;
  }

  void checkWrite(ToolContext context, Iterable<String> ids) {
    context.cancel.check();
    validateScope(context.run.scope);
    if (!context.run.scope.writeNotes) {
      throw const HarnessException(
        'writePermission',
        'Note modifications have not been authorized.',
      );
    }
    if (ids.any((id) => editors.isOpen(NoteId.parse(id)))) {
      throw const HarnessException(
        'editorOpen',
        'This note is open in an editor. Apply suggestions there or close it before approving background changes.',
        toolObservation: true,
      );
    }
  }

  Future<T> domain<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on NoteWriteConflict {
      throw const HarnessException(
        'noteChanged',
        'A note changed. Generate and review a new preview.',
        toolObservation: true,
      );
    } on NoteAgentConflict catch (e) {
      throw HarnessException(
        e.code,
        'The note library or operation no longer matches this task.',
      );
    }
  }
}

Json _source(Note n, String excerpt) => {
  'noteId': n.id.value,
  'revision': n.revision,
  'title': n.title,
  'tags': n.tags,
  'createdAt': n.createdAt.toIso8601String(),
  'updatedAt': n.updatedAt.toIso8601String(),
  'isPinned': n.isPinned,
  'attachmentCount': n.assets.length,
  'excerpt': excerpt,
};

Json _searchSource(Note note, String query) {
  final text = note.contentProjection.plainText;
  const excerptLimit = 500;
  final match = query.isEmpty
      ? -1
      : text.toLowerCase().indexOf(query.toLowerCase());
  var start = match < 0 ? 0 : (match - excerptLimit ~/ 3).clamp(0, text.length);
  var end = (start + excerptLimit).clamp(start, text.length);
  if (end - start < excerptLimit) {
    start = (end - excerptLimit).clamp(0, end);
  }
  start = _safeUtf16Boundary(text, start);
  end = _safeUtf16Boundary(text, end);
  final omittedBefore = start;
  final omittedAfter = text.length - end;
  return {
    ..._source(note, text.substring(start, end)),
    'contentLength': text.length,
    'excerptStart': start,
    'excerptEnd': end,
    'excerptLength': end - start,
    'offsetUnit': 'utf16',
    'omittedBefore': omittedBefore,
    'omittedAfter': omittedAfter,
    'omittedCharacters': omittedBefore + omittedAfter,
    'truncated': omittedBefore > 0 || omittedAfter > 0,
  };
}

int _safeUtf16Boundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return offset;
  final codeUnit = text.codeUnitAt(offset);
  return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF ? offset - 1 : offset;
}

DateTime? _dateArgument(Json arguments, String key, {bool end = false}) {
  final raw = (arguments[key] as String?)?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      final parts = raw.split('-').map(int.parse).toList();
      final local = end
          ? DateTime(parts[0], parts[1], parts[2], 23, 59, 59, 999)
          : DateTime(parts[0], parts[1], parts[2]);
      if (local.year != parts[0] ||
          local.month != parts[1] ||
          local.day != parts[2]) {
        throw const FormatException();
      }
      return local.toUtc();
    }
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw HarnessException(
      'invalidArguments',
      '$key must be an ISO-8601 date or timestamp.',
    );
  }
}

int _compareNotes(Note a, Note b, NoteQuerySort sort) {
  final result = switch (sort) {
    NoteQuerySort.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
    NoteQuerySort.createdDesc => b.createdAt.compareTo(a.createdAt),
    NoteQuerySort.titleAsc => a.title.toLowerCase().compareTo(
      b.title.toLowerCase(),
    ),
    NoteQuerySort.titleDesc => b.title.toLowerCase().compareTo(
      a.title.toLowerCase(),
    ),
  };
  return result != 0 ? result : a.id.value.compareTo(b.id.value);
}

bool _matchesNote(Note note, NoteQueryFilter filter) {
  final query = filter.query.toLowerCase();
  if (query.isNotEmpty && !note.searchText.toLowerCase().contains(query)) {
    return false;
  }
  final title = filter.title.toLowerCase();
  if (title.isNotEmpty && !note.title.toLowerCase().contains(title)) {
    return false;
  }
  final noteTags = note.tags.map((tag) => tag.toLowerCase()).toSet();
  final tags = filter.tags.map((tag) => tag.toLowerCase());
  if (filter.matchAllTags) {
    if (!noteTags.containsAll(tags)) return false;
  } else if (tags.isNotEmpty && !tags.any(noteTags.contains)) {
    return false;
  }
  if (filter.createdFrom case final value?
      when note.createdAt.isBefore(value)) {
    return false;
  }
  if (filter.createdTo case final value? when note.createdAt.isAfter(value)) {
    return false;
  }
  if (filter.updatedFrom case final value?
      when note.updatedAt.isBefore(value)) {
    return false;
  }
  if (filter.updatedTo case final value? when note.updatedAt.isAfter(value)) {
    return false;
  }
  if (filter.isPinned case final value? when note.isPinned != value) {
    return false;
  }
  if (filter.hasAttachments case final value?
      when note.assets.isNotEmpty != value) {
    return false;
  }
  return true;
}

String _bounded(String text, int length) =>
    text.length > length ? text.substring(0, length) : text;

class SearchNotesTool extends AgentTool {
  final NoteToolAccess access;
  SearchNotesTool(this.access);
  @override
  ToolSpec get spec => ToolSpec(
    name: 'search_notes',
    description:
        'Search authorized notes with structured filters for full text, title, exact tags, created/updated time ranges, pinned state, and attachment presence. Combine filters to narrow results. Set browseAll to true only when the user explicitly requests a library-wide task. Never browse all notes merely to inspect structure, choose a write destination, or proactively check for duplicates. Results are paginated and include metadata plus query-centered excerpts with UTF-16 ranges and explicit omitted-character counts.',
    schema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'minLength': 1,
          'maxLength': 200,
          'description':
              'Specific keywords derived from the user task. Do not use blank or wildcard queries.',
        },
        'title': {
          'type': 'string',
          'minLength': 1,
          'maxLength': 200,
          'description': 'Case-insensitive title substring.',
        },
        'tags': {
          'type': 'array',
          'items': {'type': 'string', 'minLength': 1, 'maxLength': 100},
          'minItems': 1,
          'maxItems': 10,
          'uniqueItems': true,
          'description': 'Exact note tags, matched case-insensitively.',
        },
        'tagMode': {
          'type': 'string',
          'enum': ['all', 'any'],
          'description': 'Whether all or any supplied tags must match.',
        },
        for (final field in const [
          'createdFrom',
          'createdTo',
          'updatedFrom',
          'updatedTo',
        ])
          field: {
            'type': 'string',
            'minLength': 10,
            'maxLength': 40,
            'description':
                'Inclusive ISO-8601 date or timestamp boundary. A date uses the full local day.',
          },
        'isPinned': {'type': 'boolean'},
        'hasAttachments': {'type': 'boolean'},
        'sort': {
          'type': 'string',
          'enum': ['updatedDesc', 'createdDesc', 'titleAsc', 'titleDesc'],
        },
        'browseAll': {
          'type': 'boolean',
          'enum': [true],
          'description':
              'Explicit whole-library pagination. Use only for a user-requested library-wide task.',
        },
        'cursor': {'type': 'integer', 'minimum': 0},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20},
      },
      'anyOf': [
        {
          'required': ['query'],
        },
        for (final field in const [
          'title',
          'tags',
          'createdFrom',
          'createdTo',
          'updatedFrom',
          'updatedTo',
          'isPinned',
          'hasAttachments',
        ])
          {
            'required': [field],
          },
        {
          'required': ['browseAll'],
        },
      ],
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
    access.validateScope(context.run.scope);
    if (!context.run.scope.readNotes) {
      throw const HarnessException(
        'readPermission',
        'Grant access to notes before searching.',
      );
    }
    final query = (arguments['query'] as String? ?? '').trim();
    final title = (arguments['title'] as String? ?? '').trim();
    final tags = (arguments['tags'] as List? ?? const [])
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final createdFrom = _dateArgument(arguments, 'createdFrom');
    final createdTo = _dateArgument(arguments, 'createdTo', end: true);
    final updatedFrom = _dateArgument(arguments, 'updatedFrom');
    final updatedTo = _dateArgument(arguments, 'updatedTo', end: true);
    final hasStructuredFilter =
        query.isNotEmpty ||
        title.isNotEmpty ||
        tags.isNotEmpty ||
        createdFrom != null ||
        createdTo != null ||
        updatedFrom != null ||
        updatedTo != null ||
        arguments.containsKey('isPinned') ||
        arguments.containsKey('hasAttachments');
    final browseAll = arguments['browseAll'] == true && !hasStructuredFilter;
    if (!hasStructuredFilter && !browseAll) {
      throw const HarnessException(
        'invalidArguments',
        'Provide a search filter or an explicit whole-library browse.',
      );
    }
    if (createdFrom != null &&
        createdTo != null &&
        createdFrom.isAfter(createdTo)) {
      throw const HarnessException(
        'invalidArguments',
        'createdFrom must not be later than createdTo.',
      );
    }
    if (updatedFrom != null &&
        updatedTo != null &&
        updatedFrom.isAfter(updatedTo)) {
      throw const HarnessException(
        'invalidArguments',
        'updatedFrom must not be later than updatedTo.',
      );
    }
    final sortName = arguments['sort'] as String? ?? 'updatedDesc';
    final sort = NoteQuerySort.values
        .where((value) => value.name == sortName)
        .firstOrNull;
    if (sort == null) {
      throw const HarnessException(
        'invalidArguments',
        'Unsupported note sort order.',
      );
    }
    final filter = NoteQueryFilter(
      query: query,
      title: title,
      tags: tags,
      matchAllTags: arguments['tagMode'] != 'any',
      createdFrom: createdFrom,
      createdTo: createdTo,
      updatedFrom: updatedFrom,
      updatedTo: updatedTo,
      isPinned: arguments['isPinned'] as bool?,
      hasAttachments: arguments['hasAttachments'] as bool?,
      sort: sort,
    );
    final repo = await access.repository();
    final cursor = arguments['cursor'] as int? ?? 0;
    final limit = arguments['limit'] as int? ?? 10;
    final notes = <Note>[];
    var total = 0;
    if (context.run.scope.allNotes) {
      final result = await repo.queryPage(
        filter,
        privateSpace: context.run.scope.privateNotes,
        offset: cursor,
        limit: limit,
      );
      total = result.total;
      notes.addAll(result.notes);
    } else {
      for (final id in context.run.scope.noteIds) {
        final note = await access.read(context, id);
        if (_matchesNote(note, filter)) {
          notes.add(note);
        }
      }
      total = notes.length;
    }
    notes.removeWhere((n) => !context.run.scope.permitsNote(n.id.value));
    notes.sort((a, b) => _compareNotes(a, b, sort));
    final page = context.run.scope.allNotes
        ? notes
        : notes.skip(cursor).take(limit).toList();
    await context.ensureActive();
    final sources = [for (final n in page) _searchSource(n, query)];
    return ToolResult({
      'notes': sources,
      'nextCursor': cursor + page.length < total ? cursor + page.length : null,
      'total': total,
    }, sources: sources);
  }
}

class ReadNotesTool extends AgentTool {
  final NoteToolAccess access;
  ReadNotesTool(this.access);
  @override
  ToolSpec get spec => ToolSpec(
    name: 'read_notes',
    description:
        'Read authorized notes with UTF-16 document offsets for precise edits. Embeds occupy one offset and cannot be overwritten by text edits. Read additional ranges when truncated.',
    schema: {
      'type': 'object',
      'properties': {
        'ids': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'maxItems': 8,
          'uniqueItems': true,
        },
        'start': {'type': 'integer', 'minimum': 0},
        'length': {'type': 'integer', 'minimum': 1, 'maximum': 6000},
      },
      'required': ['ids'],
      'additionalProperties': false,
    },
  );
  @override
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  ) async {
    final results = <Json>[];
    final sources = <Json>[];
    for (final id in (arguments['ids'] as List).cast<String>()) {
      final n = await access.read(context, id);
      final delta = n.document.toDelta();
      final documentLength = delta.toList().fold<int>(
        0,
        (sum, op) => sum + op.length!,
      );
      final start = (arguments['start'] as int? ?? 0).clamp(0, documentLength);
      final end = (start + (arguments['length'] as int? ?? 4000)).clamp(
        start,
        documentLength,
      );
      final slice = delta.slice(start, end);
      final text = slice
          .map(
            (op) => op.data is String
                ? op.data as String
                : NoteDocument.objectReplacementCharacter,
          )
          .join();
      results.add({
        'noteId': id,
        'revision': n.revision,
        'title': n.title,
        'tags': n.tags,
        'text': text,
        'start': start,
        'end': end,
        'documentLength': delta.toList().fold<int>(
          0,
          (sum, op) => sum + op.length!,
        ),
        'truncated': end < documentLength,
      });
      sources.add(_source(n, _bounded(text, 500)));
    }
    await context.ensureActive();
    return ToolResult({'notes': results}, sources: sources);
  }
}

class ProposeNoteChangesTool extends AgentTool {
  final NoteToolAccess access;
  ProposeNoteChangesTool(this.access);
  @override
  ToolSpec get spec => ToolSpec(
    name: 'propose_note_changes',
    risk: ToolRisk.write,
    idempotency: ToolIdempotency.transactional,
    description:
        'Submit an atomic note change group: create, append, replace_range, metadata, or delete. Text for create, append, and replace_range accepts Markdown and is stored as native note formatting. Existing notes require the exact revision from read_notes. Delete only when the user explicitly asks to remove a note. Offsets are UTF-16; preserve embeds and unrelated content. The harness applies the task approval policy before committing.',
    schema: {
      'type': 'object',
      'properties': {
        'changes': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 30,
          'items': {
            'type': 'object',
            'properties': {
              'kind': {
                'type': 'string',
                'enum': [
                  'create',
                  'append',
                  'replace_range',
                  'metadata',
                  'delete',
                ],
              },
              'noteId': {'type': 'string'},
              'baseRevision': {'type': 'integer', 'minimum': 1},
              'title': {'type': 'string', 'maxLength': 200},
              'text': {
                'type': 'string',
                'maxLength': 12000,
                'description':
                    'Note content. For create, append, and replace_range, use Markdown headings, quotes, lists and inline formatting when appropriate.',
              },
              'tags': {
                'type': 'array',
                'maxItems': 30,
                'items': {'type': 'string', 'maxLength': 80},
              },
              'start': {'type': 'integer', 'minimum': 0},
              'end': {'type': 'integer', 'minimum': 0},
            },
            'required': ['kind'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['changes'],
      'additionalProperties': false,
    },
  );

  @override
  Future<ToolPreview> prepare(ToolContext context, Json arguments) async {
    final changes = <Json>[];
    final versions = <String, int>{};
    var index = 0;
    for (final raw in arguments['changes'] as List) {
      final c = Map<String, dynamic>.from(raw as Map);
      final creating = c['kind'] == 'create';
      final deleting = c['kind'] == 'delete';
      final id = creating
          ? const Uuid().v5(
              Namespace.url.value,
              '${context.operationId}:${index++}',
            )
          : c['noteId'] as String?;
      if (id == null || !creating && c['baseRevision'] is! int) {
        throw const HarnessException(
          'invalidChanges',
          'An existing note ID and base revision are required.',
          toolObservation: true,
        );
      }
      access.checkWrite(context, [id]);
      final before = creating ? null : await access.read(context, id);
      if (before != null && before.revision != c['baseRevision']) {
        throw const HarnessException(
          'noteChanged',
          'Read the latest note revision before proposing changes.',
          toolObservation: true,
        );
      }
      final document = before?.document ?? NoteDocument.empty();
      var next = document;
      if (c['kind'] != 'metadata' && !deleting) {
        if (c['text'] is! String) {
          throw const HarnessException(
            'invalidChanges',
            'Text is required for this edit.',
            toolObservation: true,
          );
        }
        final text = c['text'] as String;
        if (creating) {
          next = NoteMarkdownMutation.replaceDocument(text);
        } else {
          final delta = document.toDelta();
          final documentLength = delta.toList().fold<int>(
            0,
            (sum, op) => sum + op.length!,
          );
          final append = c['kind'] == 'append';
          final start = append ? documentLength - 1 : c['start'] as int?;
          final end = append ? start : c['end'] as int?;
          if (start == null ||
              end == null ||
              start < 0 ||
              end < start ||
              end >= documentLength) {
            throw const HarnessException(
              'invalidRange',
              'The edit range must stay inside the text document.',
              toolObservation: true,
            );
          }
          if (delta
              .slice(start, end)
              .toList()
              .any((op) => op.data is! String)) {
            throw const HarnessException(
              'embedProtected',
              'Text edits cannot remove attachments, tables or dividers.',
              toolObservation: true,
            );
          }
          final rawText = delta
              .map((op) => op.data is String ? op.data as String : '\uFFFC')
              .join();
          for (final boundary in [start, end]) {
            if (boundary > 0 &&
                boundary < rawText.length &&
                rawText.codeUnitAt(boundary) >= 0xDC00 &&
                rawText.codeUnitAt(boundary) <= 0xDFFF &&
                rawText.codeUnitAt(boundary - 1) >= 0xD800 &&
                rawText.codeUnitAt(boundary - 1) <= 0xDBFF) {
              throw const HarnessException(
                'invalidRange',
                'An edit cannot split a Unicode character.',
                toolObservation: true,
              );
            }
          }
          next = append
              ? NoteMarkdownMutation.append(document, text)
              : NoteMarkdownMutation.replaceRange(
                  document,
                  start: start,
                  end: end,
                  markdown: text,
                );
        }
      }
      final after = deleting
          ? null
          : <String, dynamic>{
              'title': c['title'] as String? ?? before?.title ?? '',
              'document': next.toJsonString(),
              'tags': c['tags'] as List? ?? before?.tags ?? <String>[],
            };
      if (versions.containsKey(id)) {
        throw const HarnessException(
          'duplicateNote',
          'Combine multiple edits to one note into a single change.',
          toolObservation: true,
        );
      }
      versions[id] = before?.revision ?? 0;
      changes.add({
        'noteId': id,
        'kind': c['kind'],
        'baseRevision': before?.revision ?? 0,
        'before': before == null ? null : _snapshot(before),
        'after': after,
        'beforeText': before?.contentProjection.plainText ?? '',
        'afterText': deleting ? '' : next.project().plainText,
      });
    }
    return ToolPreview(
      data: {'changes': changes},
      versions: versions,
      requiresApproval: changes.any((change) => change['kind'] == 'delete'),
    );
  }

  static Json _snapshot(Note note) => {
    'title': note.title,
    'document': note.document.toJsonString(),
    'tags': note.tags,
    'isPinned': note.isPinned,
    'isPrivate': note.isPrivate,
    'reminderAt': note.reminderAt?.toIso8601String(),
    'coverAttachmentId': note.coverAttachmentId?.value,
    'revision': note.revision,
    'createdAt': note.createdAt.toIso8601String(),
    'updatedAt': note.updatedAt.toIso8601String(),
    'assets': [for (final asset in note.assets) _assetSnapshot(asset)],
  };

  static Json _assetSnapshot(NoteAsset asset) => {
    'id': asset.id.value,
    'kind': asset.kind.name,
    'storageKey': asset.storageKey,
    'originalName': asset.originalName,
    'displayName': asset.displayName,
    'byteLength': asset.byteLength,
    'mimeType': asset.mimeType,
    'previewStorageKey': asset.previewStorageKey,
    'durationMs': asset.durationMs,
    'ocrText': asset.ocrText,
    'transcript': asset.transcript,
    'transcriptionEngine': asset.transcriptionEngine,
    'transcribedAt': asset.transcribedAt?.toIso8601String(),
    'createdAt': asset.createdAt.toIso8601String(),
    'updatedAt': asset.updatedAt.toIso8601String(),
  };

  static Note _noteFromSnapshot(String id, Json snapshot, {Note? fallback}) {
    DateTime? optionalDate(String key) {
      final value = snapshot[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    final hasCover = snapshot.containsKey('coverAttachmentId');
    final coverAttachmentId = snapshot['coverAttachmentId'] as String?;
    final createdAt = snapshot['createdAt'] as String?;
    final updatedAt = snapshot['updatedAt'] as String?;
    final rawAssets = snapshot['assets'] as List?;

    return Note(
      id: NoteId.parse(id),
      title: snapshot['title'] as String,
      document: NoteDocument.fromJsonString(snapshot['document'] as String),
      tags: (snapshot['tags'] as List).cast<String>(),
      isPinned: snapshot['isPinned'] as bool? ?? fallback?.isPinned ?? false,
      isPrivate: snapshot['isPrivate'] as bool? ?? fallback?.isPrivate ?? false,
      reminderAt: snapshot.containsKey('reminderAt')
          ? optionalDate('reminderAt')
          : fallback?.reminderAt,
      coverAttachmentId: hasCover
          ? coverAttachmentId == null
                ? null
                : NoteAttachmentId.parse(coverAttachmentId)
          : fallback?.coverAttachmentId,
      assets: rawAssets == null
          ? fallback?.assets ?? const []
          : [
              for (final raw in rawAssets)
                _assetFromSnapshot(Map<String, dynamic>.from(raw as Map)),
            ],
      revision: snapshot['revision'] as int? ?? fallback?.revision ?? 0,
      createdAt: createdAt == null
          ? fallback?.createdAt ?? DateTime.now().toUtc()
          : DateTime.parse(createdAt),
      updatedAt: updatedAt == null
          ? fallback?.updatedAt ?? DateTime.now().toUtc()
          : DateTime.parse(updatedAt),
    );
  }

  static NoteAsset _assetFromSnapshot(Json snapshot) {
    DateTime? optionalDate(String key) {
      final value = snapshot[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return NoteAsset(
      id: NoteAttachmentId.parse(snapshot['id'] as String),
      kind: NoteAssetKind.values.byName(snapshot['kind'] as String),
      storageKey: snapshot['storageKey'] as String,
      originalName: snapshot['originalName'] as String,
      displayName: snapshot['displayName'] as String?,
      byteLength: snapshot['byteLength'] as int,
      mimeType: snapshot['mimeType'] as String,
      previewStorageKey: snapshot['previewStorageKey'] as String?,
      durationMs: snapshot['durationMs'] as int?,
      ocrText: snapshot['ocrText'] as String?,
      transcript: snapshot['transcript'] as String?,
      transcriptionEngine: snapshot['transcriptionEngine'] as String?,
      transcribedAt: optionalDate('transcribedAt'),
      createdAt: DateTime.parse(snapshot['createdAt'] as String),
      updatedAt: DateTime.parse(snapshot['updatedAt'] as String),
    );
  }

  @override
  Future<ToolResult?> recover(ToolContext context, Json arguments) =>
      access.domain(() async {
        final result = await (await access.repository()).agentReceipt(
          operationId: context.operationId,
          argumentsDigest: context.argumentsDigest,
          epoch: context.run.noteStoreEpoch,
        );
        return result == null ? null : _writeResult(result);
      });

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Json arguments,
    ToolPreview preview,
  ) => access.domain(() async {
    await context.ensureActive();
    final changes = (preview.data['changes'] as List).cast<Json>();
    final mutations = <AgentNoteMutation>[];
    for (final c in changes) {
      final id = c['noteId'] as String;
      final revision = c['baseRevision'] as int;
      final current = revision == 0
          ? Note(
              id: NoteId.parse(id),
              title: '',
              document: NoteDocument.empty(),
              isPrivate: context.run.scope.privateNotes,
              createdAt: context.run.createdAt,
              updatedAt: context.run.createdAt,
            )
          : await access.read(context, id);
      if (current.revision != revision) {
        throw const HarnessException(
          'noteChanged',
          'The note changed after approval.',
          toolObservation: true,
        );
      }
      final after = c['after'] as Json?;
      final next = after == null
          ? null
          : current.copyWith(
              title: after['title'] as String,
              document: NoteDocument.fromJsonString(
                after['document'] as String,
              ),
              tags: (after['tags'] as List).cast<String>(),
              updatedAt: DateTime.now().toUtc(),
            );
      mutations.add(
        AgentNoteMutation(
          id: current.id,
          expectedRevision: revision,
          replacement: next,
        ),
      );
    }
    await context.ensureActive();
    final result = await (await access.repository()).applyAgentMutations(
      operationId: context.operationId,
      argumentsDigest: context.argumentsDigest,
      epoch: context.run.noteStoreEpoch,
      mutations: mutations,
      validateAccess: () =>
          access.checkWrite(context, mutations.map((m) => m.id.value)),
    );
    return _writeResult(result, changes: changes);
  });

  ToolResult _writeResult(Json result, {List<Json> changes = const []}) =>
      ToolResult(
        result,
        sources: [
          for (final row in result['results'] as List)
            if (row['deleted'] != true)
              {
                'noteId': row['noteId'],
                'revision': row['revision'],
                if (changes
                        .where((c) => c['noteId'] == row['noteId'])
                        .firstOrNull
                    case final change?)
                  if (change['after'] case final Json after)
                    'title': after['title'],
              },
        ],
      );

  /// User-requested undo is itself an idempotent, version-checked transaction.
  /// Restore from the trusted preview snapshot. This makes deletion undoable
  /// without asking the model to reconstruct private metadata or attachments.
  Future<ToolResult> undo(
    ToolContext context,
    Json action,
  ) => access.domain(() async {
    await context.ensureActive();
    final preview = action['preview'] as Json;
    final changes = ((preview['data'] as Json)['changes'] as List).cast<Json>();
    final result = (action['result'] as Json)['data'] as Json;
    final receipts = (result['results'] as List).cast<Json>();
    final repo = await access.repository();
    final operationId = 'undo:${action['operationId']}';
    final digest = contentDigest({'undo': action['operationId']});
    final recovered = await repo.agentReceipt(
      operationId: operationId,
      argumentsDigest: digest,
      epoch: context.run.noteStoreEpoch,
    );
    if (recovered != null) return ToolResult(recovered);
    final mutations = <AgentNoteMutation>[];
    for (final c in changes) {
      final id = c['noteId'] as String;
      // Newly created notes are included in the approved action even when the
      // original read grant was restricted to an existing selection.
      final note = await repo.get(
        NoteId.parse(id),
        privateSpace: context.run.scope.privateNotes,
      );
      final expected =
          receipts.firstWhere((r) => r['noteId'] == id)['revision'] as int;
      final deleted =
          receipts.firstWhere((r) => r['noteId'] == id)['deleted'] == true;
      if (deleted ? note != null : note == null || note.revision != expected) {
        throw const HarnessException(
          'undoConflict',
          'Undo would overwrite a later edit. Keep the current note.',
        );
      }
      final before = c['before'] as Json?;
      final restored = before == null
          ? null
          : _noteFromSnapshot(id, before, fallback: note);
      mutations.add(
        AgentNoteMutation(
          id: NoteId.parse(id),
          expectedRevision: expected,
          replacement: restored?.copyWith(updatedAt: DateTime.now().toUtc()),
          nextRevision: deleted ? (before!['revision'] as int) + 1 : null,
        ),
      );
    }
    await context.ensureActive();
    return ToolResult(
      await repo.applyAgentMutations(
        operationId: operationId,
        argumentsDigest: digest,
        epoch: context.run.noteStoreEpoch,
        mutations: mutations,
        validateAccess: () =>
            access.checkWrite(context, mutations.map((m) => m.id.value)),
      ),
    );
  });
}

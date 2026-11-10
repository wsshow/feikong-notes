import 'package:fknotes_harness/fknotes_harness.dart';

import '../models/note.dart';
import '../providers/private_notes_controller.dart';
import '../services/note_repository.dart';
import 'model_profile.dart';
import 'note_tools.dart' show taskCreatedNoteIds;

class AgentPolicy {
  final PrivateNotesController privateNotes;
  final Future<NoteRepository> Function() repository;
  final Future<ModelProfile> Function(String id) profile;
  final void Function(String sessionId)? onPrivateNoteContent;
  AgentPolicy({
    required this.privateNotes,
    required this.repository,
    required this.profile,
    this.onPrivateNoteContent,
  });

  void validateScope(RunScope scope) {
    if (scope.privateNotes &&
        (privateNotes.protected ||
            scope.privateGeneration != privateNotes.authorizationGeneration)) {
      throw const HarnessException(
        'privateLocked',
        'Unlock the private space and renew this task grant.',
      );
    }
  }

  Future<void> authorize(
    AgentRun run, {
    ToolSpec? tool,
    bool sendingToModel = false,
  }) async {
    validateScope(run.scope);
    if (run.requiresPrivateAccess && !run.scope.privateNotes) {
      throw const HarnessException(
        'privateLocked',
        'Renew private history access.',
      );
    }
    final repo = await repository();
    if (await repo.agentEpoch != run.noteStoreEpoch) {
      throw const HarnessException(
        'libraryChanged',
        'The note library was restored or replaced. Start a new task.',
      );
    }
    if (tool?.network == true && !run.scope.networkTools) {
      throw const HarnessException(
        'networkPermission',
        'This task has no network tool permission.',
      );
    }
    if (tool?.risk == ToolRisk.write &&
        !(tool!.network ? run.scope.externalWrites : run.scope.writeNotes)) {
      throw const HarnessException(
        'writePermission',
        'This task has no note write permission.',
      );
    }
    if (sendingToModel) {
      if (run.scope.privateNotes &&
          run.messages.any(
            (message) =>
                message.sources.any((source) => source['noteId'] is String),
          )) {
        onPrivateNoteContent?.call(run.sessionId);
      }
      final current = await profile(run.profileId);
      if (current.isRemote &&
          (!run.scope.online || run.scope.modelBinding != current.binding)) {
        throw const HarnessException(
          'modelPermission',
          'Review the endpoint and grant online access to this model configuration.',
        );
      }
      // A formerly public source may have moved into private space while a
      // task was paused. Old snapshots are still sensitive after that move.
      for (final id
          in run.messages
              .expand((m) => m.sources)
              .map((s) => s['noteId'])
              .whereType<String>()
              .toSet()) {
        if (!run.scope.permitsNote(id) &&
            !taskCreatedNoteIds(run).contains(id)) {
          throw const HarnessException(
            'historyScope',
            'Conversation history contains notes outside this task grant. Start without that history or renew access.',
          );
        }
        if (await repo.isPrivateNote(NoteId.parse(id)) &&
            !run.scope.privateNotes) {
          throw const HarnessException(
            'sourceNowPrivate',
            'A source note is now private. Renew the data scope before continuing.',
          );
        }
        if (run.scope.privateNotes &&
            await repo.get(NoteId.parse(id)) != null) {
          throw const HarnessException(
            'historyScope',
            'Conversation history contains a note from another workspace.',
          );
        }
      }
    }
    validateScope(run.scope);
  }
}

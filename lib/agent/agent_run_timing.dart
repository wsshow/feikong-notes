import 'package:fknotes_harness/fknotes_harness.dart';

const agentRunDurationRefreshInterval = Duration(seconds: 1);

bool agentRunDurationIsLive(AgentRun run) => {
  RunStatus.queued,
  RunStatus.running,
  RunStatus.cancelling,
}.contains(run.status);

Duration agentRunDuration(AgentRun run, {DateTime? now}) {
  final live = agentRunDurationIsLive(run);
  if (!live && run.activeMs > 0) {
    return Duration(milliseconds: run.activeMs);
  }

  final marker = run.events.lastIndexWhere(
    (event) => event.type == 'regenerated',
  );
  final generationEvents = run.events.skip(marker + 1);
  final runningAt = generationEvents
      .where(
        (event) => event.type == 'status' && event.data['status'] == 'running',
      )
      .lastOrNull
      ?.time;
  final queuedAt = generationEvents
      .where(
        (event) => event.type == 'status' && event.data['status'] == 'queued',
      )
      .lastOrNull
      ?.time;
  final startedAt = run.status == RunStatus.queued
      ? queuedAt ?? run.createdAt
      : runningAt ?? queuedAt ?? run.createdAt;
  final end = live ? now ?? DateTime.now() : run.updatedAt;
  final elapsed = end.difference(startedAt);
  final current = elapsed.isNegative ? Duration.zero : elapsed;
  return live ? Duration(milliseconds: run.activeMs) + current : current;
}

String formatAgentRunDuration(Duration value) {
  if (value.inMilliseconds < 1000) return '${value.inMilliseconds} ms';
  if (value.inSeconds < 60) {
    final seconds = value.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
  }
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes min ${seconds}s';
}

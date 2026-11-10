import 'package:fknotes/agent/agent_run_timing.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts silent model wait as active task time', () {
    final startedAt = DateTime.utc(2026, 8, 29, 10);
    final run = _run(
      createdAt: startedAt.subtract(const Duration(seconds: 1)),
      status: RunStatus.running,
      activeMs: 2000,
      events: [_status('running', startedAt)],
    );

    expect(
      agentRunDuration(run, now: startedAt.add(const Duration(seconds: 5))),
      const Duration(seconds: 7),
    );
  });

  test('does not count time spent waiting for approval', () {
    final startedAt = DateTime.utc(2026, 8, 29, 10);
    final run = _run(
      createdAt: startedAt,
      status: RunStatus.waitingApproval,
      activeMs: 7000,
      updatedAt: startedAt.add(const Duration(seconds: 7)),
      events: [_status('running', startedAt)],
    );

    expect(
      agentRunDuration(run, now: startedAt.add(const Duration(minutes: 2))),
      const Duration(seconds: 7),
    );
    expect(agentRunDurationIsLive(run), isFalse);
  });
}

AgentRun _run({
  required DateTime createdAt,
  required RunStatus status,
  required List<RunEvent> events,
  DateTime? updatedAt,
  int activeMs = 0,
}) => AgentRun(
  id: 'run',
  sessionId: 'session',
  profileId: 'model',
  noteStoreEpoch: 'epoch',
  scope: const RunScope(),
  limits: const RunLimits(),
  system: '',
  skillId: 'assistant',
  createdAt: createdAt,
  updatedAt: updatedAt,
  status: status,
  activeMs: activeMs,
  events: events,
);

RunEvent _status(String status, DateTime time) => RunEvent(
  runId: 'run',
  seq: 1,
  type: 'status',
  data: {'status': status},
  time: time,
);

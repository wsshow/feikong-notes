import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';

import '../agent/agent_number_format.dart';
import '../agent/agent_service.dart';
import '../agent/model_profile.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';

/// A privacy-preserving, user-facing summary of agent activity.
///
/// The runtime keeps detailed records for recovery and diagnostics, but this
/// page intentionally reads only aggregate metadata. Task prompts, replies,
/// reasoning and tool arguments never enter the statistics UI.
class AgentStatisticsPage extends StatefulWidget {
  final AgentService? service;
  final bool privateSpace;

  const AgentStatisticsPage({
    super.key,
    this.service,
    this.privateSpace = false,
  });

  @override
  State<AgentStatisticsPage> createState() => _AgentStatisticsPageState();
}

/// Kept as a source-compatible alias for routes and integrations that used the
/// former task-history page.
@Deprecated('Use AgentStatisticsPage')
class AgentTasksPage extends AgentStatisticsPage {
  const AgentTasksPage({super.key, super.service});
}

class _AgentStatisticsPageState extends State<AgentStatisticsPage> {
  late final AgentService service = widget.service ?? AgentService.instance;
  Map<String, ModelProfile> _profiles = const {};
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await service.initializeIfHistoryExists();
      final profiles = await service.profiles.list();
      _profiles = {for (final profile in profiles) profile.id: profile};
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.agentTasks)),
    body: PaperShell(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: service,
              builder: (context, _) {
                if (_error != null) {
                  return Center(
                    child: Text(context.l10n.agentError('taskStorage')),
                  );
                }
                final statistics = _AgentStatistics.fromRuns(
                  service.runs
                      .where(
                        (run) =>
                            service.isPrivateRun(run) == widget.privateSpace,
                      )
                      .toList(),
                  profiles: _profiles,
                );
                return _StatisticsView(statistics: statistics);
              },
            ),
    ),
  );
}

class _StatisticsView extends StatelessWidget {
  final _AgentStatistics statistics;

  const _StatisticsView({required this.statistics});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ListView(
      key: const Key('agent-statistics-list'),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        Text(
          l.agentStatisticsPrivacy,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.appColors.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        _StatisticsOverview(statistics: statistics),
        const SizedBox(height: 24),
        InsetSettingsSection(
          title: l.agentStatisticsModels,
          children: statistics.models.isEmpty
              ? [
                  InsetSettingsRow(
                    rowKey: const Key('agent-statistics-empty'),
                    title: l.agentStatisticsEmpty,
                    subtitle: l.agentStatisticsEmptyHint,
                    showDisclosure: false,
                  ),
                ]
              : [
                  for (final model in statistics.models.take(3))
                    InsetSettingsRow(
                      rowKey: ValueKey(
                        'agent-statistics-model-${model.profileId}',
                      ),
                      title: model.displayName,
                      subtitle: l.agentStatisticsModelUsage(
                        model.executions,
                        formatAgentTokenCount(model.tokens),
                      ),
                      showDisclosure: false,
                    ),
                ],
        ),
      ],
    );
  }
}

class _StatisticsOverview extends StatelessWidget {
  final _AgentStatistics statistics;

  const _StatisticsOverview({required this.statistics});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Material(
      key: const Key('agent-statistics-overview'),
      color: context.appColors.surface.withValues(alpha: .92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appRadii.large),
        side: BorderSide(
          color: context.appColors.line.withValues(alpha: .82),
          width: .75,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    key: const Key('agent-statistics-recent'),
                    value: statistics.recentTasks.toString(),
                    label: l.agentStatisticsRecent,
                  ),
                ),
                _OverviewDivider(color: context.appColors.line),
                Expanded(
                  child: _OverviewMetric(
                    key: const Key('agent-statistics-tokens'),
                    value: formatAgentTokenCount(statistics.tokens),
                    label: l.agentStatisticsTokens,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                thickness: .75,
                color: context.appColors.line.withValues(alpha: .78),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _OverviewMetric(
                    key: const Key('agent-statistics-local-runs'),
                    value: statistics.localExecutions.toString(),
                    label: l.agentStatisticsLocalRuns,
                  ),
                ),
                _OverviewDivider(color: context.appColors.line),
                Expanded(
                  child: _OverviewMetric(
                    key: const Key('agent-statistics-online-runs'),
                    value: statistics.onlineExecutions.toString(),
                    label: l.agentStatisticsOnlineRuns,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String value;
  final String label;

  const _OverviewMetric({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Column(
      children: [
        Text(
          value,
          maxLines: 1,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFamilyFallback: AppTypography.fallback,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appColors.muted),
        ),
      ],
    ),
  );
}

class _OverviewDivider extends StatelessWidget {
  final Color color;

  const _OverviewDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: .75, height: 52, color: color.withValues(alpha: .78));
}

class _AgentStatistics {
  final int recentTasks;
  final int tokens;
  final int localExecutions;
  final int onlineExecutions;
  final List<_ModelStatistics> models;

  const _AgentStatistics({
    required this.recentTasks,
    required this.tokens,
    required this.localExecutions,
    required this.onlineExecutions,
    required this.models,
  });

  factory _AgentStatistics.fromRuns(
    Iterable<AgentRun> allRuns, {
    required Map<String, ModelProfile> profiles,
    DateTime? now,
  }) {
    final roots = allRuns
        .where((run) => run.parentId == null && !run.conversationQueuePending)
        .toList();
    final rootsById = {for (final run in roots) run.id: run};
    final logicalRuns = <String, AgentRun>{};
    for (final run in roots) {
      var original = run;
      final visited = <String>{run.id};
      while (original.retryOf != null) {
        final previousId = original.retryOf!;
        final previous = rootsById[previousId];
        if (previous == null || !visited.add(previous.id)) break;
        original = previous;
      }
      final current = logicalRuns[original.id];
      if (current == null || run.createdAt.isAfter(current.createdAt)) {
        logicalRuns[original.id] = run;
      }
    }
    final recentCutoff = (now ?? DateTime.now()).toUtc().subtract(
      const Duration(days: 7),
    );
    final recentTasks = logicalRuns.values
        .where((run) => !run.updatedAt.isBefore(recentCutoff))
        .length;

    final models = <String, _MutableModelStatistics>{};
    var localExecutions = 0;
    for (final run in roots) {
      final profile = profiles[run.profileId];
      final local =
          profile?.isRemote == false ||
          profile == null && run.profileId == ModelProfile.local.id;
      if (local) localExecutions++;
      final value = models.putIfAbsent(
        run.profileId,
        () => _MutableModelStatistics(
          profileId: run.profileId,
          displayName: profiles[run.profileId]?.displayName ?? run.profileId,
        ),
      );
      value.executions++;
      value.tokens += run.tokens;
    }
    final modelStatistics =
        models.values.map((model) => model.freeze()).toList()..sort((a, b) {
          final byExecutions = b.executions.compareTo(a.executions);
          return byExecutions != 0
              ? byExecutions
              : a.displayName.compareTo(b.displayName);
        });

    return _AgentStatistics(
      recentTasks: recentTasks,
      tokens: roots.fold(0, (total, run) => total + run.tokens),
      localExecutions: localExecutions,
      onlineExecutions: roots.length - localExecutions,
      models: modelStatistics,
    );
  }
}

class _ModelStatistics {
  final String profileId;
  final String displayName;
  final int executions;
  final int tokens;

  const _ModelStatistics({
    required this.profileId,
    required this.displayName,
    required this.executions,
    required this.tokens,
  });
}

class _MutableModelStatistics {
  final String profileId;
  final String displayName;
  int executions = 0;
  int tokens = 0;

  _MutableModelStatistics({required this.profileId, required this.displayName});

  _ModelStatistics freeze() => _ModelStatistics(
    profileId: profileId,
    displayName: displayName,
    executions: executions,
    tokens: tokens,
  );
}

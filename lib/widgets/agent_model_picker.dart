import 'package:flutter/material.dart';

import 'app_overlay.dart';

import '../agent/model_profile.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

Future<ModelProfile?> showAgentModelPicker(
  BuildContext context, {
  required List<ModelProfile> profiles,
  required String selectedId,
  VoidCallback? onManage,
}) => AppOverlay.bottomSheet<ModelProfile>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ModelPicker(
    profiles: profiles,
    selectedId: selectedId,
    onManage: onManage,
  ),
);

class _ModelPicker extends StatefulWidget {
  final List<ModelProfile> profiles;
  final String selectedId;
  final VoidCallback? onManage;
  const _ModelPicker({
    required this.profiles,
    required this.selectedId,
    this.onManage,
  });
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final profiles = widget.profiles
        .where(
          (p) =>
              '${p.displayName} ${p.endpoint} ${p.isRemote ? '' : l.agentLocal}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomScrollView(
          key: const Key('agent-model-picker-list'),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.agentSwitchModel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (widget.onManage != null)
                        IconButton(
                          key: const Key('agent-picker-settings'),
                          tooltip: l.agentSettings,
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onManage!();
                          },
                          icon: const AppIcon(Icons.tune_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('agent-model-search'),
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      labelText: l.agentSearchModels,
                      prefixIcon: const AppIcon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: profiles.length,
              itemBuilder: (context, i) {
                final profile = profiles[i];
                return ListTile(
                  key: ValueKey('agent-pick-model-${profile.id}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(profile.isRemote ? profile.model : l.agentLocal),
                  subtitle: Text(
                    profile.isRemote
                        ? '${profile.name} · ${profile.baseUri.host}'
                        : l.agentOfflineNotice,
                  ),
                  selected: profile.id == widget.selectedId,
                  trailing: profile.id == widget.selectedId
                      ? const AppIcon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, profile),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

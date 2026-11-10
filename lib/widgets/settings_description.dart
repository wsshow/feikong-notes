import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_overlay.dart';

import '../l10n/l10n.dart';

Future<void> showSettingsDescription(
  BuildContext context, {
  required String title,
  required String description,
}) => AppOverlay.bottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheetContext).height * .65,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(
              sheetContext,
            ).textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    ),
  ),
);

class SettingsInlineDescription extends StatelessWidget {
  final String description;
  final String? detailsTitle;
  final String? detailsDescription;
  final Key? detailsButtonKey;

  const SettingsInlineDescription({
    super.key,
    required this.description,
    this.detailsTitle,
    this.detailsDescription,
    this.detailsButtonKey,
  }) : assert(
         (detailsTitle == null) == (detailsDescription == null),
         'A details title and description must be supplied together.',
       );

  @override
  Widget build(BuildContext context) {
    final text = Text(
      description,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.appColors.muted,
        height: 1.45,
      ),
    );
    if (detailsDescription == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: text),
        const SizedBox(width: 8),
        TextButton(
          key: detailsButtonKey,
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: Theme.of(context).textTheme.bodySmall,
          ),
          onPressed: () => showSettingsDescription(
            context,
            title: detailsTitle!,
            description: detailsDescription!,
          ),
          child: Text(context.l10n.details),
        ),
      ],
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String? description;
  final String? detailsDescription;
  final Key? descriptionButtonKey;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.detailsDescription,
    this.descriptionButtonKey,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (description case final text?) ...[
        const SizedBox(height: 3),
        SettingsInlineDescription(
          description: text,
          detailsTitle: detailsDescription == null ? null : title,
          detailsDescription: detailsDescription,
          detailsButtonKey: descriptionButtonKey,
        ),
      ],
    ],
  );
}

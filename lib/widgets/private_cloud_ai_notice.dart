import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

/// A quiet, fixed disclosure; never asks the user to approve each message.
class PrivateCloudAiNotice extends StatelessWidget {
  const PrivateCloudAiNotice({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('private-cloud-ai-notice'),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          Icons.lock_outline_rounded,
          size: 14,
          color: context.appColors.muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.l10n.privateCloudAiNotice,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.appColors.muted,
            ),
          ),
        ),
      ],
    ),
  );
}

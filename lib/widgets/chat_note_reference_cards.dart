import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import 'app_icon.dart';
import 'chat_reference_card_tokens.dart';

class ChatNoteReferenceItem {
  final String id;
  final String title;

  const ChatNoteReferenceItem({required this.id, required this.title});
}

/// Compact note references attached to a user message.
class ChatNoteReferenceCards extends StatelessWidget {
  final List<ChatNoteReferenceItem> notes;
  final String keyPrefix;
  final Future<void> Function(ChatNoteReferenceItem note)? onOpen;

  const ChatNoteReferenceCards({
    super.key,
    required this.notes,
    required this.keyPrefix,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      alignment: WrapAlignment.end,
      runAlignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final note in notes)
          Semantics(
            button: onOpen != null,
            label: note.title,
            child: SizedBox(
              width: ChatReferenceCardTokens.width,
              height: ChatReferenceCardTokens.height,
              child: Material(
                color: context.appColors.surfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ChatReferenceCardTokens.radius,
                  ),
                  side: BorderSide(color: context.appColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('$keyPrefix-${note.id}'),
                  onTap: onOpen == null ? null : () => unawaited(onOpen!(note)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
                    child: Row(
                      children: [
                        AppIcon(
                          Icons.description_outlined,
                          color: context.appColors.moss,
                          size: ChatReferenceCardTokens.iconSize,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (onOpen != null) ...[
                          const SizedBox(width: 3),
                          AppIcon(
                            Icons.chevron_right_rounded,
                            color: context.appColors.muted,
                            size: ChatReferenceCardTokens.iconSize,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

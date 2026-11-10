import 'dart:math' as math;

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';
import 'chat_reference_card_tokens.dart';

typedef ChatQuoteSelectionCallback =
    void Function(String sourceId, String sourceText, String selectedText);

/// Compact conversation quote previews used by both the composer and sent
/// messages. A snapshot is shown even when the original run is unavailable.
class ChatTextQuoteCards extends StatelessWidget {
  static const double cardWidth = ChatReferenceCardTokens.width;
  static const double cardHeight = ChatReferenceCardTokens.height;
  static const double cardGap = ChatReferenceCardTokens.gap;

  final List<ConversationQuote> quotes;
  final String keyPrefix;
  final ValueChanged<ConversationQuote>? onOpen;
  final ValueChanged<ConversationQuote>? onRemove;
  final AlignmentGeometry alignment;

  const ChatTextQuoteCards({
    super.key,
    required this.quotes,
    required this.keyPrefix,
    this.onOpen,
    this.onRemove,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            quotes.length * cardWidth + (quotes.length - 1) * cardGap;
        final stripWidth = constraints.hasBoundedWidth
            ? math.min(contentWidth, constraints.maxWidth)
            : contentWidth;
        return Align(
          alignment: alignment,
          child: SizedBox(
            width: stripWidth,
            height: cardHeight,
            child: ListView.separated(
              key: ValueKey('$keyPrefix-strip'),
              scrollDirection: Axis.horizontal,
              itemCount: quotes.length,
              separatorBuilder: (_, _) => const SizedBox(width: cardGap),
              itemBuilder: (context, index) {
                final quote = quotes[index];
                return SizedBox(
                  width: cardWidth,
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
                      key: ValueKey('$keyPrefix-${quote.id}'),
                      onTap: onOpen == null ? null : () => onOpen!(quote),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
                        child: Row(
                          children: [
                            AppIcon(
                              Icons.format_quote,
                              size: ChatReferenceCardTokens.iconSize,
                              color: context.appColors.muted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                quote.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.ink,
                                  fontSize: 12,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (onRemove != null)
                              IconButton(
                                key: ValueKey('$keyPrefix-remove-${quote.id}'),
                                tooltip: context.l10n.removeReference,
                                onPressed: () => onRemove!(quote),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 32,
                                ),
                                icon: const AppIcon(
                                  Icons.close_rounded,
                                  size: 16,
                                ),
                              )
                            else if (onOpen != null)
                              AppIcon(
                                Icons.chevron_right_rounded,
                                size: ChatReferenceCardTokens.iconSize,
                                color: context.appColors.muted,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

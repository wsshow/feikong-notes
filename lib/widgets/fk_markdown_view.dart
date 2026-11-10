import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../markdown/markdown_front_matter.dart';
import 'app_feedback.dart';
import 'editor_context_menu.dart';
import 'markdown_latex.dart';
import 'app_icon.dart';

/// Shared Markdown reading surface for model output and notes.
///
/// Remote images are never loaded because rendering a private note must not
/// disclose that the document was opened.
class FkMarkdownView extends StatefulWidget {
  final String data;
  final bool selectable;
  final Color? textColor;
  final bool compact;
  final ValueChanged<String>? onQuoteSelection;

  const FkMarkdownView({
    super.key,
    required this.data,
    this.selectable = true,
    this.textColor,
    this.compact = false,
    this.onQuoteSelection,
  });

  @override
  State<FkMarkdownView> createState() => _FkMarkdownViewState();
}

class _FkMarkdownViewState extends State<FkMarkdownView> {
  String _selectedText = '';

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor ?? context.appColors.ink;
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color, fontSize: 15, height: 1.55);
    final codeBackground = widget.textColor == Colors.white
        ? Colors.white.withValues(alpha: .12)
        : context.appColors.softBlue;
    final markdown = MarkdownBody(
      data: MarkdownFrontMatter.normalize(widget.data),
      selectable: false,
      extensionSet: fkMarkdownExtensionSet,
      builders: {
        markdownInlineMathTag: FkLatexElementBuilder(
          displayMode: false,
          textStyle: base ?? TextStyle(color: color, fontSize: 15),
        ),
        markdownBlockMathTag: FkLatexElementBuilder(
          displayMode: true,
          textStyle: (base ?? TextStyle(color: color)).copyWith(fontSize: 16),
        ),
      },
      softLineBreak: true,
      fitContent: true,
      imageBuilder: (uri, title, alt) => _BlockedMarkdownImage(
        label: alt?.trim().isNotEmpty == true ? alt!.trim() : uri.toString(),
      ),
      onTapLink: (text, href, title) {
        if (href == null || !context.mounted) return;
        unawaited(_confirmAndOpenLink(context, href));
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: base,
        pPadding: widget.compact
            ? EdgeInsets.zero
            : const EdgeInsets.only(bottom: 8),
        h1: _heading(color, 25),
        h2: _heading(color, 21),
        h3: _heading(color, 18),
        h4: _heading(color, 16),
        h5: _heading(color, 15),
        h6: _heading(color, 14),
        h1Padding: const EdgeInsets.only(top: 5, bottom: 9),
        h2Padding: const EdgeInsets.only(top: 5, bottom: 8),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 7),
        blockquote: base?.copyWith(color: color.withValues(alpha: .78)),
        blockquoteDecoration: BoxDecoration(
          color: color == Colors.white
              ? Colors.white.withValues(alpha: .08)
              : context.appColors.softGreen,
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        code: base?.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: codeBackground,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listBullet: base,
        tableBody: base?.copyWith(fontSize: 13),
        tableHead: base?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        tableHeadAlign: TextAlign.left,
        // The surrounding MediaQuery has no page safe-area padding, so the
        // horizontal thumb stays on the table's actual bottom edge.
        tablePadding: EdgeInsets.zero,
        tableScrollbarThumbVisibility: false,
        tableBorder: TableBorder.all(
          color: context.appColors.line,
          borderRadius: BorderRadius.circular(10),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        tableHeadCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        tableHeadCellsDecoration: BoxDecoration(
          color: context.appColors.softGreen,
        ),
        tableVerticalAlignment: TableCellVerticalAlignment.top,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.appColors.line)),
        ),
        a: base?.copyWith(
          color: widget.textColor == Colors.white
              ? Colors.white
              : context.appColors.moss,
          decoration: TextDecoration.underline,
          decorationColor: widget.textColor == Colors.white
              ? Colors.white
              : context.appColors.moss,
        ),
      ),
    );
    final content = widget.selectable
        ? SelectionArea(
            onSelectionChanged: (selection) {
              _selectedText = selection?.plainText.trim() ?? '';
            },
            contextMenuBuilder: (context, state) =>
                buildAppSelectableRegionContextMenu(
                  context,
                  state,
                  onQuote:
                      widget.onQuoteSelection == null || _selectedText.isEmpty
                      ? null
                      : () => widget.onQuoteSelection!(_selectedText),
                ),
            child: markdown,
          )
        : markdown;
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        thickness: const WidgetStatePropertyAll(3),
        radius: const Radius.circular(2),
        thumbColor: WidgetStatePropertyAll(
          context.appColors.muted.withValues(alpha: .48),
        ),
        mainAxisMargin: 4,
        crossAxisMargin: 0,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: content,
      ),
    );
  }

  static TextStyle _heading(Color color, double size) => TextStyle(
    color: color,
    fontFamily: 'serif',
    fontSize: size,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  static Future<void> _confirmAndOpenLink(
    BuildContext context,
    String href,
  ) async {
    final uri = Uri.tryParse(href);
    if (uri == null || !{'http', 'https', 'mailto'}.contains(uri.scheme)) {
      AppFeedback.error(context, context.l10n.invalidExternalLink);
      return;
    }
    final confirmed = await AppOverlay.dialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.openExternalLinkQuestion),
        content: Text(
          context.l10n.externalLinkWarning(uri.host.isEmpty ? href : uri.host),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.continueOpening),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        AppFeedback.error(context, context.l10n.noExternalLinkHandler);
      }
    } catch (_) {
      if (context.mounted) {
        AppFeedback.error(context, context.l10n.externalLinkOpenFailed);
      }
    }
  }
}

class _BlockedMarkdownImage extends StatelessWidget {
  final String label;
  const _BlockedMarkdownImage({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.appColors.softBlue,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.appColors.line),
    ),
    child: Row(
      children: [
        AppIcon(
          Icons.image_not_supported_outlined,
          color: context.appColors.muted,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            context.l10n.remoteImageBlocked(label),
            style: TextStyle(color: context.appColors.muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

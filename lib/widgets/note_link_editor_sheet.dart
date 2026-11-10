import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../app.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';
import 'editor_context_menu.dart';

Future<quill.QuillTextLink?> showNoteLinkEditorSheet(
  BuildContext context, {
  required String initialText,
  required String? initialLink,
}) => AppOverlay.inputSheet<quill.QuillTextLink>(
  context: context,
  builder: (_) =>
      NoteLinkEditorSheet(initialText: initialText, initialLink: initialLink),
);

/// A keyboard-safe form for creating, updating, and removing editor links.
final class NoteLinkEditorSheet extends StatefulWidget {
  const NoteLinkEditorSheet({
    required this.initialText,
    required this.initialLink,
    super.key,
  });

  final String initialText;
  final String? initialLink;

  @override
  State<NoteLinkEditorSheet> createState() => _NoteLinkEditorSheetState();
}

final class _NoteLinkEditorSheetState extends State<NoteLinkEditorSheet> {
  static const _supportedPrefixes = [
    'http://',
    'https://',
    'mailto:',
    'tel:',
    'sms:',
    'callto:',
    'wtai:',
    'market:',
    'geopoint:',
    'ymsgr:',
    'msnim:',
    'gtalk:',
    'skype:',
    'sip:',
    'whatsapp:',
  ];

  late final TextEditingController _textController;
  late final TextEditingController _linkController;
  late final FocusNode _textFocusNode;
  late final FocusNode _linkFocusNode;
  var _showLinkError = false;

  bool get _editing => widget.initialLink?.isNotEmpty ?? false;
  bool get _linkValid {
    final link = _linkController.text.trim().toLowerCase();
    return _supportedPrefixes.any(link.startsWith);
  }

  bool get _canSave => _textController.text.trim().isNotEmpty && _linkValid;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText)
      ..addListener(_changed);
    _linkController = TextEditingController(text: widget.initialLink ?? '')
      ..addListener(_changed);
    _textFocusNode = FocusNode(debugLabel: 'note-link-text');
    _linkFocusNode = FocusNode(debugLabel: 'note-link-address');
  }

  void _changed() {
    setState(() {
      if (_linkController.text.trim().isEmpty || _linkValid) {
        _showLinkError = false;
      }
    });
  }

  void _save() {
    if (!_canSave) {
      setState(() => _showLinkError = _linkController.text.trim().isNotEmpty);
      (_textController.text.trim().isEmpty ? _textFocusNode : _linkFocusNode)
          .requestFocus();
      return;
    }
    Navigator.pop(
      context,
      quill.QuillTextLink(
        _textController.text.trim(),
        _linkController.text.trim(),
      ),
    );
  }

  void _remove() => Navigator.pop(
    context,
    quill.QuillTextLink(_textController.text.trim(), null),
  );

  @override
  void dispose() {
    _textController
      ..removeListener(_changed)
      ..dispose();
    _linkController
      ..removeListener(_changed)
      ..dispose();
    _textFocusNode.dispose();
    _linkFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? context.l10n.editLink : context.l10n.addLink,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.linkPrivacyDescription,
                style: TextStyle(color: context.appColors.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('note-link-text-field'),
                controller: _textController,
                focusNode: _textFocusNode,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                autofocus: widget.initialText.trim().isEmpty,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _linkFocusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText: context.l10n.linkText,
                  hintText: context.l10n.linkTextHint,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('note-link-address-field'),
                controller: _linkController,
                focusNode: _linkFocusNode,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                autofocus: widget.initialText.trim().isNotEmpty,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                autofillHints: const [AutofillHints.url],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: context.l10n.linkAddress,
                  hintText: context.l10n.linkAddressHint,
                  errorText: _showLinkError
                      ? context.l10n.invalidExternalLink
                      : null,
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('remove-note-link'),
                    onPressed: _remove,
                    icon: const AppIcon(Icons.link_off_rounded, size: 18),
                    label: Text(context.l10n.removeLink),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('cancel-note-link'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('save-note-link'),
                      onPressed: _canSave ? _save : null,
                      child: Text(context.l10n.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

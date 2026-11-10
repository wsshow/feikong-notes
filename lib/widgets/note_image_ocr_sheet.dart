import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/ocr_service.dart';
import 'app_icon.dart';
import 'editor_context_menu.dart';

enum NoteImageOcrSaveStatus { saved, failed, imageChanged }

/// On-demand OCR. Closing the sheet discards unfinished recognition; copying
/// and saving are separate, so OCR never silently writes to the clipboard.
final class NoteImageOcrSheet extends StatefulWidget {
  const NoteImageOcrSheet({
    this.initialText,
    required this.recognizeText,
    required this.saveText,
    super.key,
  });

  final String? initialText;
  final Future<OcrResult> Function() recognizeText;
  final Future<NoteImageOcrSaveStatus> Function(String text) saveText;

  @override
  State<NoteImageOcrSheet> createState() => _NoteImageOcrSheetState();
}

final class _NoteImageOcrSheetState extends State<NoteImageOcrSheet> {
  late String _text;
  bool _busy = false;
  bool _saving = false;
  bool _copying = false;
  bool _saveFailed = false;
  bool _imageChanged = false;
  bool _noText = false;
  String? _error;
  String? _copyMessage;
  bool _copyFailed = false;

  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _text = widget.initialText?.trim() ?? '';
    if (_text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active) unawaited(_recognize());
      });
    }
  }

  Future<void> _recognize() async {
    if (_busy || !_active) return;
    setState(() {
      _busy = true;
      _error = null;
      _noText = false;
      _copyMessage = null;
    });
    try {
      final result = await widget.recognizeText();
      if (!_active) return;
      if (result.didFail) {
        setState(
          () => _error = result.errorMessage ?? context.l10n.imageOcrFailed,
        );
      } else if (result.text.trim().isEmpty) {
        // A failed/empty retry must not erase useful previously saved text.
        setState(() => _noText = true);
      } else {
        setState(() => _text = result.text.trim());
        await _save();
      }
    } catch (_) {
      if (_active) setState(() => _error = context.l10n.imageOcrFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final status = await widget.saveText(_text);
      if (!_active) return;
      setState(() {
        _saveFailed = status == NoteImageOcrSaveStatus.failed;
        _imageChanged = status == NoteImageOcrSaveStatus.imageChanged;
        _error = switch (status) {
          NoteImageOcrSaveStatus.saved => null,
          NoteImageOcrSaveStatus.failed => context.l10n.imageOcrSaveFailed,
          NoteImageOcrSaveStatus.imageChanged =>
            context.l10n.imageOcrSourceChanged,
        };
      });
    } catch (_) {
      if (_active) {
        setState(() {
          _saveFailed = true;
          _error = context.l10n.imageOcrSaveFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _retrySave() async {
    if (_busy || !_active) return;
    setState(() => _busy = true);
    try {
      await _save();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (_copying || _busy || _text.isEmpty) return;
    final l10n = context.l10n;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: _text));
      if (_active) {
        setState(() {
          _copyMessage = l10n.recognizedTextCopied;
          _copyFailed = false;
        });
      }
    } catch (_) {
      if (_active) {
        setState(() {
          _copyMessage = l10n.imageOcrCopyFailed;
          _copyFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.imageOcrAction,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('close-image-ocr'),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              l10n.imageOcrDescription,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (_text.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .38,
                ),
                child: SingleChildScrollView(
                  key: const Key('image-ocr-text-scroll'),
                  child: SelectableText(
                    _text,
                    key: const Key('image-ocr-result'),
                    contextMenuBuilder: buildAppEditableTextContextMenu,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
              ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_saving ? l10n.saving : l10n.recognizing),
              ),
            ],
            if (_noText || _error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ?? l10n.noClearTextRecognized,
                    key: const Key('image-ocr-status'),
                    style: TextStyle(
                      color: _error == null
                          ? context.appColors.muted
                          : context.appColors.danger,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('retry-image-ocr'),
                  onPressed: _busy || _imageChanged
                      ? null
                      : _saveFailed
                      ? _retrySave
                      : _recognize,
                  child: Text(_saveFailed ? l10n.retry : l10n.recognizeAgain),
                ),
                FilledButton(
                  key: const Key('copy-image-ocr'),
                  onPressed: _busy || _copying || _text.isEmpty ? null : _copy,
                  child: Text(l10n.copyAll),
                ),
              ],
            ),
            if (_copyMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _copyMessage!,
                    style: TextStyle(
                      color: _copyFailed
                          ? context.appColors.danger
                          : context.appColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'settings_description.dart';

/// An inset-grouped settings section inspired by platform settings screens.
///
/// The group owns its border and separators so individual controls stay quiet,
/// aligned and easy to scan. Explanatory copy lives below the group instead of
/// competing with the control labels.
class InsetSettingsSection extends StatelessWidget {
  const InsetSettingsSection({
    super.key,
    required this.children,
    this.title,
    this.footnote,
    this.detailsTitle,
    this.detailsDescription,
    this.detailsButtonKey,
    this.titleStyle,
  });

  final String? title;
  final List<Widget> children;
  final String? footnote;
  final String? detailsTitle;
  final String? detailsDescription;
  final Key? detailsButtonKey;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title case final title?) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            title,
            style:
                titleStyle ??
                Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: context.appColors.muted,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
      InsetSettingsGroup(children: children),
      if (footnote case final footnote?) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SettingsInlineDescription(
            description: footnote,
            detailsTitle: detailsDescription == null
                ? null
                : (detailsTitle ?? title),
            detailsDescription: detailsDescription,
            detailsButtonKey: detailsButtonKey,
          ),
        ),
      ],
    ],
  );
}

class InsetSettingsGroup extends StatelessWidget {
  const InsetSettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final separated = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        separated.add(
          Divider(
            height: 1,
            thickness: .75,
            indent: 16,
            color: context.appColors.line.withValues(alpha: .78),
          ),
        );
      }
      separated.add(children[index]);
    }
    return Material(
      color: context.appColors.surface.withValues(alpha: .92),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appRadii.large),
        side: BorderSide(
          color: context.appColors.line.withValues(alpha: .82),
          width: .75,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: separated,
      ),
    );
  }
}

class InsetSettingsRow extends StatelessWidget {
  const InsetSettingsRow({
    super.key,
    this.rowKey,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.selected = false,
    this.busy = false,
    this.showDisclosure = true,
    this.foregroundColor,
  });

  final Key? rowKey;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
  final bool selected;
  final bool busy;
  final bool showDisclosure;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? context.appColors.subtle
        : destructive
        ? context.appColors.danger
        : foregroundColor ?? context.appColors.ink;
    return ListTile(
      key: rowKey,
      enabled: enabled,
      selected: selected,
      selectedTileColor: Colors.transparent,
      minTileHeight: subtitle == null ? 56 : 72,
      minVerticalPadding: subtitle == null ? 10 : 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading,
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled
                    ? context.appColors.muted
                    : context.appColors.subtle,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
      trailing:
          trailing ??
          (busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : selected
              ? AppIcon(
                  Icons.check_rounded,
                  size: 20,
                  color: context.appColors.accent,
                )
              : onTap == null || !showDisclosure
              ? null
              : AppIcon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.appColors.subtle,
                )),
      onTap: enabled ? onTap : null,
    );
  }
}

class InsetSettingsFieldRow extends StatelessWidget {
  const InsetSettingsFieldRow({
    super.key,
    this.fieldKey,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.suffix,
    this.forceStacked = false,
  });

  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final Widget? suffix;
  final bool forceStacked;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textTheme = Theme.of(context).textTheme;
        final valueStyle = textTheme.bodyMedium?.copyWith(height: 1.45);
        final labelStyle = textTheme.bodyMedium?.copyWith(
          height: 1.45,
          fontWeight: FontWeight.w500,
        );
        final availableWidth = constraints.maxWidth - 48;
        final labelWidth = availableWidth * .4;
        final valueWidth = availableWidth * .6;
        final visibleValue = controller.text.isEmpty
            ? (hintText ?? '')
            : controller.text;
        final stacked =
            forceStacked ||
            maxLines > 1 ||
            constraints.maxWidth < 340 ||
            textScale > 1.35 ||
            _textWidth(context, label, labelStyle) > labelWidth * .9 ||
            _textWidth(
                  context,
                  obscureText && visibleValue.isNotEmpty
                      ? _obscuredPreview(visibleValue)
                      : visibleValue,
                  valueStyle,
                ) >
                valueWidth * .9;
        final field = TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          style: valueStyle,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: valueStyle?.copyWith(color: context.appColors.subtle),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            filled: false,
            isDense: true,
            counterText: '',
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        );
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                field,
              ],
            ),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: field),
              ],
            ),
          ),
        );
      },
    );
  }
}

class InsetSettingsControlRow extends StatelessWidget {
  const InsetSettingsControlRow({
    super.key,
    required this.label,
    required this.control,
    this.forceStacked = false,
  });

  final String label;
  final Widget control;
  final bool forceStacked;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.bodyMedium?.copyWith(
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    final styledControl = DefaultTextStyle.merge(
      style: textTheme.bodyMedium?.copyWith(height: 1.45),
      child: control,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            forceStacked || constraints.maxWidth < 340 || textScale > 1.35;
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: styledControl),
              ],
            ),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text(label, style: labelStyle)),
                const SizedBox(width: 16),
                Flexible(child: styledControl),
              ],
            ),
          ),
        );
      },
    );
  }
}

class InsetSettingsSwitchRow extends StatelessWidget {
  const InsetSettingsSwitchRow({
    super.key,
    this.rowKey,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key? rowKey;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    key: rowKey,
    minTileHeight: subtitle == null ? 56 : 76,
    minVerticalPadding: subtitle == null ? 10 : 12,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    title: Text(
      title,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.appColors.muted,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
    value: value,
    onChanged: onChanged,
  );
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout();
  return painter.width;
}

String _obscuredPreview(String value) {
  final length = value.length < 6
      ? 6
      : value.length > 16
      ? 16
      : value.length;
  return List.filled(length, '•').join();
}

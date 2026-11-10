import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../providers/app_theme_controller.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/inset_settings.dart';
import '../widgets/quiet_paper.dart';
import '../widgets/sunny_growth_decoration.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() save) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await save();
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.themeSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppThemeController>();
    final colors = context.appColors;
    final l10n = context.l10n;
    return Scaffold(
      key: const Key('theme-settings-page'),
      appBar: AppBar(title: Text(l10n.themeSettings)),
      body: PaperShell(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(
                l10n.themeDescription,
                style: TextStyle(color: colors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              InsetSettingsSection(
                children: [
                  for (final definition in AppThemeCatalog.definitions)
                    _ThemeOption(
                      definition: definition,
                      selected: controller.style == definition.style,
                      onTap: _saving
                          ? null
                          : () => _save(
                              () => controller.setStyle(definition.style),
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              InsetSettingsSection(
                title: l10n.themeBrightness,
                footnote: controller.style.supportsDark
                    ? null
                    : controller.style.definition.lightOnlyDescription?.call(
                            l10n,
                          ) ??
                          l10n.themeSunnyGrowthLightOnly,
                children: controller.style.supportsDark
                    ? [
                        for (final mode in [
                          ThemeMode.system,
                          ThemeMode.light,
                          ThemeMode.dark,
                        ])
                          InsetSettingsRow(
                            rowKey: ValueKey('app-theme-mode-${mode.name}'),
                            title: switch (mode) {
                              ThemeMode.system => l10n.themeModeSystem,
                              ThemeMode.light => l10n.themeModeLight,
                              ThemeMode.dark => l10n.themeModeDark,
                            },
                            enabled: !_saving,
                            selected: controller.mode == mode,
                            showDisclosure: false,
                            onTap: _saving
                                ? null
                                : () => _save(() => controller.setMode(mode)),
                          ),
                      ]
                    : [
                        InsetSettingsRow(
                          title: l10n.themeModeLight,
                          selected: true,
                          showDisclosure: false,
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.definition,
    required this.selected,
    required this.onTap,
  });

  final AppThemeDefinition definition;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = definition.style;
    final preview = AppPalette.forStyle(style, Theme.of(context).brightness);
    final l10n = context.l10n;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? colors.accentSoft.withValues(alpha: .42)
            : Colors.transparent,
        child: InkWell(
          key: ValueKey('app-theme-${style.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    height: 66,
                    width: 104,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: _ThemePreviewPainter(preview)),
                        if (definition.previewDecoration ==
                            AppThemePreviewDecoration.sunCloud)
                          const Positioned(
                            right: AppSpacing.xs,
                            top: 2,
                            child: SunCloudDecoration(size: 36),
                          ),
                        if (definition.previewDecoration ==
                            AppThemePreviewDecoration.paperCraft)
                          const Positioned(
                            right: 4,
                            top: 4,
                            child: _PaperCraftPreview(compact: true),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        definition.label(l10n),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        definition.description(l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (selected)
                  AppIcon(Icons.check_rounded, color: colors.accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperCraftPreview extends StatelessWidget {
  const _PaperCraftPreview({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 48 : 62,
    height: compact ? 40 : 52,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 5,
          top: 7,
          child: Transform.rotate(
            angle: -.08,
            child: Container(
              width: 48,
              height: 36,
              decoration: BoxDecoration(
                color: context.appColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 2,
          child: Container(
            width: 50,
            height: 38,
            decoration: BoxDecoration(
              color: context.appColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.appColors.line),
              boxShadow: context.appColors.lowShadows,
            ),
            child: Align(
              alignment: const Alignment(.45, -.25),
              child: AppIcon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: context.appColors.decoration,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A decoration-only preview; never copies or modifies the user's notes.
class _ThemePreviewPainter extends CustomPainter {
  const _ThemePreviewPainter(this.colors);
  final AppPalette colors;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleY = size.height / 92;
    void bar(Rect rect, Color color, [double radius = 4]) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
    bar(Offset.zero & size, colors.canvas, 12);
    bar(
      Rect.fromLTWH(16, 15 * scaleY, size.width * .28, 7 * scaleY),
      colors.ink,
    );
    bar(
      Rect.fromLTWH(16, 29 * scaleY, size.width * .44, 5 * scaleY),
      colors.muted.withValues(alpha: .65),
    );
    bar(Rect.fromLTWH(16, 47 * scaleY, size.width - 32, 1), colors.line);
    bar(
      Rect.fromLTWH(16, 62 * scaleY, size.width * .3, 6 * scaleY),
      colors.muted,
    );
    final action = Rect.fromLTWH(size.width - 72, 59 * scaleY, 56, 22 * scaleY);
    canvas.drawRRect(
      RRect.fromRectAndRadius(action, const Radius.circular(7)),
      Paint()
        ..color = colors.accent
        ..shader = colors.primaryGradient?.createShader(action),
    );
    final paint = Paint()
      ..color = colors.onStrong
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      action.center - const Offset(4, 0),
      action.center + const Offset(4, 0),
      paint,
    );
    canvas.drawLine(
      action.center - const Offset(0, 4),
      action.center + const Offset(0, 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ThemePreviewPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

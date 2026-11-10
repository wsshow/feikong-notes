import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_icon.dart';
import 'app_component_theme.dart';
import 'app_theme_catalog.dart';
import 'editorial_journal_tokens.dart';
import 'sunny_growth_tokens.dart';

export 'app_component_theme.dart';
export 'app_theme_catalog.dart';
export 'editorial_journal_tokens.dart';
export 'sunny_growth_tokens.dart';

class AppColors {
  // Default paper palette for non-themed rendering. UI components resolve
  // AppPalette from Theme so open routes update without replacing their state.
  static const ink = Color(0xFF2C2C2E);
  static const muted = Color(0xFF6C6C70);
  static const subtle = Color(0xFF929297);
  static const canvas = Color(0xFFFAFAFC);
  static const paperPrimary = Color(0xFFFAFAFC);
  static const paperSecondary = Color(0xFFF2F2F7);
  static const toolLayer = Color(0xFFF7F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = paperSecondary;
  static const line = Color(0xFFE5E5EA);
  static const mechanicalBlue = accent;
  static const terracotta = muted;
  static const shadow = Color(0xFF2C2C2E);
  static const accent = Color(0xFF48484D);
  static const accentPressed = Color(0xFF36363B);
  static const accentSoft = Color(0xFFEBEBF0);
  static const success = Color(0xFF3F6653);
  static const successSoft = Color(0xFFEDF3EF);
  static const warning = Color(0xFF85652F);
  static const warningSoft = Color(0xFFF6F1E7);
  static const danger = Color(0xFFB3423E);
  static const dangerSoft = Color(0xFFF8ECEB);
  static const scrim = Color(0x52151515);

  // Compatibility names used by feature surfaces while they migrate to the
  // semantic palette above.
  static const moss = accent;
  static const coral = danger;
  static const lime = surfaceMuted;
  static const softGreen = accentSoft;
  static const softBlue = surfaceMuted;
  static const softAmber = warningSoft;
  static const softLavender = surfaceMuted;
  static const softCoral = dangerSoft;
}

abstract final class AppTypography {
  static const fallback = [
    'PingFang SC',
    'HarmonyOS Sans SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  // Long-form note typography, shared by editing and rich document previews.
  // Keep natural CJK tracking; readability comes from line and paragraph space.
  static const editorBody = TextStyle(
    fontFamilyFallback: fallback,
    fontSize: 16,
    height: 1.75,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
    wordSpacing: 0,
  );
  static const editorTitle = TextStyle(
    fontFamilyFallback: fallback,
    fontSize: 27,
    height: 1.4,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    wordSpacing: 0,
  );
}

abstract final class AppMenuTokens {
  static const edgeInset = 16.0;
  static const anchorGap = 8.0;
  static const minWidth = 216.0;
  static const maxWidth = 288.0;
  static const itemHeight = 52.0;
  static const elevation = 12.0;
  static const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
  static const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );
  static const textStyle = TextStyle(
    fontFamilyFallback: AppTypography.fallback,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
  static MenuStyle styleFor(AppPalette colors, AppComponentTheme components) =>
      MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
          colors.shadow.withValues(alpha: .16),
        ),
        elevation: WidgetStatePropertyAll(components.menuElevation),
        shape: WidgetStatePropertyAll(shape),
        padding: WidgetStatePropertyAll(padding),
        visualDensity: VisualDensity.standard,
      );
}

/// Semantic colors shared by Material controls, feature widgets and painters.
/// ThemeExtension interpolation updates open routes without recreating them.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.style,
    required this.brightness,
    required this.ink,
    required this.muted,
    required this.subtle,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.toolLayer,
    required this.line,
    required this.control,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.onAccent,
    required this.gradientStart,
    required this.gradientEnd,
    required this.decoration,
    required this.calendarWeekend,
    required this.calendarFestival,
    required this.calendarSolarTerm,
    required this.shadow,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.scrim,
  });

  final AppThemeStyle style;
  final Brightness brightness;
  final Color ink;
  final Color muted;
  final Color subtle;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color toolLayer;
  final Color line;
  final Color control;
  final Color accent;
  final Color accentPressed;
  final Color accentSoft;
  final Color onAccent;
  final Color gradientStart;
  final Color gradientEnd;
  final Color decoration;
  // Calendar accents are informational, independent of error/warning colors.
  final Color calendarWeekend;
  final Color calendarFestival;
  final Color calendarSolarTerm;
  final Color shadow;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color scrim;

  AppThemeComponentProfile get _componentProfile =>
      style.definition.componentProfile;
  bool get _usesStarlightComponents =>
      _componentProfile == AppThemeComponentProfile.starlight;
  bool get _usesCloudComponents =>
      _componentProfile == AppThemeComponentProfile.cloud;
  bool get _usesEditorialComponents =>
      _componentProfile == AppThemeComponentProfile.editorial;
  Color get link => _usesCloudComponents ? SunnyGrowthTokens.colorLink : accent;
  LinearGradient? get canvasGradient => _usesCloudComponents
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [canvas, SunnyGrowthTokens.colorBackgroundCanvasEnd],
        )
      : _usesEditorialComponents
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            EditorialJournalTokens.colorCanvas,
            EditorialJournalTokens.colorCanvasEnd,
          ],
        )
      : null;
  // Media overlays stay legible over arbitrary user image pixels.
  Color get mediaScrim => const Color(0xB8000000);
  Color get onMedia => const Color(0xFFFFFFFF);
  Color get onDanger =>
      brightness == Brightness.dark ? canvas : const Color(0xFFFFFFFF);
  Color get paperPrimary => canvas;
  Color get paperSecondary => surfaceMuted;
  Color get mechanicalBlue => accent;
  Color get terracotta => decoration;
  // Small text on a tinted surface needs slightly more contrast than an icon.
  Color get onAccentSoft => _usesCloudComponents
      ? ink
      : _usesStarlightComponents && brightness == Brightness.light
      ? accentPressed
      : accent;
  Color get moss => accent;
  // Legacy status alias; decoration has its own token and never signals errors.
  Color get coral => danger;
  Color get lime => surfaceMuted;
  Color get softGreen => accentSoft;
  Color get softBlue => surfaceMuted;
  Color get softAmber => warningSoft;
  Color get softLavender => surfaceMuted;
  Color get softCoral => dangerSoft;
  Color get onStrong =>
      _usesStarlightComponents ? const Color(0xFFFFFFFF) : onAccent;
  // Filled controls share the paper lift used by the home filters. Keep accent
  // itself for small text/icons; lightening that token would reduce legibility.
  Color get primaryFill => _usesEditorialComponents
      ? Color.alphaBlend(Colors.white.withValues(alpha: .06), accent)
      : accent;
  LinearGradient? get primaryGradient => _usesStarlightComponents
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        )
      : _usesEditorialComponents
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: .09), accent),
            primaryFill,
          ],
        )
      : null;
  List<BoxShadow> get lowShadows => [
    BoxShadow(
      color: shadow.withValues(alpha: _usesCloudComponents ? .10 : .045),
      blurRadius: _usesCloudComponents ? 16 : 12,
      offset: Offset(0, _usesCloudComponents ? 4 : 3),
    ),
  ];
  List<BoxShadow> get floatingShadows => [
    BoxShadow(
      color: shadow.withValues(alpha: _usesCloudComponents ? .16 : .08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  List<BoxShadow> get paperEdgeShadows => [
    BoxShadow(
      color: shadow.withValues(alpha: .035),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static AppPalette forStyle(AppThemeStyle style, Brightness brightness) =>
      switch ((style, brightness)) {
        (AppThemeStyle.paper, Brightness.light) => paperLight,
        (AppThemeStyle.paper, Brightness.dark) => paperDark,
        (AppThemeStyle.starlight, Brightness.light) => starlightLight,
        (AppThemeStyle.starlight, Brightness.dark) => starlightDark,
        (AppThemeStyle.sunnyGrowth, _) => sunnyGrowthLight,
        (AppThemeStyle.editorialJournal, _) => editorialJournalLight,
      };

  static const paperLight = AppPalette(
    style: AppThemeStyle.paper,
    brightness: Brightness.light,
    ink: Color(0xFF2C2C2E),
    muted: Color(0xFF6C6C70),
    subtle: Color(0xFF929297),
    canvas: Color(0xFFFAFAFC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F2F7),
    toolLayer: Color(0xFFF7F7FA),
    line: Color(0xFFE5E5EA),
    control: Color(0xFF85858B),
    accent: Color(0xFF48484D),
    accentPressed: Color(0xFF36363B),
    accentSoft: Color(0xFFEBEBF0),
    onAccent: Color(0xFFFFFFFF),
    gradientStart: Color(0xFF48484D),
    gradientEnd: Color(0xFF48484D),
    decoration: Color(0xFFA6A6AC),
    calendarWeekend: Color(0xFFAF4E38),
    calendarFestival: Color(0xFFB04665),
    calendarSolarTerm: Color(0xFF906617),
    shadow: Color(0xFF303038),
    success: Color(0xFF3F6653),
    successSoft: Color(0xFFEDF3EF),
    warning: Color(0xFF85652F),
    warningSoft: Color(0xFFF6F1E7),
    danger: Color(0xFFB3423E),
    dangerSoft: Color(0xFFF8ECEB),
    scrim: Color(0x522C2C2E),
  );

  static const paperDark = AppPalette(
    style: AppThemeStyle.paper,
    brightness: Brightness.dark,
    ink: Color(0xFFF2F2F7),
    muted: Color(0xFFB5B5BD),
    subtle: Color(0xFF85858D),
    canvas: Color(0xFF1C1C1E),
    surface: Color(0xFF262629),
    surfaceMuted: Color(0xFF303034),
    toolLayer: Color(0xFF2C2C2F),
    line: Color(0xFF3D3D43),
    control: Color(0xFF92929A),
    accent: Color(0xFFD1D1D8),
    accentPressed: Color(0xFFEBEBF0),
    accentSoft: Color(0xFF3A3A41),
    onAccent: Color(0xFF242426),
    gradientStart: Color(0xFFD1D1D8),
    gradientEnd: Color(0xFFD1D1D8),
    decoration: Color(0xFFA6A6AC),
    calendarWeekend: Color(0xFFF0A48F),
    calendarFestival: Color(0xFFEAA0BE),
    calendarSolarTerm: Color(0xFFE0BD7D),
    shadow: Color(0xFF000000),
    success: Color(0xFF8ACCAE),
    successSoft: Color(0xFF253F34),
    warning: Color(0xFFE6BF7A),
    warningSoft: Color(0xFF423725),
    danger: Color(0xFFF09B99),
    dangerSoft: Color(0xFF472C30),
    scrim: Color(0x99000000),
  );

  static const starlightLight = AppPalette(
    style: AppThemeStyle.starlight,
    brightness: Brightness.light,
    ink: Color(0xFF171943),
    muted: Color(0xFF62658D),
    subtle: Color(0xFFA9AABC),
    canvas: Color(0xFFFAF9FF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F0FF),
    toolLayer: Color(0xFFF5F4FF),
    line: Color(0xFFE4E2F3),
    control: Color(0xFF7779A7),
    accent: Color(0xFF5B5DEB),
    accentPressed: Color(0xFF4648C8),
    accentSoft: Color(0xFFECEBFF),
    onAccent: Color(0xFFFFFFFF),
    gradientStart: Color(0xFF5359F4),
    gradientEnd: Color(0xFF7657F4),
    decoration: Color(0xFFFF747C),
    calendarWeekend: Color(0xFFAF4B50),
    calendarFestival: Color(0xFFA34876),
    calendarSolarTerm: Color(0xFF906219),
    shadow: Color(0xFF3A3482),
    success: Color(0xFF187A5B),
    successSoft: Color(0xFFE8F5EE),
    warning: Color(0xFFA65C00),
    warningSoft: Color(0xFFFFF2DC),
    danger: Color(0xFFC63852),
    dangerSoft: Color(0xFFFCEBF0),
    scrim: Color(0x52171943),
  );

  static const starlightDark = AppPalette(
    style: AppThemeStyle.starlight,
    brightness: Brightness.dark,
    ink: Color(0xFFF0EEFF),
    muted: Color(0xFFB9B5D5),
    subtle: Color(0xFF85839D),
    canvas: Color(0xFF191827),
    surface: Color(0xFF242236),
    surfaceMuted: Color(0xFF2E2B45),
    toolLayer: Color(0xFF29263C),
    line: Color(0xFF413B5A),
    control: Color(0xFF9390B8),
    accent: Color(0xFFB1ADFF),
    accentPressed: Color(0xFFCDC9FF),
    accentSoft: Color(0xFF373154),
    onAccent: Color(0xFF211C3B),
    gradientStart: Color(0xFF5359F4),
    gradientEnd: Color(0xFF7657F4),
    decoration: Color(0xFFFF8C96),
    calendarWeekend: Color(0xFFEDABAA),
    calendarFestival: Color(0xFFE5A1CF),
    calendarSolarTerm: Color(0xFFDFC184),
    shadow: Color(0xFF080611),
    success: Color(0xFF89D9B6),
    successSoft: Color(0xFF203D35),
    warning: Color(0xFFEFCA86),
    warningSoft: Color(0xFF443726),
    danger: Color(0xFFFF9CAF),
    dangerSoft: Color(0xFF482B3A),
    scrim: Color(0x990B091A),
  );

  static const sunnyGrowthLight = AppPalette(
    style: AppThemeStyle.sunnyGrowth,
    brightness: Brightness.light,
    ink: SunnyGrowthTokens.colorTextPrimary,
    muted: SunnyGrowthTokens.colorTextSecondary,
    subtle: SunnyGrowthTokens.colorTextTertiary,
    canvas: SunnyGrowthTokens.colorBackgroundCanvas,
    surface: SunnyGrowthTokens.colorSurface,
    surfaceMuted: SunnyGrowthTokens.colorSurfaceSubtle,
    toolLayer: SunnyGrowthTokens.colorSurfaceSubtle,
    line: SunnyGrowthTokens.colorBorderSubtle,
    control: SunnyGrowthTokens.colorBorderControl,
    accent: SunnyGrowthTokens.colorActionPrimary,
    accentPressed: SunnyGrowthTokens.colorActionPressed,
    accentSoft: SunnyGrowthTokens.colorActionSubtle,
    onAccent: SunnyGrowthTokens.colorTextInverse,
    gradientStart: SunnyGrowthTokens.colorActionPrimary,
    gradientEnd: SunnyGrowthTokens.colorActionPrimary,
    decoration: SunnyGrowthTokens.colorSun,
    calendarWeekend: SunnyGrowthTokens.colorTextPrimary,
    calendarFestival: SunnyGrowthTokens.colorCoralContent,
    calendarSolarTerm: SunnyGrowthTokens.colorWarning,
    shadow: SunnyGrowthTokens.colorShadow,
    success: SunnyGrowthTokens.colorSuccess,
    successSoft: SunnyGrowthTokens.colorSuccessContainer,
    warning: SunnyGrowthTokens.colorWarning,
    warningSoft: SunnyGrowthTokens.colorWarningContainer,
    danger: SunnyGrowthTokens.colorError,
    dangerSoft: SunnyGrowthTokens.colorErrorContainer,
    scrim: Color(0x7A0B1F51),
  );

  static const editorialJournalLight = AppPalette(
    style: AppThemeStyle.editorialJournal,
    brightness: Brightness.light,
    ink: EditorialJournalTokens.colorInk,
    muted: EditorialJournalTokens.colorMuted,
    subtle: EditorialJournalTokens.colorSubtle,
    canvas: EditorialJournalTokens.colorCanvas,
    surface: EditorialJournalTokens.colorSurface,
    surfaceMuted: EditorialJournalTokens.colorSurfaceMuted,
    toolLayer: EditorialJournalTokens.colorToolLayer,
    line: EditorialJournalTokens.colorLine,
    control: EditorialJournalTokens.colorControl,
    accent: EditorialJournalTokens.colorAccent,
    accentPressed: EditorialJournalTokens.colorAccentPressed,
    accentSoft: EditorialJournalTokens.colorAccentSoft,
    onAccent: Color(0xFFFFFFFF),
    gradientStart: EditorialJournalTokens.colorAccent,
    gradientEnd: EditorialJournalTokens.colorAccent,
    decoration: EditorialJournalTokens.colorCoralDecoration,
    calendarWeekend: EditorialJournalTokens.colorCobalt,
    calendarFestival: Color(0xFF875668),
    calendarSolarTerm: Color(0xFF7D612B),
    shadow: EditorialJournalTokens.colorShadow,
    success: Color(0xFF47705A),
    successSoft: Color(0xFFE4F0E9),
    warning: Color(0xFF80622F),
    warningSoft: Color(0xFFF7EACB),
    danger: Color(0xFF944F47),
    dangerSoft: Color(0xFFF7E1DD),
    scrim: Color(0x7053483D),
  );

  @override
  AppPalette copyWith({
    AppThemeStyle? style,
    Brightness? brightness,
    Color? ink,
    Color? muted,
    Color? subtle,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? toolLayer,
    Color? line,
    Color? control,
    Color? accent,
    Color? accentPressed,
    Color? accentSoft,
    Color? onAccent,
    Color? gradientStart,
    Color? gradientEnd,
    Color? decoration,
    Color? calendarWeekend,
    Color? calendarFestival,
    Color? calendarSolarTerm,
    Color? shadow,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? scrim,
  }) => AppPalette(
    style: style ?? this.style,
    brightness: brightness ?? this.brightness,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    subtle: subtle ?? this.subtle,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    toolLayer: toolLayer ?? this.toolLayer,
    line: line ?? this.line,
    control: control ?? this.control,
    accent: accent ?? this.accent,
    accentPressed: accentPressed ?? this.accentPressed,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccent: onAccent ?? this.onAccent,
    gradientStart: gradientStart ?? this.gradientStart,
    gradientEnd: gradientEnd ?? this.gradientEnd,
    decoration: decoration ?? this.decoration,
    calendarWeekend: calendarWeekend ?? this.calendarWeekend,
    calendarFestival: calendarFestival ?? this.calendarFestival,
    calendarSolarTerm: calendarSolarTerm ?? this.calendarSolarTerm,
    shadow: shadow ?? this.shadow,
    success: success ?? this.success,
    successSoft: successSoft ?? this.successSoft,
    warning: warning ?? this.warning,
    warningSoft: warningSoft ?? this.warningSoft,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    scrim: scrim ?? this.scrim,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      style: t < .5 ? style : other.style,
      brightness: t < .5 ? brightness : other.brightness,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      toolLayer: Color.lerp(toolLayer, other.toolLayer, t)!,
      line: Color.lerp(line, other.line, t)!,
      control: Color.lerp(control, other.control, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
      decoration: Color.lerp(decoration, other.decoration, t)!,
      calendarWeekend: Color.lerp(calendarWeekend, other.calendarWeekend, t)!,
      calendarFestival: Color.lerp(
        calendarFestival,
        other.calendarFestival,
        t,
      )!,
      calendarSolarTerm: Color.lerp(
        calendarSolarTerm,
        other.calendarSolarTerm,
        t,
      )!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppRadii get appRadii => appComponents.radii;

  AppComponentTheme get appComponents {
    final theme = Theme.of(this);
    return theme.extension<AppComponentTheme>() ??
        AppComponentTheme.forStyle(appColors.style);
  }

  AppPalette get appColors {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        AppPalette.forStyle(AppThemeStyle.paper, theme.brightness);
  }
}

abstract final class AppMotion {
  static const press = Duration(milliseconds: 120);
  static const state = Duration(milliseconds: 200);
  static const page = Duration(milliseconds: 280);
}

SystemUiOverlayStyle appSystemOverlayStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

ThemeData buildAppTheme(AppThemeStyle style, Brightness requestedBrightness) {
  final colors = AppPalette.forStyle(style, requestedBrightness);
  final components = AppComponentTheme.forStyle(style);
  final brightness = colors.brightness;
  final radii = components.radii;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.accentSoft,
    onPrimaryContainer: colors.onAccentSoft,
    primaryFixed: colors.accentSoft,
    primaryFixedDim: colors.surfaceMuted,
    onPrimaryFixed: colors.ink,
    onPrimaryFixedVariant: colors.accent,
    secondary: colors.muted,
    onSecondary: brightness == Brightness.dark ? colors.canvas : colors.onMedia,
    secondaryContainer: colors.warningSoft,
    onSecondaryContainer: colors.ink,
    secondaryFixed: colors.surfaceMuted,
    secondaryFixedDim: colors.warningSoft,
    onSecondaryFixed: colors.ink,
    onSecondaryFixedVariant: colors.muted,
    tertiary: colors.muted,
    onTertiary: brightness == Brightness.dark ? colors.canvas : colors.onMedia,
    tertiaryContainer: colors.surfaceMuted,
    onTertiaryContainer: colors.ink,
    tertiaryFixed: colors.surfaceMuted,
    tertiaryFixedDim: colors.surfaceMuted,
    onTertiaryFixed: colors.ink,
    onTertiaryFixedVariant: colors.muted,
    error: colors.danger,
    onError: colors.onDanger,
    errorContainer: colors.dangerSoft,
    onErrorContainer: colors.danger,
    surface: colors.surface,
    onSurface: colors.ink,
    surfaceDim: colors.surfaceMuted,
    surfaceBright: colors.surface,
    surfaceContainerLowest: colors.surface,
    surfaceContainerLow: colors.canvas,
    surfaceContainer: colors.surface,
    surfaceContainerHigh: colors.surfaceMuted,
    surfaceContainerHighest: colors.line,
    onSurfaceVariant: colors.muted,
    outline: colors.control,
    outlineVariant: colors.line,
    shadow: colors.shadow,
    scrim: colors.scrim,
    inverseSurface: colors.ink,
    onInverseSurface: colors.surface,
    inversePrimary: colors.lime,
    surfaceTint: Colors.transparent,
  );

  final displayFontFamily = components.displayFontFamily;
  final displayFontFamilyFallback =
      components.displayFontFamilyFallback ?? AppTypography.fallback;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [colors, components],
    colorScheme: scheme,
    actionIconTheme: appActionIconTheme,
    iconTheme: IconThemeData(color: colors.muted, size: 24),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.accent),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: colors.canvas,
    splashFactory: InkRipple.splashFactory,
    splashColor: colors.accent.withValues(alpha: .08),
    highlightColor: colors.accent.withValues(alpha: .04),
    hoverColor: colors.accent.withValues(alpha: .04),
    focusColor: colors.accent.withValues(alpha: .12),
    disabledColor: colors.subtle,
    fontFamilyFallback: AppTypography.fallback,
    textTheme: ThemeData(brightness: brightness).textTheme
        .apply(
          bodyColor: colors.ink,
          displayColor: colors.ink,
          fontFamilyFallback: AppTypography.fallback,
        )
        .copyWith(
          headlineLarge: TextStyle(
            fontFamily: displayFontFamily,
            fontFamilyFallback: displayFontFamilyFallback,
            color: colors.ink,
            fontSize: components.pageTitleSize,
            height: components.pageTitleHeight,
            fontWeight: FontWeight.w700,
            letterSpacing: -.55,
          ),
          headlineMedium: TextStyle(
            fontFamily: displayFontFamily,
            fontFamilyFallback: displayFontFamilyFallback,
            color: colors.ink,
            fontSize: 27,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -.55,
          ),
          headlineSmall: TextStyle(
            fontFamily: displayFontFamily,
            fontFamilyFallback: displayFontFamilyFallback,
            color: colors.ink,
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
          ),
          titleLarge: TextStyle(
            fontFamily: displayFontFamily,
            fontFamilyFallback: displayFontFamilyFallback,
            color: colors.ink,
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: -.15,
          ),
          titleMedium: TextStyle(
            fontFamily: displayFontFamily,
            fontFamilyFallback: displayFontFamilyFallback,
            color: colors.ink,
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            fontFamilyFallback: AppTypography.fallback,
            color: colors.ink,
            fontSize: components.bodyLargeSize,
            height: components.bodyLargeHeight,
            fontWeight: FontWeight.w400,
          ),
          bodyMedium: TextStyle(
            fontFamilyFallback: AppTypography.fallback,
            color: colors.ink,
            fontSize: components.bodySize,
            height: components.bodyHeight,
            fontWeight: FontWeight.w400,
          ),
          bodySmall: TextStyle(
            fontFamilyFallback: AppTypography.fallback,
            color: colors.muted,
            fontSize: components.captionSize,
            height: 1.5,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          labelLarge: TextStyle(
            fontFamilyFallback: AppTypography.fallback,
            color: colors.ink,
            fontSize: components.labelSize,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.ink,
      titleTextStyle: TextStyle(
        fontFamily: displayFontFamily,
        fontFamilyFallback: displayFontFamilyFallback,
        color: colors.ink,
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -.15,
      ),
      systemOverlayStyle: appSystemOverlayStyle(brightness),
    ),
    cardTheme: CardThemeData(
      elevation: components.cardElevation,
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: colors.shadow.withValues(alpha: .12),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.large),
        side: components.outlinesSurfaces
            ? BorderSide(
                color: colors.line,
                width: components.surfaceBorderWidth,
              )
            : BorderSide.none,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceMuted,
      hintStyle: TextStyle(
        fontFamilyFallback: AppTypography.fallback,
        color: colors.muted,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radii.medium),
        borderSide: components.outlinesControls
            ? BorderSide(
                color: colors.control,
                width: components.controlBorderWidth,
              )
            : BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radii.medium),
        borderSide: components.outlinesControls
            ? BorderSide(
                color: colors.control,
                width: components.controlBorderWidth,
              )
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radii.medium),
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: components.navigationIconSize,
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamilyFallback: AppTypography.fallback,
          fontSize: components.navigationLabelSize,
          fontWeight: FontWeight.w500,
          color: colors.muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primaryFill,
      foregroundColor: colors.onAccent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 1,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.large),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.primaryFill,
            foregroundColor: colors.onAccent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radii.button),
            ),
            textStyle: const TextStyle(
              fontFamilyFallback: AppTypography.fallback,
              fontWeight: FontWeight.w600,
            ),
          ).copyWith(
            backgroundBuilder: components.usesPaperCraftDecoration
                ? (context, states, child) {
                    final button = context.widget;
                    final customFill = button is ButtonStyleButton
                        ? button.style?.backgroundColor?.resolve(states)
                        : null;
                    if (states.contains(WidgetState.disabled) ||
                        customFill != null &&
                            customFill != colors.primaryFill) {
                      return child ?? const SizedBox.shrink();
                    }
                    return Ink(
                      decoration: ShapeDecoration(
                        gradient: colors.primaryGradient,
                        shape:
                            (button is ButtonStyleButton
                                ? button.style?.shape?.resolve(states)
                                : null) ??
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radii.button),
                            ),
                      ),
                      child: child,
                    );
                  }
                : null,
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        side: BorderSide(
          color: components.outlinesSurfaces ? colors.accent : colors.line,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.button),
        ),
        textStyle: const TextStyle(
          fontFamilyFallback: AppTypography.fallback,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.medium),
        ),
        textStyle: const TextStyle(
          fontFamilyFallback: AppTypography.fallback,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceMuted,
      disabledColor: colors.softBlue,
      selectedColor: colors.softGreen,
      secondarySelectedColor: colors.softGreen,
      surfaceTintColor: Colors.transparent,
      checkmarkColor: colors.accent,
      deleteIconColor: colors.muted,
      iconTheme: IconThemeData(color: colors.muted, size: 18),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: TextStyle(
        fontFamilyFallback: AppTypography.fallback,
        color: components.usesPaperCraftDecoration
            ? WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? colors.subtle
                    : states.contains(WidgetState.selected)
                    ? colors.onAccentSoft
                    : colors.ink,
              )
            : colors.ink,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamilyFallback: AppTypography.fallback,
        color: colors.onAccentSoft,
        fontWeight: FontWeight.w600,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: colors.ink,
      iconColor: colors.muted,
      selectedColor: colors.onAccentSoft,
      selectedTileColor: colors.softGreen,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.small),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.line.withValues(alpha: .45),
      circularTrackColor: colors.line.withValues(alpha: .45),
      linearMinHeight: 3,
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(colors.surfaceMuted),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      hintStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamilyFallback: AppTypography.fallback,
          color: colors.muted,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.medium),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.surface
            : colors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colors.accent : colors.line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentSoft
              : colors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onAccentSoft
              : colors.muted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colors.line)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamilyFallback: AppTypography.fallback,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: components.sheetElevation,
      shadowColor: colors.ink,
      modalBarrierColor: colors.scrim,
      showDragHandle: true,
      dragHandleColor: colors.line,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(radii.extraLarge),
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: components.dialogElevation,
      shadowColor: colors.ink.withValues(alpha: .12),
      barrierColor: colors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.large),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    menuTheme: MenuThemeData(style: AppMenuTokens.styleFor(colors, components)),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: components.menuElevation,
      shadowColor: colors.shadow.withValues(alpha: .16),
      menuPadding: AppMenuTokens.padding,
      shape: AppMenuTokens.shape,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppMenuTokens.textStyle.copyWith(
          color: states.contains(WidgetState.disabled)
              ? colors.subtle
              : colors.ink,
        ),
      ),
      iconColor: colors.muted,
      iconSize: 22,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamilyFallback: AppTypography.fallback,
        color: colors.surface,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: .2),
      selectionHandleColor: colors.accent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.line, thickness: 1, space: 1),
  );
}

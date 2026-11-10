import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_theme_catalog.dart';
import 'editorial_journal_tokens.dart';
import 'sunny_growth_tokens.dart';

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const small = 6.0;
  static const medium = 10.0;
  static const large = 14.0;
  static const extraLarge = 22.0;
  static const pill = 999.0;
}

@immutable
final class AppRadii {
  const AppRadii({
    required this.small,
    required this.medium,
    required this.large,
    required this.extraLarge,
    required this.button,
    required this.date,
    required this.dock,
  });

  static const quiet = AppRadii(
    small: AppRadius.small,
    medium: AppRadius.medium,
    large: AppRadius.large,
    extraLarge: AppRadius.extraLarge,
    button: 18,
    date: AppRadius.medium,
    dock: 0,
  );

  static const cloud = AppRadii(
    small: SunnyGrowthTokens.radiusSmall,
    medium: SunnyGrowthTokens.radiusMedium,
    large: SunnyGrowthTokens.radiusLarge,
    extraLarge: SunnyGrowthTokens.radiusLarge,
    button: SunnyGrowthTokens.radiusButton,
    date: SunnyGrowthTokens.radiusDate,
    dock: SunnyGrowthTokens.radiusDock,
  );

  static const editorial = AppRadii(
    small: 12,
    medium: 18,
    large: 24,
    extraLarge: 30,
    button: 20,
    date: 18,
    dock: 30,
  );

  final double small;
  final double medium;
  final double large;
  final double extraLarge;
  final double button;
  final double date;
  final double dock;

  static AppRadii lerp(AppRadii first, AppRadii second, double t) => AppRadii(
    small: lerpDouble(first.small, second.small, t)!,
    medium: lerpDouble(first.medium, second.medium, t)!,
    large: lerpDouble(first.large, second.large, t)!,
    extraLarge: lerpDouble(first.extraLarge, second.extraLarge, t)!,
    button: lerpDouble(first.button, second.button, t)!,
    date: lerpDouble(first.date, second.date, t)!,
    dock: lerpDouble(first.dock, second.dock, t)!,
  );
}

enum AppHomeLayout { quietList, editorialBoard }

enum AppLibraryPresentation { quiet, spacious, editorial }

enum AppCalendarPresentation { quiet, illustrated, layered }

enum AppThemeDecoration { none, sunCloud, paperCraft }

enum AppSettingsPresentation { flat, cardSections }

enum AppAssistantPresentation { quiet, paperCards }

enum AppEditorPresentation { plain, journal }

enum AppNavigationPresentation { fullWidth, floatingPaper }

/// Non-color design decisions shared by built-in and future experience themes.
///
/// Widgets consume these semantic values instead of branching on a concrete
/// theme name. A new theme can therefore reuse an existing component language
/// or introduce a new profile without leaking identity checks across the app.
@immutable
final class AppComponentTheme extends ThemeExtension<AppComponentTheme> {
  const AppComponentTheme({
    required this.radii,
    required this.homeLayout,
    required this.libraryPresentation,
    required this.calendarPresentation,
    required this.decoration,
    required this.settingsPresentation,
    required this.assistantPresentation,
    required this.editorPresentation,
    required this.navigationPresentation,
    required this.displayFontFamily,
    required this.displayFontFamilyFallback,
    required this.surfaceBorderWidth,
    required this.controlBorderWidth,
    required this.menuElevation,
    required this.dialogElevation,
    required this.sheetElevation,
    required this.cardElevation,
    required this.pageTitleSize,
    required this.pageTitleHeight,
    required this.bodyLargeSize,
    required this.bodyLargeHeight,
    required this.bodySize,
    required this.bodyHeight,
    required this.itemTitleSize,
    required this.itemTitleHeight,
    required this.labelSize,
    required this.captionSize,
    required this.iconSize,
    required this.iconStrokeWidth,
    required this.navigationIconSize,
    required this.navigationLabelSize,
    required this.buttonHeight,
    required this.largeTextButtonHeight,
    required this.controlHeight,
    required this.primaryButtonShadowOpacity,
    required this.primaryPressedOverlayUsesForeground,
  });

  static const quiet = AppComponentTheme(
    radii: AppRadii.quiet,
    homeLayout: AppHomeLayout.quietList,
    libraryPresentation: AppLibraryPresentation.quiet,
    calendarPresentation: AppCalendarPresentation.quiet,
    decoration: AppThemeDecoration.none,
    settingsPresentation: AppSettingsPresentation.flat,
    assistantPresentation: AppAssistantPresentation.quiet,
    editorPresentation: AppEditorPresentation.plain,
    navigationPresentation: AppNavigationPresentation.fullWidth,
    displayFontFamily: null,
    displayFontFamilyFallback: null,
    surfaceBorderWidth: 0,
    controlBorderWidth: 0,
    menuElevation: 12,
    dialogElevation: 2,
    sheetElevation: 2,
    cardElevation: 0,
    pageTitleSize: 30,
    pageTitleHeight: 1.28,
    bodyLargeSize: 16,
    bodyLargeHeight: 1.6,
    bodySize: 14,
    bodyHeight: 1.5,
    itemTitleSize: 17,
    itemTitleHeight: 1.3,
    labelSize: 14,
    captionSize: 12,
    iconSize: 21,
    iconStrokeWidth: 2,
    navigationIconSize: 22,
    navigationLabelSize: 11,
    buttonHeight: SunnyGrowthTokens.compButtonHeight,
    largeTextButtonHeight: SunnyGrowthTokens.compButtonLargeTextHeight,
    controlHeight: 48,
    primaryButtonShadowOpacity: .08,
    primaryPressedOverlayUsesForeground: false,
  );

  static const starlight = AppComponentTheme(
    radii: AppRadii.quiet,
    homeLayout: AppHomeLayout.quietList,
    libraryPresentation: AppLibraryPresentation.quiet,
    calendarPresentation: AppCalendarPresentation.quiet,
    decoration: AppThemeDecoration.none,
    settingsPresentation: AppSettingsPresentation.flat,
    assistantPresentation: AppAssistantPresentation.quiet,
    editorPresentation: AppEditorPresentation.plain,
    navigationPresentation: AppNavigationPresentation.fullWidth,
    displayFontFamily: null,
    displayFontFamilyFallback: null,
    surfaceBorderWidth: 0,
    controlBorderWidth: 0,
    menuElevation: 12,
    dialogElevation: 2,
    sheetElevation: 2,
    cardElevation: 0,
    pageTitleSize: 30,
    pageTitleHeight: 1.28,
    bodyLargeSize: 16,
    bodyLargeHeight: 1.6,
    bodySize: 14,
    bodyHeight: 1.5,
    itemTitleSize: 17,
    itemTitleHeight: 1.3,
    labelSize: 14,
    captionSize: 12,
    iconSize: 21,
    iconStrokeWidth: 2,
    navigationIconSize: 22,
    navigationLabelSize: 11,
    buttonHeight: SunnyGrowthTokens.compButtonHeight,
    largeTextButtonHeight: SunnyGrowthTokens.compButtonLargeTextHeight,
    controlHeight: 48,
    primaryButtonShadowOpacity: .08,
    primaryPressedOverlayUsesForeground: true,
  );

  static const cloud = AppComponentTheme(
    radii: AppRadii.cloud,
    homeLayout: AppHomeLayout.quietList,
    libraryPresentation: AppLibraryPresentation.spacious,
    calendarPresentation: AppCalendarPresentation.illustrated,
    decoration: AppThemeDecoration.sunCloud,
    settingsPresentation: AppSettingsPresentation.flat,
    assistantPresentation: AppAssistantPresentation.quiet,
    editorPresentation: AppEditorPresentation.plain,
    navigationPresentation: AppNavigationPresentation.fullWidth,
    displayFontFamily: null,
    displayFontFamilyFallback: null,
    surfaceBorderWidth: 1,
    controlBorderWidth: 1,
    menuElevation: 2,
    dialogElevation: 2,
    sheetElevation: 2,
    cardElevation: 0,
    pageTitleSize: 32,
    pageTitleHeight: 1.25,
    bodyLargeSize: 17,
    bodyLargeHeight: 1.5294117647058822,
    bodySize: 16,
    bodyHeight: 1.5,
    itemTitleSize: 18,
    itemTitleHeight: 1.4444444444444444,
    labelSize: 14,
    captionSize: 12,
    iconSize: SunnyGrowthTokens.compIconSize,
    iconStrokeWidth: SunnyGrowthTokens.compIconStroke,
    navigationIconSize: SunnyGrowthTokens.compNavigationIconSize,
    navigationLabelSize: 14,
    buttonHeight: SunnyGrowthTokens.compButtonHeight,
    largeTextButtonHeight: SunnyGrowthTokens.compButtonLargeTextHeight,
    controlHeight: SunnyGrowthTokens.compControlHeight,
    primaryButtonShadowOpacity: 0,
    primaryPressedOverlayUsesForeground: false,
  );

  static const editorial = AppComponentTheme(
    radii: AppRadii.editorial,
    homeLayout: AppHomeLayout.editorialBoard,
    libraryPresentation: AppLibraryPresentation.editorial,
    calendarPresentation: AppCalendarPresentation.layered,
    decoration: AppThemeDecoration.paperCraft,
    settingsPresentation: AppSettingsPresentation.cardSections,
    assistantPresentation: AppAssistantPresentation.paperCards,
    editorPresentation: AppEditorPresentation.journal,
    navigationPresentation: AppNavigationPresentation.floatingPaper,
    displayFontFamily: EditorialJournalTokens.serifFamily,
    displayFontFamilyFallback: EditorialJournalTokens.serifFallback,
    surfaceBorderWidth: 1,
    controlBorderWidth: 1,
    menuElevation: 4,
    dialogElevation: 3,
    sheetElevation: 3,
    cardElevation: 1,
    pageTitleSize: 32,
    pageTitleHeight: 1.25,
    bodyLargeSize: 17,
    bodyLargeHeight: 1.55,
    bodySize: 15,
    bodyHeight: 1.5,
    itemTitleSize: 17,
    itemTitleHeight: 1.4,
    labelSize: 14,
    captionSize: 12,
    iconSize: 23,
    iconStrokeWidth: 2.1,
    navigationIconSize: 26,
    navigationLabelSize: 12,
    buttonHeight: 54,
    largeTextButtonHeight: 66,
    controlHeight: 52,
    primaryButtonShadowOpacity: .12,
    primaryPressedOverlayUsesForeground: false,
  );

  static AppComponentTheme forStyle(AppThemeStyle style) =>
      switch (style.definition.componentProfile) {
        AppThemeComponentProfile.quiet => quiet,
        AppThemeComponentProfile.starlight => starlight,
        AppThemeComponentProfile.cloud => cloud,
        AppThemeComponentProfile.editorial => editorial,
      };

  final AppRadii radii;
  final AppHomeLayout homeLayout;
  final AppLibraryPresentation libraryPresentation;
  final AppCalendarPresentation calendarPresentation;
  final AppThemeDecoration decoration;
  final AppSettingsPresentation settingsPresentation;
  final AppAssistantPresentation assistantPresentation;
  final AppEditorPresentation editorPresentation;
  final AppNavigationPresentation navigationPresentation;
  final String? displayFontFamily;
  final List<String>? displayFontFamilyFallback;
  final double surfaceBorderWidth;
  final double controlBorderWidth;
  final double menuElevation;
  final double dialogElevation;
  final double sheetElevation;
  final double cardElevation;
  final double pageTitleSize;
  final double pageTitleHeight;
  final double bodyLargeSize;
  final double bodyLargeHeight;
  final double bodySize;
  final double bodyHeight;
  final double itemTitleSize;
  final double itemTitleHeight;
  final double labelSize;
  final double captionSize;
  final double iconSize;
  final double iconStrokeWidth;
  final double navigationIconSize;
  final double navigationLabelSize;
  final double buttonHeight;
  final double largeTextButtonHeight;
  final double controlHeight;
  final double primaryButtonShadowOpacity;
  final bool primaryPressedOverlayUsesForeground;

  bool get outlinesSurfaces => surfaceBorderWidth > 0;
  bool get outlinesControls => controlBorderWidth > 0;
  bool get usesIllustratedCalendar =>
      calendarPresentation == AppCalendarPresentation.illustrated;
  bool get usesLayeredCalendarSurfaces =>
      calendarPresentation != AppCalendarPresentation.quiet;
  bool get usesSunCloudDecoration => decoration == AppThemeDecoration.sunCloud;
  bool get usesPaperCraftDecoration =>
      decoration == AppThemeDecoration.paperCraft;
  bool get usesCardSettings =>
      settingsPresentation == AppSettingsPresentation.cardSections;
  EdgeInsets get edgeAlignedInteractivePadding => usesCardSettings
      ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
      : EdgeInsets.zero;
  bool get usesPaperAssistantCards =>
      assistantPresentation == AppAssistantPresentation.paperCards;
  bool get usesJournalEditor =>
      editorPresentation == AppEditorPresentation.journal;
  bool get usesFloatingNavigationDock =>
      navigationPresentation == AppNavigationPresentation.floatingPaper;

  @override
  AppComponentTheme copyWith() => this;

  @override
  AppComponentTheme lerp(covariant AppComponentTheme? other, double t) {
    if (other == null) return this;
    return AppComponentTheme(
      radii: AppRadii.lerp(radii, other.radii, t),
      homeLayout: t < .5 ? homeLayout : other.homeLayout,
      libraryPresentation: t < .5
          ? libraryPresentation
          : other.libraryPresentation,
      calendarPresentation: t < .5
          ? calendarPresentation
          : other.calendarPresentation,
      decoration: t < .5 ? decoration : other.decoration,
      settingsPresentation: t < .5
          ? settingsPresentation
          : other.settingsPresentation,
      assistantPresentation: t < .5
          ? assistantPresentation
          : other.assistantPresentation,
      editorPresentation: t < .5
          ? editorPresentation
          : other.editorPresentation,
      navigationPresentation: t < .5
          ? navigationPresentation
          : other.navigationPresentation,
      displayFontFamily: t < .5 ? displayFontFamily : other.displayFontFamily,
      displayFontFamilyFallback: t < .5
          ? displayFontFamilyFallback
          : other.displayFontFamilyFallback,
      surfaceBorderWidth: lerpDouble(
        surfaceBorderWidth,
        other.surfaceBorderWidth,
        t,
      )!,
      controlBorderWidth: lerpDouble(
        controlBorderWidth,
        other.controlBorderWidth,
        t,
      )!,
      menuElevation: lerpDouble(menuElevation, other.menuElevation, t)!,
      dialogElevation: lerpDouble(dialogElevation, other.dialogElevation, t)!,
      sheetElevation: lerpDouble(sheetElevation, other.sheetElevation, t)!,
      cardElevation: lerpDouble(cardElevation, other.cardElevation, t)!,
      pageTitleSize: lerpDouble(pageTitleSize, other.pageTitleSize, t)!,
      pageTitleHeight: lerpDouble(pageTitleHeight, other.pageTitleHeight, t)!,
      bodyLargeSize: lerpDouble(bodyLargeSize, other.bodyLargeSize, t)!,
      bodyLargeHeight: lerpDouble(bodyLargeHeight, other.bodyLargeHeight, t)!,
      bodySize: lerpDouble(bodySize, other.bodySize, t)!,
      bodyHeight: lerpDouble(bodyHeight, other.bodyHeight, t)!,
      itemTitleSize: lerpDouble(itemTitleSize, other.itemTitleSize, t)!,
      itemTitleHeight: lerpDouble(itemTitleHeight, other.itemTitleHeight, t)!,
      labelSize: lerpDouble(labelSize, other.labelSize, t)!,
      captionSize: lerpDouble(captionSize, other.captionSize, t)!,
      iconSize: lerpDouble(iconSize, other.iconSize, t)!,
      iconStrokeWidth: lerpDouble(iconStrokeWidth, other.iconStrokeWidth, t)!,
      navigationIconSize: lerpDouble(
        navigationIconSize,
        other.navigationIconSize,
        t,
      )!,
      navigationLabelSize: lerpDouble(
        navigationLabelSize,
        other.navigationLabelSize,
        t,
      )!,
      buttonHeight: lerpDouble(buttonHeight, other.buttonHeight, t)!,
      largeTextButtonHeight: lerpDouble(
        largeTextButtonHeight,
        other.largeTextButtonHeight,
        t,
      )!,
      controlHeight: lerpDouble(controlHeight, other.controlHeight, t)!,
      primaryButtonShadowOpacity: lerpDouble(
        primaryButtonShadowOpacity,
        other.primaryButtonShadowOpacity,
        t,
      )!,
      primaryPressedOverlayUsesForeground: t < .5
          ? primaryPressedOverlayUsesForeground
          : other.primaryPressedOverlayUsesForeground,
    );
  }
}

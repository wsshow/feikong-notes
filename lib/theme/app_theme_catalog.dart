import '../l10n/generated/app_localizations.dart';

/// Stable identifier for an application-wide visual experience.
///
/// Persisted preferences use [AppThemeDefinition.storageId], not enum indexes,
/// so adding or reordering themes cannot change an existing user's choice.
enum AppThemeStyle { paper, starlight, sunnyGrowth, editorialJournal }

enum AppThemePreviewDecoration { none, sunCloud, paperCraft }

enum AppThemeComponentProfile { quiet, starlight, cloud, editorial }

typedef AppThemeLocalizedCopy = String Function(AppLocalizations l10n);

/// Metadata and capabilities owned by one registered application theme.
final class AppThemeDefinition {
  const AppThemeDefinition({
    required this.style,
    required this.storageId,
    required this.label,
    required this.description,
    required this.supportsDark,
    required this.componentProfile,
    this.previewDecoration = AppThemePreviewDecoration.none,
    this.lightOnlyDescription,
  });

  final AppThemeStyle style;
  final String storageId;
  final AppThemeLocalizedCopy label;
  final AppThemeLocalizedCopy description;
  final bool supportsDark;
  final AppThemeComponentProfile componentProfile;
  final AppThemePreviewDecoration previewDecoration;
  final AppThemeLocalizedCopy? lightOnlyDescription;
}

/// The single source of truth for themes exposed by the application.
///
/// Page code consumes the selected definition and semantic theme extensions;
/// it must not maintain its own list of theme names or capabilities.
abstract final class AppThemeCatalog {
  static const defaultStyle = AppThemeStyle.editorialJournal;

  static final List<AppThemeDefinition> definitions = List.unmodifiable([
    AppThemeDefinition(
      style: AppThemeStyle.paper,
      storageId: 'paper',
      label: (l10n) => l10n.themePaper,
      description: (l10n) => l10n.themePaperDescription,
      supportsDark: true,
      componentProfile: AppThemeComponentProfile.quiet,
    ),
    AppThemeDefinition(
      style: AppThemeStyle.starlight,
      storageId: 'starlight',
      label: (l10n) => l10n.themeStarlight,
      description: (l10n) => l10n.themeStarlightDescription,
      supportsDark: true,
      componentProfile: AppThemeComponentProfile.starlight,
    ),
    AppThemeDefinition(
      style: AppThemeStyle.sunnyGrowth,
      storageId: 'sunnyGrowth',
      label: (l10n) => l10n.themeSunnyGrowth,
      description: (l10n) => l10n.themeSunnyGrowthDescription,
      supportsDark: false,
      componentProfile: AppThemeComponentProfile.cloud,
      previewDecoration: AppThemePreviewDecoration.sunCloud,
      lightOnlyDescription: (l10n) => l10n.themeSunnyGrowthLightOnly,
    ),
    AppThemeDefinition(
      style: AppThemeStyle.editorialJournal,
      storageId: 'editorialJournal',
      label: (l10n) => l10n.themeEditorialJournal,
      description: (l10n) => l10n.themeEditorialJournalDescription,
      supportsDark: false,
      componentProfile: AppThemeComponentProfile.editorial,
      previewDecoration: AppThemePreviewDecoration.paperCraft,
      lightOnlyDescription: (l10n) => l10n.themeEditorialJournalLightOnly,
    ),
  ]);

  static final Map<AppThemeStyle, AppThemeDefinition> _byStyle = {
    for (final definition in definitions) definition.style: definition,
  };

  static final Map<String, AppThemeDefinition> _byStorageId = {
    for (final definition in definitions) definition.storageId: definition,
  };

  static AppThemeDefinition definitionFor(AppThemeStyle style) =>
      _byStyle[style] ?? _byStyle[defaultStyle]!;

  static AppThemeStyle styleFromStorage(Object? value) => value is String
      ? (_byStorageId[value]?.style ?? defaultStyle)
      : defaultStyle;
}

extension AppThemeStyleDefinition on AppThemeStyle {
  AppThemeDefinition get definition => AppThemeCatalog.definitionFor(this);

  bool get supportsDark => definition.supportsDark;

  String get storageId => definition.storageId;
}

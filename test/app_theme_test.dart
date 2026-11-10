import 'dart:io';
import 'dart:convert';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/pages/theme_settings_page.dart';
import 'package:fknotes/providers/app_theme_controller.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/app_primary_button.dart';
import 'package:fknotes/widgets/sunny_growth_decoration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('theme catalog presents one cohesive literary naming system', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    expect(
      AppThemeCatalog.definitions
          .map((definition) => definition.label(zh))
          .toList(),
      ['素笺留白', '星河入梦', '云间拾光', '纸短情长'],
    );
    expect(
      AppThemeCatalog.definitions
          .map((definition) => definition.label(en))
          .toList(),
      ['Quiet Margins', 'Starlit Reverie', 'Cloud Reverie', 'Letters Unending'],
    );
  });

  test('every registered theme installs a component profile', () {
    for (final definition in AppThemeCatalog.definitions) {
      final expected = AppComponentTheme.forStyle(definition.style);
      final theme = buildAppTheme(definition.style, Brightness.light);
      expect(theme.extension<AppComponentTheme>(), same(expected));
    }
    expect(
      AppComponentTheme.forStyle(AppThemeStyle.paper).radii,
      same(AppRadii.quiet),
    );
    expect(
      AppComponentTheme.forStyle(
        AppThemeStyle.starlight,
      ).primaryPressedOverlayUsesForeground,
      isTrue,
    );
    expect(
      AppComponentTheme.forStyle(
        AppThemeStyle.sunnyGrowth,
      ).usesIllustratedCalendar,
      isTrue,
    );
    final editorial = AppComponentTheme.forStyle(
      AppThemeStyle.editorialJournal,
    );
    expect(editorial.usesPaperCraftDecoration, isTrue);
    expect(editorial.usesCardSettings, isTrue);
    expect(
      editorial.edgeAlignedInteractivePadding,
      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    expect(
      AppComponentTheme.quiet.edgeAlignedInteractivePadding,
      EdgeInsets.zero,
    );
    expect(editorial.usesPaperAssistantCards, isTrue);
    expect(editorial.usesJournalEditor, isTrue);
    expect(editorial.usesLayeredCalendarSurfaces, isTrue);
    expect(editorial.usesFloatingNavigationDock, isTrue);
    expect(AppComponentTheme.cloud.usesFloatingNavigationDock, isFalse);
    expect(editorial.displayFontFamily, isNotNull);
  });

  testWidgets('paper craft decoration is a static background layer', (
    tester,
  ) async {
    Future<void> pump(AppThemeStyle style) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(style, Brightness.light),
          home: const AppThemeCanvas(child: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(AppThemeStyle.editorialJournal);
    final editorialDecoration = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-theme-static-decoration')),
    );
    final editorialBox = editorialDecoration.decoration as BoxDecoration;
    expect(
      editorialBox.image?.image,
      const AssetImage(EditorialJournalTokens.paperTextureAsset),
    );
    expect(find.byKey(const Key('app-theme-paper-grain')), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    expect(
      tester
          .widget<Material>(find.byKey(const Key('app-theme-content-material')))
          .type,
      MaterialType.transparency,
    );

    await pump(AppThemeStyle.paper);
    final quietDecoration = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-theme-static-decoration')),
    );
    expect((quietDecoration.decoration as BoxDecoration).image, isNull);
  });

  for (final style in AppThemeStyle.values) {
    for (final brightness in Brightness.values) {
      test(
        '${style.name} ${brightness.name} maintains readable semantic colors',
        () {
          final colors = AppPalette.forStyle(style, brightness);
          final scheme = buildAppTheme(style, brightness).colorScheme;
          for (final pair in [
            (scheme.secondary, scheme.onSecondary),
            (scheme.tertiary, scheme.onTertiary),
            (scheme.error, scheme.onError),
          ]) {
            expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
          }
          for (final background in [
            colors.canvas,
            colors.surface,
            colors.surfaceMuted,
          ]) {
            expect(_contrast(colors.ink, background), greaterThanOrEqualTo(7));
            expect(
              _contrast(colors.muted, background),
              greaterThanOrEqualTo(4.5),
            );
            for (final accent in [
              colors.calendarWeekend,
              colors.calendarFestival,
              colors.calendarSolarTerm,
            ]) {
              expect(_contrast(accent, background), greaterThanOrEqualTo(4.5));
            }
          }
          expect(
            _contrast(colors.onAccentSoft, colors.accentSoft),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(colors.onAccentSoft, colors.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(colors.onAccent, colors.primaryFill),
            greaterThanOrEqualTo(4.5),
          );
          for (final stop in colors.primaryGradient?.colors ?? <Color>[]) {
            expect(_contrast(colors.onStrong, stop), greaterThanOrEqualTo(4.5));
          }
          for (final end in [colors.gradientStart, colors.gradientEnd]) {
            expect(_contrast(colors.onStrong, end), greaterThanOrEqualTo(4.5));
          }
        },
      );
    }
  }

  test('calendar accents participate in palette copies and interpolation', () {
    final start = AppPalette.paperLight;
    final end = AppPalette.starlightDark;
    final copy = start.copyWith(
      calendarWeekend: end.calendarWeekend,
      calendarFestival: end.calendarFestival,
      calendarSolarTerm: end.calendarSolarTerm,
    );
    expect(copy.calendarWeekend, end.calendarWeekend);
    expect(copy.calendarFestival, end.calendarFestival);
    expect(copy.calendarSolarTerm, end.calendarSolarTerm);
    final middle = start.lerp(end, .5);
    expect(
      middle.calendarWeekend,
      Color.lerp(start.calendarWeekend, end.calendarWeekend, .5),
    );
    expect(
      middle.calendarFestival,
      Color.lerp(start.calendarFestival, end.calendarFestival, .5),
    );
    expect(
      middle.calendarSolarTerm,
      Color.lerp(start.calendarSolarTerm, end.calendarSolarTerm, .5),
    );
  });

  test('bottom navigation selection changes only the icon color', () {
    for (final style in AppThemeStyle.values) {
      final colors = AppPalette.forStyle(style, Brightness.light);
      final navigation = buildAppTheme(
        style,
        Brightness.light,
      ).navigationBarTheme;
      expect(navigation.indicatorColor, Colors.transparent);
      expect(
        navigation.iconTheme?.resolve({WidgetState.selected})?.color,
        colors.accent,
      );
      expect(
        navigation.labelTextStyle?.resolve({WidgetState.selected})?.color,
        colors.muted,
      );
    }
  });

  test('editorial accents stay muted while preserving readable actions', () {
    final colors = AppPalette.editorialJournalLight;
    final theme = buildAppTheme(
      AppThemeStyle.editorialJournal,
      Brightness.light,
    );

    expect(
      HSLColor.fromColor(colors.accent).saturation,
      lessThanOrEqualTo(.45),
    );
    expect(
      HSLColor.fromColor(colors.decoration).saturation,
      lessThanOrEqualTo(.5),
    );
    expect(
      HSLColor.fromColor(colors.calendarWeekend).saturation,
      lessThanOrEqualTo(.35),
    );
    for (final background in [
      colors.canvas,
      colors.surface,
      colors.surfaceMuted,
    ]) {
      expect(_contrast(colors.accent, background), greaterThanOrEqualTo(4.5));
    }
    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
      colors.primaryFill,
    );
    expect(
      colors.primaryFill.computeLuminance(),
      greaterThan(colors.accent.computeLuminance()),
    );
    expect(colors.onAccentSoft, colors.accent);
  });

  testWidgets('paper button lift preserves disabled and destructive states', (
    tester,
  ) async {
    final colors = AppPalette.editorialJournalLight;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                key: const Key('primary'),
                onPressed: () => taps++,
                child: const Text('Import'),
              ),
              const FilledButton(
                key: Key('disabled'),
                onPressed: null,
                child: Text('Import'),
              ),
              FilledButton(
                key: const Key('destructive'),
                onPressed: () {},
                style: FilledButton.styleFrom(backgroundColor: colors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
    Finder ink(String key) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Ink));
    expect(
      (tester.widget<Ink>(ink('primary')).decoration! as ShapeDecoration)
          .gradient,
      colors.primaryGradient,
    );
    expect(ink('disabled'), findsNothing);
    expect(ink('destructive'), findsNothing);
    final destructiveMaterial = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const Key('destructive')),
        matching: find.byType(Material),
      ),
    );
    expect(destructiveMaterial.color, colors.danger);
    await tester.tap(find.byKey(const Key('primary')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paper location and type chips share selected text color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              ChoiceChip(
                label: const Text('All files'),
                selected: true,
                onSelected: (_) {},
              ),
              FilterChip(
                label: const Text('All types'),
                selected: true,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    for (final label in ['All files', 'All types']) {
      expect(
        DefaultTextStyle.of(tester.element(find.text(label))).style.color,
        AppPalette.editorialJournalLight.accent,
      );
    }
  });

  test('sunny appearance remains light when a dark theme is requested', () {
    final theme = buildAppTheme(AppThemeStyle.sunnyGrowth, Brightness.dark);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.extension<AppPalette>(), AppPalette.sunnyGrowthLight);
    expect(
      theme.appBarTheme.systemOverlayStyle!.statusBarIconBrightness,
      Brightness.dark,
    );
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('primary press respects reduced motion: $reduceMotion', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppThemeStyle.starlight, Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  height: 52,
                  child: AppPrimaryButton(
                    onPressed: () => taps++,
                    icon: const Icon(Icons.add),
                    label: const Text('New note'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.byType(AppPrimaryButton);
      final original = tester.getRect(button);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      await tester.pump(AppMotion.press);
      final scale = tester.widget<AnimatedScale>(
        find.descendant(of: button, matching: find.byType(AnimatedScale)),
      );
      expect(scale.scale, reduceMotion ? 1 : .98);
      expect(tester.getRect(button), original);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'theme settings persist on an open route at large text in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final directory = Directory.systemTemp.createTempSync(
          'fknotes_theme_ui_',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final controller = AppThemeController(
          settingsPath: '${directory.path}/theme.json',
          preferenceWriter: (style, mode) async {
            File('${directory.path}/theme.json').writeAsStringSync(
              jsonEncode({'style': style.name, 'mode': mode.name}),
            );
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<AppThemeController>.value(
            value: controller,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildAppTheme(controller.style, Brightness.light),
                darkTheme: buildAppTheme(controller.style, Brightness.dark),
                themeMode: controller.mode,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ThemeSettingsPage(),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(ThemeSettingsPage));
        final settingsList = find.descendant(
          of: find.byType(ThemeSettingsPage),
          matching: find.byType(Scrollable),
        );
        final violet = find.byKey(const Key('app-theme-starlight'));
        await tester.scrollUntilVisible(violet, 250, scrollable: settingsList);
        await tester.pumpAndSettle();
        await tester.tap(violet);
        await tester.pumpAndSettle();
        expect(controller.style, AppThemeStyle.starlight);
        expect(tester.state(find.byType(ThemeSettingsPage)), same(state));
        expect(
          tester.element(find.byType(ThemeSettingsPage)).appColors,
          AppPalette.starlightLight,
        );
        final dark = find.byKey(const Key('app-theme-mode-dark'));
        // Large theme cards can leave brightness options outside the list cache.
        await tester.scrollUntilVisible(dark, 250, scrollable: settingsList);
        await tester.pumpAndSettle();
        await tester.tap(dark);
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byType(ThemeSettingsPage)).appColors,
          AppPalette.starlightDark,
        );
        final restored = AppThemeController(
          settingsPath: '${directory.path}/theme.json',
        );
        addTearDown(restored.dispose);
        await tester.runAsync(restored.initialize);
        expect(restored.style, AppThemeStyle.starlight);
        expect(restored.mode, ThemeMode.dark);
        final followSystem = find.byKey(const Key('app-theme-mode-system'));
        await tester.scrollUntilVisible(
          followSystem,
          -250,
          scrollable: settingsList,
        );
        await tester.pumpAndSettle();
        await tester.tap(followSystem);
        await tester.pumpAndSettle();
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byType(ThemeSettingsPage)).appColors,
          AppPalette.starlightDark,
        );
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byType(ThemeSettingsPage)).appColors,
          AppPalette.starlightLight,
        );
        expect(tester.state(find.byType(ThemeSettingsPage)), same(state));
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byTooltip(
            MaterialLocalizations.of(
              tester.element(find.byType(ThemeSettingsPage)),
            ).backButtonTooltip,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
      },
    );
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

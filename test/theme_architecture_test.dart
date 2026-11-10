import 'dart:io';

import 'package:fknotes/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme catalog has one stable definition for every style', () {
    final definitions = AppThemeCatalog.definitions;

    expect(AppThemeCatalog.defaultStyle, AppThemeStyle.editorialJournal);
    expect(
      AppThemeCatalog.styleFromStorage(null),
      AppThemeStyle.editorialJournal,
    );
    expect(
      AppThemeCatalog.styleFromStorage('unsupported-theme'),
      AppThemeStyle.editorialJournal,
    );

    expect(
      definitions.map((definition) => definition.style).toSet(),
      AppThemeStyle.values.toSet(),
    );
    expect(
      definitions.map((definition) => definition.storageId).toSet().length,
      definitions.length,
      reason: 'Persisted theme identifiers must remain unique.',
    );
    for (final definition in definitions) {
      expect(
        AppThemeCatalog.styleFromStorage(definition.storageId),
        definition.style,
      );
      expect(
        AppComponentTheme.forStyle(definition.style),
        isA<AppComponentTheme>(),
      );
    }
  });

  test('feature presentation never branches on a concrete theme identity', () {
    const presentationRoots = ['lib/pages', 'lib/widgets', 'lib/experience'];
    final offenders = <String>[];

    for (final root in presentationRoots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (RegExp(r'\bAppThemeStyle\.').hasMatch(source)) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Feature UI must consume AppPalette/AppComponentTheme semantics. '
          'Concrete theme identities belong in lib/theme only.',
    );
  });

  test('overview surfaces cannot project or clone complete note bodies', () {
    const overviewFiles = [
      'lib/pages/note_library_page.dart',
      'lib/pages/note_tag_groups_page.dart',
      'lib/pages/note_calendar_page.dart',
      'lib/widgets/note_calendar_note_card.dart',
      'lib/widgets/note_delta_preview.dart',
      'lib/widgets/local_chat_note_picker.dart',
      'lib/widgets/local_chat_tool_action_sheet.dart',
    ];
    final offenders = <String>[];

    for (final path in overviewFiles) {
      final source = File(path).readAsStringSync();
      if (source.contains('.project(') ||
          source.contains('.toDelta().operations')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Overview UI must consume the shared bounded preview APIs instead '
          'of traversing or cloning complete note documents.',
    );
  });
}

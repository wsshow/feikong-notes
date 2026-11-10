import 'dart:convert';
import 'dart:io';

import 'package:fknotes/providers/app_theme_controller.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String settingsPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_theme_');
    settingsPath = '${directory.path}/theme.json';
  });
  tearDown(() => directory.delete(recursive: true));

  AppThemeController create() {
    final controller = AppThemeController(settingsPath: settingsPath);
    addTearDown(controller.dispose);
    return controller;
  }

  test('uses Letters Unending in light mode on first launch', () async {
    final controller = create();
    await controller.initialize();
    expect(controller.style, AppThemeStyle.editorialJournal);
    expect(controller.mode, ThemeMode.light);
  });

  test('restores both theme and appearance after restart', () async {
    final controller = create();
    await controller.setStyle(AppThemeStyle.starlight);
    await controller.setMode(ThemeMode.system);
    final restored = create();
    await restored.initialize();
    expect(restored.style, AppThemeStyle.starlight);
    expect(restored.mode, ThemeMode.system);
    expect(await File('$settingsPath.tmp').exists(), isFalse);
  });

  test('catalog exposes stable unique persisted identifiers', () {
    final definitions = AppThemeCatalog.definitions;
    expect(definitions.map((item) => item.style).toSet(), {
      ...AppThemeStyle.values,
    });
    expect(
      definitions.map((item) => item.storageId).toSet(),
      hasLength(definitions.length),
    );
    for (final definition in definitions) {
      expect(
        AppThemeCatalog.styleFromStorage(definition.storageId),
        definition.style,
      );
    }
  });

  test(
    'sunny theme restores without overwriting the preferred brightness',
    () async {
      final controller = create();
      await controller.setMode(ThemeMode.dark);
      await controller.setStyle(AppThemeStyle.sunnyGrowth);
      expect(controller.effectiveMode, ThemeMode.light);
      final restored = create();
      await restored.initialize();
      expect(restored.style, AppThemeStyle.sunnyGrowth);
      expect(restored.mode, ThemeMode.dark);
      expect(restored.effectiveMode, ThemeMode.light);
      await restored.setStyle(AppThemeStyle.starlight);
      expect(restored.effectiveMode, ThemeMode.dark);
    },
  );

  for (final contents in [
    '{broken',
    '[]',
    'null',
    '{"style":"future","mode":42}',
  ]) {
    test('safely reads unsupported preference $contents', () async {
      await File(settingsPath).writeAsString(contents);
      final controller = create();
      await controller.initialize();
      expect(controller.style, AppThemeStyle.editorialJournal);
      expect(controller.mode, ThemeMode.light);
    });
  }

  test('serializes rapid updates and persists the most recent pair', () async {
    final controller = create();
    await Future.wait([
      controller.setStyle(AppThemeStyle.starlight),
      controller.setMode(ThemeMode.dark),
      controller.setStyle(AppThemeStyle.paper),
      controller.setMode(ThemeMode.system),
    ]);
    expect(jsonDecode(await File(settingsPath).readAsString()), {
      'style': 'paper',
      'mode': 'system',
    });
    final restored = create();
    await restored.initialize();
    expect(restored.style, controller.style);
    expect(restored.mode, controller.mode);
  });

  test(
    'failed queued saves roll back to disk and a later retry succeeds',
    () async {
      await Directory(settingsPath).create();
      final controller = create();
      final first = expectLater(
        controller.setStyle(AppThemeStyle.starlight),
        throwsA(isA<FileSystemException>()),
      );
      final second = expectLater(
        controller.setMode(ThemeMode.dark),
        throwsA(isA<FileSystemException>()),
      );
      await Future.wait([first, second]);
      expect(controller.style, AppThemeStyle.editorialJournal);
      expect(controller.mode, ThemeMode.light);
      await Directory(settingsPath).delete();
      await controller.setStyle(AppThemeStyle.starlight);
      final restored = create();
      await restored.initialize();
      expect(restored.style, AppThemeStyle.starlight);
    },
  );
}

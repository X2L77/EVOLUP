import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/preferences_store.dart';
import 'package:my_training/theme/app_theme.dart';

class _MemoryPreferencesStore implements PreferencesStore {
  ThemePreferences? stored;

  @override
  Future<ThemePreferences?> load() async => stored;

  @override
  Future<void> save(ThemePreferences preferences) async {
    stored = preferences;
  }
}

void main() {
  test('theme preferences restore a saved palette and brightness', () async {
    final store = _MemoryPreferencesStore()
      ..stored = const ThemePreferences(
        palette: EvolupPalette.blue,
        isDark: false,
      );
    final controller = ThemeController(store);

    await controller.load();

    expect(controller.value.palette, EvolupPalette.blue);
    expect(controller.value.isDark, isFalse);
    expect(buildEvolupTheme(controller.value).brightness, Brightness.light);
  });

  test('all four palettes support both brightness modes', () {
    for (final palette in EvolupPalette.values) {
      for (final isDark in [true, false]) {
        final theme = buildEvolupTheme(
          ThemePreferences(palette: palette, isDark: isDark),
        );
        expect(theme.brightness, isDark ? Brightness.dark : Brightness.light);
        expect(theme.colorScheme.primary, isNotNull);
      }
    }
  });

  test('updating theme persists the new value for the next launch', () async {
    final store = _MemoryPreferencesStore();
    final controller = ThemeController(store);
    await controller.update(
      const ThemePreferences(palette: EvolupPalette.monochrome, isDark: false),
    );

    final nextLaunch = ThemeController(store);
    await nextLaunch.load();
    expect(nextLaunch.value.palette, EvolupPalette.monochrome);
    expect(nextLaunch.value.isDark, isFalse);
  });
}

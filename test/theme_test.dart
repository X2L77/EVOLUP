import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/theme/evolup_theme.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('dark mode with the Blue palette is the default', () {
    const appearance = AppAppearance();
    expect(appearance.palette, AppPalette.blue);
    expect(appearance.mode, AppThemeMode.dark);
    expect(AppPalette.fromStorage(null), AppPalette.blue);
    expect(AppThemeMode.fromStorage('nonsense'), AppThemeMode.dark);
  });

  test('the four planned palettes exist in both modes, with readable text', () {
    expect(AppPalette.values.map((p) => p.label), [
      'Gold',
      'Black & White',
      'Blue',
      'Violet',
    ]);
    for (final palette in AppPalette.values) {
      for (final mode in AppThemeMode.values) {
        final colors = EvolupColors.resolve(
          AppAppearance(palette: palette, mode: mode),
        );
        final label = '${palette.name}/${mode.name}';
        expect(colors.brightness, mode.brightness, reason: label);
        expect(
          _contrast(colors.textPrimary, colors.background),
          greaterThanOrEqualTo(7),
          reason: label,
        );
        expect(
          _contrast(colors.textSecondary, colors.background),
          greaterThanOrEqualTo(4.5),
          reason: label,
        );
        expect(
          _contrast(colors.primaryButtonText, colors.primaryButton),
          greaterThanOrEqualTo(7),
          reason: label,
        );
        expect(
          _contrast(colors.accent, colors.background),
          greaterThanOrEqualTo(3),
          reason: label,
        );
        final theme = buildEvolupTheme(colors);
        expect(theme.extension<EvolupColors>(), colors);
        expect(theme.scaffoldBackgroundColor, colors.background);
      }
    }
  });

  test('app bar titles keep the Material title size in every theme', () {
    final themes = [
      (EvolupColors.brand, 'brand'),
      for (final palette in AppPalette.values)
        for (final mode in AppThemeMode.values)
          (
            EvolupColors.resolve(AppAppearance(palette: palette, mode: mode)),
            '${palette.name}/${mode.name}',
          ),
    ];
    for (final (colors, label) in themes) {
      final style = buildEvolupTheme(colors).appBarTheme.titleTextStyle!;
      expect(style.fontSize, 22, reason: label);
      expect(style.height, isNotNull, reason: label);
      expect(style.color, colors.textPrimary, reason: label);
      expect(style.fontWeight, FontWeight.w700, reason: label);
    }
  });

  testWidgets('an app bar title is rendered at 22 px, not 14 px', (
    tester,
  ) async {
    for (final mode in AppThemeMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEvolupTheme(
            EvolupColors.resolve(AppAppearance(mode: mode)),
          ),
          home: Scaffold(appBar: AppBar(title: const Text('Mes données'))),
        ),
      );
      final style = DefaultTextStyle.of(
        tester.element(find.text('Mes données')),
      ).style;
      expect(style.fontSize, 22, reason: mode.name);
      expect(style.fontWeight, FontWeight.w700, reason: mode.name);
    }
  });

  test('the sign-in identity stays the EVOLUP night blue', () {
    expect(EvolupColors.brand.background, EvolupBrand.background);
    expect(EvolupColors.brand.isDark, isTrue);
    expect(
      EvolupColors.resolve(const AppAppearance()).background,
      EvolupBrand.background,
    );
  });
}

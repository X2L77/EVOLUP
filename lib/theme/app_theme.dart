import 'package:flutter/material.dart';

enum EvolupPalette {
  gold('Gold', Color(0xFFC99A3B)),
  monochrome('Black & White', Color(0xFF8B929C)),
  blue('Blue', Color(0xFF4F8FE8)),
  violet('Violet', Color(0xFF9473E8));

  const EvolupPalette(this.label, this.seedColor);

  final String label;
  final Color seedColor;

  static EvolupPalette fromName(String? value) =>
      EvolupPalette.values
          .where((palette) => palette.name == value)
          .firstOrNull ??
      EvolupPalette.gold;
}

@immutable
class ThemePreferences {
  const ThemePreferences({
    this.palette = EvolupPalette.gold,
    this.isDark = true,
  });

  final EvolupPalette palette;
  final bool isDark;

  ThemePreferences copyWith({EvolupPalette? palette, bool? isDark}) =>
      ThemePreferences(
        palette: palette ?? this.palette,
        isDark: isDark ?? this.isDark,
      );
}

ThemeData buildEvolupTheme(ThemePreferences preferences) {
  final brightness = preferences.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: preferences.palette.seedColor,
    brightness: brightness,
  );
  final background = preferences.isDark
      ? const Color(0xFF101114)
      : const Color(0xFFF7F7F5);
  final surface = preferences.isDark ? const Color(0xFF1A1B1F) : Colors.white;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme.copyWith(
      surface: surface,
      primary: preferences.palette.seedColor,
    ),
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: preferences.isDark
          ? const Color(0xFF23252A)
          : const Color(0xFFF1F1EF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: preferences.isDark
              ? const Color(0xFF383A40)
              : const Color(0xFFE1E1DE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: preferences.palette.seedColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textTheme: Typography.material2021().black.apply(
      bodyColor: preferences.isDark
          ? const Color(0xFFF4F3F0)
          : const Color(0xFF202124),
      displayColor: preferences.isDark
          ? const Color(0xFFF4F3F0)
          : const Color(0xFF202124),
    ),
  );
}

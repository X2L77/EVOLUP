import 'package:flutter/material.dart';

/// Fixed colors of the sign-in screen (build guide §1.2).
///
/// The sign-in screen always uses this dark night-blue identity, whatever
/// palette the user picks later in the app.
abstract final class EvolupColors {
  static const background = Color(0xFF04060D);
  static const haloBlueViolet = Color(0xFF4C4FE0);
  static const haloCyan = Color(0xFF18B8D4);
  static const dot = Color(0x1FFFFFFF);
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF9AA3B5);
  static const glassFillTop = Color(0x17FFFFFF);
  static const glassFillBottom = Color(0x08FFFFFF);
  static const glassBorder = Color(0x24FFFFFF);
  static const fieldFill = Color(0x0FFFFFFF);
  static const fieldBorder = Color(0x26FFFFFF);
  static const focus = Color(0xFF8EA2FF);
  static const primaryButton = Color(0xFFEEF1F8);
  static const primaryButtonText = Color(0xFF0A0F1F);
  static const error = Color(0xFFFF8A8A);
  static const success = Color(0xFF7FE3C9);

  /// Dark tint under the navigation bar's glass, so its labels stay readable
  /// over any content scrolling behind it.
  static const navBarTint = Color(0xB30A0E1C);
  static const navSelected = Color(0x268EA2FF);
}

ThemeData buildEvolupBrandTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: EvolupColors.haloBlueViolet,
        brightness: Brightness.dark,
      ).copyWith(
        primary: EvolupColors.focus,
        onPrimary: EvolupColors.primaryButtonText,
        surface: EvolupColors.background,
        onSurface: EvolupColors.textPrimary,
        onSurfaceVariant: EvolupColors.textSecondary,
        error: EvolupColors.error,
      );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: EvolupColors.background,
    textTheme: Typography.material2021().white.apply(
      bodyColor: EvolupColors.textPrimary,
      displayColor: EvolupColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EvolupColors.fieldFill,
      labelStyle: const TextStyle(color: EvolupColors.textSecondary),
      floatingLabelStyle: const TextStyle(color: EvolupColors.textPrimary),
      prefixIconColor: EvolupColors.textSecondary,
      suffixIconColor: EvolupColors.textSecondary,
      border: border(EvolupColors.fieldBorder),
      enabledBorder: border(EvolupColors.fieldBorder),
      focusedBorder: border(EvolupColors.focus, 1.5),
      errorBorder: border(EvolupColors.error),
      focusedErrorBorder: border(EvolupColors.error, 1.5),
      errorStyle: const TextStyle(color: EvolupColors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EvolupColors.primaryButton,
        foregroundColor: EvolupColors.primaryButtonText,
        disabledBackgroundColor: EvolupColors.primaryButton.withValues(
          alpha: 0.55,
        ),
        disabledForegroundColor: EvolupColors.primaryButtonText,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: EvolupColors.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: EvolupColors.primaryButtonText,
    ),
  );
}

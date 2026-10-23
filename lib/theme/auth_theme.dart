import 'package:flutter/material.dart';

/// Fixed colors of the sign-in screen (build guide §1.2).
///
/// The sign-in screen always uses this dark night-blue identity, whatever
/// palette the user picks later in the app.
abstract final class AuthColors {
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
}

ThemeData buildAuthTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AuthColors.haloBlueViolet,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AuthColors.focus,
        onPrimary: AuthColors.primaryButtonText,
        surface: AuthColors.background,
        onSurface: AuthColors.textPrimary,
        onSurfaceVariant: AuthColors.textSecondary,
        error: AuthColors.error,
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
    scaffoldBackgroundColor: AuthColors.background,
    textTheme: Typography.material2021().white.apply(
      bodyColor: AuthColors.textPrimary,
      displayColor: AuthColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AuthColors.fieldFill,
      labelStyle: const TextStyle(color: AuthColors.textSecondary),
      floatingLabelStyle: const TextStyle(color: AuthColors.textPrimary),
      prefixIconColor: AuthColors.textSecondary,
      suffixIconColor: AuthColors.textSecondary,
      border: border(AuthColors.fieldBorder),
      enabledBorder: border(AuthColors.fieldBorder),
      focusedBorder: border(AuthColors.focus, 1.5),
      errorBorder: border(AuthColors.error),
      focusedErrorBorder: border(AuthColors.error, 1.5),
      errorStyle: const TextStyle(color: AuthColors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AuthColors.primaryButton,
        foregroundColor: AuthColors.primaryButtonText,
        disabledBackgroundColor: AuthColors.primaryButton.withValues(
          alpha: 0.55,
        ),
        disabledForegroundColor: AuthColors.primaryButtonText,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AuthColors.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AuthColors.primaryButtonText,
    ),
  );
}

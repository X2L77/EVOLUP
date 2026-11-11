import 'package:flutter/material.dart';

/// Fixed colors of the sign-in screens (build guide §1.2): the night-blue
/// EVOLUP identity, whatever palette the user picks in the app.
abstract final class EvolupBrand {
  static const background = Color(0xFF04060D);
  static const haloBlueViolet = Color(0xFF4C4FE0);
  static const haloCyan = Color(0xFF18B8D4);
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF9AA3B5);
  static const glassBorder = Color(0x24FFFFFF);
  static const fieldFill = Color(0x0FFFFFFF);
  static const focus = Color(0xFF8EA2FF);
}

/// Palettes offered in Paramètres → Préférences (stored in
/// `profiles.theme_palette`).
enum AppPalette {
  gold('gold', 'Gold'),
  blackWhite('black_white', 'Black & White'),
  blue('blue', 'Blue'),
  violet('violet', 'Violet');

  const AppPalette(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static AppPalette fromStorage(String? value) => values.firstWhere(
    (palette) => palette.storageValue == value,
    orElse: () => AppPalette.blue,
  );
}

/// Display mode (stored in `profiles.theme_mode`); dark by default.
enum AppThemeMode {
  dark('dark', 'Sombre', Brightness.dark),
  light('light', 'Clair', Brightness.light);

  const AppThemeMode(this.storageValue, this.label, this.brightness);

  final String storageValue;
  final String label;
  final Brightness brightness;

  static AppThemeMode fromStorage(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => AppThemeMode.dark,
  );
}

@immutable
class AppAppearance {
  const AppAppearance({
    this.palette = AppPalette.blue,
    this.mode = AppThemeMode.dark,
  });

  final AppPalette palette;
  final AppThemeMode mode;

  @override
  bool operator ==(Object other) =>
      other is AppAppearance && other.palette == palette && other.mode == mode;

  @override
  int get hashCode => Object.hash(palette, mode);
}

/// Every color of the app, resolved from the palette and the mode. Widgets
/// read it with [EvolupColors.of] instead of hard-coding colors.
@immutable
class EvolupColors extends ThemeExtension<EvolupColors> {
  const EvolupColors({
    required this.brightness,
    required this.background,
    required this.haloPrimary,
    required this.haloSecondary,
    required this.haloOpacity,
    required this.dot,
    required this.textPrimary,
    required this.textSecondary,
    required this.glassFillTop,
    required this.glassFillBottom,
    required this.glassBorder,
    required this.fieldFill,
    required this.fieldBorder,
    required this.accent,
    required this.primaryButton,
    required this.primaryButtonText,
    required this.error,
    required this.success,
    required this.navBarTint,
    required this.navSelected,
    required this.chartPrimary,
    required this.chartSecondary,
    required this.chartGrid,
  });

  /// The sign-in identity, also used before the user's profile is known.
  static const brand = EvolupColors(
    brightness: Brightness.dark,
    background: EvolupBrand.background,
    haloPrimary: EvolupBrand.haloBlueViolet,
    haloSecondary: EvolupBrand.haloCyan,
    haloOpacity: 0.30,
    dot: Color(0x1FFFFFFF),
    textPrimary: EvolupBrand.textPrimary,
    textSecondary: EvolupBrand.textSecondary,
    glassFillTop: Color(0x17FFFFFF),
    glassFillBottom: Color(0x08FFFFFF),
    glassBorder: EvolupBrand.glassBorder,
    fieldFill: EvolupBrand.fieldFill,
    fieldBorder: Color(0x26FFFFFF),
    accent: EvolupBrand.focus,
    primaryButton: Color(0xFFEEF1F8),
    primaryButtonText: Color(0xFF0A0F1F),
    error: Color(0xFFFF8A8A),
    success: Color(0xFF7FE3C9),
    navBarTint: Color(0xB30A0E1C),
    navSelected: Color(0x268EA2FF),
    chartPrimary: EvolupBrand.focus,
    chartSecondary: Color(0xFF4FD1E6),
    chartGrid: Color(0x1FFFFFFF),
  );

  factory EvolupColors.resolve(AppAppearance appearance) {
    final dark = appearance.mode == AppThemeMode.dark;
    final p = _palettes[appearance.palette]!;
    final background = dark ? p.darkBackground : p.lightBackground;
    final accent = dark ? p.darkAccent : p.lightAccent;
    if (dark) {
      return brand.copyWith(
        background: background,
        haloPrimary: p.haloPrimary,
        haloSecondary: p.haloSecondary,
        haloOpacity: p.darkHaloOpacity,
        accent: accent,
        navBarTint: Color.alphaBlend(
          const Color(0x0DFFFFFF),
          background,
        ).withValues(alpha: 0.72),
        navSelected: accent.withValues(alpha: 0.16),
        chartPrimary: accent,
        chartSecondary: p.darkChartSecondary,
      );
    }
    return EvolupColors(
      brightness: Brightness.light,
      background: background,
      haloPrimary: p.haloPrimary,
      haloSecondary: p.haloSecondary,
      haloOpacity: 0.16,
      dot: const Color(0x1A0F172A),
      textPrimary: const Color(0xFF10131C),
      textSecondary: const Color(0xFF586072),
      glassFillTop: const Color(0xCCFFFFFF),
      glassFillBottom: const Color(0x99FFFFFF),
      glassBorder: const Color(0x1F0F172A),
      fieldFill: const Color(0x0A0F172A),
      fieldBorder: const Color(0x290F172A),
      accent: accent,
      primaryButton: const Color(0xFF10131C),
      primaryButtonText: const Color(0xFFF6F7FA),
      error: const Color(0xFFC62828),
      success: const Color(0xFF1B7F64),
      navBarTint: const Color(0xD9FFFFFF),
      navSelected: accent.withValues(alpha: 0.14),
      chartPrimary: accent,
      chartSecondary: p.lightChartSecondary,
      chartGrid: const Color(0x1F0F172A),
    );
  }

  static EvolupColors of(BuildContext context) =>
      Theme.of(context).extension<EvolupColors>() ?? brand;

  final Brightness brightness;
  final Color background;
  final Color haloPrimary;
  final Color haloSecondary;
  final double haloOpacity;
  final Color dot;
  final Color textPrimary;
  final Color textSecondary;
  final Color glassFillTop;
  final Color glassFillBottom;
  final Color glassBorder;
  final Color fieldFill;
  final Color fieldBorder;

  /// Palette color: focus rings, selected items, icons, first chart series.
  final Color accent;
  final Color primaryButton;
  final Color primaryButtonText;
  final Color error;
  final Color success;

  /// Tint under the navigation bar's glass, so its labels stay readable over
  /// any content scrolling behind it.
  final Color navBarTint;
  final Color navSelected;
  final Color chartPrimary;
  final Color chartSecondary;
  final Color chartGrid;

  bool get isDark => brightness == Brightness.dark;

  @override
  EvolupColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? haloPrimary,
    Color? haloSecondary,
    double? haloOpacity,
    Color? dot,
    Color? textPrimary,
    Color? textSecondary,
    Color? glassFillTop,
    Color? glassFillBottom,
    Color? glassBorder,
    Color? fieldFill,
    Color? fieldBorder,
    Color? accent,
    Color? primaryButton,
    Color? primaryButtonText,
    Color? error,
    Color? success,
    Color? navBarTint,
    Color? navSelected,
    Color? chartPrimary,
    Color? chartSecondary,
    Color? chartGrid,
  }) => EvolupColors(
    brightness: brightness ?? this.brightness,
    background: background ?? this.background,
    haloPrimary: haloPrimary ?? this.haloPrimary,
    haloSecondary: haloSecondary ?? this.haloSecondary,
    haloOpacity: haloOpacity ?? this.haloOpacity,
    dot: dot ?? this.dot,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    glassFillTop: glassFillTop ?? this.glassFillTop,
    glassFillBottom: glassFillBottom ?? this.glassFillBottom,
    glassBorder: glassBorder ?? this.glassBorder,
    fieldFill: fieldFill ?? this.fieldFill,
    fieldBorder: fieldBorder ?? this.fieldBorder,
    accent: accent ?? this.accent,
    primaryButton: primaryButton ?? this.primaryButton,
    primaryButtonText: primaryButtonText ?? this.primaryButtonText,
    error: error ?? this.error,
    success: success ?? this.success,
    navBarTint: navBarTint ?? this.navBarTint,
    navSelected: navSelected ?? this.navSelected,
    chartPrimary: chartPrimary ?? this.chartPrimary,
    chartSecondary: chartSecondary ?? this.chartSecondary,
    chartGrid: chartGrid ?? this.chartGrid,
  );

  @override
  EvolupColors lerp(EvolupColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return EvolupColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      haloPrimary: c(haloPrimary, other.haloPrimary),
      haloSecondary: c(haloSecondary, other.haloSecondary),
      haloOpacity: haloOpacity + (other.haloOpacity - haloOpacity) * t,
      dot: c(dot, other.dot),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      glassFillTop: c(glassFillTop, other.glassFillTop),
      glassFillBottom: c(glassFillBottom, other.glassFillBottom),
      glassBorder: c(glassBorder, other.glassBorder),
      fieldFill: c(fieldFill, other.fieldFill),
      fieldBorder: c(fieldBorder, other.fieldBorder),
      accent: c(accent, other.accent),
      primaryButton: c(primaryButton, other.primaryButton),
      primaryButtonText: c(primaryButtonText, other.primaryButtonText),
      error: c(error, other.error),
      success: c(success, other.success),
      navBarTint: c(navBarTint, other.navBarTint),
      navSelected: c(navSelected, other.navSelected),
      chartPrimary: c(chartPrimary, other.chartPrimary),
      chartSecondary: c(chartSecondary, other.chartSecondary),
      chartGrid: c(chartGrid, other.chartGrid),
    );
  }
}

class _PaletteSpec {
  const _PaletteSpec({
    required this.darkBackground,
    required this.lightBackground,
    required this.haloPrimary,
    required this.haloSecondary,
    required this.darkAccent,
    required this.lightAccent,
    required this.darkChartSecondary,
    required this.lightChartSecondary,
    this.darkHaloOpacity = 0.30,
  });

  final Color darkBackground;
  final Color lightBackground;
  final Color haloPrimary;
  final Color haloSecondary;
  final Color darkAccent;
  final Color lightAccent;
  final Color darkChartSecondary;
  final Color lightChartSecondary;
  final double darkHaloOpacity;
}

// Accent seeds of the palettes first planned for EVOLUP: gold #C99A3B,
// black & white #8B929C, blue #4F8FE8 (here the EVOLUP night blue), violet
// #9473E8.
const _palettes = <AppPalette, _PaletteSpec>{
  AppPalette.blue: _PaletteSpec(
    darkBackground: EvolupBrand.background,
    lightBackground: Color(0xFFF3F5FA),
    haloPrimary: EvolupBrand.haloBlueViolet,
    haloSecondary: EvolupBrand.haloCyan,
    darkAccent: EvolupBrand.focus,
    lightAccent: Color(0xFF3B50D2),
    darkChartSecondary: Color(0xFF4FD1E6),
    lightChartSecondary: Color(0xFF0E8FA6),
  ),
  AppPalette.violet: _PaletteSpec(
    darkBackground: Color(0xFF07050F),
    lightBackground: Color(0xFFF6F3FB),
    haloPrimary: Color(0xFF7C4DFF),
    haloSecondary: Color(0xFFD04DD8),
    darkAccent: Color(0xFFB9A2FF),
    lightAccent: Color(0xFF6A3FD6),
    darkChartSecondary: Color(0xFFE58BEA),
    lightChartSecondary: Color(0xFFA63CB0),
  ),
  AppPalette.gold: _PaletteSpec(
    darkBackground: Color(0xFF0A0805),
    lightBackground: Color(0xFFFAF7EF),
    haloPrimary: Color(0xFFC99A3B),
    haloSecondary: Color(0xFF8A5A1E),
    darkAccent: Color(0xFFE3B65A),
    lightAccent: Color(0xFF94650F),
    darkChartSecondary: Color(0xFFD9895A),
    lightChartSecondary: Color(0xFFA4552A),
    darkHaloOpacity: 0.24,
  ),
  AppPalette.blackWhite: _PaletteSpec(
    darkBackground: Color(0xFF050505),
    lightBackground: Color(0xFFF5F5F5),
    haloPrimary: Color(0xFF8B929C),
    haloSecondary: Color(0xFF5A5F66),
    darkAccent: Color(0xFFF0F0F0),
    lightAccent: Color(0xFF161616),
    darkChartSecondary: Color(0xFF9AA0A8),
    lightChartSecondary: Color(0xFF6B7078),
    darkHaloOpacity: 0.18,
  ),
};

ThemeData buildEvolupTheme([EvolupColors colors = EvolupColors.brand]) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: colors.brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.isDark ? colors.primaryButtonText : Colors.white,
        surface: colors.background,
        onSurface: colors.textPrimary,
        onSurfaceVariant: colors.textSecondary,
        error: colors.error,
        outline: colors.fieldBorder,
        outlineVariant: colors.glassBorder,
      );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  final typography = colors.isDark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final dialogSurface = colors.isDark
      ? Color.alphaBlend(const Color(0x14FFFFFF), colors.background)
      : Colors.white;
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    extensions: [colors],
    textTheme: typography.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    ),
    iconTheme: IconThemeData(color: colors.textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      titleSpacing: 20,
      titleTextStyle: typography.titleLarge?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.fieldFill,
      labelStyle: TextStyle(color: colors.textSecondary),
      floatingLabelStyle: TextStyle(color: colors.textPrimary),
      hintStyle: TextStyle(color: colors.textSecondary),
      prefixIconColor: colors.textSecondary,
      suffixIconColor: colors.textSecondary,
      border: border(colors.fieldBorder),
      enabledBorder: border(colors.fieldBorder),
      disabledBorder: border(colors.fieldBorder),
      focusedBorder: border(colors.accent, 1.5),
      errorBorder: border(colors.error),
      focusedErrorBorder: border(colors.error, 1.5),
      errorStyle: TextStyle(color: colors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primaryButton,
        foregroundColor: colors.primaryButtonText,
        disabledBackgroundColor: colors.primaryButton.withValues(alpha: 0.55),
        disabledForegroundColor: colors.primaryButtonText,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.glassBorder),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.fieldFill,
      selectedColor: colors.navSelected,
      side: BorderSide(color: colors.glassBorder),
      labelStyle: TextStyle(color: colors.textPrimary),
      secondaryLabelStyle: TextStyle(color: colors.textPrimary),
      checkmarkColor: colors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primaryButtonText
            : colors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.fieldFill,
      ),
      trackOutlineColor: WidgetStatePropertyAll(colors.fieldBorder),
    ),
    dividerTheme: DividerThemeData(color: colors.glassBorder, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dialogSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.glassBorder),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dialogSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.isDark
          ? const Color(0xFFEEF1F8)
          : const Color(0xFF10131C),
      contentTextStyle: TextStyle(
        color: colors.isDark ? const Color(0xFF0A0F1F) : Colors.white,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: dialogSurface,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primaryButtonText,
    ),
  );
}

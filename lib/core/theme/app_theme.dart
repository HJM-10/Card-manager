import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        surface: AppColors.background,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
      ),
    );
  }
}

/// Shorthand text styles so widgets don't repeat font settings.
abstract final class AppText {
  static TextStyle _base(double size, FontWeight weight, Color color) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.2,
      );

  static TextStyle title([Color c = AppColors.textPrimary]) =>
      _base(20, FontWeight.w700, c);
  static TextStyle heading([Color c = AppColors.textPrimary]) =>
      _base(15, FontWeight.w700, c);
  static TextStyle body([Color c = AppColors.textPrimary]) =>
      _base(14, FontWeight.w600, c);
  static TextStyle caption([Color c = AppColors.textSecondary]) =>
      _base(11.5, FontWeight.w500, c);
  static TextStyle tiny([Color c = AppColors.textSecondary]) =>
      _base(10, FontWeight.w500, c);
  static TextStyle balance([Color c = Colors.white]) =>
      _base(30, FontWeight.w700, c).copyWith(letterSpacing: -0.6);
  static TextStyle wordmark([Color c = AppColors.textPrimary]) =>
      _base(28, FontWeight.w800, c).copyWith(letterSpacing: -0.8);
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'wallet_style.dart';

abstract final class AppTheme {
  static ThemeData wallet(WalletStyle style, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final (background, surface) = switch ((style, dark)) {
      (WalletStyle.classic, false) => (AppColors.background, AppColors.surface),
      (WalletStyle.classic, true) => (
        const Color(0xFF141319),
        const Color(0xFF211E29),
      ),
      (WalletStyle.cobaltFold, false) => (
        const Color(0xFFEAF2FF),
        const Color(0xFFFBFDFF),
      ),
      (WalletStyle.cobaltFold, true) => (
        const Color(0xFF101B2C),
        const Color(0xFF19283F),
      ),
      (WalletStyle.figCarousel, false) => (
        const Color(0xFFF9EFF5),
        const Color(0xFFFFFAFD),
      ),
      (WalletStyle.figCarousel, true) => (
        const Color(0xFF261923),
        const Color(0xFF382432),
      ),
    };
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: style.bodyFont,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: style.accent,
        brightness: brightness,
        surface: surface,
        onSurface: switch ((style, dark)) {
          (WalletStyle.cobaltFold, false) => const Color(0xFF142C52),
          (WalletStyle.figCarousel, true) => const Color(0xFFFFF0F8),
          _ => null,
        },
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: style.displayFont,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: style.displayFont,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: style.displayFont,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: style.displayFont,
        ),
      ),
    );
  }

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF141319),
    fontFamily: 'PlusJakartaSans',
  );
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        surface: AppColors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
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
  static TextStyle _base(double size, FontWeight weight, Color? color) =>
      TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.2,
      );

  static TextStyle title([Color? c]) => _base(20, FontWeight.w700, c);
  static TextStyle heading([Color? c]) => _base(15, FontWeight.w700, c);
  static TextStyle body([Color? c]) => _base(14, FontWeight.w600, c);
  static TextStyle caption([Color? c]) => _base(11.5, FontWeight.w500, c);
  static TextStyle tiny([Color? c]) => _base(10, FontWeight.w500, c);
  static TextStyle balance([Color c = Colors.white]) =>
      _base(30, FontWeight.w700, c).copyWith(letterSpacing: -0.6);
  static TextStyle wordmark([Color c = AppColors.textPrimary]) =>
      _base(28, FontWeight.w800, c).copyWith(letterSpacing: -0.8);
}

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:system_theme/system_theme.dart';

import '../platform_info.dart';

/// Адаптивная тема приложения.
///
/// Для Windows: использует [fluent.FluentThemeData] с Segoe UI Variable / Segoe UI.
/// Для macOS: использует Material с .SF Pro (San Francisco) шрифтами.
/// Для Linux: использует Material 3 с Roboto / Cantarell.
class AppTheme {
  AppTheme._();

  // ─── Шрифты по платформам ───

  static String get _fontFamily {
    switch (PlatformInfo.current) {
      case AppPlatformType.windows:
        return 'Segoe UI Variable';
      case AppPlatformType.macos:
        return '.AppleSystemUIFont';
      case AppPlatformType.linux:
        return 'Cantarell';
    }
  }

  static String get _monoFontFamily {
    switch (PlatformInfo.current) {
      case AppPlatformType.windows:
        return 'Cascadia Code';
      case AppPlatformType.macos:
        return 'SF Mono';
      case AppPlatformType.linux:
        return 'Fira Code';
    }
  }

  // ─── Цвета ───

  /// Акцентный цвет из системных настроек (Windows / macOS)
  /// или fallback на фирменный синий.
  static Color get accentColor {
    try {
      return SystemTheme.accentColor.accent;
    } catch (_) {
      return const Color(0xFF3B82F6);
    }
  }

  // ─── Material Theme (для Linux / macOS / fallback) ───

  static ThemeData get materialTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      typography: Typography.material2021(
        platform: TargetPlatform.linux,
      ),
    );
  }

  static ThemeData get materialDarkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      brightness: Brightness.dark,
      typography: Typography.material2021(
        platform: TargetPlatform.linux,
      ),
    );
  }

  // ─── Fluent Theme (для Windows) ───

  static fluent.FluentThemeData get fluentTheme {
    return fluent.FluentThemeData(
      brightness: Brightness.light,
      accentColor: _toFluentAccentColor(accentColor),
      fontFamily: _fontFamily,
      visualDensity: VisualDensity.standard,
    );
  }

  static fluent.FluentThemeData get fluentDarkTheme {
    return fluent.FluentThemeData(
      brightness: Brightness.dark,
      accentColor: _toFluentAccentColor(accentColor),
      fontFamily: _fontFamily,
      visualDensity: VisualDensity.standard,
    );
  }

  /// Конвертирует [Color] в [fluent.AccentColor] для fluent_ui.
  static fluent.AccentColor _toFluentAccentColor(Color color) {
    return fluent.AccentColor.swatch({
      'darkest': _darken(color, 0.3),
      'darker': _darken(color, 0.2),
      'dark': _darken(color, 0.1),
      'normal': color,
      'light': _lighten(color, 0.1),
      'lighter': _lighten(color, 0.2),
      'lightest': _lighten(color, 0.3),
    });
  }

  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Шрифт для моноширинного текста (лог, код).
  static String get monoFontFamily => _monoFontFamily;
}

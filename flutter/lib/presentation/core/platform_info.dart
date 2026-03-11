import 'dart:io';

/// Определяет текущую платформу для выбора UI-фреймворка.
enum AppPlatformType {
  windows,
  macos,
  linux,
}

/// Синглтон для определения текущей платформы.
///
/// Используется вместо прямых вызовов [Platform.isWindows] и т.д.,
/// чтобы можно было централизованно переопределить платформу для тестов.
class PlatformInfo {
  PlatformInfo._();

  static AppPlatformType? _override;

  /// Текущая платформа. Определяется автоматически или через [overrideForTest].
  static AppPlatformType get current {
    if (_override != null) return _override!;
    if (Platform.isWindows) return AppPlatformType.windows;
    if (Platform.isMacOS) return AppPlatformType.macos;
    return AppPlatformType.linux;
  }

  static bool get isWindows => current == AppPlatformType.windows;
  static bool get isMacOS => current == AppPlatformType.macos;
  static bool get isLinux => current == AppPlatformType.linux;

  /// Переопределить платформу для тестов.
  static void overrideForTest(AppPlatformType platform) {
    _override = platform;
  }

  /// Сбросить переопределение.
  static void resetOverride() {
    _override = null;
  }
}

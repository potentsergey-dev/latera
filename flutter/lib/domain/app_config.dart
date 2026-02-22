/// Конфигурация приложения.
///
/// Immutable-сущность, представляющая настройки приложения.
/// Используется для хранения пользовательских предпочтений
/// и настроек окружения.
class AppConfig {
  /// Путь к наблюдаемой директории (null = дефолт Desktop/Latera).
  final String? watchPath;

  /// Интервал проверки изменений файлов (в миллисекундах).
  final int watchIntervalMs;

  /// Включить уведомления о новых файлах.
  final bool notificationsEnabled;

  /// Включить логирование.
  final bool loggingEnabled;

  /// Уровень логирования (debug, info, warning, error).
  final String logLevel;

  /// Тема приложения (light, dark, system).
  final String theme;

  /// Язык интерфейса (null = системный).
  final String? language;

  const AppConfig({
    this.watchPath,
    this.watchIntervalMs = 300,
    this.notificationsEnabled = true,
    this.loggingEnabled = true,
    this.logLevel = 'info',
    this.theme = 'system',
    this.language,
  });

  /// Конфигурация по умолчанию.
  static const AppConfig defaultConfig = AppConfig();

  /// Создаёт копию с обновлёнными полями.
  AppConfig copyWith({
    String? watchPath,
    int? watchIntervalMs,
    bool? notificationsEnabled,
    bool? loggingEnabled,
    String? logLevel,
    String? theme,
    String? language,
  }) {
    return AppConfig(
      watchPath: watchPath ?? this.watchPath,
      watchIntervalMs: watchIntervalMs ?? this.watchIntervalMs,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      logLevel: logLevel ?? this.logLevel,
      theme: theme ?? this.theme,
      language: language ?? this.language,
    );
  }

  @override
  String toString() {
    return 'AppConfig(watchPath: $watchPath, notificationsEnabled: $notificationsEnabled, theme: $theme)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppConfig &&
        other.watchPath == watchPath &&
        other.watchIntervalMs == watchIntervalMs &&
        other.notificationsEnabled == notificationsEnabled &&
        other.loggingEnabled == loggingEnabled &&
        other.logLevel == logLevel &&
        other.theme == theme &&
        other.language == language;
  }

  @override
  int get hashCode {
    return Object.hash(
      watchPath,
      watchIntervalMs,
      notificationsEnabled,
      loggingEnabled,
      logLevel,
      theme,
      language,
    );
  }
}

/// Контракт на сервис конфигурации.
///
/// Domain слой не зависит от реализации хранения
/// (shared_preferences, JSON файл, реестр Windows и т.д.).
///
/// Реализация будет в infrastructure слое.
abstract interface class ConfigService {
  /// Текущая конфигурация.
  AppConfig get currentConfig;

  /// Stream изменений конфигурации.
  Stream<AppConfig> get configChanges;

  /// Загрузить конфигурацию из хранилища.
  Future<AppConfig> load();

  /// Сохранить конфигурацию в хранилище.
  Future<void> save(AppConfig config);

  /// Сбросить конфигурацию к значениям по умолчанию.
  Future<void> reset();

  /// Обновить отдельное поле конфигурации.
  Future<void> updateValue({
    String? watchPath,
    int? watchIntervalMs,
    bool? notificationsEnabled,
    bool? loggingEnabled,
    String? logLevel,
    String? theme,
    String? language,
  });
}

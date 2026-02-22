/// Идентификаторы функций приложения.
///
/// Централизованный список всех функций, которые могут быть
/// ограничены лицензией (Free vs Pro).
///
/// Используется для проверки доступности функций через [LicenseService].
abstract final class FeatureId {
  // === Индексация и поиск ===

  /// Базовый поиск по имени файла.
  static const String basicSearch = 'basic_search';

  /// Поиск по содержимому файлов (FTS).
  static const String contentSearch = 'content_search';

  /// Расширенный поиск с фильтрами.
  static const String advancedSearch = 'advanced_search';

  /// Семантический поиск (эмбеддинги).
  static const String semanticSearch = 'semantic_search';

  // === Индексация ===

  /// Базовая индексация (до N файлов).
  static const String basicIndexing = 'basic_indexing';

  /// Безлимитная индексация.
  static const String unlimitedIndexing = 'unlimited_indexing';

  /// Индексация содержимого файлов.
  static const String contentIndexing = 'content_indexing';

  // === Уведомления ===

  /// Базовые уведомления о новых файлах.
  static const String basicNotifications = 'basic_notifications';

  /// Настраиваемые уведомления.
  static const String customNotifications = 'custom_notifications';

  // === UI и настройки ===

  /// Тёмная тема.
  static const String darkTheme = 'dark_theme';

  /// Кастомизация UI.
  static const String uiCustomization = 'ui_customization';

  // === Экспорт и интеграции ===

  /// Экспорт результатов поиска.
  static const String exportResults = 'export_results';

  /// Интеграция с внешними инструментами.
  static const String externalIntegrations = 'external_integrations';
}

/// Конфигурация ограничений Free версии.
///
/// Определяет лимиты для бесплатной версии приложения.
/// Используется для проверки доступности функций.
class FreeTierLimits {
  /// Максимальное количество индексируемых файлов.
  static const int maxIndexedFiles = 100;

  /// Максимальный размер файла для индексации (в байтах, 10 MB).
  static const int maxFileSizeBytes = 10 * 1024 * 1024;

  /// Максимальное количество результатов поиска.
  static const int maxSearchResults = 20;

  /// Максимальное количество наблюдаемых директорий.
  static const int maxWatchedDirectories = 1;

  /// Поддерживаемые форматы файлов (базовый набор).
  static const Set<String> supportedFileFormats = {
    'txt',
    'md',
    'pdf',
    'doc',
    'docx',
  };
}

/// Конфигурация возможностей Pro версии.
///
/// Определяет расширенные возможности Pro версии.
class ProTierFeatures {
  /// Безлимитное количество индексируемых файлов.
  static const bool unlimitedFiles = true;

  /// Максимальный размер файла для индексации (в байтах, 100 MB).
  static const int maxFileSizeBytes = 100 * 1024 * 1024;

  /// Безлимитное количество результатов поиска.
  static const bool unlimitedSearchResults = true;

  /// Максимальное количество наблюдаемых директорий.
  static const int maxWatchedDirectories = 10;

  /// Расширенный набор форматов файлов.
  static const Set<String> supportedFileFormats = {
    'txt',
    'md',
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'rtf',
    'odt',
    'html',
    'json',
    'xml',
    'csv',
  };

  /// Семантический поиск.
  static const bool semanticSearch = true;

  /// Приоритетная поддержка.
  static const bool prioritySupport = true;
}

/// Контракт на сервис фиче-флагов.
///
/// Предоставляет информацию о доступности функций
/// на основе текущей лицензии и конфигурации.
///
/// Реализация будет в infrastructure слое.
abstract interface class FeatureFlags {
  /// Проверить, доступна ли функция.
  ///
  /// [featureId] — идентификатор функции (см. [FeatureId]).
  bool isAvailable(String featureId);

  /// Получить лимит для функции.
  ///
  /// [limitId] — идентификатор лимита.
  /// Возвращает null, если лимит не ограничен.
  int? getLimit(String limitId);

  /// Stream изменений доступности функций.
  ///
  /// Срабатывает при изменении лицензии или конфигурации.
  Stream<Set<String>> get availableFeaturesChanges;

  /// Получить множество всех доступных функций.
  Set<String> get availableFeatures;
}

/// Идентификаторы лимитов.
abstract final class LimitId {
  /// Максимальное количество индексируемых файлов.
  static const String maxIndexedFiles = 'max_indexed_files';

  /// Максимальный размер файла.
  static const String maxFileSize = 'max_file_size';

  /// Максимальное количество результатов поиска.
  static const String maxSearchResults = 'max_search_results';

  /// Максимальное количество наблюдаемых директорий.
  static const String maxWatchedDirectories = 'max_watched_directories';
}

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

  // === Производительность и контент ===

  /// Режим экономии ресурсов.
  ///
  /// Когда включён, тяжёлые операции (OCR, транскрибация, эмбеддинги,
  /// RAG, автосаммари, автотеги) отключаются, а лимиты ужесточаются.
  /// Пользователь может включить этот режим на слабом компьютере.
  final bool resourceSaverEnabled;

  /// Извлечение текста из офисных документов (PDF, DOCX и др.).
  final bool enableOfficeDocs;

  /// Оптическое распознавание символов (OCR) для изображений и скан-PDF.
  final bool enableOcr;

  /// Транскрибация аудио/видео (Whisper).
  final bool enableTranscription;

  /// Вычисление эмбеддингов для семантического поиска.
  final bool enableEmbeddings;

  /// Поиск похожих файлов по семантическому сходству.
  final bool enableSemanticSimilarity;

  /// Локальный RAG — «Спроси свою папку».
  final bool enableRag;

  /// Автоматическое создание саммари документов.
  final bool enableAutoSummary;

  /// Автоматическое присвоение тегов документам.
  final bool enableAutoTags;

  // === Лимиты ресурсов ===

  /// Максимальное количество параллельных задач обогащения контента.
  final int maxConcurrentJobs;

  /// Максимальный размер файла (МБ) для обработки контента.
  final int maxFileSizeMbForEnrichment;

  /// Максимальная длительность медиа (минуты) для транскрибации.
  final int maxMediaMinutes;

  /// Максимальное количество страниц PDF для обработки.
  final int maxPagesPerPdf;

  const AppConfig({
    this.watchPath,
    this.watchIntervalMs = 300,
    this.notificationsEnabled = true,
    this.loggingEnabled = true,
    this.logLevel = 'info',
    this.theme = 'system',
    this.language,
    // Производительность и контент
    this.resourceSaverEnabled = false,
    this.enableOfficeDocs = true,
    this.enableOcr = false,
    this.enableTranscription = false,
    this.enableEmbeddings = false,
    this.enableSemanticSimilarity = false,
    this.enableRag = false,
    this.enableAutoSummary = false,
    this.enableAutoTags = false,
    // Лимиты
    this.maxConcurrentJobs = 2,
    this.maxFileSizeMbForEnrichment = 50,
    this.maxMediaMinutes = 60,
    this.maxPagesPerPdf = 100,
  });

  /// Конфигурация по умолчанию.
  static const AppConfig defaultConfig = AppConfig();

  /// Пресет «Экономия ресурсов» — лимиты для слабых ПК.
  static const AppConfig resourceSaverPreset = AppConfig(
    resourceSaverEnabled: true,
    enableOfficeDocs: true,
    enableOcr: false,
    enableTranscription: false,
    enableEmbeddings: false,
    enableSemanticSimilarity: false,
    enableRag: false,
    enableAutoSummary: false,
    enableAutoTags: false,
    maxConcurrentJobs: 1,
    maxFileSizeMbForEnrichment: 10,
    maxMediaMinutes: 0,
    maxPagesPerPdf: 30,
  );

  /// Проверяет, включена ли конкретная контент-функция
  /// с учётом режима экономии ресурсов.
  ///
  /// Если [resourceSaverEnabled] == true, тяжёлые функции
  /// (OCR, транскрибация, эмбеддинги, RAG, автосаммари, автотеги)
  /// считаются выключенными, даже если их флаг == true.
  /// Извлечение текста из офисных документов остаётся доступным
  /// в режиме экономии, но с уменьшенными лимитами.
  bool isFeatureEffectivelyEnabled(ContentFeature feature) {
    if (resourceSaverEnabled) {
      return switch (feature) {
        ContentFeature.officeDocs => enableOfficeDocs,
        // Тяжёлые функции отключаются в режиме экономии
        ContentFeature.ocr => false,
        ContentFeature.transcription => false,
        ContentFeature.embeddings => false,
        ContentFeature.semanticSimilarity => false,
        ContentFeature.rag => false,
        ContentFeature.autoSummary => false,
        ContentFeature.autoTags => false,
      };
    }
    return switch (feature) {
      ContentFeature.officeDocs => enableOfficeDocs,
      ContentFeature.ocr => enableOcr,
      ContentFeature.transcription => enableTranscription,
      ContentFeature.embeddings => enableEmbeddings,
      ContentFeature.semanticSimilarity => enableSemanticSimilarity && enableEmbeddings,
      ContentFeature.rag => enableRag,
      ContentFeature.autoSummary => enableAutoSummary,
      ContentFeature.autoTags => enableAutoTags,
    };
  }

  /// Возвращает эффективные лимиты с учётом режима экономии ресурсов.
  ContentLimits get effectiveLimits {
    if (resourceSaverEnabled) {
      return ContentLimits(
        maxConcurrentJobs: 1,
        maxFileSizeMb: 10,
        maxMediaMinutes: 0,
        maxPagesPerPdf: 30,
      );
    }
    return ContentLimits(
      maxConcurrentJobs: maxConcurrentJobs,
      maxFileSizeMb: maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf,
    );
  }

  /// Создаёт копию с обновлёнными полями.
  AppConfig copyWith({
    String? watchPath,
    int? watchIntervalMs,
    bool? notificationsEnabled,
    bool? loggingEnabled,
    String? logLevel,
    String? theme,
    String? language,
    bool? resourceSaverEnabled,
    bool? enableOfficeDocs,
    bool? enableOcr,
    bool? enableTranscription,
    bool? enableEmbeddings,
    bool? enableSemanticSimilarity,
    bool? enableRag,
    bool? enableAutoSummary,
    bool? enableAutoTags,
    int? maxConcurrentJobs,
    int? maxFileSizeMbForEnrichment,
    int? maxMediaMinutes,
    int? maxPagesPerPdf,
  }) {
    return AppConfig(
      watchPath: watchPath ?? this.watchPath,
      watchIntervalMs: watchIntervalMs ?? this.watchIntervalMs,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      logLevel: logLevel ?? this.logLevel,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      resourceSaverEnabled: resourceSaverEnabled ?? this.resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs ?? this.enableOfficeDocs,
      enableOcr: enableOcr ?? this.enableOcr,
      enableTranscription: enableTranscription ?? this.enableTranscription,
      enableEmbeddings: enableEmbeddings ?? this.enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity ?? this.enableSemanticSimilarity,
      enableRag: enableRag ?? this.enableRag,
      enableAutoSummary: enableAutoSummary ?? this.enableAutoSummary,
      enableAutoTags: enableAutoTags ?? this.enableAutoTags,
      maxConcurrentJobs: maxConcurrentJobs ?? this.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment ?? this.maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes ?? this.maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf ?? this.maxPagesPerPdf,
    );
  }

  @override
  String toString() {
    return 'AppConfig(watchPath: $watchPath, notificationsEnabled: $notificationsEnabled, '
        'theme: $theme, resourceSaver: $resourceSaverEnabled)';
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
        other.language == language &&
        other.resourceSaverEnabled == resourceSaverEnabled &&
        other.enableOfficeDocs == enableOfficeDocs &&
        other.enableOcr == enableOcr &&
        other.enableTranscription == enableTranscription &&
        other.enableEmbeddings == enableEmbeddings &&
        other.enableSemanticSimilarity == enableSemanticSimilarity &&
        other.enableRag == enableRag &&
        other.enableAutoSummary == enableAutoSummary &&
        other.enableAutoTags == enableAutoTags &&
        other.maxConcurrentJobs == maxConcurrentJobs &&
        other.maxFileSizeMbForEnrichment == maxFileSizeMbForEnrichment &&
        other.maxMediaMinutes == maxMediaMinutes &&
        other.maxPagesPerPdf == maxPagesPerPdf;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      watchPath,
      watchIntervalMs,
      notificationsEnabled,
      loggingEnabled,
      logLevel,
      theme,
      language,
      resourceSaverEnabled,
      enableOfficeDocs,
      enableOcr,
      enableTranscription,
      enableEmbeddings,
      enableSemanticSimilarity,
      enableRag,
      enableAutoSummary,
      enableAutoTags,
      maxConcurrentJobs,
      maxFileSizeMbForEnrichment,
      maxMediaMinutes,
      maxPagesPerPdf,
    ]);
  }
}

/// Идентификаторы контент-функций для проверки через
/// [AppConfig.isFeatureEffectivelyEnabled].
enum ContentFeature {
  /// Извлечение текста из PDF/DOCX.
  officeDocs,

  /// OCR — распознавание текста на изображениях.
  ocr,

  /// Транскрибация аудио/видео.
  transcription,

  /// Эмбеддинги для семантического поиска.
  embeddings,

  /// Поиск похожих файлов по семантическому сходству.
  semanticSimilarity,

  /// Локальный RAG («Спроси свою папку»).
  rag,

  /// Автоматические саммари.
  autoSummary,

  /// Автоматические теги.
  autoTags,
}

/// Эффективные лимиты ресурсов с учётом режима экономии.
class ContentLimits {
  final int maxConcurrentJobs;
  final int maxFileSizeMb;
  final int maxMediaMinutes;
  final int maxPagesPerPdf;

  const ContentLimits({
    required this.maxConcurrentJobs,
    required this.maxFileSizeMb,
    required this.maxMediaMinutes,
    required this.maxPagesPerPdf,
  });
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
  /// 
  /// Для очистки nullable полей (watchPath, language) используйте
  /// соответствующие флаги clearWatchPath и clearLanguage.
  Future<void> updateValue({
    String? watchPath,
    int? watchIntervalMs,
    bool? notificationsEnabled,
    bool? loggingEnabled,
    String? logLevel,
    String? theme,
    String? language,
    bool clearWatchPath = false,
    bool clearLanguage = false,
    // Производительность и контент
    bool? resourceSaverEnabled,
    bool? enableOfficeDocs,
    bool? enableOcr,
    bool? enableTranscription,
    bool? enableEmbeddings,
    bool? enableSemanticSimilarity,
    bool? enableRag,
    bool? enableAutoSummary,
    bool? enableAutoTags,
    // Лимиты
    int? maxConcurrentJobs,
    int? maxFileSizeMbForEnrichment,
    int? maxMediaMinutes,
    int? maxPagesPerPdf,
  });

  // === Onboarding ===

  /// Проверяет, пройден ли онбординг.
  bool get isOnboardingCompleted;

  /// Отмечает онбординг как пройденный.
  Future<void> completeOnboarding();

  /// Сбрасывает флаг онбординга (для тестирования).
  Future<void> resetOnboarding();
}

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/app_config.dart';

/// Ключи для хранения настроек в SharedPreferences.
class _ConfigKeys {
  static const String watchPath = 'watch_path';
  static const String watchIntervalMs = 'watch_interval_ms';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String loggingEnabled = 'logging_enabled';
  static const String logLevel = 'log_level';
  static const String theme = 'theme';
  static const String language = 'language';
  static const String onboardingCompleted = 'onboarding_completed';

  // === Производительность и контент ===
  static const String resourceSaverEnabled = 'resource_saver_enabled';
  static const String enableOfficeDocs = 'enable_office_docs';
  static const String enableOcr = 'enable_ocr';
  static const String enableTranscription = 'enable_transcription';
  static const String enableEmbeddings = 'enable_embeddings';
  static const String enableSemanticSimilarity = 'enable_semantic_similarity';
  static const String enableRag = 'enable_rag';
  static const String enableAutoSummary = 'enable_auto_summary';
  static const String enableAutoTags = 'enable_auto_tags';

  // === Лимиты ресурсов ===
  static const String maxConcurrentJobs = 'max_concurrent_jobs';
  static const String maxFileSizeMbForEnrichment = 'max_file_size_mb_for_enrichment';
  static const String maxMediaMinutes = 'max_media_minutes';
  static const String maxPagesPerPdf = 'max_pages_per_pdf';

  // Prevent instantiation
  _ConfigKeys._();
}

/// Реализация [ConfigService] на базе SharedPreferences.
///
/// Обеспечивает персистентное хранение настроек приложения.
/// Все операции асинхронны и безопасны для многопоточного доступа.
class SharedPreferencesConfigService implements ConfigService {
  final Logger _logger;
  SharedPreferences? _prefs;
  AppConfig _currentConfig = AppConfig.defaultConfig;
  final StreamController<AppConfig> _configController =
      StreamController<AppConfig>.broadcast();

  bool _isInitialized = false;

  SharedPreferencesConfigService({required Logger logger}) : _logger = logger;

  /// Инициализирует сервис (загружает SharedPreferences).
  ///
  /// Должен быть вызван до первого использования.
  /// Безопасен для многократного вызова.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.d('SharedPreferencesConfigService: initializing');
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
    _logger.d('SharedPreferencesConfigService: initialized');
  }

  void _ensureInitialized() {
    if (!_isInitialized || _prefs == null) {
      throw StateError(
        'SharedPreferencesConfigService not initialized. '
        'Call initialize() before using.',
      );
    }
  }

  @override
  AppConfig get currentConfig => _currentConfig;

  @override
  Stream<AppConfig> get configChanges => _configController.stream;

  // === Onboarding ===

  @override
  bool get isOnboardingCompleted {
    _ensureInitialized();
    return _prefs!.getBool(_ConfigKeys.onboardingCompleted) ?? false;
  }

  @override
  Future<void> completeOnboarding() async {
    _ensureInitialized();
    await _prefs!.setBool(_ConfigKeys.onboardingCompleted, true);
    _logger.i('Onboarding completed');
  }

  @override
  Future<void> resetOnboarding() async {
    _ensureInitialized();
    await _prefs!.setBool(_ConfigKeys.onboardingCompleted, false);
    _logger.i('Onboarding reset');
  }

  @override
  Future<AppConfig> load() async {
    _ensureInitialized();
    _logger.d('SharedPreferencesConfigService: load');

    final prefs = _prefs!;

    final watchPath = prefs.getString(_ConfigKeys.watchPath);
    final watchIntervalMs = prefs.getInt(_ConfigKeys.watchIntervalMs);
    final notificationsEnabled = prefs.getBool(_ConfigKeys.notificationsEnabled);
    final loggingEnabled = prefs.getBool(_ConfigKeys.loggingEnabled);
    final logLevel = prefs.getString(_ConfigKeys.logLevel);
    final theme = prefs.getString(_ConfigKeys.theme);
    final language = prefs.getString(_ConfigKeys.language);

    // Производительность и контент
    final resourceSaverEnabled = prefs.getBool(_ConfigKeys.resourceSaverEnabled);
    final enableOfficeDocs = prefs.getBool(_ConfigKeys.enableOfficeDocs);
    final enableOcr = prefs.getBool(_ConfigKeys.enableOcr);
    final enableTranscription = prefs.getBool(_ConfigKeys.enableTranscription);
    final enableEmbeddings = prefs.getBool(_ConfigKeys.enableEmbeddings);
    final enableSemanticSimilarity = prefs.getBool(_ConfigKeys.enableSemanticSimilarity);
    final enableRag = prefs.getBool(_ConfigKeys.enableRag);
    final enableAutoSummary = prefs.getBool(_ConfigKeys.enableAutoSummary);
    final enableAutoTags = prefs.getBool(_ConfigKeys.enableAutoTags);

    // Лимиты
    final maxConcurrentJobs = prefs.getInt(_ConfigKeys.maxConcurrentJobs);
    final maxFileSizeMbForEnrichment = prefs.getInt(_ConfigKeys.maxFileSizeMbForEnrichment);
    final maxMediaMinutes = prefs.getInt(_ConfigKeys.maxMediaMinutes);
    final maxPagesPerPdf = prefs.getInt(_ConfigKeys.maxPagesPerPdf);

    _currentConfig = AppConfig(
      watchPath: watchPath,
      watchIntervalMs: watchIntervalMs ?? AppConfig.defaultConfig.watchIntervalMs,
      notificationsEnabled: notificationsEnabled ?? AppConfig.defaultConfig.notificationsEnabled,
      loggingEnabled: loggingEnabled ?? AppConfig.defaultConfig.loggingEnabled,
      logLevel: logLevel ?? AppConfig.defaultConfig.logLevel,
      theme: theme ?? AppConfig.defaultConfig.theme,
      language: language,
      // Производительность и контент
      resourceSaverEnabled: resourceSaverEnabled ?? AppConfig.defaultConfig.resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs ?? AppConfig.defaultConfig.enableOfficeDocs,
      enableOcr: enableOcr ?? AppConfig.defaultConfig.enableOcr,
      enableTranscription: enableTranscription ?? AppConfig.defaultConfig.enableTranscription,
      enableEmbeddings: enableEmbeddings ?? AppConfig.defaultConfig.enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity ?? AppConfig.defaultConfig.enableSemanticSimilarity,
      enableRag: enableRag ?? AppConfig.defaultConfig.enableRag,
      enableAutoSummary: enableAutoSummary ?? AppConfig.defaultConfig.enableAutoSummary,
      enableAutoTags: enableAutoTags ?? AppConfig.defaultConfig.enableAutoTags,
      // Лимиты
      maxConcurrentJobs: maxConcurrentJobs ?? AppConfig.defaultConfig.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment ?? AppConfig.defaultConfig.maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes ?? AppConfig.defaultConfig.maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf ?? AppConfig.defaultConfig.maxPagesPerPdf,
    );

    _logger.d('SharedPreferencesConfigService: loaded config: $_currentConfig');
    return _currentConfig;
  }

  @override
  Future<void> save(AppConfig config) async {
    _ensureInitialized();
    _logger.d('SharedPreferencesConfigService: save');

    final prefs = _prefs!;

    // Сохраняем все поля
    if (config.watchPath != null) {
      await prefs.setString(_ConfigKeys.watchPath, config.watchPath!);
    } else {
      await prefs.remove(_ConfigKeys.watchPath);
    }

    await prefs.setInt(_ConfigKeys.watchIntervalMs, config.watchIntervalMs);
    await prefs.setBool(_ConfigKeys.notificationsEnabled, config.notificationsEnabled);
    await prefs.setBool(_ConfigKeys.loggingEnabled, config.loggingEnabled);
    await prefs.setString(_ConfigKeys.logLevel, config.logLevel);
    await prefs.setString(_ConfigKeys.theme, config.theme);

    if (config.language != null) {
      await prefs.setString(_ConfigKeys.language, config.language!);
    } else {
      await prefs.remove(_ConfigKeys.language);
    }

    // Производительность и контент
    await prefs.setBool(_ConfigKeys.resourceSaverEnabled, config.resourceSaverEnabled);
    await prefs.setBool(_ConfigKeys.enableOfficeDocs, config.enableOfficeDocs);
    await prefs.setBool(_ConfigKeys.enableOcr, config.enableOcr);
    await prefs.setBool(_ConfigKeys.enableTranscription, config.enableTranscription);
    await prefs.setBool(_ConfigKeys.enableEmbeddings, config.enableEmbeddings);
    await prefs.setBool(_ConfigKeys.enableSemanticSimilarity, config.enableSemanticSimilarity);
    await prefs.setBool(_ConfigKeys.enableRag, config.enableRag);
    await prefs.setBool(_ConfigKeys.enableAutoSummary, config.enableAutoSummary);
    await prefs.setBool(_ConfigKeys.enableAutoTags, config.enableAutoTags);

    // Лимиты
    await prefs.setInt(_ConfigKeys.maxConcurrentJobs, config.maxConcurrentJobs);
    await prefs.setInt(_ConfigKeys.maxFileSizeMbForEnrichment, config.maxFileSizeMbForEnrichment);
    await prefs.setInt(_ConfigKeys.maxMediaMinutes, config.maxMediaMinutes);
    await prefs.setInt(_ConfigKeys.maxPagesPerPdf, config.maxPagesPerPdf);

    _currentConfig = config;
    _configController.add(_currentConfig);
    _logger.i('SharedPreferencesConfigService: config saved');
  }

  @override
  Future<void> reset() async {
    _ensureInitialized();
    _logger.d('SharedPreferencesConfigService: reset');

    final prefs = _prefs!;

    // Удаляем все ключи кроме onboarding
    await prefs.remove(_ConfigKeys.watchPath);
    await prefs.remove(_ConfigKeys.watchIntervalMs);
    await prefs.remove(_ConfigKeys.notificationsEnabled);
    await prefs.remove(_ConfigKeys.loggingEnabled);
    await prefs.remove(_ConfigKeys.logLevel);
    await prefs.remove(_ConfigKeys.theme);
    await prefs.remove(_ConfigKeys.language);

    // Производительность и контент
    await prefs.remove(_ConfigKeys.resourceSaverEnabled);
    await prefs.remove(_ConfigKeys.enableOfficeDocs);
    await prefs.remove(_ConfigKeys.enableOcr);
    await prefs.remove(_ConfigKeys.enableTranscription);
    await prefs.remove(_ConfigKeys.enableEmbeddings);
    await prefs.remove(_ConfigKeys.enableSemanticSimilarity);
    await prefs.remove(_ConfigKeys.enableRag);
    await prefs.remove(_ConfigKeys.enableAutoSummary);
    await prefs.remove(_ConfigKeys.enableAutoTags);
    await prefs.remove(_ConfigKeys.maxConcurrentJobs);
    await prefs.remove(_ConfigKeys.maxFileSizeMbForEnrichment);
    await prefs.remove(_ConfigKeys.maxMediaMinutes);
    await prefs.remove(_ConfigKeys.maxPagesPerPdf);

    _currentConfig = AppConfig.defaultConfig;
    _configController.add(_currentConfig);
    _logger.i('SharedPreferencesConfigService: config reset to defaults');
  }

  @override
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
  }) async {
    _ensureInitialized();
    _logger.d('SharedPreferencesConfigService: updateValue');

    final prefs = _prefs!;

    // Обрабатываем watchPath: устанавливаем, удаляем или оставляем без изменений
    if (clearWatchPath) {
      await prefs.remove(_ConfigKeys.watchPath);
    } else if (watchPath != null) {
      await prefs.setString(_ConfigKeys.watchPath, watchPath);
    }

    if (watchIntervalMs != null) {
      await prefs.setInt(_ConfigKeys.watchIntervalMs, watchIntervalMs);
    }

    if (notificationsEnabled != null) {
      await prefs.setBool(_ConfigKeys.notificationsEnabled, notificationsEnabled);
    }

    if (loggingEnabled != null) {
      await prefs.setBool(_ConfigKeys.loggingEnabled, loggingEnabled);
    }

    if (logLevel != null) {
      await prefs.setString(_ConfigKeys.logLevel, logLevel);
    }

    if (theme != null) {
      await prefs.setString(_ConfigKeys.theme, theme);
    }

    // Обрабатываем language: устанавливаем, удаляем или оставляем без изменений
    if (clearLanguage) {
      await prefs.remove(_ConfigKeys.language);
    } else if (language != null) {
      await prefs.setString(_ConfigKeys.language, language);
    }

    // Производительность и контент
    if (resourceSaverEnabled != null) {
      await prefs.setBool(_ConfigKeys.resourceSaverEnabled, resourceSaverEnabled);
    }
    if (enableOfficeDocs != null) {
      await prefs.setBool(_ConfigKeys.enableOfficeDocs, enableOfficeDocs);
    }
    if (enableOcr != null) {
      await prefs.setBool(_ConfigKeys.enableOcr, enableOcr);
    }
    if (enableTranscription != null) {
      await prefs.setBool(_ConfigKeys.enableTranscription, enableTranscription);
    }
    if (enableEmbeddings != null) {
      await prefs.setBool(_ConfigKeys.enableEmbeddings, enableEmbeddings);
    }
    if (enableSemanticSimilarity != null) {
      await prefs.setBool(_ConfigKeys.enableSemanticSimilarity, enableSemanticSimilarity);
    }
    if (enableRag != null) {
      await prefs.setBool(_ConfigKeys.enableRag, enableRag);
    }
    if (enableAutoSummary != null) {
      await prefs.setBool(_ConfigKeys.enableAutoSummary, enableAutoSummary);
    }
    if (enableAutoTags != null) {
      await prefs.setBool(_ConfigKeys.enableAutoTags, enableAutoTags);
    }

    // Лимиты
    if (maxConcurrentJobs != null) {
      await prefs.setInt(_ConfigKeys.maxConcurrentJobs, maxConcurrentJobs);
    }
    if (maxFileSizeMbForEnrichment != null) {
      await prefs.setInt(_ConfigKeys.maxFileSizeMbForEnrichment, maxFileSizeMbForEnrichment);
    }
    if (maxMediaMinutes != null) {
      await prefs.setInt(_ConfigKeys.maxMediaMinutes, maxMediaMinutes);
    }
    if (maxPagesPerPdf != null) {
      await prefs.setInt(_ConfigKeys.maxPagesPerPdf, maxPagesPerPdf);
    }

    // Обновляем текущую конфигурацию
    // ВАЖНО: copyWith() не умеет устанавливать null (паттерн newValue ?? oldValue).
    // Поэтому создаём AppConfig напрямую с явными значениями для всех полей.
    _currentConfig = AppConfig(
      watchPath: clearWatchPath ? null : (watchPath ?? _currentConfig.watchPath),
      watchIntervalMs: watchIntervalMs ?? _currentConfig.watchIntervalMs,
      notificationsEnabled: notificationsEnabled ?? _currentConfig.notificationsEnabled,
      loggingEnabled: loggingEnabled ?? _currentConfig.loggingEnabled,
      logLevel: logLevel ?? _currentConfig.logLevel,
      theme: theme ?? _currentConfig.theme,
      language: clearLanguage ? null : (language ?? _currentConfig.language),
      // Производительность и контент
      resourceSaverEnabled: resourceSaverEnabled ?? _currentConfig.resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs ?? _currentConfig.enableOfficeDocs,
      enableOcr: enableOcr ?? _currentConfig.enableOcr,
      enableTranscription: enableTranscription ?? _currentConfig.enableTranscription,
      enableEmbeddings: enableEmbeddings ?? _currentConfig.enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity ?? _currentConfig.enableSemanticSimilarity,
      enableRag: enableRag ?? _currentConfig.enableRag,
      enableAutoSummary: enableAutoSummary ?? _currentConfig.enableAutoSummary,
      enableAutoTags: enableAutoTags ?? _currentConfig.enableAutoTags,
      // Лимиты
      maxConcurrentJobs: maxConcurrentJobs ?? _currentConfig.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment ?? _currentConfig.maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes ?? _currentConfig.maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf ?? _currentConfig.maxPagesPerPdf,
    );

    _configController.add(_currentConfig);
    _logger.i('SharedPreferencesConfigService: config updated');
  }

  /// Обновляет путь наблюдения (удобный метод).
  ///
  /// Важно: этот метод корректно обрабатывает null (очистку пути),
  /// в отличие от copyWith(), который не умеет устанавливать null.
  Future<void> setWatchPath(String? path) async {
    _ensureInitialized();
    final prefs = _prefs!;

    if (path != null) {
      await prefs.setString(_ConfigKeys.watchPath, path);
    } else {
      await prefs.remove(_ConfigKeys.watchPath);
    }

    // ВАЖНО: copyWith() не умеет устанавливать null (паттерн newValue ?? oldValue).
    // Создаём AppConfig напрямую с явными значениями для всех полей.
    _currentConfig = AppConfig(
      watchPath: path,
      watchIntervalMs: _currentConfig.watchIntervalMs,
      notificationsEnabled: _currentConfig.notificationsEnabled,
      loggingEnabled: _currentConfig.loggingEnabled,
      logLevel: _currentConfig.logLevel,
      theme: _currentConfig.theme,
      language: _currentConfig.language,
      // Сохраняем настройки производительности и контента
      resourceSaverEnabled: _currentConfig.resourceSaverEnabled,
      enableOfficeDocs: _currentConfig.enableOfficeDocs,
      enableOcr: _currentConfig.enableOcr,
      enableTranscription: _currentConfig.enableTranscription,
      enableEmbeddings: _currentConfig.enableEmbeddings,
      enableSemanticSimilarity: _currentConfig.enableSemanticSimilarity,
      enableRag: _currentConfig.enableRag,
      enableAutoSummary: _currentConfig.enableAutoSummary,
      enableAutoTags: _currentConfig.enableAutoTags,
      maxConcurrentJobs: _currentConfig.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: _currentConfig.maxFileSizeMbForEnrichment,
      maxMediaMinutes: _currentConfig.maxMediaMinutes,
      maxPagesPerPdf: _currentConfig.maxPagesPerPdf,
    );
    _configController.add(_currentConfig);
    _logger.i('Watch path updated: $path');
  }

  /// Освободить ресурсы.
  void dispose() {
    _configController.close();
    _logger.d('SharedPreferencesConfigService disposed');
  }
}

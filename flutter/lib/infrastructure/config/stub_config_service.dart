import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/app_config.dart';

/// Stub-реализация сервиса конфигурации.
///
/// Хранит конфигурацию в памяти (без персистентности).
/// Используется для разработки и тестирования.
class StubConfigService implements ConfigService {
  final Logger _logger;

  AppConfig _currentConfig = AppConfig.defaultConfig;
  final StreamController<AppConfig> _configController =
      StreamController<AppConfig>.broadcast();
  bool _onboardingCompleted = false;

  StubConfigService({required Logger logger}) : _logger = logger;

  @override
  AppConfig get currentConfig => _currentConfig;

  @override
  Stream<AppConfig> get configChanges => _configController.stream;

  @override
  Future<AppConfig> load() async {
    _logger.d('StubConfigService: load');
    // Имитация задержки чтения
    await Future.delayed(const Duration(milliseconds: 50));
    return _currentConfig;
  }

  @override
  Future<void> save(AppConfig config) async {
    _logger.d('StubConfigService: save');
    // Имитация задержки записи
    await Future.delayed(const Duration(milliseconds: 50));
    _currentConfig = config;
    _configController.add(_currentConfig);
  }

  @override
  Future<void> reset() async {
    _logger.d('StubConfigService: reset');
    await Future.delayed(const Duration(milliseconds: 50));
    _currentConfig = AppConfig.defaultConfig;
    _configController.add(_currentConfig);
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
    _logger.d('StubConfigService: updateValue');
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
      resourceSaverEnabled: resourceSaverEnabled ?? _currentConfig.resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs ?? _currentConfig.enableOfficeDocs,
      enableOcr: enableOcr ?? _currentConfig.enableOcr,
      enableTranscription: enableTranscription ?? _currentConfig.enableTranscription,
      enableEmbeddings: enableEmbeddings ?? _currentConfig.enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity ?? _currentConfig.enableSemanticSimilarity,
      enableRag: enableRag ?? _currentConfig.enableRag,
      enableAutoSummary: enableAutoSummary ?? _currentConfig.enableAutoSummary,
      enableAutoTags: enableAutoTags ?? _currentConfig.enableAutoTags,
      maxConcurrentJobs: maxConcurrentJobs ?? _currentConfig.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment ?? _currentConfig.maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes ?? _currentConfig.maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf ?? _currentConfig.maxPagesPerPdf,
    );
    _configController.add(_currentConfig);
  }

  // === Onboarding ===

  @override
  bool get isOnboardingCompleted => _onboardingCompleted;

  @override
  Future<void> completeOnboarding() async {
    _logger.d('StubConfigService: completeOnboarding');
    _onboardingCompleted = true;
  }

  @override
  Future<void> resetOnboarding() async {
    _logger.d('StubConfigService: resetOnboarding');
    _onboardingCompleted = false;
  }

  /// Освободить ресурсы.
  void dispose() {
    _configController.close();
  }
}

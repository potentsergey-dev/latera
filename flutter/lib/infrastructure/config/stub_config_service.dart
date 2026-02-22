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
  }) async {
    _logger.d('StubConfigService: updateValue');
    _currentConfig = _currentConfig.copyWith(
      watchPath: watchPath,
      watchIntervalMs: watchIntervalMs,
      notificationsEnabled: notificationsEnabled,
      loggingEnabled: loggingEnabled,
      logLevel: logLevel,
      theme: theme,
      language: language,
    );
    _configController.add(_currentConfig);
  }

  /// Освободить ресурсы.
  void dispose() {
    _configController.close();
  }
}

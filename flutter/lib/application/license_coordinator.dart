import 'package:logger/logger.dart';

import '../domain/feature_flags.dart';
import '../domain/license.dart';
import '../domain/license_service.dart';

/// Координатор управления лицензиями.
///
/// Application-слой сервис, координирующий операции с лицензиями
/// и предоставляющий бизнес-логику для UI.
///
/// Точка расширения для Free/Pro функциональности.
class LicenseCoordinator {
  final Logger _logger;
  final LicenseService _licenseService;
  final FeatureFlags _featureFlags;

  LicenseCoordinator({
    required Logger logger,
    required LicenseService licenseService,
    required FeatureFlags featureFlags,
  })  : _logger = logger,
        _licenseService = licenseService,
        _featureFlags = featureFlags;

  /// Текущая лицензия.
  License get currentLicense => _licenseService.currentLicense;

  /// Stream изменений лицензии.
  Stream<License> get licenseChanges => _licenseService.licenseChanges;

  /// Stream изменений доступных функций.
  Stream<Set<String>> get availableFeaturesChanges =>
      _featureFlags.availableFeaturesChanges;

  /// Множество доступных функций.
  Set<String> get availableFeatures => _featureFlags.availableFeatures;

  /// Проверить, активна ли Pro лицензия.
  bool get isPro => currentLicense.isPro;

  /// Проверить, используется ли Free версия.
  bool get isFree => currentLicense.isFree;

  /// Проверить доступность функции.
  bool isFeatureAvailable(String featureId) =>
      _licenseService.isFeatureAvailable(featureId);

  /// Получить лимит для функции.
  int? getLimit(String limitId) => _featureFlags.getLimit(limitId);

  /// Обновить статус лицензии.
  ///
  /// Выполняет проверку лицензии и обновляет состояние.
  Future<License> refreshLicense() async {
    _logger.i('Refreshing license status');
    try {
      final license = await _licenseService.refreshLicense();
      _logger.i('License refreshed: ${license.type}, status: ${license.status}');
      return license;
    } catch (e, st) {
      _logger.e('Failed to refresh license', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Активировать лицензию по ключу.
  ///
  /// Возвращает результат активации.
  Future<LicenseActivationResult> activateLicense(String licenseKey) async {
    _logger.i('Activating license');
    try {
      final result = await _licenseService.activateLicense(licenseKey);
      if (result.success) {
        _logger.i('License activated successfully: ${result.license?.type}');
      } else {
        _logger.w('License activation failed: ${result.error}');
      }
      return result;
    } catch (e, st) {
      _logger.e('Failed to activate license', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Деактивировать текущую лицензию.
  Future<void> deactivateLicense() async {
    _logger.i('Deactivating license');
    try {
      await _licenseService.deactivateLicense();
      _logger.i('License deactivated');
    } catch (e, st) {
      _logger.e('Failed to deactivate license', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Проверить, можно ли выполнить операцию с учётом лимитов.
  ///
  /// [featureId] — идентификатор функции.
  /// [currentCount] — текущее количество (например, проиндексированных файлов).
  /// Возвращает true, если операция разрешена.
  bool canPerformOperation(String featureId, {int? currentCount}) {
    if (!isFeatureAvailable(featureId)) {
      return false;
    }

    // Для Pro версии нет ограничений
    if (isPro) {
      return true;
    }

    // Для Free версии проверяем лимиты
    if (currentCount != null) {
      final limit = getLimit(featureId);
      if (limit != null && currentCount >= limit) {
        return false;
      }
    }

    return true;
  }

  /// Получить информацию об ограничениях для текущей лицензии.
  LicenseLimitsInfo getLimitsInfo() {
    if (isPro) {
      return const LicenseLimitsInfo(
        maxIndexedFiles: null, // unlimited
        maxFileSizeBytes: ProTierFeatures.maxFileSizeBytes,
        maxSearchResults: null, // unlimited
        maxWatchedDirectories: ProTierFeatures.maxWatchedDirectories,
        supportedFormats: ProTierFeatures.supportedFileFormats,
      );
    }

    return LicenseLimitsInfo(
      maxIndexedFiles: FreeTierLimits.maxIndexedFiles,
      maxFileSizeBytes: FreeTierLimits.maxFileSizeBytes,
      maxSearchResults: FreeTierLimits.maxSearchResults,
      maxWatchedDirectories: FreeTierLimits.maxWatchedDirectories,
      supportedFormats: FreeTierLimits.supportedFileFormats,
    );
  }
}

/// Информация об ограничениях лицензии.
class LicenseLimitsInfo {
  /// Максимальное количество индексируемых файлов (null = безлимитно).
  final int? maxIndexedFiles;

  /// Максимальный размер файла в байтах.
  final int maxFileSizeBytes;

  /// Максимальное количество результатов поиска (null = безлимитно).
  final int? maxSearchResults;

  /// Максимальное количество наблюдаемых директорий.
  final int maxWatchedDirectories;

  /// Поддерживаемые форматы файлов.
  final Set<String> supportedFormats;

  const LicenseLimitsInfo({
    required this.maxIndexedFiles,
    required this.maxFileSizeBytes,
    required this.maxSearchResults,
    required this.maxWatchedDirectories,
    required this.supportedFormats,
  });

  /// Проверяет, поддерживается ли формат файла.
  bool isFormatSupported(String extension) {
    final normalized = extension.toLowerCase().replaceAll('.', '');
    return supportedFormats.contains(normalized);
  }
}

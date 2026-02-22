import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/feature_flags.dart';
import '../../domain/license.dart';
import '../../domain/license_service.dart';

/// Stub-реализация сервиса фиче-флагов.
///
/// Предоставляет доступность функций на основе текущей лицензии.
/// Используется для разработки и тестирования.
class StubFeatureFlags implements FeatureFlags {
  final Logger _logger;
  final LicenseService _licenseService;

  final StreamController<Set<String>> _featuresController =
      StreamController<Set<String>>.broadcast();

  StreamSubscription<License>? _licenseSubscription;

  StubFeatureFlags({
    required Logger logger,
    required LicenseService licenseService,
  })  : _logger = logger,
        _licenseService = licenseService {
    _init();
  }

  void _init() {
    // Подписываемся на изменения лицензии
    _licenseSubscription = _licenseService.licenseChanges.listen((license) {
      _logger.d('StubFeatureFlags: License changed to ${license.type}');
      _featuresController.add(availableFeatures);
    });
  }

  @override
  bool isAvailable(String featureId) {
    return availableFeatures.contains(featureId);
  }

  @override
  int? getLimit(String limitId) {
    final license = _licenseService.currentLicense;

    // Pro версия - без лимитов
    if (license.isPro) {
      return _getProLimit(limitId);
    }

    // Free версия - ограниченные лимиты
    return _getFreeLimit(limitId);
  }

  int? _getFreeLimit(String limitId) {
    switch (limitId) {
      case LimitId.maxIndexedFiles:
        return FreeTierLimits.maxIndexedFiles;
      case LimitId.maxFileSize:
        return FreeTierLimits.maxFileSizeBytes;
      case LimitId.maxSearchResults:
        return FreeTierLimits.maxSearchResults;
      case LimitId.maxWatchedDirectories:
        return FreeTierLimits.maxWatchedDirectories;
      default:
        _logger.w('Unknown limit ID: $limitId');
        return null;
    }
  }

  int? _getProLimit(String limitId) {
    switch (limitId) {
      case LimitId.maxIndexedFiles:
        return null; // unlimited
      case LimitId.maxFileSize:
        return ProTierFeatures.maxFileSizeBytes;
      case LimitId.maxSearchResults:
        return null; // unlimited
      case LimitId.maxWatchedDirectories:
        return ProTierFeatures.maxWatchedDirectories;
      default:
        _logger.w('Unknown limit ID: $limitId');
        return null;
    }
  }

  @override
  Stream<Set<String>> get availableFeaturesChanges => _featuresController.stream;

  @override
  Set<String> get availableFeatures {
    final license = _licenseService.currentLicense;

    // Базовые функции, доступные всегда
    const baseFeatures = {
      FeatureId.basicSearch,
      FeatureId.basicIndexing,
      FeatureId.basicNotifications,
      FeatureId.darkTheme,
    };

    // Pro функции
    const proFeatures = {
      FeatureId.contentSearch,
      FeatureId.advancedSearch,
      FeatureId.semanticSearch,
      FeatureId.unlimitedIndexing,
      FeatureId.contentIndexing,
      FeatureId.customNotifications,
      FeatureId.uiCustomization,
      FeatureId.exportResults,
      FeatureId.externalIntegrations,
    };

    if (license.isPro) {
      return {...baseFeatures, ...proFeatures};
    }

    return baseFeatures;
  }

  /// Освободить ресурсы.
  void dispose() {
    _licenseSubscription?.cancel();
    _featuresController.close();
  }
}

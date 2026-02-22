import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/feature_flags.dart';
import '../../domain/license.dart';
import '../../domain/license_service.dart';

/// Stub-реализация сервиса лицензирования.
///
/// Всегда возвращает Free лицензию.
/// Используется для разработки и тестирования.
class StubLicenseService implements LicenseService {
  final Logger _logger;

  License _currentLicense = License.defaultFree;
  final StreamController<License> _licenseController =
      StreamController<License>.broadcast();

  StubLicenseService({required Logger logger}) : _logger = logger;

  @override
  License get currentLicense => _currentLicense;

  @override
  Stream<License> get licenseChanges => _licenseController.stream;

  @override
  Future<License> refreshLicense() async {
    _logger.d('StubLicenseService: refreshLicense');
    // Имитация задержки сети
    await Future.delayed(const Duration(milliseconds: 100));
    return _currentLicense;
  }

  @override
  Future<LicenseActivationResult> activateLicense(String licenseKey) async {
    _logger.d('StubLicenseService: activateLicense with key: $licenseKey');
    // Имитация задержки сети
    await Future.delayed(const Duration(milliseconds: 500));

    // Для тестирования: ключ "PRO-TEST" активирует Pro лицензию
    if (licenseKey.toUpperCase() == 'PRO-TEST') {
      _currentLicense = License(
        type: LicenseType.pro,
        status: LicenseStatus.active,
        licenseId: 'stub-pro-license',
        userEmail: 'test@example.com',
        activatedAt: DateTime.now(),
      );
      _licenseController.add(_currentLicense);
      return LicenseActivationResult.success(_currentLicense);
    }

    // Для тестирования: ключ "EXPIRED-TEST" возвращает истёкшую лицензию
    if (licenseKey.toUpperCase() == 'EXPIRED-TEST') {
      return LicenseActivationResult.failure(
        error: LicenseActivationError.expired,
        errorMessage: 'License has expired',
      );
    }

    // Для тестирования: ключ "ERROR-TEST" возвращает ошибку сети
    if (licenseKey.toUpperCase() == 'ERROR-TEST') {
      return LicenseActivationResult.failure(
        error: LicenseActivationError.networkError,
        errorMessage: 'Network error during activation',
      );
    }

    // Все остальные ключи считаются недействительными
    return const LicenseActivationResult.failure(
      error: LicenseActivationError.invalidKey,
      errorMessage: 'Invalid license key',
    );
  }

  @override
  Future<void> deactivateLicense() async {
    _logger.d('StubLicenseService: deactivateLicense');
    await Future.delayed(const Duration(milliseconds: 100));
    _currentLicense = License.defaultFree;
    _licenseController.add(_currentLicense);
  }

  @override
  bool isFeatureAvailable(String featureId) {
    // Free функции всегда доступны
    const freeFeatures = {
      FeatureId.basicSearch,
      FeatureId.basicIndexing,
      FeatureId.basicNotifications,
      FeatureId.darkTheme,
    };

    if (freeFeatures.contains(featureId)) {
      return true;
    }

    // Pro функции доступны только с Pro лицензией
    return _currentLicense.isPro;
  }

  /// Освободить ресурсы.
  void dispose() {
    _licenseController.close();
  }
}

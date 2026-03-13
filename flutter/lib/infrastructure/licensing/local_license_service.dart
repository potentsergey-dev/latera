import 'dart:async';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/feature_flags.dart';
import '../../domain/license.dart';
import '../../domain/license_service.dart';

/// Реализация LicenseService на базе SharedPreferences.
///
/// Поддерживает 3-дневный бесплатный триал Pro-функций
/// и покупку Pro-версии.
class LocalLicenseService implements LicenseService {
  final Logger _logger;
  final SharedPreferences _prefs;

  /// Длительность триала Pro-функций.
  static const trialDuration = Duration(days: 3);

  static const _keyInstallDate = 'latera_install_date';
  static const _keyIsProPurchased = 'latera_is_pro_purchased';

  License _currentLicense = License.defaultFree;
  final StreamController<License> _licenseController =
      StreamController<License>.broadcast();

  LocalLicenseService({
    required Logger logger,
    required SharedPreferences prefs,
  })  : _logger = logger,
        _prefs = prefs;

  /// Инициализация: фиксирует дату первого запуска и вычисляет лицензию.
  Future<void> initialize() async {
    // Фиксируем дату установки при первом запуске
    if (!_prefs.containsKey(_keyInstallDate)) {
      final now = DateTime.now().toIso8601String();
      await _prefs.setString(_keyInstallDate, now);
      _logger.i('LocalLicenseService: first launch, install date = $now');
    }
    _currentLicense = _computeLicense();
    _logger.i('LocalLicenseService: initialized, mode = ${_currentLicense.mode}');
  }

  License _computeLicense() {
    final isProPurchased = _prefs.getBool(_keyIsProPurchased) ?? false;
    if (isProPurchased) {
      return const License(
        type: LicenseType.pro,
        status: LicenseStatus.active,
        mode: LicenseMode.pro,
      );
    }

    final installDateStr = _prefs.getString(_keyInstallDate);
    if (installDateStr != null) {
      final installDate = DateTime.parse(installDateStr);
      final trialEnd = installDate.add(trialDuration);
      if (DateTime.now().isBefore(trialEnd)) {
        return License(
          type: LicenseType.pro,
          status: LicenseStatus.active,
          mode: LicenseMode.proTrial,
          trialExpiresAt: trialEnd,
        );
      }
    }

    return const License(
      type: LicenseType.free,
      status: LicenseStatus.active,
      mode: LicenseMode.basic,
    );
  }

  @override
  License get currentLicense => _currentLicense;

  @override
  Stream<License> get licenseChanges => _licenseController.stream;

  @override
  Future<License> refreshLicense() async {
    _currentLicense = _computeLicense();
    _licenseController.add(_currentLicense);
    return _currentLicense;
  }

  @override
  Future<LicenseActivationResult> activateLicense(String licenseKey) async {
    _logger.d('LocalLicenseService: activateLicense with key');
    // Делегируем покупку через activateProPurchase().
    // Ключи можно верифицировать удалённо в будущем.
    return const LicenseActivationResult.failure(
      error: LicenseActivationError.invalidKey,
      errorMessage: 'License key activation not yet implemented',
    );
  }

  @override
  Future<void> deactivateLicense() async {
    _logger.d('LocalLicenseService: deactivateLicense');
    await _prefs.remove(_keyIsProPurchased);
    _currentLicense = _computeLicense();
    _licenseController.add(_currentLicense);
  }

  @override
  bool isFeatureAvailable(String featureId) {
    const freeFeatures = {
      FeatureId.basicSearch,
      FeatureId.basicIndexing,
      FeatureId.basicNotifications,
      FeatureId.darkTheme,
    };

    if (freeFeatures.contains(featureId)) {
      return true;
    }

    return _currentLicense.isPro;
  }

  @override
  Future<void> activateProPurchase() async {
    _logger.i('LocalLicenseService: activateProPurchase');
    await _prefs.setBool(_keyIsProPurchased, true);
    _currentLicense = _computeLicense();
    _licenseController.add(_currentLicense);
  }

  /// Синхронизация статуса с Microsoft Store.
  ///
  /// Вызывается при старте приложения для обработки сценария переустановки:
  /// если пользователь переустановил приложение, но покупка сохранилась в Store.
  Future<void> syncStoreStatus(bool isStorePurchased) async {
    final localPurchased = _prefs.getBool(_keyIsProPurchased) ?? false;
    if (isStorePurchased && !localPurchased) {
      _logger.i('LocalLicenseService: Store purchase detected, activating Pro');
      await activateProPurchase();
    }
  }

  /// Освободить ресурсы.
  void dispose() {
    _licenseController.close();
  }
}

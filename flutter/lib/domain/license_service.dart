import 'license.dart';

/// Контракт на сервис лицензирования.
///
/// Domain слой не зависит от реализации проверки лицензии
/// (локальная, серверная, Gumroad, LemonSqueezy и т.д.).
///
/// Реализация будет в infrastructure слое.
abstract interface class LicenseService {
  /// Текущая лицензия.
  ///
  /// Возвращает [License.defaultFree] если лицензия не активирована.
  License get currentLicense;

  /// Stream изменений лицензии.
  ///
  /// Позволяет UI реагировать на изменения статуса лицензии
  /// (активация, истечение, отзыв).
  Stream<License> get licenseChanges;

  /// Проверить и обновить статус лицензии.
  ///
  /// Выполняет проверку лицензии (локально или удалённо).
  /// Возвращает актуальный статус лицензии.
  Future<License> refreshLicense();

  /// Активировать лицензию по ключу.
  ///
  /// [licenseKey] — ключ лицензии (формат зависит от провайдера).
  /// Возвращает активированную лицензию или ошибку.
  Future<LicenseActivationResult> activateLicense(String licenseKey);

  /// Деактивировать текущую лицензию.
  ///
  /// Отвязывает лицензию от устройства.
  Future<void> deactivateLicense();

  /// Проверить, доступна ли функция для текущей лицензии.
  ///
  /// [featureId] — идентификатор функции (см. [FeatureId]).
  bool isFeatureAvailable(String featureId);
}

/// Результат активации лицензии.
class LicenseActivationResult {
  /// Успешность активации.
  final bool success;

  /// Активированная лицензия (при успехе).
  final License? license;

  /// Код ошибки (при неудаче).
  final LicenseActivationError? error;

  /// Сообщение об ошибке.
  final String? errorMessage;

  const LicenseActivationResult.success(License this.license)
      : success = true,
        error = null,
        errorMessage = null;

  const LicenseActivationResult.failure({
    required this.error,
    this.errorMessage,
  })  : success = false,
        license = null;

  /// Была ли ошибка сети.
  bool get isNetworkError => error == LicenseActivationError.networkError;

  /// Был ли ключ недействительным.
  bool get isInvalidKey => error == LicenseActivationError.invalidKey;

  /// Был ли ключ уже использован.
  bool get isAlreadyUsed => error == LicenseActivationError.alreadyUsed;
}

/// Коды ошибок активации лицензии.
enum LicenseActivationError {
  /// Неверный ключ лицензии.
  invalidKey,

  /// Ключ уже использован на другом устройстве.
  alreadyUsed,

  /// Ошибка сети при проверке.
  networkError,

  /// Превышен лимит активаций.
  activationLimitReached,

  /// Лицензия истекла.
  expired,

  /// Внутренняя ошибка.
  internalError,
}

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Результат попытки покупки через Microsoft Store.
enum PurchaseStatus {
  /// Покупка завершена успешно.
  success,

  /// Пользователь отменил покупку.
  cancelled,

  /// Произошла ошибка при покупке.
  error,

  /// Microsoft Store недоступен (например, приложение не упаковано в MSIX
  /// или запущено вне Store-контекста).
  storeUnavailable,
}

/// Результат операции покупки.
class PurchaseResult {
  final PurchaseStatus status;
  final String? errorMessage;

  const PurchaseResult._(this.status, [this.errorMessage]);

  static const success = PurchaseResult._(PurchaseStatus.success);
  static const cancelled = PurchaseResult._(PurchaseStatus.cancelled);
  static const storeUnavailable =
      PurchaseResult._(PurchaseStatus.storeUnavailable);

  factory PurchaseResult.error([String? message]) =>
      PurchaseResult._(PurchaseStatus.error, message);

  bool get isSuccess => status == PurchaseStatus.success;
  bool get isCancelled => status == PurchaseStatus.cancelled;
  bool get isError =>
      status == PurchaseStatus.error ||
      status == PurchaseStatus.storeUnavailable;
}

/// Сервис покупки PRO-версии через Microsoft Store IAP.
///
/// Использует MethodChannel для вызова нативного C++ плагина,
/// который обращается к WinRT API Windows.Services.Store.StoreContext.
///
/// Работает только в MSIX-упакованном приложении с identity.
/// При запуске вне Store-контекста (dev mode) возвращает graceful fallback.
class StorePurchaseService {
  static const _channel = MethodChannel('com.latera.store_purchase');

  /// ID Add-On продукта в Partner Center.
  static const productId = 'latera_pro';

  final Logger _logger;

  StorePurchaseService({required Logger logger}) : _logger = logger;

  /// Проверяет, куплен ли PRO Add-On через Microsoft Store.
  ///
  /// Возвращает true если лицензия на Add-On активна.
  /// Возвращает false если не куплен, Store недоступен или произошла ошибка.
  Future<bool> isProPurchased() async {
    try {
      final result = await _channel.invokeMethod<bool>('isProPurchased');
      _logger.d('StorePurchaseService: isProPurchased = $result');
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.w('StorePurchaseService: Store API error: ${e.message}');
      return false;
    } on MissingPluginException {
      _logger.w('StorePurchaseService: native plugin not registered');
      return false;
    }
  }

  /// Запускает флоу покупки PRO Add-On через диалог Microsoft Store.
  ///
  /// Возвращает [PurchaseResult] с результатом операции.
  Future<PurchaseResult> buyPro() async {
    try {
      _logger.i('StorePurchaseService: starting purchase flow for $productId');
      final result =
          await _channel.invokeMethod<String>('buyPro', productId);
      _logger.i('StorePurchaseService: purchase result = $result');
      switch (result) {
        case 'success':
          return PurchaseResult.success;
        case 'cancelled':
          return PurchaseResult.cancelled;
        default:
          return PurchaseResult.error(result);
      }
    } on PlatformException catch (e) {
      _logger.e('StorePurchaseService: purchase error: ${e.message}');
      return PurchaseResult.error(e.message);
    } on MissingPluginException {
      _logger.w('StorePurchaseService: native plugin not registered');
      return PurchaseResult.storeUnavailable;
    }
  }
}

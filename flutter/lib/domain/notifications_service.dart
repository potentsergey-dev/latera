/// Контракт на систему уведомлений.
///
/// Domain слой не зависит от Flutter/плагинов.
abstract interface class NotificationsService {
  /// Инициализация уведомлений.
  Future<void> init();

  /// Показать уведомление о новом файле.
  Future<void> showFileAdded({required String fileName});
}

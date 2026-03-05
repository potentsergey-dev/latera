/// Контракт на систему уведомлений.
///
/// Domain слой не зависит от Flutter/плагинов.
abstract interface class NotificationsService {
  /// Инициализация уведомлений.
  Future<void> init();

  /// Показать уведомление о новом файле.
  Future<void> showFileAdded({required String fileName});

  /// Показать тихое уведомление о файле, который не удалось распознать.
  ///
  /// Файл добавлен в индекс, но требует ручного описания.
  Future<void> showFileNeedsReview({required String fileName});
}

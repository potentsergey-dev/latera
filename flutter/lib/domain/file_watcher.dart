import 'file_added_event.dart';

/// Контракт на источник событий файловой системы.
///
/// Реальная реализация будет в infrastructure через Rust core.
abstract interface class FileWatcher {
  Stream<FileAddedEvent> get fileAddedEvents;

  /// Запуск наблюдения.
  ///
  /// [overridePath] — абсолютный путь. Если null, дефолт выбирается внутри Rust.
  Future<void> startWatching({String? overridePath});

  /// Остановка наблюдения.
  Future<void> stopWatching();
}


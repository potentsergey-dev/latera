import 'core_error.dart';
import 'file_added_event.dart';

/// Результат запуска наблюдения.
///
/// Содержит путь к директории наблюдения.
sealed class WatchResult {
  const WatchResult();
}

final class WatchSuccess extends WatchResult {
  final String watchDir;
  const WatchSuccess(this.watchDir);
}

final class WatchFailure extends WatchResult {
  final CoreError error;
  const WatchFailure(this.error);
}

/// Контракт на источник событий файловой системы.
///
/// Реальная реализация будет в infrastructure через Rust core.
abstract interface class FileWatcher {
  /// Поток событий добавления файлов.
  ///
  /// Может завершиться с ошибкой [StreamError].
  Stream<FileAddedEvent> get fileAddedEvents;

  /// Запуск наблюдения.
  ///
  /// [overridePath] — абсолютный путь. Если null, дефолт выбирается внутри Rust.
  ///
  /// Возвращает [WatchResult] с путём к директории наблюдения или ошибкой.
  Future<WatchResult> startWatching({String? overridePath});

  /// Остановка наблюдения.
  ///
  /// Возвращает [CoreError] если произошла ошибка, или null при успехе.
  Future<CoreError?> stopWatching();

  /// Проверка, запущен ли watcher.
  bool get isWatching;
}

import 'dart:async';

import 'package:logger/logger.dart';

import '../domain/core_error.dart';
import '../domain/file_added_event.dart';
import '../domain/file_watcher.dart';
import '../domain/notifications_service.dart';

/// UI-friendly событие (application слой).
class FileAddedUiEvent {
  final String fileName;
  final String? fullPath;
  final DateTime occurredAt;

  const FileAddedUiEvent({
    required this.fileName,
    required this.occurredAt,
    this.fullPath,
  });

  factory FileAddedUiEvent.fromDomain(FileAddedEvent e) {
    return FileAddedUiEvent(
      fileName: e.fileName,
      fullPath: e.fullPath,
      occurredAt: e.occurredAt,
    );
  }
}

/// Результат запуска координатора.
sealed class CoordinatorStartResult {
  const CoordinatorStartResult();
}

final class CoordinatorStartSuccess extends CoordinatorStartResult {
  final String watchDir;
  const CoordinatorStartSuccess(this.watchDir);
}

final class CoordinatorStartFailure extends CoordinatorStartResult {
  final CoreError error;
  const CoordinatorStartFailure(this.error);
}

/// Application-layer координатор:
/// - стартует watcher
/// - слушает domain-события
/// - применяет политику уведомлений
///
/// ## Lifecycle
/// Координатор поддерживает множественные циклы start/stop.
/// Stream [fileAddedEvents] остаётся активным между циклами.
/// Для освобождения ресурсов вызовите [dispose].
class FileEventsCoordinator {
  final Logger _log;
  final FileWatcher _watcher;
  final NotificationsService _notifications;

  late final StreamController<FileAddedUiEvent> _controller =
      StreamController<FileAddedUiEvent>.broadcast();
  StreamSubscription<FileAddedEvent>? _sub;
  bool _isRunning = false;
  bool _isDisposed = false;

  FileEventsCoordinator({
    required Logger logger,
    required FileWatcher watcher,
    required NotificationsService notifications,
  })  : _log = logger,
        _watcher = watcher,
        _notifications = notifications;

  /// Broadcast stream событий файла.
  ///
  /// Остается активным между циклами start/stop.
  /// Закрывается только при [dispose].
  Stream<FileAddedUiEvent> get fileAddedEvents => _controller.stream;
  bool get isRunning => _isRunning;
  bool get isDisposed => _isDisposed;

  /// Запускает координатор.
  ///
  /// Возвращает [CoordinatorStartResult] с путём к директории наблюдения или ошибкой.
  ///
  /// Throws [StateError] if coordinator is disposed.
  Future<CoordinatorStartResult> start() async {
    if (_isDisposed) {
      throw StateError('Cannot start disposed coordinator');
    }

    _log.i('Starting file events coordinator');

    final result = await _watcher.startWatching();

    return switch (result) {
      WatchSuccess(:final watchDir) => _onStartSuccess(watchDir),
      WatchFailure(:final error) => _onStartFailure(error),
    };
  }

  CoordinatorStartResult _onStartSuccess(String watchDir) {
    // Отменяем предыдущую подписку если есть (защита от утечек при повторном start)
    _sub?.cancel();
    _sub = null;

    _isRunning = true;

    // Подписываемся на события файла
    // Оборачиваем async callback для обработки ошибок
    _sub = _watcher.fileAddedEvents.listen(
      (event) {
        // Запускаем async обработку с обработкой ошибок
        // unawaited используется намеренно - обработка не должна блокировать stream
        unawaited(_onFileEventSafe(event));
      },
      onError: _onStreamError,
      onDone: _onStreamDone,
    );

    _log.i('File events coordinator started. Watching: $watchDir');
    return CoordinatorStartSuccess(watchDir);
  }

  CoordinatorStartResult _onStartFailure(CoreError error) {
    _log.e('Failed to start file events coordinator', error: error);
    return CoordinatorStartFailure(error);
  }

  /// Безопасная обёртка для обработки событий файла.
  ///
  /// Гарантирует, что любые ошибки будут залогированы и не прервут stream.
  Future<void> _onFileEventSafe(FileAddedEvent event) async {
    try {
      // Эмитим UI событие
      _controller.add(FileAddedUiEvent.fromDomain(event));

      // Показываем уведомление
      await _notifications.showFileAdded(fileName: event.fileName);
    } catch (e, st) {
      _log.e(
        'Error processing file event for ${event.fileName}',
        error: e,
        stackTrace: st,
      );
      // Не пробрасываем ошибку - обработка событий не должна прерываться
    }
  }

  void _onStreamError(Object error, StackTrace st) {
    _log.e('File watcher stream error', error: error, stackTrace: st);

    // Эмитим ошибку в UI поток
    if (error is CoreError) {
      _controller.addError(error, st);
    } else {
      _controller.addError(
        StreamError(
          message: error.toString(),
          originalError: error,
          stackTrace: st,
        ),
        st,
      );
    }
  }

  void _onStreamDone() {
    _log.i('File watcher stream completed');
    _isRunning = false;
  }

  /// Останавливает координатор.
  ///
  /// Возвращает ошибку если произошла, или null при успехе.
  /// Контроллер остаётся открытым для возможности повторного start.
  Future<CoreError?> stop() async {
    _log.i('Stopping file events coordinator');

    // Отменяем подписку
    await _sub?.cancel();
    _sub = null;

    // Останавливаем watcher
    final error = await _watcher.stopWatching();

    _isRunning = false;
    _log.i('File events coordinator stopped');

    return error;
  }

  /// Освобождает все ресурсы.
  ///
  /// После вызова этого метода координатор нельзя использовать.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _log.i('Disposing file events coordinator');

    await stop();
    await _controller.close();

    _isDisposed = true;
    _log.i('File events coordinator disposed');
  }
}

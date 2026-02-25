import 'dart:async';

import 'package:logger/logger.dart';

import '../domain/app_config.dart';
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
  final ConfigService _configService;

  late final StreamController<FileAddedUiEvent> _controller =
      StreamController<FileAddedUiEvent>.broadcast();
  StreamSubscription<FileAddedEvent>? _sub;
  StreamSubscription<AppConfig>? _configSub;
  bool _isRunning = false;
  bool _isStarting = false;
  bool _isDisposed = false;
  bool _isDisposing = false;
  Future<void>? _restartFuture;
  bool _restartRequested = false; // Флаг для отслеживания отложенных restart'ов
  String? _lastWatchPath; // Последний известный путь для обнаружения изменений

  FileEventsCoordinator({
    required Logger logger,
    required FileWatcher watcher,
    required NotificationsService notifications,
    required ConfigService configService,
  })  : _log = logger,
        _watcher = watcher,
        _notifications = notifications,
        _configService = configService {
    // Сохраняем начальный путь для обнаружения изменений
    _lastWatchPath = _configService.currentConfig.watchPath;
    // Подписываемся на изменения конфигурации
    _configSub = _configService.configChanges.listen(_onConfigChanged);
  }

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

    // Отмечаем, что start() выполняется, чтобы корректно обрабатывать
    // изменения конфигурации, пришедшие в окно между чтением config и
    // фактическим завершением startWatching().
    _isStarting = true;

    // Получаем путь из конфигурации
    final watchPath = _configService.currentConfig.watchPath;

    _log.i('Using watch path from config: ${watchPath ?? "default (Desktop/Latera)"}');

    // Обновляем последний известный путь
    _lastWatchPath = watchPath;

    late final WatchResult result;
    try {
      result = await _watcher.startWatching(overridePath: watchPath);
    } finally {
      _isStarting = false;
    }

    final mapped = switch (result) {
      WatchSuccess(:final watchDir) => _onStartSuccess(watchDir),
      WatchFailure(:final error) => _onStartFailure(error),
    };

    // Если watchPath изменился во время await startWatching(),
    // watcher мог запуститься на устаревшем пути.
    // Планируем сериализованный рестарт после успешного старта.
    final latestWatchPath = _configService.currentConfig.watchPath;
    if (latestWatchPath != watchPath &&
        _isRunning &&
        !_isDisposed &&
        !_isDisposing) {
      _log.i(
        'watchPath changed during start, scheduling restart: '
        '${watchPath ?? "default"} -> ${latestWatchPath ?? "default"}',
      );

      _restartRequested = true;
      if (_restartFuture == null) {
        _restartFuture = _performRestart().whenComplete(() {
          _restartFuture = null;
        });
        unawaited(_restartFuture);
      }
    }

    return mapped;
  }

  /// Обрабатывает изменения конфигурации.
  ///
  /// Перезапускает watcher только если watchPath действительно изменился.
  void _onConfigChanged(AppConfig config) {
    final newWatchPath = config.watchPath;
    
    // Перезапускаем только если watchPath изменился
    if (newWatchPath == _lastWatchPath) {
      _log.d('Config changed but watchPath unchanged, skipping restart');
      return;
    }
    
    _log.i('Watch path changed: ${_lastWatchPath ?? "default"} -> ${newWatchPath ?? "default"}');
    _lastWatchPath = newWatchPath;
    
    // Если координатор запущен или в процессе старта, запрашиваем restart.
    // Используем флаги для сериализации операций перезапуска.
    // Во время dispose() рестарт запрещён (иначе возможна гонка: start() после stop()).
    if ((_isRunning || _isStarting) && !_isDisposed && !_isDisposing) {
      _restartRequested = true;

      // Если мы ещё не в running-состоянии, не пытаемся выполнять stop/start прямо сейчас.
      // Иначе возможна гонка: stop() во время in-flight startWatching().
      if (!_isRunning) {
        _log.d('Config changed while starting, deferring restart');
        return;
      }

      // Сериализуем restarts через единственный Future-замок.
      // Это защищает от параллельных restart'ов и гарантирует,
      // что последующие изменения будут обработаны текущим циклом while.
      if (_restartFuture != null) {
        _log.d('Restart already scheduled/in progress, coalescing request');
        return;
      }

      _log.i('Restarting watcher due to watch path change');
      _restartFuture = _performRestart().whenComplete(() {
        _restartFuture = null;
      });
      unawaited(_restartFuture);
    }
  }
  
  /// Выполняет restart watcher'а с обработкой всех отложенных запросов.
  ///
  /// Гарантирует, что только один restart выполняется одновременно,
  /// а все отложенные запросы обрабатываются в одном цикле.
  Future<void> _performRestart() async {
    // Обрабатываем все отложенные запросы в одном цикле
    while (_restartRequested && !_isDisposed && !_isDisposing) {
      _restartRequested = false;

      try {
        final stopError = await stop();
        if (stopError != null) {
          throw stopError;
        }

        // Проверяем состояние после stop
        if (_isDisposed || _isDisposing) {
          _log.i('Coordinator disposed during restart, aborting');
          break;
        }

        // Если пришёл новый запрос во время stop, продолжаем цикл
        if (_restartRequested) {
          _log.i('New restart request during stop, continuing loop');
          continue;
        }

        await start();
      } catch (e, st) {
        _log.e(
          'Failed to restart watcher after config change',
          error: e,
          stackTrace: st,
        );
        // Сбрасываем флаг, чтобы следующие изменения могли инициировать restart
        _restartRequested = false;
        // При ошибке не повторяем попытку автоматически
        // Пользователь может перезапустить вручную
        break;
      }
    }
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
    if (_isDisposed || _isDisposing) return;

    // Важно: выставляем флаг как можно раньше, чтобы запретить рестарты,
    // которые могут быть инициированы через configChanges в момент dispose().
    _isDisposing = true;

    _log.i('Disposing file events coordinator');

    // 1) Отключаем источник рестартов.
    await _configSub?.cancel();
    _configSub = null;

    // 2) Дожидаемся in-flight рестарта, чтобы избежать ситуации,
    // когда restart продолжает работу после закрытия контроллера.
    final restartFuture = _restartFuture;
    if (restartFuture != null) {
      await restartFuture;
    }

    // 3) Останавливаем watcher.
    await stop();

    // 4) Закрываем поток UI-событий.
    await _controller.close();

    _isDisposed = true;
    _isDisposing = false;
    _log.i('File events coordinator disposed');
  }
}

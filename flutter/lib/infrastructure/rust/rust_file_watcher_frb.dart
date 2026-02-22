import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/core_error.dart';
import '../../domain/file_added_event.dart';
import '../../domain/file_watcher.dart';
import 'generated/api.dart' as rust_api;
import 'rust_core.dart';

/// Реальная реализация [`FileWatcher`](../../domain/file_watcher.dart:1) через
/// flutter_rust_bridge.
class RustFileWatcherFrb implements FileWatcher {
  final Logger _log;
  StreamController<FileAddedEvent>? _controller;
  StreamSubscription<rust_api.FileAddedEvent>? _sub;
  bool _isWatching = false;

  StreamController<FileAddedEvent> get _eventsController =>
      _controller ??= StreamController<FileAddedEvent>.broadcast();

  RustFileWatcherFrb({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _eventsController.stream;

  @override
  bool get isWatching => _isWatching;

  @override
  Future<WatchResult> startWatching({String? overridePath}) async {
    _log.i('Starting Rust file watcher...');

    // Инициализация Rust Core
    try {
      await RustCoreBootstrap.ensureInitialized();
    } catch (e, st) {
      _log.e('Failed to initialize RustCore', error: e, stackTrace: st);
      return WatchFailure(InitializationError.rustCore(e, st));
    }

    await rust_api.initLogging();

    // Если ранее watcher уже останавливался, то контроллер был закрыт.
    // Для нового запуска создаём новый controller.
    // Также закрываем старый контроллер если он есть и не закрыт (защита от утечек).
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;

    // Подписку делаем до старта watcher, чтобы не пропустить первые события.
    // Явно отменяем старую подписку перед созданием новой (защита от утечек)
    await _sub?.cancel();
    _sub = rust_api.onFileAdded().listen(
      (e) {
        _eventsController.add(
          FileAddedEvent(
            fileName: e.fileName,
            fullPath: e.fullPath,
            occurredAt: DateTime.fromMillisecondsSinceEpoch(e.occurredAtMs),
          ),
        );
      },
      onError: (Object error, StackTrace st) {
        _log.e('Rust stream error', error: error, stackTrace: st);
        // Не закрываем контроллер, а эмитим ошибку в поток
        _eventsController.addError(
          StreamError.fromRust(error, st),
          st,
        );
      },
      onDone: () {
        _log.i('Rust stream completed (onDone)');
        _isWatching = false;
        // Stream закрылся со стороны Rust - эмитим событие
        // но не закрываем контроллер, чтобы можно было перезапустить
      },
    );

    // Запуск watcher'а
    try {
      final watchDir = await rust_api.startWatching(overridePath: overridePath);
      _isWatching = true;
      _log.i('Rust watcher started. dir=$watchDir');
      return WatchSuccess(watchDir);
    } catch (e, st) {
      _log.e('Failed to start Rust watcher', error: e, stackTrace: st);
      // При ошибке запуска отменяем подписку, чтобы избежать утечки
      await _sub?.cancel();
      _sub = null;
      return WatchFailure(WatcherError.fromRust(e, st));
    }
  }

  @override
  Future<CoreError?> stopWatching() async {
    _log.i('Stopping Rust file watcher...');

    CoreError? error;

    // Сначала останавливаем Rust watcher
    try {
      await rust_api.stopWatching();
    } catch (e, st) {
      _log.w('stopWatching failed in Rust', error: e, stackTrace: st);
      error = WatcherError.fromRust(e, st);
    }

    // Отменяем подписку
    await _sub?.cancel();
    _sub = null;

    // Закрываем поток событий на Dart-стороне.
    final c = _controller;
    _controller = null;
    await c?.close();

    _isWatching = false;
    _log.i('Rust file watcher stopped');

    return error;
  }
}

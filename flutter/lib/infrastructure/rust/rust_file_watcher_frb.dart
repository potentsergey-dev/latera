import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

import '../../domain/core_error.dart';
import '../../domain/file_added_event.dart';
import '../../domain/file_removed_event.dart';
import '../../domain/file_watcher.dart';
import 'generated/api.dart' as rust_api;
import 'rust_core.dart';

/// Реальная реализация [`FileWatcher`](../../domain/file_watcher.dart:1) через
/// flutter_rust_bridge.
class RustFileWatcherFrb implements FileWatcher {
  final Logger _log;
  StreamController<FileAddedEvent>? _controller;
  StreamController<FileRemovedEvent>? _removedController;
  StreamSubscription<rust_api.FileAddedEvent>? _sub;
  StreamSubscription<FileSystemEvent>? _fsSub;
  bool _isWatching = false;

  StreamController<FileAddedEvent> get _eventsController =>
      _controller ??= StreamController<FileAddedEvent>.broadcast();

  StreamController<FileRemovedEvent> get _removedEventsController =>
      _removedController ??= StreamController<FileRemovedEvent>.broadcast();

  RustFileWatcherFrb({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _eventsController.stream;

  @override
  Stream<FileRemovedEvent> get fileRemovedEvents =>
      _removedEventsController.stream;

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

    if (_removedController != null && !_removedController!.isClosed) {
      await _removedController!.close();
    }
    _removedController = null;

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

      // Запускаем Dart-сторонний мониторинг удалений файлов
      _startDartDeleteWatcher(watchDir);

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

    // Отменяем Dart file system watcher
    await _fsSub?.cancel();
    _fsSub = null;

    // Закрываем поток событий на Dart-стороне.
    final c = _controller;
    _controller = null;
    await c?.close();

    final rc = _removedController;
    _removedController = null;
    await rc?.close();

    _isWatching = false;
    _log.i('Rust file watcher stopped');

    return error;
  }

  /// Запускает Dart-сторонний мониторинг удалений файлов через dart:io.
  ///
  /// Используем отдельный dart:io watcher, так как FRB codegen не работает
  /// на Windows для добавления новых stream'ов. После исправления codegen
  /// можно перенести на Rust stream.
  void _startDartDeleteWatcher(String watchDir) {
    _fsSub?.cancel();
    _fsSub = null;

    final dir = Directory(watchDir);
    if (!dir.existsSync()) {
      _log.w('Watch directory does not exist for delete monitoring: $watchDir');
      return;
    }

    _log.i('Starting Dart delete watcher for: $watchDir');
    _fsSub = dir.watch(events: FileSystemEvent.delete).listen(
      (event) {
        if (event is FileSystemDeleteEvent) {
          final path = event.path;
          final fileName = path.split(Platform.pathSeparator).last;
          _log.i('File deleted: $fileName ($path)');
          _removedEventsController.add(
            FileRemovedEvent(
              fileName: fileName,
              fullPath: path,
              occurredAt: DateTime.now(),
            ),
          );
        }
      },
      onError: (Object error, StackTrace st) {
        _log.e('Dart delete watcher error', error: error, stackTrace: st);
      },
    );
  }
}

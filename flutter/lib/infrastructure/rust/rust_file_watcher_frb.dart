import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/file_added_event.dart';
import '../../domain/file_watcher.dart';
import 'generated/api.dart' as rust_api;
import 'rust_core.dart';

/// Реальная реализация [`FileWatcher`](../../domain/file_watcher.dart:1) через
/// flutter_rust_bridge.
class RustFileWatcherFrb implements FileWatcher {
  final Logger _log;
  final _controller = StreamController<FileAddedEvent>.broadcast();
  StreamSubscription<rust_api.FileAddedEvent>? _sub;

  RustFileWatcherFrb({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  Future<void> startWatching({String? overridePath}) async {
    await RustCoreBootstrap.ensureInitialized();
    await rust_api.initLogging();

    // Подписку делаем до старта watcher, чтобы не пропустить первые события.
    _sub ??= rust_api.onFileAdded().listen((e) {
      _controller.add(
        FileAddedEvent(
          fileName: e.fileName,
          fullPath: e.fullPath,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(e.occurredAtMs),
        ),
      );
    });

    final watchDir = await rust_api.startWatching(overridePath: overridePath);
    _log.i('Rust watcher started. dir=$watchDir');
  }

  @override
  Future<void> stopWatching() async {
    try {
      await rust_api.stopWatching();
    } catch (e, st) {
      _log.w('stopWatching failed (ignored): $e', error: e, stackTrace: st);
    }
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}


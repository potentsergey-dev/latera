import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/core_error.dart';
import '../../domain/file_added_event.dart';
import '../../domain/file_watcher.dart';

/// Заглушка watcher.
///
/// Это безопасная `no-op` реализация, чтобы проект компилировался без Rust.
///
/// После подключения Rust core этот класс будет заменён на реализацию,
/// вызывающую FRB-сгенерированный API и отдающую реальные события.
class RustFileWatcherStub implements FileWatcher {
  final Logger _log;
  final _controller = StreamController<FileAddedEvent>.broadcast();
  bool _isWatching = false;

  RustFileWatcherStub({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  bool get isWatching => _isWatching;

  @override
  Future<WatchResult> startWatching({String? overridePath}) async {
    _log.w(
      'Rust core is not connected yet. startWatching(overridePath=$overridePath) ignored.',
    );
    _isWatching = true;
    return const WatchSuccess('(stub - no Rust core)');
  }

  @override
  Future<CoreError?> stopWatching() async {
    _log.w('Rust core is not connected yet. stopWatching() called.');
    _isWatching = false;
    await _controller.close();
    return null;
  }
}

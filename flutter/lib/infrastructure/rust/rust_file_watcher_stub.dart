import 'dart:async';

import 'package:logger/logger.dart';

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

  RustFileWatcherStub({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  Future<void> startWatching({String? overridePath}) async {
    _log.w(
      'Rust core is not connected yet. startWatching(overridePath=$overridePath) ignored.',
    );
  }

  @override
  Future<void> stopWatching() async {
    _log.w('Rust core is not connected yet. stopWatching() called.');
    await _controller.close();
  }
}


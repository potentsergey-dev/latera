import 'dart:async';

import 'package:logger/logger.dart';

import '../../domain/core_error.dart';
import '../../domain/file_added_event.dart';
import '../../domain/file_removed_event.dart';
import '../../domain/file_watcher.dart';

/// Заглушка watcher.
///
/// Это безопасная `no-op` реализация, чтобы проект компилировался без Rust.
///
/// После подключения Rust core этот класс будет заменён на реализацию,
/// вызывающую FRB-сгенерированный API и отдающую реальные события.
class RustFileWatcherStub implements FileWatcher {
  final Logger _log;
  StreamController<FileAddedEvent>? _controller;
  StreamController<FileRemovedEvent>? _removedController;
  bool _isWatching = false;

  /// Lazy-initialized broadcast controller.
  ///
  /// Recreated if accessed after [stopWatching] to support multiple start/stop cycles.
  /// Note: When [stopWatching] is called, the current controller is closed and
  /// all existing subscribers will receive a 'done' event. Subscribers must
  /// re-subscribe to [fileAddedEvents] after a new [startWatching] call.
  StreamController<FileAddedEvent> get _eventsController =>
      _controller ??= StreamController<FileAddedEvent>.broadcast();

  RustFileWatcherStub({required Logger logger}) : _log = logger;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _eventsController.stream;

  @override
  Stream<FileRemovedEvent> get fileRemovedEvents =>
      (_removedController ??= StreamController<FileRemovedEvent>.broadcast()).stream;

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
    final c = _controller;
    _controller = null;
    await c?.close();
    final rc = _removedController;
    _removedController = null;
    await rc?.close();
    return null;
  }
}

import 'dart:async';

import 'package:logger/logger.dart';

import '../domain/file_added_event.dart';
import '../domain/file_watcher.dart';
import '../infrastructure/notifications/local_notifications_service.dart';

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

/// Application-layer координатор:
/// - стартует watcher
/// - слушает domain-события
/// - применяет политику уведомлений
class FileEventsCoordinator {
  final Logger _log;
  final FileWatcher _watcher;
  final LocalNotificationsService _notifications;

  final _controller = StreamController<FileAddedUiEvent>.broadcast();
  StreamSubscription<FileAddedEvent>? _sub;

  FileEventsCoordinator({
    required Logger logger,
    required FileWatcher watcher,
    required LocalNotificationsService notifications,
  })  : _log = logger,
        _watcher = watcher,
        _notifications = notifications;

  Stream<FileAddedUiEvent> get fileAddedEvents => _controller.stream;

  Future<void> start() async {
    _log.i('Starting file events coordinator');
    await _watcher.startWatching();
    _sub = _watcher.fileAddedEvents.listen((event) async {
      _controller.add(FileAddedUiEvent.fromDomain(event));

      // Политика: уведомлять всегда.
      await _notifications.showFileAdded(fileName: event.fileName);
    });
  }

  Future<void> stop() async {
    _log.i('Stopping file events coordinator');
    await _sub?.cancel();
    _sub = null;
    await _watcher.stopWatching();
    await _controller.close();
  }
}


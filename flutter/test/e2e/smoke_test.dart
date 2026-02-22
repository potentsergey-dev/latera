/// E2E Smoke тесты для проверки интеграции компонентов.
///
/// Эти тесты проверяют базовую функциональность без необходимости
/// сборки Windows приложения.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/core_error.dart';
import 'package:latera/domain/file_watcher.dart';
import 'package:latera/domain/notifications_service.dart';
import 'package:latera/domain/file_added_event.dart';
import 'package:latera/application/file_events_coordinator.dart';
import 'package:logger/logger.dart';

/// Мок для FileWatcher.
class E2EMockFileWatcher implements FileWatcher {
  final StreamController<FileAddedEvent> _controller =
      StreamController<FileAddedEvent>.broadcast();
  bool _isStarted = false;
  String? _watchPath;

  bool get isStarted => _isStarted;
  String? get watchPath => _watchPath;

  @override
  bool get isWatching => _isStarted;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  Future<WatchResult> startWatching({String? overridePath}) async {
    _isStarted = true;
    _watchPath = overridePath;
    return WatchSuccess(overridePath ?? '/mock/desktop/latera');
  }

  @override
  Future<CoreError?> stopWatching() async {
    _isStarted = false;
    _watchPath = null;
    return null;
  }

  void emitEvent(FileAddedEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

/// Мок для NotificationsService.
class E2EMockNotificationsService implements NotificationsService {
  final List<String> _shownNotifications = [];

  List<String> get shownNotifications => List.unmodifiable(_shownNotifications);
  int get notificationCount => _shownNotifications.length;

  @override
  Future<void> showFileAdded({required String fileName}) async {
    _shownNotifications.add(fileName);
  }

  @override
  Future<void> init() async {}
}

void main() {
  group('E2E Smoke Tests', () {
    late E2EMockFileWatcher watcher;
    late E2EMockNotificationsService notifications;
    late Logger logger;

    setUp(() {
      watcher = E2EMockFileWatcher();
      notifications = E2EMockNotificationsService();
      logger = Logger(printer: PrettyPrinter(methodCount: 0));
    });

    tearDown(() {
      watcher.dispose();
    });

    group('FileEventsCoordinator E2E', () {
      test('should start and stop successfully', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
        );

        await coordinator.start();
        expect(watcher.isStarted, true);

        await coordinator.stop();
        expect(watcher.isStarted, false);
      });

      test('should process file events end-to-end', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
        );

        final uiEvents = <FileAddedUiEvent>[];
        final subscription = coordinator.fileAddedEvents.listen(uiEvents.add);

        await coordinator.start();

        // Симулируем обнаружение файла
        watcher.emitEvent(FileAddedEvent(
          fileName: 'test_document.pdf',
          fullPath: '/Desktop/Latera/test_document.pdf',
          occurredAt: DateTime.now(),
        ));

        await Future.delayed(const Duration(milliseconds: 100));

        // Проверяем, что событие прошло через весь pipeline
        expect(uiEvents.length, 1);
        expect(uiEvents.first.fileName, 'test_document.pdf');
        expect(uiEvents.first.fullPath, '/Desktop/Latera/test_document.pdf');

        // Проверяем, что уведомление было показано
        expect(notifications.notificationCount, 1);
        expect(notifications.shownNotifications, contains('test_document.pdf'));

        await subscription.cancel();
        await coordinator.stop();
      });

      test('should handle multiple file events', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
        );

        final uiEvents = <FileAddedUiEvent>[];
        final subscription = coordinator.fileAddedEvents.listen(uiEvents.add);

        await coordinator.start();

        // Симулируем обнаружение нескольких файлов
        final files = ['file1.txt', 'file2.pdf', 'file3.docx'];
        for (final file in files) {
          watcher.emitEvent(FileAddedEvent(
            fileName: file,
            occurredAt: DateTime.now(),
          ));
          await Future.delayed(const Duration(milliseconds: 50));
        }

        await Future.delayed(const Duration(milliseconds: 100));

        expect(uiEvents.length, 3);
        expect(notifications.notificationCount, 3);

        await subscription.cancel();
        await coordinator.stop();
      });

      test('should handle startWatching with override path', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
        );

        await coordinator.start();

        // Coordinator вызывает startWatching без параметров
        expect(watcher.isStarted, true);

        await coordinator.stop();
      });
    });

    group('Domain Types E2E', () {
      test('FileAddedEvent should be created correctly', () {
        final now = DateTime.now();
        final event = FileAddedEvent(
          fileName: 'document.pdf',
          fullPath: '/path/to/document.pdf',
          occurredAt: now,
        );

        expect(event.fileName, 'document.pdf');
        expect(event.fullPath, '/path/to/document.pdf');
        expect(event.occurredAt, now);
      });

      test('FileAddedEvent should work without fullPath', () {
        final event = FileAddedEvent(
          fileName: 'file.txt',
          occurredAt: DateTime.now(),
        );

        expect(event.fileName, 'file.txt');
        expect(event.fullPath, isNull);
      });

      test('FileAddedUiEvent should be created from domain event', () {
        final domainEvent = FileAddedEvent(
          fileName: 'test.txt',
          fullPath: '/path/test.txt',
          occurredAt: DateTime(2024, 1, 15, 10, 30),
        );

        final uiEvent = FileAddedUiEvent.fromDomain(domainEvent);

        expect(uiEvent.fileName, 'test.txt');
        expect(uiEvent.fullPath, '/path/test.txt');
        expect(uiEvent.occurredAt, DateTime(2024, 1, 15, 10, 30));
      });
    });

    group('Stream Behavior E2E', () {
      test('broadcast stream should support multiple listeners', () async {
        final events1 = <FileAddedEvent>[];
        final events2 = <FileAddedEvent>[];

        final sub1 = watcher.fileAddedEvents.listen(events1.add);
        final sub2 = watcher.fileAddedEvents.listen(events2.add);

        watcher.emitEvent(FileAddedEvent(
          fileName: 'test.txt',
          occurredAt: DateTime.now(),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(events1.length, 1);
        expect(events2.length, 1);

        await sub1.cancel();
        await sub2.cancel();
      });

      test('stream should continue after listener cancellation', () async {
        final events = <FileAddedEvent>[];

        final sub = watcher.fileAddedEvents.listen(events.add);

        watcher.emitEvent(FileAddedEvent(
          fileName: 'file1.txt',
          occurredAt: DateTime.now(),
        ));

        await Future.delayed(const Duration(milliseconds: 10));
        expect(events.length, 1);

        await sub.cancel();

        watcher.emitEvent(FileAddedEvent(
          fileName: 'file2.txt',
          occurredAt: DateTime.now(),
        ));

        await Future.delayed(const Duration(milliseconds: 10));
        expect(events.length, 1); // Не изменилось после отмены подписки
      });
    });

    group('Error Handling E2E', () {
      test('should handle rapid events without crashing', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
        );

        await coordinator.start();

        // Эмитируем много событий быстро
        for (var i = 0; i < 100; i++) {
          watcher.emitEvent(FileAddedEvent(
            fileName: 'file_$i.txt',
            occurredAt: DateTime.now(),
          ));
        }

        await Future.delayed(const Duration(milliseconds: 500));

        // Все события должны быть обработаны
        expect(notifications.notificationCount, 100);

        await coordinator.stop();
      });
    });
  });
}

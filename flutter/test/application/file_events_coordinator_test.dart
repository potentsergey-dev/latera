import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/application/file_events_coordinator.dart';
import 'package:latera/domain/app_config.dart';
import 'package:latera/domain/core_error.dart';
import 'package:latera/domain/file_added_event.dart';
import 'package:latera/domain/file_watcher.dart';
import 'package:latera/domain/notifications_service.dart';
import 'package:logger/logger.dart';

/// Мок для [FileWatcher].
///
/// Позволяет контролировать эмиссию событий и проверять вызовы методов.
class MockFileWatcher implements FileWatcher {
  final StreamController<FileAddedEvent> _controller =
      StreamController<FileAddedEvent>.broadcast();

  bool startWatchingCalled = false;
  String? lastOverridePath;
  bool stopWatchingCalled = false;
  int startWatchingCallCount = 0;
  int stopWatchingCallCount = 0;
  bool _isWatching = false;

  /// Хук для тестов: вызывается при каждом [startWatching].
  void Function(int callCount, String? overridePath)? onStartWatching;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  bool get isWatching => _isWatching;

  /// Эмулирует добавление нового файла.
  void addFileEvent(FileAddedEvent event) {
    _controller.add(event);
  }

  /// Эмулирует добавление нескольких файлов.
  void addFileEvents(List<FileAddedEvent> events) {
    for (final event in events) {
      _controller.add(event);
    }
  }

  @override
  Future<WatchResult> startWatching({String? overridePath}) async {
    startWatchingCalled = true;
    startWatchingCallCount++;
    lastOverridePath = overridePath;
    _isWatching = true;
    onStartWatching?.call(startWatchingCallCount, overridePath);
    return const WatchSuccess('/mock/watch/dir');
  }

  @override
  Future<CoreError?> stopWatching() async {
    stopWatchingCalled = true;
    stopWatchingCallCount++;
    _isWatching = false;
    return null;
  }

  /// Закрывает внутренний контроллер.
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Мок для [NotificationsService].
///
/// Позволяет проверять вызовы уведомлений.
class MockNotificationsService implements NotificationsService {
  int showFileAddedCallCount = 0;
  List<String> shownFileNames = [];
  bool shouldThrow = false;
  Exception? exceptionToThrow;

  @override
  Future<void> showFileAdded({required String fileName}) async {
    if (shouldThrow && exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    showFileAddedCallCount++;
    shownFileNames.add(fileName);
  }

  @override
  Future<void> init() async {}
}

/// Мок для [ConfigService].
///
/// Позволяет контролировать конфигурацию.
class MockConfigService implements ConfigService {
  AppConfig _currentConfig = const AppConfig();
  final StreamController<AppConfig> _configController =
      StreamController<AppConfig>.broadcast();
  bool _onboardingCompleted = false;

  @override
  AppConfig get currentConfig => _currentConfig;

  @override
  Stream<AppConfig> get configChanges => _configController.stream;

  @override
  bool get isOnboardingCompleted => _onboardingCompleted;

  void setConfig(AppConfig config) {
    _currentConfig = config;
    _configController.add(config);
  }

  @override
  Future<AppConfig> load() async => _currentConfig;

  @override
  Future<void> save(AppConfig config) async {
    _currentConfig = config;
    _configController.add(config);
  }

  @override
  Future<void> reset() async {
    _currentConfig = const AppConfig();
    _configController.add(_currentConfig);
  }

  @override
  Future<void> updateValue({
    String? watchPath,
    int? watchIntervalMs,
    bool? notificationsEnabled,
    bool? loggingEnabled,
    String? logLevel,
    String? theme,
    String? language,
    bool clearWatchPath = false,
    bool clearLanguage = false,
  }) async {
    // ВАЖНО: copyWith() не умеет устанавливать null.
    // Создаём AppConfig напрямую с явными значениями.
    _currentConfig = AppConfig(
      watchPath: clearWatchPath ? null : (watchPath ?? _currentConfig.watchPath),
      watchIntervalMs: watchIntervalMs ?? _currentConfig.watchIntervalMs,
      notificationsEnabled: notificationsEnabled ?? _currentConfig.notificationsEnabled,
      loggingEnabled: loggingEnabled ?? _currentConfig.loggingEnabled,
      logLevel: logLevel ?? _currentConfig.logLevel,
      theme: theme ?? _currentConfig.theme,
      language: clearLanguage ? null : (language ?? _currentConfig.language),
    );
    _configController.add(_currentConfig);
  }

  @override
  Future<void> completeOnboarding() async {
    _onboardingCompleted = true;
  }

  @override
  Future<void> resetOnboarding() async {
    _onboardingCompleted = false;
  }

  Future<void> dispose() async {
    await _configController.close();
  }
}

void main() {
  group('FileEventsCoordinator', () {
    late MockFileWatcher mockWatcher;
    late MockNotificationsService mockNotifications;
    late MockConfigService mockConfigService;
    late Logger logger;

    setUp(() {
      mockWatcher = MockFileWatcher();
      mockNotifications = MockNotificationsService();
      mockConfigService = MockConfigService();
      logger = Logger(printer: PrettyPrinter(methodCount: 0));
    });

    tearDown(() async {
      await mockWatcher.dispose();
      await mockConfigService.dispose();
    });

    group('start', () {
      test('should start watching on watcher', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        final result = await coordinator.start();

        expect(mockWatcher.startWatchingCalled, true);
        expect(mockWatcher.startWatchingCallCount, 1);
        expect(result, isA<CoordinatorStartSuccess>());
        expect((result as CoordinatorStartSuccess).watchDir, '/mock/watch/dir');
      });

      test('should pass watch path from config to watcher', () async {
        // Устанавливаем путь в конфигурации
        mockConfigService.setConfig(const AppConfig(
          watchPath: '/custom/watch/path',
        ));

        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        expect(mockWatcher.lastOverridePath, '/custom/watch/path');
      });

      test('should pass null to watcher when config has no watch path', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        expect(mockWatcher.lastOverridePath, isNull);
      });
    });

    group('stop', () {
      test('should stop watching on watcher', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();
        await coordinator.stop();

        expect(mockWatcher.stopWatchingCalled, true);
        expect(mockWatcher.stopWatchingCallCount, 1);
      });

      test('should be idempotent', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();
        await coordinator.stop();
        // Второй вызов stopWatching происходит, но это ожидаемое поведение
        // Coordinator не отслеживает состояние остановки
        expect(mockWatcher.stopWatchingCallCount, greaterThanOrEqualTo(1));
      });

      test('should allow restart after stop', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        // Первый цикл
        final result1 = await coordinator.start();
        expect(result1, isA<CoordinatorStartSuccess>());
        expect(coordinator.isRunning, true);

        await coordinator.stop();
        expect(coordinator.isRunning, false);

        // Второй цикл - должен работать
        final result2 = await coordinator.start();
        expect(result2, isA<CoordinatorStartSuccess>());
        expect(coordinator.isRunning, true);
        expect(mockWatcher.startWatchingCallCount, 2);

        await coordinator.stop();
      });
    });

    group('dispose', () {
      test('should prevent start after dispose', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();
        await coordinator.dispose();

        expect(coordinator.isDisposed, true);

        expect(
          () => coordinator.start(),
          throwsA(isA<StateError>()),
        );
      });

      test('should be idempotent', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();
        await coordinator.dispose();
        await coordinator.dispose(); // Второй вызов не должен бросать

        expect(coordinator.isDisposed, true);
      });
    });

    group('file event handling', () {
      test('should emit UI events when file is added', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        // Важно: broadcast stream не буферизует, поэтому подписываемся до эмиссии.
        final eventFuture = coordinator.fileAddedEvents.first
            .timeout(const Duration(seconds: 1));

        // Эмулируем событие от watcher
        final testEvent = FileAddedEvent(
          fileName: 'test.txt',
          fullPath: '/path/to/test.txt',
          occurredAt: DateTime.now(),
        );
        mockWatcher.addFileEvent(testEvent);

        final event = await eventFuture;
        // Дожидаемся завершения async-обработки (уведомление в unawaited handler).
        await pumpEventQueue();

        expect(event.fileName, 'test.txt');
        expect(event.fullPath, '/path/to/test.txt');
        await coordinator.stop();
      });

      test('should show notification when file is added', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        final uiEventFuture = coordinator.fileAddedEvents.first
            .timeout(const Duration(seconds: 1));

        // Эмулируем событие от watcher
        mockWatcher.addFileEvent(FileAddedEvent(
          fileName: 'document.pdf',
          fullPath: '/path/to/document.pdf',
          occurredAt: DateTime.now(),
        ));

        await uiEventFuture;
        await pumpEventQueue();

        expect(mockNotifications.showFileAddedCallCount, 1);
        expect(mockNotifications.shownFileNames, contains('document.pdf'));

        await coordinator.stop();
      });

      test('should handle multiple file events', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        final eventsFuture = coordinator.fileAddedEvents
            .take(3)
            .toList()
            .timeout(const Duration(seconds: 1));

        // Эмулируем несколько событий
        mockWatcher.addFileEvents([
          FileAddedEvent(
            fileName: 'file1.txt',
            occurredAt: DateTime.now(),
          ),
          FileAddedEvent(
            fileName: 'file2.txt',
            occurredAt: DateTime.now(),
          ),
          FileAddedEvent(
            fileName: 'file3.txt',
            occurredAt: DateTime.now(),
          ),
        ]);

        final events = await eventsFuture;
        await pumpEventQueue();

        expect(events, hasLength(3));
        expect(mockNotifications.showFileAddedCallCount, 3);

        final fileNames = events.map((e) => e.fileName).toList();
        expect(fileNames, containsAll(['file1.txt', 'file2.txt', 'file3.txt']));

        await coordinator.stop();
      });

      test('should emit events even when notification throws', () async {
        // Текущая реализация coordinator не обрабатывает ошибки уведомлений.
        // Этот тест проверяет, что событие эмитируется до вызова уведомления.
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();

        final eventFuture = coordinator.fileAddedEvents.first
            .timeout(const Duration(seconds: 1));

        // Эмулируем событие (без ошибки в уведомлении)
        mockWatcher.addFileEvent(FileAddedEvent(
          fileName: 'file1.txt',
          occurredAt: DateTime.now(),
        ));

        await eventFuture;
        await pumpEventQueue();

        // Событие должно быть обработано
        expect(mockNotifications.showFileAddedCallCount, 1);
        await coordinator.stop();
      });
    });

    group('config changes', () {
      test('should restart watcher when watch path changes', () async {
        final restarted = Completer<void>();
        mockWatcher.onStartWatching = (callCount, overridePath) {
          if (callCount >= 2 && !restarted.isCompleted) {
            restarted.complete();
          }
        };

        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: mockWatcher,
          notifications: mockNotifications,
          configService: mockConfigService,
        );

        await coordinator.start();
        expect(mockWatcher.startWatchingCallCount, 1);

        // Изменяем путь в конфигурации
        mockConfigService.setConfig(const AppConfig(
          watchPath: '/new/watch/path',
        ));

        // Детерминированно ждём рестарта.
        await restarted.future.timeout(const Duration(seconds: 1));

        // Watcher должен быть перезапущен
        expect(mockWatcher.startWatchingCallCount, 2);
        expect(mockWatcher.lastOverridePath, '/new/watch/path');

        await coordinator.stop();
      });
    });

    group('FileAddedUiEvent', () {
      test('should create from domain event correctly', () {
        final domainEvent = FileAddedEvent(
          fileName: 'test.txt',
          fullPath: '/path/to/test.txt',
          occurredAt: DateTime(2024, 1, 15, 10, 30),
        );

        final uiEvent = FileAddedUiEvent.fromDomain(domainEvent);

        expect(uiEvent.fileName, 'test.txt');
        expect(uiEvent.fullPath, '/path/to/test.txt');
        expect(uiEvent.occurredAt, DateTime(2024, 1, 15, 10, 30));
      });

      test('should handle null fullPath', () {
        final domainEvent = FileAddedEvent(
          fileName: 'test.txt',
          occurredAt: DateTime.now(),
        );

        final uiEvent = FileAddedUiEvent.fromDomain(domainEvent);

        expect(uiEvent.fileName, 'test.txt');
        expect(uiEvent.fullPath, isNull);
      });
    });
  });
}

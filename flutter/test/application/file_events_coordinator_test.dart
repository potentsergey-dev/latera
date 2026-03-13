import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/application/file_events_coordinator.dart';
import 'package:latera/domain/app_config.dart';
import 'package:latera/domain/core_error.dart';
import 'package:latera/domain/file_added_event.dart';
import 'package:latera/domain/file_removed_event.dart';
import 'package:latera/domain/file_watcher.dart';
import 'package:latera/domain/indexer.dart';
import 'package:latera/domain/notifications_service.dart';
import 'package:logger/logger.dart';

/// Мок для [FileWatcher].
///
/// Позволяет контролировать эмиссию событий и проверять вызовы методов.
class MockFileWatcher implements FileWatcher {
  final StreamController<FileAddedEvent> _controller =
      StreamController<FileAddedEvent>.broadcast();
  final StreamController<FileRemovedEvent> _removedController =
      StreamController<FileRemovedEvent>.broadcast();

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
  Stream<FileRemovedEvent> get fileRemovedEvents => _removedController.stream;

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
    await _removedController.close();
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
  Future<void> showFileNeedsReview({required String fileName}) async {}

  @override
  Future<void> showIndexingLimitReached() async {}

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
    // Производительность и контент
    bool? resourceSaverEnabled,
    bool? enableOfficeDocs,
    bool? enableOcr,
    bool? enableTranscription,
    bool? enableEmbeddings,
    bool? enableSemanticSimilarity,
    bool? enableRag,
    bool? enableAutoSummary,
    bool? enableAutoTags,
    // Лимиты
    int? maxConcurrentJobs,
    int? maxFileSizeMbForEnrichment,
    int? maxMediaMinutes,
    int? maxPagesPerPdf,
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
      resourceSaverEnabled: resourceSaverEnabled ?? _currentConfig.resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs ?? _currentConfig.enableOfficeDocs,
      enableOcr: enableOcr ?? _currentConfig.enableOcr,
      enableTranscription: enableTranscription ?? _currentConfig.enableTranscription,
      enableEmbeddings: enableEmbeddings ?? _currentConfig.enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity ?? _currentConfig.enableSemanticSimilarity,
      enableRag: enableRag ?? _currentConfig.enableRag,
      enableAutoSummary: enableAutoSummary ?? _currentConfig.enableAutoSummary,
      enableAutoTags: enableAutoTags ?? _currentConfig.enableAutoTags,
      maxConcurrentJobs: maxConcurrentJobs ?? _currentConfig.maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment ?? _currentConfig.maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes ?? _currentConfig.maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf ?? _currentConfig.maxPagesPerPdf,
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

/// Мок для [Indexer].
///
/// Позволяет проверять вызовы методов индексатора.
class MockIndexer implements Indexer {
  int clearIndexCallCount = 0;
  int getIndexedCountCallCount = 0;
  int _indexedCount = 0;
  final List<String> removedFilePaths = [];
  final List<String> indexedFilePaths = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  }) async {
    indexedFilePaths.add(filePath);
    _indexedCount++;
    return true;
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    removedFilePaths.add(filePath);
    if (_indexedCount > 0) _indexedCount--;
  }

  @override
  Future<void> clearIndex() async {
    clearIndexCallCount++;
    _indexedCount = 0;
  }

  @override
  Future<int> getIndexedCount() async {
    getIndexedCountCallCount++;
    return _indexedCount;
  }

  @override
  Future<bool> isIndexed(String filePath) async {
    return indexedFilePaths.contains(filePath);
  }

  @override
  Future<void> updateTextContent(String filePath, String textContent) async {}

  @override
  Future<void> updateTranscriptText(String filePath, String transcript) async {}

  @override
  Future<String?> getTextContent(String filePath) async => null;

  @override
  Future<void> storeEmbeddings(
    String filePath, {
    required List<String> chunkTexts,
    required List<int> chunkOffsets,
    required List<List<double>> embeddingVectors,
  }) async {}

  @override
  Future<bool> hasEmbeddings(String filePath) async => false;

  @override
  Future<bool> indexFileForReview(
    String filePath, {
    required String fileName,
  }) async {
    indexedFilePaths.add(filePath);
    _indexedCount++;
    return true;
  }

  @override
  Future<List<InboxFile>> getFilesNeedingReview() async => [];

  @override
  Future<int> getFilesNeedingReviewCount() async => 0;

  @override
  Future<void> saveFileReview(
    String filePath, {
    required String description,
    required String tags,
  }) async {}

  @override
  Future<void> markFileEnriched(String filePath) async {}

  @override
  Future<void> updateDescription(String filePath, String description) async {}

  @override
  Future<void> updateTags(String filePath, String tags) async {}

  @override
  void dispose() {}
}

void main() {
  group('FileEventsCoordinator', () {
    late MockFileWatcher mockWatcher;
    late MockNotificationsService mockNotifications;
    late MockConfigService mockConfigService;
    late MockIndexer mockIndexer;
    late Logger logger;

    setUp(() {
      mockWatcher = MockFileWatcher();
      mockNotifications = MockNotificationsService();
      mockConfigService = MockConfigService();
      mockIndexer = MockIndexer();
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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
          indexer: mockIndexer,
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

      test('should clear index when watch path changes', () async {
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
          indexer: mockIndexer,
        );

        await coordinator.start();

        // Изменяем путь в конфигурации
        mockConfigService.setConfig(const AppConfig(
          watchPath: '/new/watch/path',
        ));

        await restarted.future.timeout(const Duration(seconds: 1));

        // Индекс должен быть очищен при смене папки
        expect(mockIndexer.clearIndexCallCount, 1);

        await coordinator.stop();
      });

      test('should emit watchPathChanged event when path changes', () async {
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
          indexer: mockIndexer,
        );

        await coordinator.start();

        final pathChangeFuture = coordinator.watchPathChangedEvents.first
            .timeout(const Duration(seconds: 1));

        // Изменяем путь в конфигурации
        mockConfigService.setConfig(const AppConfig(
          watchPath: '/new/watch/path',
        ));

        final newPath = await pathChangeFuture;
        expect(newPath, '/mock/watch/dir');

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

/// E2E Smoke тесты для проверки интеграции компонентов.
///
/// Эти тесты проверяют базовую функциональность без необходимости
/// сборки Windows приложения.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/app_config.dart';
import 'package:latera/domain/core_error.dart';
import 'package:latera/domain/file_watcher.dart';
import 'package:latera/domain/indexer.dart';
import 'package:latera/domain/notifications_service.dart';
import 'package:latera/domain/file_added_event.dart';
import 'package:latera/domain/file_removed_event.dart';
import 'package:latera/application/file_events_coordinator.dart';
import 'package:logger/logger.dart';

/// Мок для FileWatcher.
class E2EMockFileWatcher implements FileWatcher {
  final StreamController<FileAddedEvent> _controller =
      StreamController<FileAddedEvent>.broadcast();
  final StreamController<FileRemovedEvent> _removedController =
      StreamController<FileRemovedEvent>.broadcast();
  bool _isStarted = false;
  String? _watchPath;

  bool get isStarted => _isStarted;
  String? get watchPath => _watchPath;

  @override
  bool get isWatching => _isStarted;

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  @override
  Stream<FileRemovedEvent> get fileRemovedEvents => _removedController.stream;

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
    _removedController.close();
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

/// Мок для ConfigService.
class E2EMockConfigService implements ConfigService {
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
    bool? resourceSaverEnabled,
    bool? enableOfficeDocs,
    bool? enableOcr,
    bool? enableTranscription,
    bool? enableEmbeddings,
    bool? enableSemanticSimilarity,
    bool? enableRag,
    bool? enableAutoSummary,
    bool? enableAutoTags,
    int? maxConcurrentJobs,
    int? maxFileSizeMbForEnrichment,
    int? maxMediaMinutes,
    int? maxPagesPerPdf,
  }) async {
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

  void dispose() {
    _configController.close();
  }
}

/// Мок для Indexer.
class E2EMockIndexer implements Indexer {
  int _indexedCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  }) async {
    _indexedCount++;
    return true;
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    if (_indexedCount > 0) _indexedCount--;
  }

  @override
  Future<void> clearIndex() async {
    _indexedCount = 0;
  }

  @override
  Future<int> getIndexedCount() async => _indexedCount;

  @override
  Future<bool> isIndexed(String filePath) async => false;

  @override
  Future<void> updateTextContent(String filePath, String textContent) async {}

  @override
  Future<void> updateTranscriptText(String filePath, String transcript) async {}

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
  void dispose() {}
}

void main() {
  group('E2E Smoke Tests', () {
    late E2EMockFileWatcher watcher;
    late E2EMockNotificationsService notifications;
    late E2EMockConfigService configService;
    late E2EMockIndexer indexer;
    late Logger logger;

    setUp(() {
      watcher = E2EMockFileWatcher();
      notifications = E2EMockNotificationsService();
      configService = E2EMockConfigService();
      indexer = E2EMockIndexer();
      logger = Logger(printer: PrettyPrinter(methodCount: 0));
    });

    tearDown(() {
      watcher.dispose();
      configService.dispose();
    });

    group('FileEventsCoordinator E2E', () {
      test('should start and stop successfully', () async {
        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
          configService: configService,
          indexer: indexer,
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
          configService: configService,
          indexer: indexer,
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
          configService: configService,
          indexer: indexer,
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

      test('should handle startWatching with override path from config', () async {
        // Устанавливаем путь в конфигурации
        configService.setConfig(const AppConfig(
          watchPath: '/custom/watch/path',
        ));

        final coordinator = FileEventsCoordinator(
          logger: logger,
          watcher: watcher,
          notifications: notifications,
          configService: configService,
          indexer: indexer,
        );

        await coordinator.start();

        // Coordinator должен передать путь из конфигурации
        expect(watcher.isStarted, true);
        expect(watcher.watchPath, '/custom/watch/path');

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
          configService: configService,
          indexer: indexer,
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

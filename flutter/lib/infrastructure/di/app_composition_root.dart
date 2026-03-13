import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/content_enrichment_coordinator.dart';
import '../../application/file_events_coordinator.dart';
import '../../application/license_coordinator.dart';
import '../../domain/app_config.dart';
import '../../domain/auto_summary.dart';
import '../../domain/auto_tags.dart';
import '../../domain/feature_flags.dart';
import '../../domain/file_watcher.dart';
import '../../domain/indexer.dart';
import '../../domain/license_service.dart';
import '../../domain/notifications_service.dart';
import '../../domain/ocr.dart';
import '../../domain/rag.dart';
import '../../domain/search_repository.dart';
import '../../domain/text_extraction.dart';
import '../../domain/transcription.dart';
import '../config/shared_preferences_config_service.dart';
import '../licensing/local_license_service.dart';
import '../licensing/store_purchase_service.dart';
import '../licensing/stub_feature_flags.dart';
import '../licensing/stub_license_service.dart';
import '../logging/app_logger.dart';
import '../notifications/local_notifications_service.dart';
import '../rust/rust_file_watcher_frb.dart';
import '../rust/stub_audio_transcriber.dart';
import '../rust/stub_auto_summary_service.dart';
import '../rust/stub_auto_tags_service.dart';
import '../rust/rust_ffi_auto_summary_service.dart';
import '../rust/rust_ffi_auto_tags_service.dart';
import '../rust/rust_ffi_embedding_service.dart';
import '../rust/rust_ffi_system_service.dart';
import '../rust/stub_embedding_service.dart';
import '../rust/rust_ocr_service.dart';
import '../rust/stub_ocr_service.dart';
import '../rust/rust_rag_service.dart';
import '../rust/generated/api.dart' as rust_api;
import '../rust/rust_core.dart';
import '../extraction/dart_rich_text_extractor.dart';
import '../llm/llm_download_service.dart';
import '../search/sqlite_index_service.dart';

/// Конфигурация окружения приложения.
enum AppEnvironment {
  development,
  production,
}

/// Composition Root (точка сборки зависимостей).
///
/// Централизованная точка создания и конфигурации всех зависимостей приложения.
/// Следует принципу Dependency Injection через конструктор.
class AppCompositionRoot {
  // === Domain Services ===
  final NotificationsService notifications;
  final FileWatcher fileWatcher;
  final LicenseService licenseService;
  final FeatureFlags featureFlags;
  final ConfigService configService;
  final Indexer indexer;
  final SearchRepository searchRepository;
  final RagService ragService;

  // === Application Coordinators ===
  final FileEventsCoordinator fileEventsCoordinator;
  final LicenseCoordinator licenseCoordinator;
  final ContentEnrichmentCoordinator contentEnrichmentCoordinator;

  // === Infrastructure ===
  final Logger logger;
  final StorePurchaseService storePurchaseService;

  /// Общий объём физической оперативной памяти в мегабайтах (0 если Rust DLL недоступна).
  final int totalRamMb;

  /// Флаг аппаратных ограничений (RAM < 6 ГБ).
  ///
  /// Когда true — лицензия ограничена до Basic, ResourceSaver включён принудительно.
  final bool isHardwareConstrained;

  /// Ссылка на SqliteIndexService для dispose.
  final SqliteIndexService? _sqliteIndexService;

  bool _isDisposed = false;

  AppCompositionRoot._({
    required this.notifications,
    required this.fileWatcher,
    required this.licenseService,
    required this.featureFlags,
    required this.configService,
    required this.indexer,
    required this.searchRepository,
    required this.ragService,
    required this.fileEventsCoordinator,
    required this.licenseCoordinator,
    required this.contentEnrichmentCoordinator,
    required this.logger,
    required this.storePurchaseService,
    required this.totalRamMb,
    required this.isHardwareConstrained,
    SqliteIndexService? sqliteIndexService,
  }) : _sqliteIndexService = sqliteIndexService;

  /// Создать Composition Root с настройками окружения.
  ///
  /// [environment] — окружение (development/production).
  /// [enableLogColors] — цветной вывод логов (отключить для CI).
  ///
  /// Точки расширения для Free/Pro:
  /// - LicenseService: определяет доступные функции
  /// - FeatureFlags: проверяет доступность по ID
  /// - ConfigService: хранит пользовательские настройки
  ///
  /// Асинхронный метод, так как требует инициализации SharedPreferences.
  static Future<AppCompositionRoot> create({
    AppEnvironment environment = AppEnvironment.development,
    bool enableLogColors = true,
  }) async {
    final isProduction = environment == AppEnvironment.production;

    // === Infrastructure Layer ===
    final logger = AppLogger.create(
      isProduction: isProduction,
      enableColors: enableLogColors,
    );

    // Инициализация flutter_rust_bridge (FFI) — обязательно до любых вызовов Rust API.
    await RustCoreBootstrap.ensureInitialized();

    // Domain services (interfaces)
    final notifications = LocalNotificationsService(logger: logger);
    final watcher = RustFileWatcherFrb(logger: logger);

    // Licensing (local implementation with trial support)
    final prefs = await SharedPreferences.getInstance();
    final licenseService = LocalLicenseService(logger: logger, prefs: prefs);
    await licenseService.initialize();

    // Microsoft Store IAP: sync purchase status (handles reinstall scenario)
    final storePurchaseService = StorePurchaseService(logger: logger);
    try {
      final isStorePurchased = await storePurchaseService.isProPurchased();
      await licenseService.syncStoreStatus(isStorePurchased);
    } catch (e) {
      logger.w('Store purchase sync failed (non-fatal)', error: e);
    }

    final featureFlags = StubFeatureFlags(
      logger: logger,
      licenseService: licenseService,
    );

    // Configuration (persistent implementation)
    final configService = SharedPreferencesConfigService(logger: logger);
    await configService.initialize();
    await configService.load();

    // System info: определяем объём RAM через Rust FFI (нужно до создания координаторов)
    final rustSystemService = RustFfiSystemService();
    int totalRamMb = 0;
    if (rustSystemService.isAvailable) {
      totalRamMb = await rustSystemService.getTotalRamMb();
      logger.i('System: total RAM = $totalRamMb MB');
    } else {
      logger.w('System info: Rust DLL not found, RAM unknown');
    }

    // Порог RAM для аппаратных ограничений (6 ГБ).
    const int lowRamThresholdMb = 6144;
    final bool isHardwareConstrained =
        totalRamMb > 0 && totalRamMb < lowRamThresholdMb;

    if (isHardwareConstrained) {
      logger.w('Hardware constrained: RAM $totalRamMb MB < $lowRamThresholdMb MB. '
          'Forcing Basic mode and ResourceSaver.');
      // Принудительно включаем ResourceSaver если ещё не включён
      if (!configService.currentConfig.resourceSaverEnabled) {
        await configService.updateValue(resourceSaverEnabled: true);
      }
    }

    // SQLite FTS5 Index Service (implements both Indexer and SearchRepository)
    final appDataDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDataDir.path, 'Latera', 'index', 'latera_index.db');
    final sqliteIndexService = SqliteIndexService(
      logger: logger,
      dbPath: dbPath,
    );
    await sqliteIndexService.initialize();

    // Инициализация Rust-стороны индексной БД (используется для RAG-запросов и эмбеддингов).
    // Открывает тот же файл SQLite, что и Dart-сторона, в WAL-режиме.
    await rust_api.initIndex(dbPath: dbPath);

    // Путь к данным модели (используется ниже для загрузки и инициализации).
    final modelDataDir = p.join(appDataDir.path, 'Latera');

    // === Application Layer ===
    final fileEventsCoordinator = FileEventsCoordinator(
      logger: logger,
      watcher: watcher,
      notifications: notifications,
      configService: configService,
      indexer: sqliteIndexService,
    );

    final licenseCoordinator = LicenseCoordinator(
      logger: logger,
      licenseService: licenseService,
      featureFlags: featureFlags,
      isHardwareConstrained: isHardwareConstrained,
    );

    // Content enrichment (PDF/DOCX text extraction + audio transcription + embeddings)
    // PDF/DOCX: Dart-side реализация (syncfusion_flutter_pdf + archive) — обход бага FRB codegen на Windows.
    // Остальное: Stub-реализации до подключения Rust FRB bindings.
    final RichTextExtractor richTextExtractor = DartRichTextExtractor(logger: logger);
    final AudioTranscriber audioTranscriber = StubAudioTranscriber();
    // Embedding: используем Rust FFI если DLL доступна, иначе stub
    final rustEmbedding = RustFfiEmbeddingService();
    final embeddingService = rustEmbedding.isAvailable ? rustEmbedding : StubEmbeddingService();
    if (rustEmbedding.isAvailable) {
      logger.i('Embeddings: using Rust ONNX (via FFI)');
    } else {
      logger.w('Embeddings: Rust DLL not found, using stub');
    }
    // OCR: используем Rust FFI если DLL доступна, иначе stub
    final OcrService ocrService;
    final ocrLibPath = RustOcrService.resolveLibraryPath();
    if (ocrLibPath != null) {
      ocrService = RustOcrService(libraryPath: ocrLibPath);
      logger.i('OCR: using Rust Windows.Media.Ocr (via FFI)');
    } else {
      ocrService = StubOcrService();
      logger.w('OCR: Rust DLL not found, using stub');
    }

    // RAG service (Phase 4: «Спроси папку»)
    // Теперь использует Rust-реализацию через FRB.
    final RagService ragService = RustRagService(logger: logger);

    // Auto-summary и Auto-tags (Phase 5)
    // Используем Rust FFI если DLL доступна, иначе stub.
    final rustAutoSummary = RustFfiAutoSummaryService();
    final AutoSummaryService autoSummaryService;
    if (rustAutoSummary.isAvailable) {
      autoSummaryService = rustAutoSummary;
      logger.i('Auto-summary: using Rust LLM (via FFI)');
    } else {
      autoSummaryService = StubAutoSummaryService();
      logger.w('Auto-summary: Rust DLL not found, using stub');
    }

    final rustAutoTags = RustFfiAutoTagsService();
    final AutoTagsService autoTagsService;
    if (rustAutoTags.isAvailable) {
      autoTagsService = rustAutoTags;
      logger.i('Auto-tags: using Rust LLM (via FFI)');
    } else {
      autoTagsService = StubAutoTagsService();
      logger.w('Auto-tags: Rust DLL not found, using stub');
    }

    final contentEnrichmentCoordinator = ContentEnrichmentCoordinator(
      logger: logger,
      configService: configService,
      indexer: sqliteIndexService,
      extractor: richTextExtractor,
      transcriber: audioTranscriber,
      embeddingService: embeddingService,
      ocrService: ocrService,
      autoSummaryService: autoSummaryService,
      autoTagsService: autoTagsService,
      notifications: notifications,
      licenseCoordinator: licenseCoordinator,
    );
    // Подключаем к потоку событий добавления файлов
    contentEnrichmentCoordinator.start(
      fileEventsCoordinator.fileAddedEvents,
    );

    // Проверка и фоновая загрузка LLM-модели с прогрессом в статус-баре.
    // Не блокирует запуск приложения — выполняется асинхронно.
    unawaited(
      _checkAndDownloadLlmModel(
        modelDataDir,
        logger,
        contentEnrichmentCoordinator,
      ),
    );

    // Реконсиляция индекса с файловой системой.
    // Удаляет из БД файлы, которых больше нет на диске, и обнаруживает новые.
    try {
      final watchPath = configService.currentConfig.watchPath ??
          await rust_api.getDefaultWatchPathPreview();
      final syncResult =
          await sqliteIndexService.syncWithFilesystem(watchPath);

      // Новые файлы: индексируем для review и ставим в очередь обогащения
      for (final f in syncResult.newFiles) {
        await sqliteIndexService.indexFileForReview(
          f['filePath']!,
          fileName: f['fileName']!,
        );
        contentEnrichmentCoordinator.enqueueFile(
          f['filePath']!,
          f['fileName']!,
        );
      }
    } catch (e, st) {
      logger.w('Filesystem sync failed (non-fatal)', error: e, stackTrace: st);
    }

    // Пересчитываем эмбеддинги для файлов, у которых их нет
    // (после миграции stub → ONNX или первой инициализации)
    final filesToReEmbed = sqliteIndexService.getFilesWithoutEmbeddings();
    if (filesToReEmbed.isNotEmpty) {
      logger.i('Re-embedding ${filesToReEmbed.length} files (migration stub → ONNX)');
      for (final f in filesToReEmbed) {
        contentEnrichmentCoordinator.enqueueFile(f['filePath']!, f['fileName']!);
      }
    }

    return AppCompositionRoot._(
      notifications: notifications,
      fileWatcher: watcher,
      licenseService: licenseService,
      featureFlags: featureFlags,
      configService: configService,
      indexer: sqliteIndexService,
      searchRepository: sqliteIndexService,
      ragService: ragService,
      fileEventsCoordinator: fileEventsCoordinator,
      licenseCoordinator: licenseCoordinator,
      contentEnrichmentCoordinator: contentEnrichmentCoordinator,
      logger: logger,
      storePurchaseService: storePurchaseService,
      totalRamMb: totalRamMb,
      isHardwareConstrained: isHardwareConstrained,
      sqliteIndexService: sqliteIndexService,
    );
  }

  /// Проверяет готовность LLM-модели и запускает загрузку при необходимости.
  ///
  /// Если модель уже загружена — инициализирует её в Rust.
  /// Если нет — скачивает с HuggingFace, показывая прогресс в статус-баре,
  /// затем инициализирует.
  static Future<void> _checkAndDownloadLlmModel(
    String modelDataDir,
    Logger logger,
    ContentEnrichmentCoordinator coordinator,
  ) async {
    final modelPath = p.join(
      modelDataDir, 'models', 'all-MiniLM-L6-v2', 'model.onnx',
    );

    if (File(modelPath).existsSync()) {
      logger.i('LLM model file exists, initializing semantic model');
      await rust_api
          .initSemanticModel(dataDir: modelDataDir)
          .then((_) => logger.i('Semantic model loaded from $modelDataDir'))
          .catchError((Object e) => logger.w('Semantic model init failed: $e'));
      return;
    }

    // Модель не существует на диске — запускаем загрузку с отображением прогресса

    final job = EnrichmentJob(
      filePath: modelPath,
      fileName: 'AI-модель',
      type: EnrichmentJobType.llmModelDownload,
      status: EnrichmentJobStatus.processing,
    );
    coordinator.addCustomJob(job);

    try {
      final llmDownloadService = LlmDownloadService();
      await for (final progress in llmDownloadService.downloadModel(
        LlmDownloadService.modelUrl,
        modelPath,
      )) {
        coordinator.updateCustomJobProgress(job, progress);
      }

      coordinator.completeCustomJob(job);

      // Инициализируем семантическую модель после успешной загрузки
      await rust_api.initSemanticModel(dataDir: modelDataDir);

      logger.i('LLM model downloaded and initialized');
    } catch (e, st) {
      coordinator.completeCustomJob(job);
      logger.e('LLM model download failed', error: e, stackTrace: st);

      // Всё равно пытаемся инициализировать — возможно, файл уже был скачан ранее
      await rust_api
          .initSemanticModel(dataDir: modelDataDir)
          .catchError((Object e) => logger.w('Semantic model init failed: $e'));
    }
  }

  /// Освободить ресурсы.
  ///
  /// Безопасен для многократного вызова — последующие вызовы игнорируются.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    logger.i('Disposing AppCompositionRoot');

    // Dispose coordinator (останавливает watcher и закрывает streams)
    await fileEventsCoordinator.dispose();

    // Dispose content enrichment coordinator
    await contentEnrichmentCoordinator.dispose();

    // Unload semantic model
    try {
      await rust_api.unloadSemanticModel();
    } catch (e) {
      logger.w('unloadSemanticModel failed: $e');
    }

    // Dispose SQLite index service
    _sqliteIndexService?.dispose();

    // Dispose stub services
    if (licenseService is StubLicenseService) {
      (licenseService as StubLicenseService).dispose();
    }
    if (featureFlags is StubFeatureFlags) {
      (featureFlags as StubFeatureFlags).dispose();
    }
    // Dispose config service
    if (configService is SharedPreferencesConfigService) {
      (configService as SharedPreferencesConfigService).dispose();
    }
  }
}

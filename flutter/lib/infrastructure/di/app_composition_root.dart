import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/content_enrichment_coordinator.dart';
import '../../application/file_events_coordinator.dart';
import '../../application/license_coordinator.dart';
import '../../application/llm_lifecycle_coordinator.dart';
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

/// Состояние загрузки AI-моделей (для UI: Settings, Status bar).
enum ModelStatus {
  /// Модель загружена и готова к работе.
  ready,

  /// Идёт загрузка модели.
  downloading,

  /// Загрузка не удалась (можно повторить).
  failed,

  /// Загрузка пропущена из-за нехватки RAM.
  skippedLowRam,

  /// Загрузка пропущена из-за нехватки места на диске.
  skippedLowDisk,

  /// Модель не загружена (начальное состояние).
  notDownloaded,
}

/// Трекер состояния загрузки AI-моделей.
class ModelDownloadTracker {
  ModelStatus _embeddingStatus = ModelStatus.notDownloaded;
  ModelStatus _ggufStatus = ModelStatus.notDownloaded;
  String? _lastEmbeddingError;
  String? _lastGgufError;

  final _controller = StreamController<void>.broadcast();

  ModelStatus get embeddingStatus => _embeddingStatus;
  ModelStatus get ggufStatus => _ggufStatus;
  String? get lastEmbeddingError => _lastEmbeddingError;
  String? get lastGgufError => _lastGgufError;

  /// Stream уведомлений об изменении состояния.
  Stream<void> get changes => _controller.stream;

  void _setEmbeddingStatus(ModelStatus status, [String? error]) {
    _embeddingStatus = status;
    _lastEmbeddingError = error;
    _controller.add(null);
  }

  void _setGgufStatus(ModelStatus status, [String? error]) {
    _ggufStatus = status;
    _lastGgufError = error;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

/// Конфигурация окружения приложения.
enum AppEnvironment { development, production }

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
  final LlmLifecycleCoordinator llmLifecycleCoordinator;

  // === Infrastructure ===
  final Logger logger;
  final StorePurchaseService storePurchaseService;

  /// Трекер состояния загрузки AI-моделей.
  final ModelDownloadTracker modelDownloadTracker;

  /// Путь к директории данных модели.
  final String _modelDataDir;

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
    required this.llmLifecycleCoordinator,
    required this.logger,
    required this.storePurchaseService,
    required this.modelDownloadTracker,
    required String modelDataDir,
    required this.totalRamMb,
    required this.isHardwareConstrained,
    SqliteIndexService? sqliteIndexService,
  }) : _sqliteIndexService = sqliteIndexService,
       _modelDataDir = modelDataDir;

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
      logger.w(
        'Hardware constrained: RAM $totalRamMb MB < $lowRamThresholdMb MB. '
        'Forcing Basic mode and ResourceSaver.',
      );
      // Принудительно включаем ResourceSaver если ещё не включён
      if (!configService.currentConfig.resourceSaverEnabled) {
        await configService.updateValue(resourceSaverEnabled: true);
      }
    }

    // AVX2 detection + adaptive RAG max_tokens
    bool hasAvx2 = false;
    if (rustSystemService.isAvailable) {
      hasAvx2 = rustSystemService.getHasAvx2();
      final int ragMaxTokens = hasAvx2 ? 300 : 100;
      rustSystemService.setRagMaxTokens(ragMaxTokens);
      logger.i(
        'CPU: AVX2=${hasAvx2 ? "yes" : "no"}, RAG max_tokens=$ragMaxTokens',
      );

      // Vulkan diagnostic: проверяем наличие Vulkan runtime для будущего GPU-ускорения
      final hasVulkan = rustSystemService.getHasVulkan();
      logger.i(
        'GPU: Vulkan=${hasVulkan ? "available" : "not found"}'
        ' (acceleration not yet enabled)',
      );
    }

    // SQLite FTS5 Index Service (implements both Indexer and SearchRepository)
    final appDataDir = await getApplicationSupportDirectory();
    final dbPath = p.join(
      appDataDir.path,
      'Latera',
      'index',
      'latera_index.db',
    );
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
    final RichTextExtractor richTextExtractor = DartRichTextExtractor(
      logger: logger,
    );
    final AudioTranscriber audioTranscriber = StubAudioTranscriber();
    // Embedding: используем Rust FFI если DLL доступна, иначе stub
    final rustEmbedding = RustFfiEmbeddingService();
    final embeddingService = rustEmbedding.isAvailable
        ? rustEmbedding
        : StubEmbeddingService();
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
    // НЕ подключаем coordinator к broadcast-стриму fileAddedEvents напрямую:
    // UI (main_screen / windows_main_page) слушает тот же стрим, сначала индексирует
    // файл через indexFileForReview(), а затем вызывает enqueueFile().
    // Прямая подписка coordinator.start() приводила к двойной обработке.

    // Проверка и фоновая загрузка LLM-модели с прогрессом в статус-баре.
    // Не блокирует запуск приложения — выполняется асинхронно.
    final modelDownloadTracker = ModelDownloadTracker();

    // LLM Lifecycle Coordinator — управляет TTL генеративной LLM (3-min idle → unload).
    final llmLifecycleCoordinator = LlmLifecycleCoordinator(logger: logger);

    // Тяжёлые фоновые операции (загрузка моделей, реконсиляция индекса) запускаем
    // только если онбординг уже пройден. При первом запуске они будут вызваны
    // через activatePostOnboarding() после завершения онбординга.
    final onboardingCompleted = configService.isOnboardingCompleted;

    if (onboardingCompleted) {
      unawaited(
        _checkAndDownloadLlmModel(
          modelDataDir,
          logger,
          contentEnrichmentCoordinator,
          modelDownloadTracker,
        ),
      );

      unawaited(
        _checkAndDownloadGgufModel(
          modelDataDir,
          totalRamMb,
          isHardwareConstrained,
          logger,
          contentEnrichmentCoordinator,
          llmLifecycleCoordinator,
          modelDownloadTracker,
        ),
      );

      // Реконсиляция индекса с файловой системой.
      // Удаляет из БД файлы, которых больше нет на диске, и обнаруживает новые.
      await _syncFilesystemAndReEmbed(
        configService,
        sqliteIndexService,
        contentEnrichmentCoordinator,
        logger,
      );
    } else {
      logger.i(
        'Onboarding not completed — deferring model downloads and filesystem sync',
      );
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
      llmLifecycleCoordinator: llmLifecycleCoordinator,
      logger: logger,
      storePurchaseService: storePurchaseService,
      modelDownloadTracker: modelDownloadTracker,
      modelDataDir: modelDataDir,
      totalRamMb: totalRamMb,
      isHardwareConstrained: isHardwareConstrained,
      sqliteIndexService: sqliteIndexService,
    );
  }

  /// Активирует отложенные операции после завершения онбординга.
  ///
  /// Запускает фоновые загрузки AI-моделей и реконсиляцию индекса,
  /// которые были отложены при первом запуске приложения.
  /// Вызывается из OnboardingScreen после completeOnboarding().
  void activatePostOnboarding() {
    if (_isDisposed) return;

    logger.i('Activating post-onboarding services');

    unawaited(
      _checkAndDownloadLlmModel(
        _modelDataDir,
        logger,
        contentEnrichmentCoordinator,
        modelDownloadTracker,
      ),
    );

    unawaited(
      _checkAndDownloadGgufModel(
        _modelDataDir,
        totalRamMb,
        isHardwareConstrained,
        logger,
        contentEnrichmentCoordinator,
        llmLifecycleCoordinator,
        modelDownloadTracker,
      ),
    );

    unawaited(
      _syncFilesystemAndReEmbed(
        configService,
        _sqliteIndexService!,
        contentEnrichmentCoordinator,
        logger,
      ),
    );
  }

  /// Реконсиляция индекса с файловой системой + пересчёт эмбеддингов.
  static Future<void> _syncFilesystemAndReEmbed(
    ConfigService configService,
    SqliteIndexService sqliteIndexService,
    ContentEnrichmentCoordinator contentEnrichmentCoordinator,
    Logger logger,
  ) async {
    try {
      final watchPath =
          configService.currentConfig.watchPath ??
          await rust_api.getDefaultWatchPathPreview();
      logger.i('[Sync] Starting filesystem reconciliation (watchPath=$watchPath)');
      final syncResult = await sqliteIndexService.syncWithFilesystem(watchPath);

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
      logger.i(
        '[Sync] Filesystem reconciliation done: ${syncResult.newFiles.length} new, '
        '${syncResult.removedCount} removed',
      );
    } catch (e, st) {
      logger.w('[Sync] Filesystem reconciliation failed (non-fatal)', error: e, stackTrace: st);
    }

    final filesToReEmbed = sqliteIndexService.getFilesWithoutEmbeddings();
    if (filesToReEmbed.isNotEmpty) {
      logger.i(
        '[Sync] Re-embedding ${filesToReEmbed.length} files (migration stub → ONNX)',
      );
      for (final f in filesToReEmbed) {
        contentEnrichmentCoordinator.enqueueFile(
          f['filePath']!,
          f['fileName']!,
        );
      }
    }
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
    ModelDownloadTracker tracker,
  ) async {
    logger.i('[ONNX] Embedding model check started (dataDir=$modelDataDir)');

    final modelPath = p.join(
      modelDataDir,
      'models',
      'paraphrase-multilingual-MiniLM-L12-v2',
      'model.onnx',
    );
    final tokenizerPath = p.join(
      modelDataDir,
      'models',
      'paraphrase-multilingual-MiniLM-L12-v2',
      'tokenizer.json',
    );

    final modelExists = File(modelPath).existsSync();
    final tokenizerExists = File(tokenizerPath).existsSync();
    logger.i(
      '[ONNX] model.onnx exists=$modelExists, tokenizer.json exists=$tokenizerExists',
    );

    if (modelExists && tokenizerExists) {
      logger.i('[ONNX] Both files present, initializing semantic model');
      try {
        final sw = Stopwatch()..start();
        await rust_api.initSemanticModel(dataDir: modelDataDir);
        sw.stop();
        logger.i('[ONNX] Semantic model loaded in ${sw.elapsedMilliseconds} ms');
        tracker._setEmbeddingStatus(ModelStatus.ready);
      } catch (e) {
        logger.w('[ONNX] Semantic model init failed: $e');
        tracker._setEmbeddingStatus(ModelStatus.failed, e.toString());
      }
      return;
    }

    // Модель не существует на диске — запускаем загрузку с отображением прогресса
    logger.i('[ONNX] Model files missing, starting download');
    tracker._setEmbeddingStatus(ModelStatus.downloading);

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
        coordinator.updateCustomJobProgress(job, progress * 0.9);
      }

      // Скачиваем tokenizer.json
      await for (final progress in llmDownloadService.downloadModel(
        LlmDownloadService.tokenizerUrl,
        tokenizerPath,
      )) {
        coordinator.updateCustomJobProgress(job, 0.9 + progress * 0.1);
      }

      coordinator.completeCustomJob(job);

      // Инициализируем семантическую модель после успешной загрузки
      logger.i('[ONNX] Download complete, initializing semantic model');
      final sw = Stopwatch()..start();
      await rust_api.initSemanticModel(dataDir: modelDataDir);
      sw.stop();

      logger.i('[ONNX] Model downloaded and initialized in ${sw.elapsedMilliseconds} ms');
      tracker._setEmbeddingStatus(ModelStatus.ready);
    } catch (e, st) {
      coordinator.completeCustomJob(job);
      logger.e('[ONNX] Model download failed', error: e, stackTrace: st);
      tracker._setEmbeddingStatus(ModelStatus.failed, e.toString());

      // Всё равно пытаемся инициализировать — возможно, файл уже был скачан ранее
      await rust_api
          .initSemanticModel(dataDir: modelDataDir)
          .then((_) => tracker._setEmbeddingStatus(ModelStatus.ready))
          .catchError((Object e) => logger.w('Semantic model init failed: $e'));
    }
  }

  /// Проверяет и скачивает GGUF-модель для генеративной LLM (llama.cpp).
  ///
  /// Порядок:
  /// 1. Если модель уже на диске — init_llm и выход
  /// 2. Проверка RAM (≥ lowRamThresholdMb) и свободного места (≥ 2 ГБ)
  /// 3. Скачивание с прогрессом через coordinator
  /// 4. init_llm → touch lifecycle coordinator
  static Future<void> _checkAndDownloadGgufModel(
    String modelDataDir,
    int totalRamMb,
    bool isHardwareConstrained,
    Logger logger,
    ContentEnrichmentCoordinator coordinator,
    LlmLifecycleCoordinator llmLifecycleCoordinator,
    ModelDownloadTracker tracker,
  ) async {
    logger.i(
      '[GGUF] Generative model check started '
      '(RAM=${totalRamMb}MB, constrained=$isHardwareConstrained, '
      'dataDir=$modelDataDir)',
    );

    final ggufModelPath = p.join(
      modelDataDir,
      'models',
      LlmDownloadService.ggufModelFileName,
    );

    // 1. Модель уже скачана — сразу загружаем
    final modelExists = File(ggufModelPath).existsSync();
    logger.i('[GGUF] Model file exists=$modelExists (path=$ggufModelPath)');

    if (modelExists) {
      logger.i('[GGUF] Initializing generative LLM from existing file');
      try {
        final sw = Stopwatch()..start();
        await rust_api.initLlm(dataDir: modelDataDir);
        sw.stop();
        llmLifecycleCoordinator.touch();
        logger.i('[GGUF] Generative LLM loaded in ${sw.elapsedMilliseconds} ms');
        tracker._setGgufStatus(ModelStatus.ready);
      } catch (e) {
        logger.w('[GGUF] Generative LLM init failed: $e');
        tracker._setGgufStatus(ModelStatus.failed, e.toString());
      }
      return;
    }

    // 2. Проверка RAM
    if (isHardwareConstrained) {
      logger.i(
        '[GGUF] Download skipped: hardware constrained (RAM ${totalRamMb}MB < 6144MB). '
        'Generative LLM requires ≥ 6 GB RAM.',
      );
      tracker._setGgufStatus(ModelStatus.skippedLowRam);
      return;
    }

    // 3. Проверка свободного места на диске
    final modelsDir = p.join(modelDataDir, 'models');
    final hasSpace = await LlmDownloadService.hasEnoughDiskSpace(modelsDir);
    logger.i('[GGUF] Disk space check: sufficient=$hasSpace (dir=$modelsDir)');
    if (!hasSpace) {
      logger.w('[GGUF] Download skipped: insufficient disk space (need ≥ 2 GB)');
      tracker._setGgufStatus(ModelStatus.skippedLowDisk);
      return;
    }

    // 4. Скачиваем с прогрессом
    logger.i('[GGUF] Starting download (~1.7 GB)');
    tracker._setGgufStatus(ModelStatus.downloading);

    final job = EnrichmentJob(
      filePath: ggufModelPath,
      fileName: 'Генеративная модель (GGUF)',
      type: EnrichmentJobType.ggufModelDownload,
      status: EnrichmentJobStatus.processing,
    );
    coordinator.addCustomJob(job);

    try {
      final llmDownloadService = LlmDownloadService();
      await for (final progress in llmDownloadService.downloadGgufModel(
        ggufModelPath,
      )) {
        coordinator.updateCustomJobProgress(job, progress);
      }

      coordinator.completeCustomJob(job);

      // 5. Инициализируем генеративную LLM после скачивания
      logger.i('[GGUF] Download complete, initializing generative LLM');
      final sw = Stopwatch()..start();
      await rust_api.initLlm(dataDir: modelDataDir);
      sw.stop();
      llmLifecycleCoordinator.touch();
      logger.i('[GGUF] Model downloaded and LLM initialized in ${sw.elapsedMilliseconds} ms');
      tracker._setGgufStatus(ModelStatus.ready);
    } catch (e, st) {
      coordinator.completeCustomJob(job);
      logger.e('[GGUF] Download/init failed', error: e, stackTrace: st);
      tracker._setGgufStatus(ModelStatus.failed, e.toString());
    }
  }

  /// Повторить загрузку embedding-модели (ONNX).
  void retryEmbeddingDownload() {
    if (modelDownloadTracker.embeddingStatus != ModelStatus.failed &&
        modelDownloadTracker.embeddingStatus != ModelStatus.notDownloaded) {
      return;
    }
    unawaited(
      _checkAndDownloadLlmModel(
        _modelDataDir,
        logger,
        contentEnrichmentCoordinator,
        modelDownloadTracker,
      ),
    );
  }

  /// Повторить загрузку генеративной модели (GGUF).
  void retryGgufDownload() {
    if (modelDownloadTracker.ggufStatus != ModelStatus.failed &&
        modelDownloadTracker.ggufStatus != ModelStatus.notDownloaded) {
      return;
    }
    unawaited(
      _checkAndDownloadGgufModel(
        _modelDataDir,
        totalRamMb,
        isHardwareConstrained,
        logger,
        contentEnrichmentCoordinator,
        llmLifecycleCoordinator,
        modelDownloadTracker,
      ),
    );
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

    // Unload generative LLM and dispose lifecycle coordinator
    llmLifecycleCoordinator.dispose();
    try {
      await rust_api.unloadLlm();
    } catch (e) {
      logger.w('unloadLlm failed: $e');
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

    // Dispose model download tracker
    modelDownloadTracker.dispose();
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/application/content_enrichment_coordinator.dart';
import 'package:latera/application/file_events_coordinator.dart';
import 'package:latera/domain/app_config.dart';
import 'package:latera/domain/embeddings.dart';
import 'package:latera/domain/indexer.dart';
import 'package:latera/domain/ocr.dart';
import 'package:latera/domain/text_extraction.dart';
import 'package:latera/domain/transcription.dart';
import 'package:logger/logger.dart';

// ============================================================================
// Mocks
// ============================================================================

/// Мок для [ConfigService].
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
    _currentConfig = _currentConfig.copyWith(
      watchPath: clearWatchPath ? null : watchPath,
      watchIntervalMs: watchIntervalMs,
      notificationsEnabled: notificationsEnabled,
      loggingEnabled: loggingEnabled,
      logLevel: logLevel,
      theme: theme,
      language: clearLanguage ? null : language,
      resourceSaverEnabled: resourceSaverEnabled,
      enableOfficeDocs: enableOfficeDocs,
      enableOcr: enableOcr,
      enableTranscription: enableTranscription,
      enableEmbeddings: enableEmbeddings,
      enableSemanticSimilarity: enableSemanticSimilarity,
      enableRag: enableRag,
      enableAutoSummary: enableAutoSummary,
      enableAutoTags: enableAutoTags,
      maxConcurrentJobs: maxConcurrentJobs,
      maxFileSizeMbForEnrichment: maxFileSizeMbForEnrichment,
      maxMediaMinutes: maxMediaMinutes,
      maxPagesPerPdf: maxPagesPerPdf,
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
}

/// Мок для [Indexer].
class MockIndexer implements Indexer {
  bool initializeCalled = false;
  final List<String> indexedFiles = [];
  final Map<String, String> updatedTextContents = {};
  final List<String> removedFiles = [];
  bool cleared = false;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  }) async {
    indexedFiles.add(filePath);
    return true;
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    removedFiles.add(filePath);
  }

  @override
  Future<void> clearIndex() async {
    cleared = true;
  }

  @override
  Future<int> getIndexedCount() async => indexedFiles.length;

  @override
  Future<bool> isIndexed(String filePath) async =>
      indexedFiles.contains(filePath);

  @override
  Future<void> updateTextContent(String filePath, String textContent) async {
    updatedTextContents[filePath] = textContent;
  }

  @override
  Future<void> updateTranscriptText(String filePath, String transcript) async {
    updatedTranscripts[filePath] = transcript;
  }

  @override
  Future<String?> getTextContent(String filePath) async {
    return updatedTextContents[filePath];
  }

  final Map<String, String> updatedTranscripts = {};

  // Phase 3: Embeddings
  final Map<String, int> storedEmbeddingsCounts = {};
  final Set<String> filesWithEmbeddings = {};

  @override
  Future<void> storeEmbeddings(
    String filePath, {
    required List<String> chunkTexts,
    required List<int> chunkOffsets,
    required List<List<double>> embeddingVectors,
  }) async {
    storedEmbeddingsCounts[filePath] = chunkTexts.length;
    filesWithEmbeddings.add(filePath);
  }

  @override
  Future<bool> hasEmbeddings(String filePath) async =>
      filesWithEmbeddings.contains(filePath);

  @override
  void dispose() {}
}

/// Мок для [RichTextExtractor].
class MockRichTextExtractor implements RichTextExtractor {
  /// Результат, который будет возвращён при вызове.
  ExtractionResult? resultToReturn;

  /// Записываем все вызовы для верификации.
  final List<String> extractedPaths = [];
  final List<ExtractionOptions> extractedOptions = [];

  /// Задержка для имитации долгой обработки.
  Duration? delay;

  /// Если не null — бросаем исключение.
  Exception? exceptionToThrow;

  @override
  Future<ExtractionResult> extractText(
    String filePath,
    ExtractionOptions options,
  ) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    extractedPaths.add(filePath);
    extractedOptions.add(options);
    return resultToReturn ??
        const ExtractionResult(
          text: 'Extracted text content',
          contentType: 'pdf',
          pagesExtracted: 3,
        );
  }
}

/// Мок для [AudioTranscriber].
class MockAudioTranscriber implements AudioTranscriber {
  /// Результат, который будет возвращён при вызове.
  TranscriptionResult? resultToReturn;

  /// Записываем все вызовы для верификации.
  final List<String> transcribedPaths = [];
  final List<TranscriptionOptions> transcribedOptions = [];

  /// Задержка для имитации долгой обработки.
  Duration? delay;

  /// Если не null — бросаем исключение.
  Exception? exceptionToThrow;

  @override
  Future<TranscriptionResult> transcribe(
    String filePath,
    TranscriptionOptions options,
  ) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    transcribedPaths.add(filePath);
    transcribedOptions.add(options);
    return resultToReturn ??
        const TranscriptionResult(
          text: 'Transcribed audio content',
          contentType: 'audio',
          durationSeconds: 120,
        );
  }
}

/// Мок для [EmbeddingService].
class MockEmbeddingService implements EmbeddingService {
  final List<String> chunkedTexts = [];
  final List<List<TextChunk>> computedChunks = [];

  @override
  List<TextChunk> chunkText(String text,
      {int chunkSize = 500, int chunkOverlap = 50}) {
    chunkedTexts.add(text);
    // Простое разбиение на чанки для теста
    final chunks = <TextChunk>[];
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, text.length);
      chunks.add(TextChunk(
        text: text.substring(i, end),
        chunkOffset: i,
        chunkIndex: chunks.length,
      ));
    }
    if (chunks.isEmpty && text.isNotEmpty) {
      chunks.add(TextChunk(text: text, chunkOffset: 0, chunkIndex: 0));
    }
    return chunks;
  }

  @override
  Future<List<EmbeddingVector>> computeEmbeddings(List<TextChunk> chunks) async {
    computedChunks.add(chunks);
    return chunks
        .asMap()
        .entries
        .map((e) => EmbeddingVector(
              chunkIndex: e.key,
              vector: List.filled(64, 0.0),
            ))
        .toList();
  }

  @override
  Future<List<SimilarityResult>> similaritySearch(
    String query, {
    int topK = 5,
  }) async =>
      [];

  @override
  Future<List<SimilarityResult>> findSimilarFiles(
    String filePath, {
    int topK = 5,
  }) async =>
      [];

  @override
  Future<bool> hasEmbeddings(String filePath) async => false;
}

/// Мок для [OcrService].
class MockOcrService implements OcrService {
  /// Результат, который будет возвращён при вызове.
  OcrResult? resultToReturn;

  /// Записываем все вызовы для верификации.
  final List<String> ocrPaths = [];
  final List<OcrOptions> ocrOptions = [];

  /// Задержка для имитации долгой обработки.
  Duration? delay;

  /// Если не null — бросаем исключение.
  Exception? exceptionToThrow;

  @override
  Future<OcrResult> extractText(
    String filePath,
    OcrOptions options,
  ) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    ocrPaths.add(filePath);
    ocrOptions.add(options);
    return resultToReturn ??
        const OcrResult(
          text: 'OCR recognized text',
          contentType: 'image',
          pagesProcessed: 1,
          confidence: 0.92,
        );
  }

  @override
  bool isSupported(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return {'png', 'jpg', 'jpeg', 'tiff', 'tif', 'bmp', 'webp', 'pdf'}
        .contains(ext);
  }
}

// ============================================================================
// Helper
// ============================================================================

Logger _testLogger() => Logger(
      printer: SimplePrinter(printTime: false),
      level: Level.off,
    );

// ============================================================================
// Tests
// ============================================================================

void main() {
  group('ContentEnrichmentCoordinator', () {
    late MockConfigService configService;
    late MockIndexer indexer;
    late MockRichTextExtractor extractor;
    late MockAudioTranscriber transcriber;
    late MockEmbeddingService embeddingService;
    late MockOcrService ocrService;
    late ContentEnrichmentCoordinator coordinator;
    late StreamController<FileAddedUiEvent> fileEventsController;

    setUp(() {
      configService = MockConfigService();
      // По умолчанию officeDocs включены
      configService.setConfig(const AppConfig(enableOfficeDocs: true));

      indexer = MockIndexer();
      extractor = MockRichTextExtractor();
      transcriber = MockAudioTranscriber();
      embeddingService = MockEmbeddingService();
      ocrService = MockOcrService();
      fileEventsController = StreamController<FileAddedUiEvent>.broadcast();

      coordinator = ContentEnrichmentCoordinator(
        logger: _testLogger(),
        configService: configService,
        indexer: indexer,
        extractor: extractor,
        transcriber: transcriber,
        embeddingService: embeddingService,
        ocrService: ocrService,
      );
    });

    tearDown(() async {
      await coordinator.dispose();
      await fileEventsController.close();
    });

    // ------------------------------------------------------------------
    // Basic enrichment
    // ------------------------------------------------------------------

    test('enriches PDF file when event received', () async {
      coordinator.start(fileEventsController.stream);

      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        fullPath: '/docs/report.pdf',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.filePath, '/docs/report.pdf');
      expect(extractor.extractedPaths, ['/docs/report.pdf']);
      expect(indexer.updatedTextContents['/docs/report.pdf'],
          'Extracted text content');
    });

    test('enriches DOCX file when event received', () async {
      extractor.resultToReturn = const ExtractionResult(
        text: 'Document text',
        contentType: 'docx',
        pagesExtracted: 0,
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'letter.docx',
        fullPath: '/docs/letter.docx',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(indexer.updatedTextContents['/docs/letter.docx'],
          'Document text');
    });

    // ------------------------------------------------------------------
    // Filtering
    // ------------------------------------------------------------------

    test('ignores non-rich, non-media, non-image files (txt, etc.)', () async {
      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'readme.txt',
        fullPath: '/docs/readme.txt',
        occurredAt: DateTime.now(),
      ));

      // Ждём чтобы события были обработаны
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(extractor.extractedPaths, isEmpty);
      expect(coordinator.queueLength, 0);
    });

    test('ignores files with null fullPath', () async {
      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(extractor.extractedPaths, isEmpty);
    });

    test('skips enrichment when officeDocs disabled', () async {
      configService.setConfig(const AppConfig(enableOfficeDocs: false));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        fullPath: '/docs/report.pdf',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(extractor.extractedPaths, isEmpty);
    });

    test('skips enrichment in resource saver mode for heavy features',
        () async {
      // officeDocs остаётся включённым в resource saver
      configService.setConfig(const AppConfig(
        resourceSaverEnabled: true,
        enableOfficeDocs: true,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        fullPath: '/docs/report.pdf',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      // officeDocs доступен даже в resource saver, но с ужесточёнными лимитами
      expect(job.status, EnrichmentJobStatus.completed);
    });

    // ------------------------------------------------------------------
    // Limits
    // ------------------------------------------------------------------

    test('passes config limits to extractor', () async {
      configService.setConfig(const AppConfig(
        maxPagesPerPdf: 42,
        maxFileSizeMbForEnrichment: 15,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        fullPath: '/docs/report.pdf',
        occurredAt: DateTime.now(),
      ));

      await completed;

      expect(extractor.extractedOptions, hasLength(1));
      expect(extractor.extractedOptions.first.maxPagesPerPdf, 42);
      expect(extractor.extractedOptions.first.maxFileSizeMb, 15);
    });

    test('respects maxConcurrentJobs limit', () async {
      // Лимит: 1 параллельная задача
      configService.setConfig(const AppConfig(maxConcurrentJobs: 1));

      extractor.delay = const Duration(milliseconds: 100);

      coordinator.start(fileEventsController.stream);

      // Отправляем 2 файла
      fileEventsController.add(FileAddedUiEvent(
        fileName: 'file1.pdf',
        fullPath: '/docs/file1.pdf',
        occurredAt: DateTime.now(),
      ));

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'file2.pdf',
        fullPath: '/docs/file2.pdf',
        occurredAt: DateTime.now(),
      ));

      // Через небольшую задержку проверяем что только 1 задача активна
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.activeJobCount, 1);
    });

    // ------------------------------------------------------------------
    // Error handling
    // ------------------------------------------------------------------

    test('handles extraction failure gracefully', () async {
      extractor.resultToReturn = const ExtractionResult(
        text: '',
        contentType: 'pdf',
        pagesExtracted: 0,
        errorCode: 'extraction_failed',
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'corrupt.pdf',
        fullPath: '/docs/corrupt.pdf',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'extraction_failed');
      expect(indexer.updatedTextContents, isEmpty);
    });

    test('handles extractor exception gracefully', () async {
      extractor.exceptionToThrow = Exception('Rust panic');

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'crash.pdf',
        fullPath: '/docs/crash.pdf',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'exception');
    });

    // ------------------------------------------------------------------
    // Manual enqueue
    // ------------------------------------------------------------------

    test('enqueueFile adds job manually', () async {
      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      coordinator.enqueueFile('/docs/manual.pdf', 'manual.pdf');

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.filePath, '/docs/manual.pdf');
    });

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    test('stop() prevents new file events from being processed', () async {
      coordinator.start(fileEventsController.stream);
      await coordinator.stop();

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'report.pdf',
        fullPath: '/docs/report.pdf',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(extractor.extractedPaths, isEmpty);
    });

    test('dispose() clears queue and closes streams', () async {
      coordinator.start(fileEventsController.stream);
      await coordinator.dispose();

      expect(coordinator.isDisposed, isTrue);
      expect(coordinator.queueLength, 0);
    });

    test('events ignored after dispose', () async {
      coordinator.start(fileEventsController.stream);
      await coordinator.dispose();

      coordinator.enqueueFile('/docs/report.pdf', 'report.pdf');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(extractor.extractedPaths, isEmpty);
    });

    // ------------------------------------------------------------------
    // Phase 2: Transcription
    // ------------------------------------------------------------------

    test('transcribes MP3 file when transcription enabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableTranscription: true,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'podcast.mp3',
        fullPath: '/media/podcast.mp3',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.type, EnrichmentJobType.transcription);
      expect(job.filePath, '/media/podcast.mp3');
      expect(transcriber.transcribedPaths, ['/media/podcast.mp3']);
      expect(
        indexer.updatedTranscripts['/media/podcast.mp3'],
        'Transcribed audio content',
      );
    });

    test('transcribes MP4 video file when transcription enabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableTranscription: true,
      ));

      transcriber.resultToReturn = const TranscriptionResult(
        text: 'Video transcript text',
        contentType: 'video',
        durationSeconds: 300,
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'lecture.mp4',
        fullPath: '/media/lecture.mp4',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.type, EnrichmentJobType.transcription);
      expect(
        indexer.updatedTranscripts['/media/lecture.mp4'],
        'Video transcript text',
      );
    });

    test('ignores audio files when transcription disabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableTranscription: false, // disabled
      ));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'song.wav',
        fullPath: '/media/song.wav',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transcriber.transcribedPaths, isEmpty);
    });

    test('transcription disabled in resource saver mode', () async {
      configService.setConfig(const AppConfig(
        resourceSaverEnabled: true,
        enableTranscription: true, // флаг включён, но resource saver отключает
      ));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'podcast.mp3',
        fullPath: '/media/podcast.mp3',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transcriber.transcribedPaths, isEmpty);
    });

    test('passes config limits to transcriber', () async {
      configService.setConfig(const AppConfig(
        enableTranscription: true,
        maxMediaMinutes: 30,
        maxFileSizeMbForEnrichment: 25,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'recording.wav',
        fullPath: '/media/recording.wav',
        occurredAt: DateTime.now(),
      ));

      await completed;

      expect(transcriber.transcribedOptions, hasLength(1));
      expect(transcriber.transcribedOptions.first.maxMediaMinutes, 30);
      expect(transcriber.transcribedOptions.first.maxFileSizeMb, 25);
    });

    test('handles transcription failure gracefully', () async {
      configService.setConfig(const AppConfig(enableTranscription: true));

      transcriber.resultToReturn = const TranscriptionResult(
        text: '',
        contentType: 'audio',
        durationSeconds: 0,
        errorCode: 'not_implemented',
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'audio.mp3',
        fullPath: '/media/audio.mp3',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'not_implemented');
      expect(indexer.updatedTranscripts, isEmpty);
    });

    test('handles transcriber exception gracefully', () async {
      configService.setConfig(const AppConfig(enableTranscription: true));
      transcriber.exceptionToThrow = Exception('Whisper crash');

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'audio.mp3',
        fullPath: '/media/audio.mp3',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'exception');
    });

    test('does not transcribe non-media files', () async {
      configService.setConfig(const AppConfig(enableTranscription: true));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'readme.txt',
        fullPath: '/docs/readme.txt',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transcriber.transcribedPaths, isEmpty);
    });

    // ------------------------------------------------------------------
    // Phase 5: OCR
    // ------------------------------------------------------------------

    test('OCR processes PNG image when OCR enabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableOcr: true,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.type, EnrichmentJobType.ocr);
      expect(job.filePath, '/images/scan.png');
      expect(ocrService.ocrPaths, ['/images/scan.png']);
      expect(
        indexer.updatedTextContents['/images/scan.png'],
        'OCR recognized text',
      );
    });

    test('OCR processes JPEG image when OCR enabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableOcr: true,
      ));

      ocrService.resultToReturn = const OcrResult(
        text: 'JPEG text content',
        contentType: 'image',
        pagesProcessed: 1,
        confidence: 0.85,
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'photo.jpg',
        fullPath: '/images/photo.jpg',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.completed);
      expect(job.type, EnrichmentJobType.ocr);
      expect(
        indexer.updatedTextContents['/images/photo.jpg'],
        'JPEG text content',
      );
    });

    test('ignores images when OCR disabled', () async {
      configService.setConfig(const AppConfig(
        enableOfficeDocs: true,
        enableOcr: false, // disabled
      ));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ocrService.ocrPaths, isEmpty);
    });

    test('OCR disabled in resource saver mode', () async {
      configService.setConfig(const AppConfig(
        resourceSaverEnabled: true,
        enableOcr: true, // флаг включён, но resource saver отключает
      ));

      coordinator.start(fileEventsController.stream);

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ocrService.ocrPaths, isEmpty);
    });

    test('passes config limits to OCR service', () async {
      configService.setConfig(const AppConfig(
        enableOcr: true,
        maxPagesPerPdf: 42,
        maxFileSizeMbForEnrichment: 15,
      ));

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      await completed;

      expect(ocrService.ocrOptions, hasLength(1));
      expect(ocrService.ocrOptions.first.maxPagesPerPdf, 42);
      expect(ocrService.ocrOptions.first.maxFileSizeMb, 15);
    });

    test('handles OCR failure gracefully', () async {
      configService.setConfig(const AppConfig(enableOcr: true));

      ocrService.resultToReturn = const OcrResult(
        text: '',
        contentType: 'image',
        pagesProcessed: 0,
        errorCode: 'not_implemented',
      );

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'not_implemented');
      expect(indexer.updatedTextContents, isEmpty);
    });

    test('handles OCR exception gracefully', () async {
      configService.setConfig(const AppConfig(enableOcr: true));
      ocrService.exceptionToThrow = Exception('Tesseract crash');

      coordinator.start(fileEventsController.stream);
      final completed = coordinator.completedJobs.first;

      fileEventsController.add(FileAddedUiEvent(
        fileName: 'scan.png',
        fullPath: '/images/scan.png',
        occurredAt: DateTime.now(),
      ));

      final job = await completed;
      expect(job.status, EnrichmentJobStatus.failed);
      expect(job.errorCode, 'exception');
    });

    test('OCR supports multiple image formats', () async {
      configService.setConfig(const AppConfig(enableOcr: true));

      coordinator.start(fileEventsController.stream);

      for (final ext in ['png', 'jpg', 'jpeg', 'tiff', 'tif', 'bmp', 'webp']) {
        fileEventsController.add(FileAddedUiEvent(
          fileName: 'file.$ext',
          fullPath: '/images/file.$ext',
          occurredAt: DateTime.now(),
        ));
      }

      // Ждём обработку
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(ocrService.ocrPaths.length, 7);
    });
  });
}

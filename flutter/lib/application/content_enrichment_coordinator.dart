import 'dart:async';
import 'dart:collection';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../domain/app_config.dart';
import '../domain/auto_summary.dart';
import '../domain/auto_tags.dart';
import '../domain/embeddings.dart';
import '../domain/indexer.dart';
import '../domain/notifications_service.dart';
import '../domain/ocr.dart';
import '../domain/text_extraction.dart';
import '../domain/transcription.dart';
import 'file_events_coordinator.dart';

// ============================================================================
// Job model
// ============================================================================

/// Статус задачи обогащения контента.
enum EnrichmentJobStatus {
  /// Ожидает обработки в очереди.
  pending,

  /// Обрабатывается прямо сейчас.
  processing,

  /// Успешно завершена.
  completed,

  /// Завершена с ошибкой.
  failed,
}

/// Тип задачи обогащения.
enum EnrichmentJobType {
  /// Извлечение текста из PDF/DOCX.
  textExtraction,

  /// Транскрибация аудио/видео.
  transcription,

  /// Вычисление эмбеддингов для семантического поиска.
  embeddings,

  /// Оптическое распознавание символов (OCR).
  ocr,

  /// Автоматическая генерация описания.
  autoSummary,

  /// Автоматическая генерация тегов.
  autoTags,
}

/// Задача обогащения контента.
///
/// Отслеживает статус обработки одного файла.
class EnrichmentJob {
  /// Абсолютный путь к файлу.
  final String filePath;

  /// Имя файла.
  final String fileName;

  /// Тип задачи.
  final EnrichmentJobType type;

  /// Текущий статус задачи.
  EnrichmentJobStatus status;

  /// Код ошибки (если [status] == [EnrichmentJobStatus.failed]).
  String? errorCode;

  EnrichmentJob({
    required this.filePath,
    required this.fileName,
    this.type = EnrichmentJobType.textExtraction,
    this.status = EnrichmentJobStatus.pending,
  });
}

// ============================================================================
// Per-file enrichment tracker
// ============================================================================

/// Отслеживает результаты обогащения для одного файла.
///
/// Позволяет определить, когда все задачи для файла завершены,
/// и было ли хотя бы одно успешное извлечение контента.
class _FileEnrichmentTracker {
  final String fileName;

  /// Количество ожидающих/активных задач извлечения контента
  /// (textExtraction, OCR, transcription — но НЕ embeddings).
  int pendingContentJobs = 0;

  /// Был ли контент успешно извлечён хотя бы одной задачей.
  bool contentExtracted = false;

  _FileEnrichmentTracker({required this.fileName});
}

// ============================================================================
// Coordinator
// ============================================================================

/// Координатор обогащения контента (application layer).
///
/// Слушает события добавления файлов из [FileEventsCoordinator],
/// обнаруживает PDF/DOCX и аудио/видео, и запускает фоновое обогащение
/// через [RichTextExtractor] и [AudioTranscriber] (Rust core).
///
/// ## Соблюдаемые лимиты
/// - `config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs)` — мастер-флаг текста
/// - `config.isFeatureEffectivelyEnabled(ContentFeature.transcription)` — мастер-флаг транскрибации
/// - `config.effectiveLimits.maxConcurrentJobs` — параллелизм
/// - `config.effectiveLimits.maxFileSizeMb` — размер файла
/// - `config.effectiveLimits.maxPagesPerPdf` — страницы PDF
/// - `config.effectiveLimits.maxMediaMinutes` — длительность медиа
///
/// ## Lifecycle
/// ```
/// coordinator.start(fileEventsCoordinator.fileAddedEvents);
/// // ... app running ...
/// coordinator.stop();   // stop listening
/// coordinator.dispose(); // release resources
/// ```
class ContentEnrichmentCoordinator {
  final Logger _log;
  final ConfigService _configService;
  final Indexer _indexer;
  final RichTextExtractor _extractor;
  final AudioTranscriber _transcriber;
  final EmbeddingService _embeddingService;
  final OcrService _ocrService;
  final AutoSummaryService _autoSummaryService;
  final AutoTagsService _autoTagsService;
  final NotificationsService _notifications;

  StreamSubscription<FileAddedUiEvent>? _fileEventSub;
  final Queue<EnrichmentJob> _queue = Queue<EnrichmentJob>();
  int _activeJobs = 0;
  final bool _isProcessing = false;
  bool _isDisposed = false;

  /// Трекеры обогащения по filePath — отслеживают цикл обогащения для каждого файла.
  final Map<String, _FileEnrichmentTracker> _trackers = {};

  /// Расширения, требующие rich text extraction.
  static const _richExtensions = {'pdf', 'docx'};

  /// Расширения изображений для OCR.
  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'tiff',
    'tif',
    'bmp',
    'webp',
  };

  /// Расширения аудиофайлов для транскрибации.
  static const _audioExtensions = {
    'wav',
    'mp3',
    'm4a',
    'ogg',
    'flac',
    'aac',
    'wma',
  };

  /// Расширения видеофайлов для транскрибации.
  static const _videoExtensions = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'wmv'};

  /// Stream завершённых задач обогащения (для UI/логирования).
  final StreamController<EnrichmentJob> _completedController =
      StreamController<EnrichmentJob>.broadcast();

  ContentEnrichmentCoordinator({
    required Logger logger,
    required ConfigService configService,
    required Indexer indexer,
    required RichTextExtractor extractor,
    required AudioTranscriber transcriber,
    required EmbeddingService embeddingService,
    required OcrService ocrService,
    required AutoSummaryService autoSummaryService,
    required AutoTagsService autoTagsService,
    required NotificationsService notifications,
  }) : _log = logger,
       _configService = configService,
       _indexer = indexer,
       _extractor = extractor,
       _transcriber = transcriber,
       _embeddingService = embeddingService,
       _ocrService = ocrService,
       _autoSummaryService = autoSummaryService,
       _autoTagsService = autoTagsService,
       _notifications = notifications;

  /// Stream завершённых (или проваленных) задач обогащения.
  Stream<EnrichmentJob> get completedJobs => _completedController.stream;

  /// Количество активных (in-progress) задач.
  int get activeJobCount => _activeJobs;

  /// Количество ожидающих задач в очереди.
  int get queueLength => _queue.length;

  /// Координатор утилизирован.
  bool get isDisposed => _isDisposed;

  /// Начать слушать события файлов для обогащения.
  ///
  /// Обычно вызывается с `fileEventsCoordinator.fileAddedEvents`.
  void start(Stream<FileAddedUiEvent> fileEvents) {
    _fileEventSub?.cancel();
    _fileEventSub = fileEvents.listen(_onFileAdded);
    _log.i('ContentEnrichmentCoordinator started');
  }

  /// Добавить файл в очередь обогащения вручную.
  ///
  /// Полезно для повторной обработки или ручного запуска.
  void enqueueFile(String filePath, String fileName) {
    _onFileAdded(
      FileAddedUiEvent(
        fileName: fileName,
        fullPath: filePath,
        occurredAt: DateTime.now(),
      ),
    );
  }

  /// Пересчитать только эмбеддинги для файла (описание/теги уже сохранены).
  void enqueueReEmbedding(String filePath, String fileName) {
    _enqueueEmbeddingsIfEnabled(filePath, fileName);
  }

  // --------------------------------------------------------------------------
  // Private
  // --------------------------------------------------------------------------

  void _enqueueEmbeddingsIfEnabled(String filePath, String fileName) {
    final config = _configService.currentConfig;
    if (config.isFeatureEffectivelyEnabled(ContentFeature.embeddings) ||
        config.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity)) {
      final embeddingsJob = EnrichmentJob(
        filePath: filePath,
        fileName: fileName,
        type: EnrichmentJobType.embeddings,
      );
      _queue.add(embeddingsJob);
      _log.d('Enqueued embeddings job (post-enrichment): $fileName');
      _processQueue();
    }
  }

  /// Добавляет задачи автоописания и автотегов в очередь после успешного извлечения контента.
  void _enqueueMetadataJobsIfEnabled(String filePath, String fileName) {
    final config = _configService.currentConfig;
    if (config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary)) {
      final job = EnrichmentJob(
        filePath: filePath,
        fileName: fileName,
        type: EnrichmentJobType.autoSummary,
      );
      _queue.add(job);
      _log.d('Enqueued auto-summary job (post-enrichment): $fileName');
    }
    if (config.isFeatureEffectivelyEnabled(ContentFeature.autoTags)) {
      final job = EnrichmentJob(
        filePath: filePath,
        fileName: fileName,
        type: EnrichmentJobType.autoTags,
      );
      _queue.add(job);
      _log.d('Enqueued auto-tags job (post-enrichment): $fileName');
    }
    _processQueue();
  }

  void _onFileAdded(FileAddedUiEvent event) {
    if (_isDisposed) return;
    if (event.fullPath == null) return;

    final ext = p
        .extension(event.fullPath!)
        .toLowerCase()
        .replaceFirst('.', '');

    final config = _configService.currentConfig;

    // Инициализируем трекер для файла — отслеживает,
    // была ли хотя бы одна успешная экстракция контента.
    final tracker = _FileEnrichmentTracker(fileName: event.fileName);
    _trackers[event.fullPath!] = tracker;

    // Rich text extraction (PDF, DOCX)
    if (_richExtensions.contains(ext)) {
      if (!config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs)) {
        _log.d('Office docs extraction disabled, skipping: ${event.fileName}');
      } else {
        final job = EnrichmentJob(
          filePath: event.fullPath!,
          fileName: event.fileName,
          type: EnrichmentJobType.textExtraction,
        );
        _queue.add(job);
        tracker.pendingContentJobs++;
        _log.d('Enqueued text extraction job: ${event.fileName}');
      }
    }

    // Transcription (audio/video)
    if (_audioExtensions.contains(ext) || _videoExtensions.contains(ext)) {
      if (!config.isFeatureEffectivelyEnabled(ContentFeature.transcription)) {
        _log.d('Transcription disabled, skipping: ${event.fileName}');
      } else {
        final job = EnrichmentJob(
          filePath: event.fullPath!,
          fileName: event.fileName,
          type: EnrichmentJobType.transcription,
        );
        _queue.add(job);
        tracker.pendingContentJobs++;
        _log.d('Enqueued transcription job: ${event.fileName}');
      }
    }

    // OCR (images)
    if (_imageExtensions.contains(ext)) {
      if (!config.isFeatureEffectivelyEnabled(ContentFeature.ocr)) {
        _log.d('OCR disabled, skipping: ${event.fileName}');
      } else {
        final job = EnrichmentJob(
          filePath: event.fullPath!,
          fileName: event.fileName,
          type: EnrichmentJobType.ocr,
        );
        _queue.add(job);
        tracker.pendingContentJobs++;
        _log.d('Enqueued OCR job: ${event.fileName}');
      }
    }

    // Determine if file needs preprocessing before embeddings
    final needsPreprocessing =
        _richExtensions.contains(ext) ||
        _audioExtensions.contains(ext) ||
        _videoExtensions.contains(ext) ||
        _imageExtensions.contains(ext);

    // Embeddings (для всех файлов при включённом семантическом поиске)
    // Если файлу нужна предобработка (экстракция, OCR и т.д.), эмбеддинги будут
    // добавлены в очередь только ПОСЛЕ успешной обработки.
    if (!needsPreprocessing &&
        (config.isFeatureEffectivelyEnabled(ContentFeature.embeddings) ||
            config.isFeatureEffectivelyEnabled(
              ContentFeature.semanticSimilarity,
            ))) {
      final job = EnrichmentJob(
        filePath: event.fullPath!,
        fileName: event.fileName,
        type: EnrichmentJobType.embeddings,
      );
      _queue.add(job);
      _log.d('Enqueued embeddings job: ${event.fileName}');
    }

    // Auto-summary и auto-tags для текстовых файлов (не нуждающихся в предобработке)
    // Для файлов с предобработкой — метаданные добавятся после экстракции.
    if (!needsPreprocessing) {
      _enqueueMetadataJobsIfEnabled(event.fullPath!, event.fileName);
    }

    // Для текстовых файлов (txt, md, rs...) контент извлекается автоматически
    // при indexFileForReview. Помечаем файл как обогащённый сразу.
    if (!needsPreprocessing) {
      unawaited(_markEnrichedIfTextFile(event.fullPath!, ext));
    }

    _processQueue();
  }

  /// Помечает текстовый файл как обогащённый (убирает needs_review).
  ///
  /// Текстовые файлы (.txt, .md, .rs и т.д.) уже имеют свой контент
  /// прочитанным при indexFileForReview, поэтому не требуют внимания.
  Future<void> _markEnrichedIfTextFile(String filePath, String ext) async {
    // Расширения из SqliteIndexService._textExtensions
    const textExtensions = <String>{
      'txt', 'md', 'markdown', 'rst', 'log', 'csv', 'tsv',
      'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'properties',
      'rs', 'dart', 'py', 'js', 'ts', 'java', 'kt', 'c', 'cpp', 'h', 'hpp',
      'cs', 'go', 'rb', 'php', 'swift', 'sh', 'bash', 'ps1', 'bat', 'cmd',
      'html', 'htm', 'css', 'scss', 'sass', 'less',
      'sql', 'graphql', 'proto', 'env',
    };
    if (textExtensions.contains(ext)) {
      try {
        await _indexer.markFileEnriched(filePath);
        _trackers.remove(filePath);
      } catch (e) {
        _log.w('Failed to mark text file as enriched: $filePath', error: e);
      }
    }
  }

  void _processQueue() {
    if (_isDisposed || _isProcessing) return;

    final limits = _configService.currentConfig.effectiveLimits;

    while (_queue.isNotEmpty && _activeJobs < limits.maxConcurrentJobs) {
      final job = _queue.removeFirst();
      _activeJobs++;
      unawaited(_processJob(job));
    }
  }

  /// Вызывается после завершения задачи извлечения контента (успех или неудача).
  ///
  /// Обновляет трекер и при завершении всех контент-задач для файла:
  /// - если контент был извлечён → снимает needs_review
  /// - если контент НЕ был извлечён → отправляет тихое уведомление
  Future<void> _onContentJobCompleted(EnrichmentJob job, {required bool success}) async {
    final tracker = _trackers[job.filePath];
    if (tracker == null) return;

    if (success) {
      tracker.contentExtracted = true;
    }
    tracker.pendingContentJobs--;

    // Все контент-задачи для файла завершились
    if (tracker.pendingContentJobs <= 0) {
      _trackers.remove(job.filePath);

      if (tracker.contentExtracted) {
        // Контент успешно извлечён → убираем из Inbox
        try {
          await _indexer.markFileEnriched(job.filePath);
          _log.i('File enriched, removed from inbox: ${job.fileName}');
        } catch (e) {
          _log.w('Failed to mark file as enriched: ${job.filePath}', error: e);
        }
      } else {
        // Контент НЕ извлечён → файл остаётся в Inbox, отправляем тихий Toast
        _log.i('File not recognized, stays in inbox: ${job.fileName}');
        try {
          await _notifications.showFileNeedsReview(fileName: job.fileName);
        } catch (e) {
          _log.w('Failed to show needs-review notification: ${job.fileName}', error: e);
        }
      }
    }
  }

  Future<void> _processJob(EnrichmentJob job) async {
    job.status = EnrichmentJobStatus.processing;
    _log.d('Processing ${job.type.name} job: ${job.fileName}');

    try {
      switch (job.type) {
        case EnrichmentJobType.textExtraction:
          await _processTextExtraction(job);
        case EnrichmentJobType.transcription:
          await _processTranscription(job);
        case EnrichmentJobType.embeddings:
          await _processEmbeddings(job);
        case EnrichmentJobType.ocr:
          await _processOcr(job);
        case EnrichmentJobType.autoSummary:
          await _processAutoSummary(job);
        case EnrichmentJobType.autoTags:
          await _processAutoTags(job);
      }
    } catch (e, st) {
      job.status = EnrichmentJobStatus.failed;
      job.errorCode = 'exception';
      _log.e(
        'Enrichment job failed: ${job.fileName}',
        error: e,
        stackTrace: st,
      );
    } finally {
      _activeJobs--;
      if (!_isDisposed) {
        _completedController.add(job);
        _processQueue();
      }
    }
  }

  /// Проверяет, является ли текст достаточно осмысленным, чтобы считать
  /// процесс извлечения контента успешным (иначе файл останется в Inbox).
  bool _isTextMeaningful(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    
    // Если текст слишком короткий - это наверняка мусор или пара цифр
    if (trimmed.length <= 3) return false;

    // Ищем хотя бы одну букву. Если только цифры/символы - считаем неосмысленным
    final hasLetters = RegExp(r'[a-zA-Zа-яА-ЯёЁ]').hasMatch(text);
    return hasLetters;
  }

  Future<void> _processTextExtraction(EnrichmentJob job) async {
    final limits = _configService.currentConfig.effectiveLimits;
    final options = ExtractionOptions(
      maxPagesPerPdf: limits.maxPagesPerPdf,
      maxFileSizeMb: limits.maxFileSizeMb,
    );

    final result = await _extractor.extractText(job.filePath, options);

    if (result.hasText) {
      await _indexer.updateTextContent(job.filePath, result.text);
      job.status = EnrichmentJobStatus.completed;
      _log.i(
        'Enriched file: ${job.fileName} '
        '(${result.contentType}, ${result.text.length} chars'
        '${result.pagesExtracted > 0 ? ", ${result.pagesExtracted} pages" : ""})',
      );
      
      final isMeaningful = _isTextMeaningful(result.text);
      await _onContentJobCompleted(job, success: isMeaningful);
      
      if (isMeaningful) {
        _enqueueEmbeddingsIfEnabled(job.filePath, job.fileName);
        _enqueueMetadataJobsIfEnabled(job.filePath, job.fileName);
      }
    } else {
      // Если PDF не содержит текстового слоя — возможно, это скан.
      // При включённом OCR отправляем его на распознавание.
      final ext = p.extension(job.filePath).toLowerCase().replaceFirst('.', '');
      final config = _configService.currentConfig;

      if (ext == 'pdf' &&
          config.isFeatureEffectivelyEnabled(ContentFeature.ocr)) {
        _log.i('PDF has no text layer, enqueuing OCR: ${job.fileName}');
        final ocrJob = EnrichmentJob(
          filePath: job.filePath,
          fileName: job.fileName,
          type: EnrichmentJobType.ocr,
        );
        _queue.add(ocrJob);
        // Трекер: переносим ожидание на OCR-задачу (не уменьшаем pending,
        // а добавляем новую задачу)
        final tracker = _trackers[job.filePath];
        if (tracker != null) {
          tracker.pendingContentJobs++; // +1 за новую OCR задачу
        }
        // Текущая задача считается завершённой (не failed),
        // но контент не извлечён — отмечаем как «передано в OCR».
        job.status = EnrichmentJobStatus.completed;
        await _onContentJobCompleted(job, success: false);
      } else {
        job.status = EnrichmentJobStatus.failed;
        job.errorCode = result.errorCode;
        _log.w(
          'Failed to enrich file: ${job.fileName} '
          '(error: ${result.errorCode})',
        );
        await _onContentJobCompleted(job, success: false);
      }
    }
  }

  Future<void> _processTranscription(EnrichmentJob job) async {
    final limits = _configService.currentConfig.effectiveLimits;
    final options = TranscriptionOptions(
      maxMediaMinutes: limits.maxMediaMinutes,
      maxFileSizeMb: limits.maxFileSizeMb,
    );

    final result = await _transcriber.transcribe(job.filePath, options);

    if (result.hasText) {
      await _indexer.updateTranscriptText(job.filePath, result.text);
      job.status = EnrichmentJobStatus.completed;
      _log.i(
        'Transcribed file: ${job.fileName} '
        '(${result.contentType}, ${result.text.length} chars, '
        '${result.durationSeconds}s)',
      );
      
      final isMeaningful = _isTextMeaningful(result.text);
      await _onContentJobCompleted(job, success: isMeaningful);
      
      if (isMeaningful) {
        _enqueueEmbeddingsIfEnabled(job.filePath, job.fileName);
        _enqueueMetadataJobsIfEnabled(job.filePath, job.fileName);
      }
    } else {
      job.status = EnrichmentJobStatus.failed;
      job.errorCode = result.errorCode;
      _log.w(
        'Failed to transcribe file: ${job.fileName} '
        '(error: ${result.errorCode})',
      );
      await _onContentJobCompleted(job, success: false);
    }
  }

  Future<void> _processEmbeddings(EnrichmentJob job) async {
    // Читаем текстовое содержимое файла (берём из БД: description, tags, text, transcript, либо fallback на чтение с диска)
    final textContent = await _indexer.getTextContent(job.filePath);

    if (textContent == null || textContent.trim().isEmpty) {
      job.status = EnrichmentJobStatus.completed;
      _log.d(
        'Cannot read text or empty content, skipping embeddings: ${job.fileName}',
      );
      return;
    }

    // Chunk + embed
    final chunks = _embeddingService.chunkText(textContent);
    if (chunks.isEmpty) {
      job.status = EnrichmentJobStatus.completed;
      return;
    }

    final embeddings = await _embeddingService.computeEmbeddings(chunks);

    // Сохраняем в индекс
    await _indexer.storeEmbeddings(
      job.filePath,
      chunkTexts: chunks.map((c) => c.text).toList(),
      chunkOffsets: chunks.map((c) => c.chunkOffset).toList(),
      embeddingVectors: embeddings.map((e) => e.vector).toList(),
    );

    job.status = EnrichmentJobStatus.completed;
    _log.i(
      'Computed embeddings: ${job.fileName} '
      '(${chunks.length} chunks)',
    );
  }

  Future<void> _processOcr(EnrichmentJob job) async {
    final limits = _configService.currentConfig.effectiveLimits;
    final options = OcrOptions(
      maxPagesPerPdf: limits.maxPagesPerPdf,
      maxFileSizeMb: limits.maxFileSizeMb,
      language: _configService.currentConfig.language,
    );

    final result = await _ocrService.extractText(job.filePath, options);

    if (result.hasText) {
      // OCR текст сохраняется в text_content — аналогично text extraction
      await _indexer.updateTextContent(job.filePath, result.text);
      job.status = EnrichmentJobStatus.completed;
      _log.i(
        'OCR completed: ${job.fileName} '
        '(${result.contentType}, ${result.text.length} chars'
        '${result.pagesProcessed > 0 ? ", ${result.pagesProcessed} pages" : ""}'
        '${result.confidence != null ? ", conf=${result.confidence!.toStringAsFixed(2)}" : ""})',
      );
      
      final isMeaningful = _isTextMeaningful(result.text);
      await _onContentJobCompleted(job, success: isMeaningful);
      
      if (isMeaningful) {
        _enqueueEmbeddingsIfEnabled(job.filePath, job.fileName);
        _enqueueMetadataJobsIfEnabled(job.filePath, job.fileName);
      }
    } else {
      job.status = EnrichmentJobStatus.failed;
      job.errorCode = result.errorCode;
      _log.w(
        'OCR failed: ${job.fileName} '
        '(error: ${result.errorCode})',
      );
      await _onContentJobCompleted(job, success: false);
    }
  }

  Future<void> _processAutoSummary(EnrichmentJob job) async {
    final textContent = await _indexer.getTextContent(job.filePath);

    if (textContent == null || textContent.trim().isEmpty) {
      job.status = EnrichmentJobStatus.completed;
      _log.d('No text content, skipping auto-summary: ${job.fileName}');
      return;
    }

    final result = await _autoSummaryService.generateSummary(
      textContent,
      fileName: job.fileName,
    );

    if (result.hasSummary) {
      await _indexer.updateDescription(job.filePath, result.summary);
      job.status = EnrichmentJobStatus.completed;
      _log.i(
        'Auto-summary generated: ${job.fileName} '
        '(${result.summary.length} chars)',
      );
    } else {
      job.status = EnrichmentJobStatus.failed;
      job.errorCode = result.errorCode;
      _log.w(
        'Auto-summary failed: ${job.fileName} '
        '(error: ${result.errorCode})',
      );
    }
  }

  Future<void> _processAutoTags(EnrichmentJob job) async {
    final textContent = await _indexer.getTextContent(job.filePath);

    if (textContent == null || textContent.trim().isEmpty) {
      job.status = EnrichmentJobStatus.completed;
      _log.d('No text content, skipping auto-tags: ${job.fileName}');
      return;
    }

    final result = await _autoTagsService.generateTags(
      textContent,
      fileName: job.fileName,
    );

    if (result.hasTags) {
      await _indexer.updateTags(job.filePath, result.tagsAsString);
      job.status = EnrichmentJobStatus.completed;
      _log.i(
        'Auto-tags generated: ${job.fileName} '
        '(${result.tags.length} tags: ${result.tagsAsString})',
      );
    } else {
      job.status = EnrichmentJobStatus.failed;
      job.errorCode = result.errorCode;
      _log.w(
        'Auto-tags failed: ${job.fileName} '
        '(error: ${result.errorCode})',
      );
    }
  }

  /// Остановить прослушивание событий.
  ///
  /// Не прерывает текущие in-progress задачи, но новые не будут приниматься.
  Future<void> stop() async {
    await _fileEventSub?.cancel();
    _fileEventSub = null;
    _log.i('ContentEnrichmentCoordinator stopped');
  }

  /// Освободить все ресурсы.
  ///
  /// После вызова координатор нельзя использовать.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();
    _queue.clear();
    await _completedController.close();
    _log.i('ContentEnrichmentCoordinator disposed');
  }
}

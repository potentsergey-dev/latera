/// Контракт на индексатор файлов.
///
/// Domain слой не зависит от реализации хранения (SQLite, FTS5 и т.д.).
/// Отвечает за индексацию файлов для последующего поиска.
abstract interface class Indexer {
  /// Инициализирует индекс (создаёт БД, таблицы и т.д.).
  ///
  /// Должен быть вызван один раз при старте приложения.
  Future<void> initialize();

  /// Индексирует один файл с описанием пользователя.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [fileName] — имя файла.
  /// [description] — описание от пользователя (основа для поиска).
  /// Возвращает true, если индексация прошла успешно.
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  });

  /// Удаляет файл из индекса.
  ///
  /// [filePath] — абсолютный путь к файлу.
  Future<void> removeFromIndex(String filePath);

  /// Очищает весь индекс.
  Future<void> clearIndex();

  /// Возвращает количество проиндексированных файлов.
  Future<int> getIndexedCount();

  /// Проверяет, проиндексирован ли файл.
  Future<bool> isIndexed(String filePath);

  /// Обновляет текстовое содержимое проиндексированного файла.
  ///
  /// Используется при фоновом обогащении контента (PDF/DOCX extraction).
  /// Если файл не найден в индексе — операция игнорируется.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [textContent] — извлечённый текст из PDF/DOCX.
  Future<void> updateTextContent(String filePath, String textContent);

  /// Обновляет транскрипт проиндексированного файла.
  ///
  /// Используется при фоновом обогащении контента (транскрибация Whisper).
  /// Если файл не найден в индексе — операция игнорируется.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [transcript] — текст транскрибации аудио/видео.
  Future<void> updateTranscriptText(String filePath, String transcript);

  /// Получает текстовое содержимое (и транскрипт) файла из индекса.
  ///
  /// Используется для генерации эмбеддингов после того, как файл был обогащен.
  Future<String?> getTextContent(String filePath);

  // === Phase 3: Embeddings ===

  /// Сохраняет чанки и их эмбеддинги для файла.
  ///
  /// Удаляет предыдущие эмбеддинги для файла перед вставкой.
  ///
  /// [filePath] — абсолютный путь к файлу (должен быть уже проиндексирован).
  /// [chunkTexts] — массив текстов чанков.
  /// [chunkOffsets] — массив байтовых смещений чанков.
  /// [embeddingVectors] — массив эмбеддинг-векторов (по одному на чанк).
  Future<void> storeEmbeddings(
    String filePath, {
    required List<String> chunkTexts,
    required List<int> chunkOffsets,
    required List<List<double>> embeddingVectors,
  });

  /// Проверяет, вычислены ли эмбеддинги для файла.
  Future<bool> hasEmbeddings(String filePath);

  // === Phase 4: Inbox (Требуют внимания) ===

  /// Индексирует файл без описания с пометкой «требует внимания».
  ///
  /// Файл сразу попадает в индекс (и FTS5), но помечается как нераспознанный.
  /// Пользователь позже добавит описание и теги через экран Inbox.
  Future<bool> indexFileForReview(
    String filePath, {
    required String fileName,
  });

  /// Возвращает файлы, требующие внимания (без описания).
  Future<List<InboxFile>> getFilesNeedingReview();

  /// Возвращает количество файлов, требующих внимания.
  Future<int> getFilesNeedingReviewCount();

  /// Сохраняет описание и теги, убирает файл из списка «требуют внимания».
  Future<void> saveFileReview(
    String filePath, {
    required String description,
    required String tags,
  });

  /// Убирает флаг «требует внимания» для файла, успешно обогащённого контентом.
  ///
  /// Вызывается из ContentEnrichmentCoordinator когда текст или OCR
  /// успешно извлечены и сохранены в базу.
  Future<void> markFileEnriched(String filePath);

  /// Освобождает ресурсы (закрывает БД).
  void dispose();
}

/// Файл, требующий внимания (Inbox).
class InboxFile {
  final String filePath;
  final String fileName;
  final String description;
  final String tags;
  final DateTime indexedAt;

  const InboxFile({
    required this.filePath,
    required this.fileName,
    required this.description,
    required this.tags,
    required this.indexedAt,
  });
}

/// Результат операции индексации.
class IndexResult {
  final bool success;
  final String? error;
  final String filePath;

  const IndexResult({
    required this.success,
    required this.filePath,
    this.error,
  });
}

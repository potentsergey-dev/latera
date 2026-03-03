/// Контракты для вычисления эмбеддингов и similarity search.
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка выполняется в Rust core.
library;

// ============================================================================
// Types
// ============================================================================

/// Текстовый чанк для вычисления эмбеддинга.
class TextChunk {
  /// Текст чанка.
  final String text;

  /// Индекс чанка в документе (0-based).
  final int chunkIndex;

  /// Смещение (байтовое) от начала документа.
  final int chunkOffset;

  const TextChunk({
    required this.text,
    required this.chunkIndex,
    required this.chunkOffset,
  });

  @override
  String toString() =>
      'TextChunk(index: $chunkIndex, offset: $chunkOffset, '
      'chars: ${text.length})';
}

/// Результат вычисления эмбеддинга для одного чанка.
class EmbeddingVector {
  /// Индекс чанка.
  final int chunkIndex;

  /// Вектор эмбеддинга (f32).
  final List<double> vector;

  const EmbeddingVector({
    required this.chunkIndex,
    required this.vector,
  });
}

/// Результат similarity search.
class SimilarityResult {
  /// Путь к файлу.
  final String filePath;

  /// Имя файла.
  final String fileName;

  /// Текст чанка, наиболее похожего на запрос.
  final String chunkSnippet;

  /// Смещение чанка в документе.
  final int chunkOffset;

  /// Косинусное сходство (0.0 – 1.0).
  final double score;

  const SimilarityResult({
    required this.filePath,
    required this.fileName,
    required this.chunkSnippet,
    required this.chunkOffset,
    required this.score,
  });

  @override
  String toString() =>
      'SimilarityResult(file: $fileName, score: ${score.toStringAsFixed(3)})';
}

// ============================================================================
// Service contract
// ============================================================================

/// Контракт для сервиса эмбеддингов.
///
/// Тяжёлая обработка выполняется в Rust core через FRB.
/// Domain-слой не зависит от реализации.
abstract interface class EmbeddingService {
  /// Разбивает текст на чанки.
  ///
  /// [text] — полный текст документа.
  /// [chunkSize] — размер чанка (символов). По умолчанию 500.
  /// [chunkOverlap] — перекрытие между чанками. По умолчанию 50.
  List<TextChunk> chunkText(
    String text, {
    int chunkSize = 500,
    int chunkOverlap = 50,
  });

  /// Вычисляет эмбеддинги для набора чанков.
  ///
  /// Возвращает список эмбеддингов (по одному на чанк).
  Future<List<EmbeddingVector>> computeEmbeddings(List<TextChunk> chunks);

  /// Ищет файлы, семантически похожие на текстовый запрос.
  ///
  /// [query] — текстовый запрос.
  /// [topK] — максимальное количество результатов.
  Future<List<SimilarityResult>> similaritySearch(
    String query, {
    int topK = 5,
  });

  /// Ищет файлы, похожие на данный файл.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [topK] — максимальное количество результатов.
  Future<List<SimilarityResult>> findSimilarFiles(
    String filePath, {
    int topK = 5,
  });

  /// Проверяет, вычислены ли эмбеддинги для файла.
  Future<bool> hasEmbeddings(String filePath);
}

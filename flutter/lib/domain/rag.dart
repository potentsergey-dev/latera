/// Контракты для локального RAG — «Спроси свою папку».
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка (similarity search, генерация ответа)
/// выполняется в Rust core.
library;

// ============================================================================
// Types
// ============================================================================

/// Источник ответа RAG (чанк, из которого взята информация).
class RagSource {
  /// Путь к файлу-источнику.
  final String filePath;

  /// Фрагмент текста чанка.
  final String chunkSnippet;

  /// Смещение (байтовое) чанка в документе.
  final int chunkOffset;

  const RagSource({
    required this.filePath,
    required this.chunkSnippet,
    required this.chunkOffset,
  });

  @override
  String toString() =>
      'RagSource(file: $filePath, offset: $chunkOffset, '
      'snippet: ${chunkSnippet.length} chars)';
}

/// Результат RAG-запроса.
class RagQueryResult {
  /// Сгенерированный ответ.
  final String answer;

  /// Источники (чанки, из которых сформирован ответ).
  final List<RagSource> sources;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"no_relevant_chunks"` — не найдено релевантных чанков
  /// - `"empty_question"` — пустой вопрос
  /// - `"query_failed"` — ошибка при выполнении запроса
  final String? errorCode;

  const RagQueryResult({
    required this.answer,
    required this.sources,
    this.errorCode,
  });

  /// Успешно ли выполнен запрос (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли ответ.
  bool get hasAnswer => answer.isNotEmpty;

  /// Количество источников.
  int get sourceCount => sources.length;

  @override
  String toString() =>
      'RagQueryResult(success: $isSuccess, '
      'answer: ${answer.length} chars, sources: ${sources.length})';
}

// ============================================================================
// Service contract
// ============================================================================

/// Контракт для сервиса RAG-запросов.
///
/// Тяжёлая обработка выполняется в Rust core через FRB.
/// Domain-слой не зависит от реализации.
abstract interface class RagService {
  /// Выполняет RAG-запрос по индексированным документам.
  ///
  /// Находит релевантные фрагменты через similarity search
  /// и формирует ответ на основе найденного контекста.
  ///
  /// [question] — вопрос пользователя.
  /// [topK] — максимальное количество источников для ответа.
  Future<RagQueryResult> query(
    String question, {
    int topK = 5,
  });
}

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
  /// - `"cancelled"` — отменён пользователем
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
// Stream events
// ============================================================================

/// Событие стриминга RAG-ответа.
sealed class RagStreamEvent {
  const RagStreamEvent();
}

/// Фрагмент ответа (один или несколько токенов).
class RagTokenEvent extends RagStreamEvent {
  final String text;
  const RagTokenEvent(this.text);
}

/// Запрос завершён.
class RagDoneEvent extends RagStreamEvent {
  final RagQueryResult result;
  const RagDoneEvent(this.result);
}

// ============================================================================
// Service contract
// ============================================================================

/// Контракт для сервиса RAG-запросов.
///
/// Тяжёлая обработка выполняется в Rust core через FRB / C FFI.
/// Domain-слой не зависит от реализации.
abstract interface class RagService {
  /// Выполняет RAG-запрос по индексированным документам (одноразовый результат).
  Future<RagQueryResult> query(String question, {int topK = 5});

  /// Запускает RAG-запрос со стримингом токенов.
  ///
  /// Возвращает поток [RagStreamEvent]:
  /// - [RagTokenEvent] — фрагменты ответа (приходят по мере генерации)
  /// - [RagDoneEvent] — финальный результат с источниками
  Stream<RagStreamEvent> queryStream(String question, {int topK = 5});

  /// Отменяет текущий RAG-запрос.
  void cancelQuery();
}

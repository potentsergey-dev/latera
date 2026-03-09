/// Контракты для автоматической генерации описаний/саммари документов.
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка (LLM-инференс) выполняется в Rust core.
library;

/// Результат генерации описания.
///
/// Всегда возвращается (ошибки кодируются в [errorCode]).
class AutoSummaryResult {
  /// Сгенерированное описание/саммари.
  final String summary;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"empty_content"` — пустое содержимое
  /// - `"content_too_short"` — содержимое слишком короткое для саммари
  /// - `"generation_failed"` — ошибка при генерации
  /// - `"not_implemented"` — модель ещё не подключена (stub)
  final String? errorCode;

  const AutoSummaryResult({
    required this.summary,
    this.errorCode,
  });

  /// Успешно ли сгенерировано описание (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли описание.
  bool get hasSummary => summary.isNotEmpty;

  @override
  String toString() =>
      'AutoSummaryResult(success: $isSuccess, '
      'summary: ${summary.length} chars, error: $errorCode)';
}

/// Контракт для сервиса автоматической генерации описаний.
///
/// Тяжёлая обработка выполняется в Rust core через FRB (LLM-инференс).
/// Domain-слой не зависит от реализации.
abstract interface class AutoSummaryService {
  /// Генерирует описание/саммари на основе текстового содержимого файла.
  ///
  /// [textContent] — текстовое содержимое файла (из text_content, transcript и т.д.).
  /// [fileName] — имя файла (для контекста).
  Future<AutoSummaryResult> generateSummary(
    String textContent, {
    required String fileName,
  });
}

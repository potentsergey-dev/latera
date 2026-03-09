/// Контракты для автоматического присвоения тегов документам.
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка (LLM-инференс / keyword extraction)
/// выполняется в Rust core.
library;

/// Результат генерации тегов.
///
/// Всегда возвращается (ошибки кодируются в [errorCode]).
class AutoTagsResult {
  /// Сгенерированные теги (список).
  final List<String> tags;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"empty_content"` — пустое содержимое
  /// - `"content_too_short"` — содержимое слишком короткое
  /// - `"generation_failed"` — ошибка при генерации
  /// - `"not_implemented"` — модель ещё не подключена (stub)
  final String? errorCode;

  const AutoTagsResult({
    required this.tags,
    this.errorCode,
  });

  /// Успешно ли сгенерированы теги (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли теги.
  bool get hasTags => tags.isNotEmpty;

  /// Теги в виде строки через запятую (для хранения в БД).
  String get tagsAsString => tags.join(', ');

  @override
  String toString() =>
      'AutoTagsResult(success: $isSuccess, '
      'tags: ${tags.length}, error: $errorCode)';
}

/// Контракт для сервиса автоматической генерации тегов.
///
/// Тяжёлая обработка выполняется в Rust core через FRB
/// (LLM-инференс или keyword extraction).
/// Domain-слой не зависит от реализации.
abstract interface class AutoTagsService {
  /// Генерирует теги на основе текстового содержимого файла.
  ///
  /// [textContent] — текстовое содержимое файла.
  /// [fileName] — имя файла (для контекста).
  Future<AutoTagsResult> generateTags(
    String textContent, {
    required String fileName,
  });
}

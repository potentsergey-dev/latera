/// Контракты для извлечения текста из файлов (PDF, DOCX и др.).
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка выполняется в Rust core.
library;

/// Опции извлечения текста.
///
/// Отражает пользовательские лимиты из [AppConfig.effectiveLimits].
class ExtractionOptions {
  /// Максимальное количество страниц PDF для обработки.
  final int maxPagesPerPdf;

  /// Максимальный размер файла в мегабайтах.
  final int maxFileSizeMb;

  const ExtractionOptions({
    required this.maxPagesPerPdf,
    required this.maxFileSizeMb,
  });
}

/// Результат извлечения текста.
///
/// Всегда возвращается (ошибки кодируются в [errorCode]).
class ExtractionResult {
  /// Извлечённый текст (может быть пуст при ошибке).
  final String text;

  /// Тип контента: `"pdf"`, `"docx"`, `"text"`, `"unsupported"`, `"unknown"`.
  final String contentType;

  /// Количество обработанных страниц (для PDF; для остальных — 0).
  final int pagesExtracted;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"file_too_large"` — файл превышает лимит
  /// - `"too_many_pages"` — PDF превышает лимит (текст до лимита извлечён)
  /// - `"unsupported_format"` — формат не поддерживается
  /// - `"extraction_failed"` — внутренняя ошибка
  /// - `"file_not_found"` — файл не найден
  /// - `"not_implemented"` — экстрактор не реализован (stub)
  final String? errorCode;

  const ExtractionResult({
    required this.text,
    required this.contentType,
    required this.pagesExtracted,
    this.errorCode,
  });

  /// Успешно ли извлечение (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли извлечённый текст.
  bool get hasText => text.isNotEmpty;

  @override
  String toString() {
    return 'ExtractionResult(contentType: $contentType, '
        'chars: ${text.length}, pages: $pagesExtracted, '
        'error: $errorCode)';
  }
}

/// Контракт для извлечения текста из файлов (PDF, DOCX и др.).
///
/// Тяжёлая обработка выполняется в Rust core через FRB.
/// Domain-слой не зависит от реализации.
abstract interface class RichTextExtractor {
  /// Извлекает текст из файла с учётом лимитов.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [options] — лимиты из конфигурации.
  Future<ExtractionResult> extractText(
    String filePath,
    ExtractionOptions options,
  );
}

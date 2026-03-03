/// Контракты для оптического распознавания символов (OCR).
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка выполняется в Rust core (Tesseract C FFI / ONNX).
library;

/// Опции OCR.
///
/// Отражает пользовательские лимиты из [AppConfig.effectiveLimits].
class OcrOptions {
  /// Максимальное количество страниц скан-PDF для обработки.
  final int maxPagesPerPdf;

  /// Максимальный размер файла в мегабайтах.
  final int maxFileSizeMb;

  /// Язык OCR (ISO 639-1, например "rus", "eng").
  /// `null` = автоопределение / eng по умолчанию.
  final String? language;

  const OcrOptions({
    required this.maxPagesPerPdf,
    required this.maxFileSizeMb,
    this.language,
  });
}

/// Результат OCR.
///
/// Всегда возвращается (ошибки кодируются в [errorCode]).
class OcrResult {
  /// Распознанный текст (может быть пуст при ошибке).
  final String text;

  /// Тип контента: `"image"`, `"scan_pdf"`, `"unsupported"`, `"unknown"`.
  final String contentType;

  /// Количество обработанных страниц.
  final int pagesProcessed;

  /// Уверенность распознавания (0.0 – 1.0), `null` при ошибке.
  final double? confidence;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"file_too_large"` — файл превышает лимит
  /// - `"too_many_pages"` — скан-PDF превышает лимит (текст до лимита извлечён)
  /// - `"unsupported_format"` — формат не поддерживается
  /// - `"ocr_failed"` — внутренняя ошибка OCR-движка
  /// - `"file_not_found"` — файл не найден
  /// - `"not_implemented"` — OCR ещё не подключён (stub)
  /// - `"empty_image"` — изображение не содержит распознаваемого текста
  final String? errorCode;

  const OcrResult({
    required this.text,
    required this.contentType,
    required this.pagesProcessed,
    this.confidence,
    this.errorCode,
  });

  /// Успешно ли распознавание (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли распознанный текст.
  bool get hasText => text.isNotEmpty;

  @override
  String toString() {
    return 'OcrResult(contentType: $contentType, '
        'chars: ${text.length}, pages: $pagesProcessed, '
        'confidence: $confidence, error: $errorCode)';
  }
}

/// Контракт для оптического распознавания символов (OCR).
///
/// Тяжёлая обработка выполняется в Rust core через FRB.
/// Domain-слой не зависит от реализации.
abstract interface class OcrService {
  /// Извлекает текст из изображения или скан-PDF через OCR.
  ///
  /// [filePath] — абсолютный путь к файлу (png, jpg, tiff, bmp, webp, pdf).
  /// [options] — лимиты из конфигурации.
  Future<OcrResult> extractText(
    String filePath,
    OcrOptions options,
  );

  /// Проверяет, поддерживается ли файл для OCR.
  bool isSupported(String filePath);
}

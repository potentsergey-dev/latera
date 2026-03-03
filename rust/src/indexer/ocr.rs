//! Оптическое распознавание символов (OCR) для изображений и скан-PDF.
//!
//! Модуль предоставляет API для извлечения текста из изображений и
//! отсканированных PDF-документов. На текущем этапе реализована
//! stub-версия с полной валидацией входных данных — полноценная
//! интеграция с Tesseract (C FFI) или ONNX будет подключена после
//! проверки codegen и кросс-платформенной сборки.
//!
//! Поддерживаемые форматы:
//! - Изображения: png, jpg, jpeg, tiff, tif, bmp, webp
//! - Скан-PDF: pdf (когда text layer пуст или не обнаружен)
//!
//! Лимиты:
//! - `max_pages_per_pdf` — максимальное количество страниц скан-PDF
//! - `max_file_size_mb` — максимальный размер файла

use std::path::Path;

use log::{debug, warn};

// ============================================================================
// Supported extensions
// ============================================================================

/// Расширения изображений, поддерживаемых OCR.
const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "tiff", "tif", "bmp", "webp"];

/// Расширения PDF (для скан-PDF без text layer).
const OCR_PDF_EXTENSIONS: &[&str] = &["pdf"];

// ============================================================================
// Public types
// ============================================================================

/// Опции OCR.
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct OcrOptions {
    /// Максимальное количество страниц скан-PDF для обработки.
    pub max_pages_per_pdf: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
    /// Язык OCR (ISO 639-1, например "rus", "eng").
    /// `None` = автоопределение / eng по умолчанию.
    pub language: Option<String>,
}

impl Default for OcrOptions {
    fn default() -> Self {
        Self {
            max_pages_per_pdf: 100,
            max_file_size_mb: 50,
            language: None,
        }
    }
}

/// Результат OCR.
///
/// Всегда возвращается (не `Result`), ошибки кодируются в `error_code`.
#[derive(Clone, Debug)]
pub struct OcrResult {
    /// Распознанный текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"image"`, `"scan_pdf"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Количество обработанных страниц (для скан-PDF; для изображений — 1 при успехе, 0 при ошибке).
    pub pages_processed: u32,
    /// Уверенность распознавания (0.0 – 1.0), `None` при ошибке.
    pub confidence: Option<f64>,
    /// Код ошибки, если была:
    /// - `None` — успех
    /// - `"file_too_large"` — файл превышает лимит `max_file_size_mb`
    /// - `"too_many_pages"` — скан-PDF превышает лимит (текст до лимита извлечён)
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"ocr_failed"` — внутренняя ошибка OCR-движка
    /// - `"file_not_found"` — файл не найден / недоступен
    /// - `"not_implemented"` — OCR ещё не подключён (stub)
    /// - `"empty_image"` — изображение не содержит распознаваемого текста
    pub error_code: Option<String>,
}

impl OcrResult {
    /// Успешное распознавание.
    #[allow(dead_code)]
    fn success(text: String, content_type: &str, pages_processed: u32, confidence: f64) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_processed,
            confidence: Some(confidence),
            error_code: None,
        }
    }

    /// Частичный успех с предупреждением (например, too_many_pages).
    #[allow(dead_code)]
    fn with_warning(
        text: String,
        content_type: &str,
        pages_processed: u32,
        confidence: f64,
        error_code: &str,
    ) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_processed,
            confidence: Some(confidence),
            error_code: Some(error_code.to_string()),
        }
    }

    /// Ошибка без текста.
    fn error(content_type: &str, error_code: &str) -> Self {
        Self {
            text: String::new(),
            content_type: content_type.to_string(),
            pages_processed: 0,
            confidence: None,
            error_code: Some(error_code.to_string()),
        }
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Проверяет, является ли файл поддерживаемым для OCR.
pub fn is_ocr_supported(file_path: &Path) -> bool {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return false,
    };
    IMAGE_EXTENSIONS.contains(&ext.as_str()) || OCR_PDF_EXTENSIONS.contains(&ext.as_str())
}

/// Определяет тип контента OCR по расширению.
///
/// Возвращает `"image"`, `"scan_pdf"` или `"unsupported"`.
pub fn ocr_content_type(file_path: &Path) -> &'static str {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return "unsupported",
    };
    if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        "image"
    } else if OCR_PDF_EXTENSIONS.contains(&ext.as_str()) {
        "scan_pdf"
    } else {
        "unsupported"
    }
}

/// Извлекает текст из изображения или скан-PDF через OCR.
///
/// Текущая реализация — **stub**: выполняет полную валидацию входных данных
/// (формат, размер файла, лимиты страниц), но возвращает
/// `error_code = "not_implemented"` вместо реального OCR.
///
/// Полноценная интеграция будет добавлена после:
/// 1. Добавления `leptess` или `tesseract-sys` в Cargo.toml (Tesseract C FFI)
///    **или** `ort` (ONNX Runtime) для ML-based OCR
/// 2. Поставки Tesseract tessdata / ONNX-модели вместе с MSIX
/// 3. Реализации рендеринга PDF-страниц в растр (через `pdfium-render` или `mupdf`)
/// 4. Проверки кросс-платформенной сборки на CI
pub fn ocr_extract_text(file_path: &Path, options: &OcrOptions) -> OcrResult {
    // Проверяем расширение файла
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => {
            return OcrResult::error("unsupported", "unsupported_format");
        }
    };

    let content_type = if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        "image"
    } else if OCR_PDF_EXTENSIONS.contains(&ext.as_str()) {
        "scan_pdf"
    } else {
        return OcrResult::error("unsupported", "unsupported_format");
    };

    // Проверяем существование файла
    let metadata = match std::fs::metadata(file_path) {
        Ok(m) => m,
        Err(e) => {
            debug!("Cannot access file {}: {}", file_path.display(), e);
            return OcrResult::error("unknown", "file_not_found");
        }
    };

    // Проверяем размер файла
    let max_bytes = u64::from(options.max_file_size_mb) * 1024 * 1024;
    if metadata.len() > max_bytes {
        debug!(
            "File too large ({} bytes, limit {} MB): {}",
            metadata.len(),
            options.max_file_size_mb,
            file_path.display()
        );
        return OcrResult::error(content_type, "file_too_large");
    }

    // Для скан-PDF: лимит страниц будет проверяться при реальной обработке.
    // На данном этапе логируем и возвращаем stub.
    if content_type == "scan_pdf" {
        debug!(
            "OCR for scan-PDF (max {} pages): {}",
            options.max_pages_per_pdf,
            file_path.display()
        );
    }

    // ========================================================================
    // STUB: OCR-движок ещё не подключён.
    //
    // Здесь будет:
    //
    // Вариант A — Tesseract (C FFI через `leptess`):
    //   1. Для изображений: загрузка Leptonica Pix → Tesseract SetImage
    //   2. Для скан-PDF: рендеринг страниц в растр через pdfium/mupdf
    //   3. Tesseract GetUTF8Text() + GetMeanTextConf()
    //   4. Сбор текста со всех страниц
    //
    // Вариант B — ONNX Runtime (ML-based OCR):
    //   1. Предобработка изображения (resize, normalize)
    //   2. Детекция текстовых областей (CRAFT / DBNet)
    //   3. Распознавание символов (CRNN / TrOCR)
    //   4. Постпроцессинг и сборка текста
    //
    // Обе реализации уважают:
    //   - max_pages_per_pdf (для скан-PDF)
    //   - max_file_size_mb (проверено выше)
    //   - options.language (выбор tessdata / модели)
    // ========================================================================
    warn!(
        "OCR not yet implemented (stub), returning not_implemented: {}",
        file_path.display()
    );

    OcrResult::error(content_type, "not_implemented")
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // ====================================================================
    // is_ocr_supported
    // ====================================================================

    #[test]
    fn test_image_extensions_supported() {
        for ext in &["png", "jpg", "jpeg", "tiff", "tif", "bmp", "webp"] {
            let name = format!("test.{ext}");
            let path = Path::new(&name);
            assert!(
                is_ocr_supported(path),
                "Expected OCR support for .{ext}"
            );
        }
    }

    #[test]
    fn test_pdf_supported_for_ocr() {
        assert!(is_ocr_supported(Path::new("scan.pdf")));
    }

    #[test]
    fn test_unsupported_extensions() {
        for ext in &["txt", "docx", "mp3", "mp4", "rs", "exe"] {
            let name = format!("file.{ext}");
            let path = Path::new(&name);
            assert!(
                !is_ocr_supported(path),
                "Expected no OCR support for .{ext}"
            );
        }
    }

    #[test]
    fn test_no_extension() {
        assert!(!is_ocr_supported(Path::new("noext")));
    }

    // ====================================================================
    // ocr_content_type
    // ====================================================================

    #[test]
    fn test_content_type_image() {
        assert_eq!(ocr_content_type(Path::new("photo.png")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.jpg")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.jpeg")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.tiff")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.bmp")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.webp")), "image");
    }

    #[test]
    fn test_content_type_scan_pdf() {
        assert_eq!(ocr_content_type(Path::new("scan.pdf")), "scan_pdf");
    }

    #[test]
    fn test_content_type_unsupported() {
        assert_eq!(ocr_content_type(Path::new("file.txt")), "unsupported");
        assert_eq!(ocr_content_type(Path::new("noext")), "unsupported");
    }

    // ====================================================================
    // ocr_extract_text — validation
    // ====================================================================

    #[test]
    fn test_ocr_unsupported_format() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("file.txt"), &options);

        assert_eq!(result.content_type, "unsupported");
        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_ocr_no_extension() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("noext"), &options);

        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
    }

    #[test]
    fn test_ocr_file_not_found() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("/nonexistent/photo.png"), &options);

        assert_eq!(result.error_code.as_deref(), Some("file_not_found"));
    }

    #[test]
    fn test_ocr_file_too_large() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("big_image.png");
        // Создаём файл размером 2 MB
        let content = vec![0u8; 2 * 1024 * 1024];
        std::fs::write(&file_path, &content).unwrap();

        let options = OcrOptions {
            max_file_size_mb: 1,
            max_pages_per_pdf: 100,
            language: None,
        };
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "image");
        assert_eq!(result.error_code.as_deref(), Some("file_too_large"));
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_ocr_stub_returns_not_implemented_for_image() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.png");
        std::fs::write(&file_path, &[0u8; 100]).unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "image");
        assert_eq!(result.error_code.as_deref(), Some("not_implemented"));
        assert!(result.text.is_empty());
        assert!(result.confidence.is_none());
        assert_eq!(result.pages_processed, 0);
    }

    #[test]
    fn test_ocr_stub_returns_not_implemented_for_scan_pdf() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("scan.pdf");
        std::fs::write(&file_path, &[0u8; 100]).unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "scan_pdf");
        assert_eq!(result.error_code.as_deref(), Some("not_implemented"));
    }

    // ====================================================================
    // OcrOptions default
    // ====================================================================

    #[test]
    fn test_ocr_options_default() {
        let options = OcrOptions::default();
        assert_eq!(options.max_pages_per_pdf, 100);
        assert_eq!(options.max_file_size_mb, 50);
        assert!(options.language.is_none());
    }

    // ====================================================================
    // OcrResult constructors
    // ====================================================================

    #[test]
    fn test_ocr_result_success() {
        let result = OcrResult::success("Hello World".to_string(), "image", 1, 0.95);
        assert_eq!(result.text, "Hello World");
        assert_eq!(result.content_type, "image");
        assert_eq!(result.pages_processed, 1);
        assert_eq!(result.confidence, Some(0.95));
        assert!(result.error_code.is_none());
    }

    #[test]
    fn test_ocr_result_with_warning() {
        let result = OcrResult::with_warning(
            "Partial text".to_string(),
            "scan_pdf",
            5,
            0.8,
            "too_many_pages",
        );
        assert_eq!(result.text, "Partial text");
        assert_eq!(result.content_type, "scan_pdf");
        assert_eq!(result.pages_processed, 5);
        assert_eq!(result.confidence, Some(0.8));
        assert_eq!(result.error_code.as_deref(), Some("too_many_pages"));
    }

    #[test]
    fn test_ocr_result_error() {
        let result = OcrResult::error("image", "ocr_failed");
        assert!(result.text.is_empty());
        assert_eq!(result.content_type, "image");
        assert_eq!(result.pages_processed, 0);
        assert!(result.confidence.is_none());
        assert_eq!(result.error_code.as_deref(), Some("ocr_failed"));
    }

    // ====================================================================
    // Case-insensitive extension matching
    // ====================================================================

    #[test]
    fn test_case_insensitive_extensions() {
        assert!(is_ocr_supported(Path::new("photo.PNG")));
        assert!(is_ocr_supported(Path::new("photo.Jpg")));
        assert!(is_ocr_supported(Path::new("scan.PDF")));
        assert!(is_ocr_supported(Path::new("image.TIFF")));
    }

    #[test]
    fn test_ocr_extract_case_insensitive() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.JPEG");
        std::fs::write(&file_path, &[0u8; 100]).unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        // Should be recognized as image, not unsupported
        assert_eq!(result.content_type, "image");
        assert_eq!(result.error_code.as_deref(), Some("not_implemented"));
    }
}

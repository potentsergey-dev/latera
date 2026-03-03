//! Извлечение текстового содержимого из файлов.
//!
//! Поддерживаемые форматы:
//! - Plain-text (txt, md, исходный код и т.д.)
//! - PDF (text layer, без OCR) — через `lopdf`
//! - DOCX (Office Open XML) — через `zip` + `quick-xml`
//!
//! PDF и DOCX извлечение уважают лимиты из [`ExtractionOptions`].

use std::io::Read;
use std::path::Path;

use log::{debug, warn};

/// Максимальный размер файла для plain-text извлечения (10 MB).
const MAX_TEXT_FILE_SIZE: u64 = 10 * 1024 * 1024;

/// Расширения файлов, из которых извлекается текстовый контент (plain-text).
const TEXT_EXTENSIONS: &[&str] = &[
    "txt", "md", "markdown", "rst", "log", "csv", "tsv", "json", "xml", "yaml", "yml", "toml",
    "ini", "cfg", "conf", "properties",
    // Исходный код
    "rs", "dart", "py", "js", "ts", "java", "kt", "c", "cpp", "h", "hpp", "cs", "go", "rb",
    "php", "swift", "sh", "bash", "ps1", "bat", "cmd",
    // Web
    "html", "htm", "css", "scss", "sass", "less",
    // Другие текстовые
    "sql", "graphql", "proto", "env",
];

/// Расширения PDF файлов.
const PDF_EXTENSIONS: &[&str] = &["pdf"];

/// Расширения DOCX файлов.
const DOCX_EXTENSIONS: &[&str] = &["docx"];

// ============================================================================
// Public types
// ============================================================================

/// Опции извлечения текста.
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct ExtractionOptions {
    /// Максимальное количество страниц PDF для обработки.
    pub max_pages_per_pdf: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
}

impl Default for ExtractionOptions {
    fn default() -> Self {
        Self {
            max_pages_per_pdf: 100,
            max_file_size_mb: 50,
        }
    }
}

/// Результат извлечения текста.
///
/// Всегда возвращается (не `Result`), ошибки кодируются в `error_code`.
#[derive(Clone, Debug)]
pub struct ExtractionResult {
    /// Извлечённый текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"pdf"`, `"docx"`, `"text"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Количество обработанных страниц (для PDF; для остальных — 0).
    pub pages_extracted: u32,
    /// Код ошибки, если была:
    /// - `None` — успех
    /// - `"file_too_large"` — файл превышает лимит `max_file_size_mb`
    /// - `"too_many_pages"` — PDF превышает лимит (текст до лимита извлечён)
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"extraction_failed"` — внутренняя ошибка при извлечении
    /// - `"file_not_found"` — файл не найден / недоступен
    pub error_code: Option<String>,
}

impl ExtractionResult {
    fn success(text: String, content_type: &str, pages_extracted: u32) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_extracted,
            error_code: None,
        }
    }

    fn with_warning(
        text: String,
        content_type: &str,
        pages_extracted: u32,
        error_code: &str,
    ) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_extracted,
            error_code: Some(error_code.to_string()),
        }
    }

    fn error(content_type: &str, error_code: &str) -> Self {
        Self {
            text: String::new(),
            content_type: content_type.to_string(),
            pages_extracted: 0,
            error_code: Some(error_code.to_string()),
        }
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Извлекает текст из файла с учётом лимитов (rich API).
///
/// Поддерживает PDF (text layer), DOCX и plain-text форматы.
/// Для неподдерживаемых форматов возвращает `error_code = "unsupported_format"`.
pub fn extract_rich_content(file_path: &Path, options: &ExtractionOptions) -> ExtractionResult {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => {
            return ExtractionResult::error("unsupported", "unsupported_format");
        }
    };

    // Проверяем существование файла
    let metadata = match std::fs::metadata(file_path) {
        Ok(m) => m,
        Err(e) => {
            debug!("Cannot access file {}: {}", file_path.display(), e);
            return ExtractionResult::error("unknown", "file_not_found");
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
        return ExtractionResult::error(&ext, "file_too_large");
    }

    if PDF_EXTENSIONS.contains(&ext.as_str()) {
        extract_pdf(file_path, options)
    } else if DOCX_EXTENSIONS.contains(&ext.as_str()) {
        extract_docx(file_path)
    } else if TEXT_EXTENSIONS.contains(&ext.as_str()) {
        extract_plain_text_rich(file_path)
    } else {
        ExtractionResult::error("unsupported", "unsupported_format")
    }
}

/// Пытается извлечь plain-text содержимое файла (legacy API).
///
/// Возвращает `Some(content)` если файл является текстовым и
/// его размер не превышает `MAX_TEXT_FILE_SIZE`.
/// Возвращает `None` для нетекстовых файлов или при ошибке чтения.
///
/// **Не** поддерживает PDF/DOCX — для этого используйте [`extract_rich_content`].
pub fn extract_text(file_path: &Path) -> Option<String> {
    // Проверяем расширение
    let ext = file_path.extension()?.to_str()?.to_lowercase();
    if !TEXT_EXTENSIONS.contains(&ext.as_str()) {
        debug!(
            "Skipping text extraction for non-text file: {}",
            file_path.display()
        );
        return None;
    }

    // Проверяем размер файла
    let metadata = std::fs::metadata(file_path).ok()?;
    if metadata.len() > MAX_TEXT_FILE_SIZE {
        debug!(
            "Skipping text extraction: file too large ({} bytes): {}",
            metadata.len(),
            file_path.display()
        );
        return None;
    }

    // Читаем содержимое
    match std::fs::read_to_string(file_path) {
        Ok(content) => {
            debug!(
                "Extracted {} chars of text from: {}",
                content.len(),
                file_path.display()
            );
            Some(content)
        }
        Err(e) => {
            debug!(
                "Failed to read text from {}: {}",
                file_path.display(),
                e
            );
            None
        }
    }
}

// ============================================================================
// PDF extraction
// ============================================================================

/// Извлекает текст из PDF (text layer, без OCR).
///
/// Использует `lopdf` для парсинга PDF и извлечения текста.
/// Уважает `max_pages_per_pdf` — если страниц больше, извлекает
/// только первые N и возвращает `error_code = "too_many_pages"`.
fn extract_pdf(file_path: &Path, options: &ExtractionOptions) -> ExtractionResult {
    let doc = match lopdf::Document::load(file_path) {
        Ok(d) => d,
        Err(e) => {
            warn!("Failed to load PDF {}: {}", file_path.display(), e);
            return ExtractionResult::error("pdf", "extraction_failed");
        }
    };

    let pages = doc.get_pages();
    let total_pages = pages.len() as u32;
    let max_pages = options.max_pages_per_pdf;
    let pages_to_extract = total_pages.min(max_pages);

    debug!(
        "PDF {} has {} pages, extracting {}",
        file_path.display(),
        total_pages,
        pages_to_extract
    );

    // Собираем номера страниц (BTreeMap итерируется в порядке ключей)
    let page_numbers: Vec<u32> = pages
        .keys()
        .copied()
        .take(pages_to_extract as usize)
        .collect();

    let text = match doc.extract_text(&page_numbers) {
        Ok(t) => t,
        Err(e) => {
            warn!(
                "Failed to extract text from PDF {}: {}",
                file_path.display(),
                e
            );
            return ExtractionResult::error("pdf", "extraction_failed");
        }
    };

    debug!(
        "Extracted {} chars from {} pages of PDF: {}",
        text.len(),
        pages_to_extract,
        file_path.display()
    );

    if total_pages > max_pages {
        ExtractionResult::with_warning(text, "pdf", pages_to_extract, "too_many_pages")
    } else {
        ExtractionResult::success(text, "pdf", pages_to_extract)
    }
}

// ============================================================================
// DOCX extraction
// ============================================================================

/// Извлекает текст из DOCX (Office Open XML).
///
/// DOCX — это ZIP-архив, содержимое в `word/document.xml`.
/// Текст извлекается из элементов `<w:t>`, параграфы разделяются `\n`.
fn extract_docx(file_path: &Path) -> ExtractionResult {
    let file = match std::fs::File::open(file_path) {
        Ok(f) => f,
        Err(e) => {
            warn!("Failed to open DOCX {}: {}", file_path.display(), e);
            return ExtractionResult::error("docx", "extraction_failed");
        }
    };

    let mut archive = match zip::ZipArchive::new(file) {
        Ok(a) => a,
        Err(e) => {
            warn!(
                "Failed to open DOCX as ZIP {}: {}",
                file_path.display(),
                e
            );
            return ExtractionResult::error("docx", "extraction_failed");
        }
    };

    // Читаем word/document.xml — основное содержимое документа
    let xml_content = match archive.by_name("word/document.xml") {
        Ok(mut entry) => {
            let mut buf = String::new();
            if let Err(e) = entry.read_to_string(&mut buf) {
                warn!(
                    "Failed to read document.xml from {}: {}",
                    file_path.display(),
                    e
                );
                return ExtractionResult::error("docx", "extraction_failed");
            }
            buf
        }
        Err(e) => {
            warn!(
                "word/document.xml not found in {}: {}",
                file_path.display(),
                e
            );
            return ExtractionResult::error("docx", "extraction_failed");
        }
    };

    let text = parse_docx_xml(&xml_content);

    debug!(
        "Extracted {} chars from DOCX: {}",
        text.len(),
        file_path.display()
    );

    ExtractionResult::success(text, "docx", 0)
}

/// Парсит XML содержимое DOCX и извлекает плоский текст.
///
/// Обрабатывает:
/// - `<w:t>` — текстовые элементы
/// - `<w:p>` — параграфы (разделяются `\n`)
/// - `<w:br/>` — принудительные переносы строк
/// - `<w:tab/>` — табуляция
fn parse_docx_xml(xml: &str) -> String {
    use quick_xml::events::Event;
    use quick_xml::Reader;

    let mut reader = Reader::from_str(xml);
    let mut buf = Vec::new();
    let mut text = String::new();
    let mut in_text_element = false;
    let mut paragraph_has_content = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(ref e)) => {
                let name = e.name();
                if name.as_ref() == b"w:t" {
                    in_text_element = true;
                } else if name.as_ref() == b"w:p" {
                    paragraph_has_content = false;
                }
            }
            Ok(Event::End(ref e)) => {
                let name = e.name();
                if name.as_ref() == b"w:t" {
                    in_text_element = false;
                } else if name.as_ref() == b"w:p" && paragraph_has_content {
                    text.push('\n');
                }
            }
            Ok(Event::Text(ref e)) => {
                if in_text_element {
                    if let Ok(t) = e.unescape() {
                        text.push_str(&t);
                        paragraph_has_content = true;
                    }
                }
            }
            Ok(Event::Empty(ref e)) => {
                let name = e.name();
                if name.as_ref() == b"w:br" {
                    text.push('\n');
                    paragraph_has_content = true;
                } else if name.as_ref() == b"w:tab" {
                    text.push('\t');
                    paragraph_has_content = true;
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => {
                warn!("XML parse error in DOCX: {}", e);
                break;
            }
            _ => {}
        }
        buf.clear();
    }

    // Убираем trailing newline
    if text.ends_with('\n') {
        text.truncate(text.len() - 1);
    }

    text
}

// ============================================================================
// Plain text extraction (rich API)
// ============================================================================

/// Извлекает plain-text через rich API (возвращает [`ExtractionResult`]).
fn extract_plain_text_rich(file_path: &Path) -> ExtractionResult {
    match std::fs::read_to_string(file_path) {
        Ok(content) => {
            debug!(
                "Extracted {} chars of plain text from: {}",
                content.len(),
                file_path.display()
            );
            ExtractionResult::success(content, "text", 0)
        }
        Err(e) => {
            debug!(
                "Failed to read text from {}: {}",
                file_path.display(),
                e
            );
            ExtractionResult::error("text", "extraction_failed")
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    // ====================================================================
    // Legacy API tests (unchanged — обратная совместимость)
    // ====================================================================

    #[test]
    fn test_extract_text_from_txt() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.txt");
        let mut file = std::fs::File::create(&file_path).unwrap();
        write!(file, "Hello World").unwrap();

        let content = extract_text(&file_path);
        assert_eq!(content, Some("Hello World".to_string()));
    }

    #[test]
    fn test_extract_text_from_md() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("readme.md");
        let mut file = std::fs::File::create(&file_path).unwrap();
        write!(file, "# Title\nSome content").unwrap();

        let content = extract_text(&file_path);
        assert_eq!(content, Some("# Title\nSome content".to_string()));
    }

    #[test]
    fn test_skip_binary_file() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("image.png");
        std::fs::File::create(&file_path).unwrap();

        let content = extract_text(&file_path);
        assert!(content.is_none());
    }

    #[test]
    fn test_skip_pdf_file_legacy() {
        // Legacy API по-прежнему не поддерживает PDF
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("document.pdf");
        std::fs::File::create(&file_path).unwrap();

        let content = extract_text(&file_path);
        assert!(content.is_none());
    }

    #[test]
    fn test_nonexistent_file() {
        let content = extract_text(Path::new("/nonexistent/file.txt"));
        assert!(content.is_none());
    }

    // ====================================================================
    // Rich extraction API tests
    // ====================================================================

    #[test]
    fn test_rich_extract_plain_text() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("hello.txt");
        std::fs::write(&file_path, "Hello from rich API").unwrap();

        let options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &options);

        assert_eq!(result.content_type, "text");
        assert_eq!(result.text, "Hello from rich API");
        assert_eq!(result.pages_extracted, 0);
        assert!(result.error_code.is_none());
    }

    #[test]
    fn test_rich_extract_unsupported_format() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("image.png");
        std::fs::write(&file_path, &[0u8; 100]).unwrap();

        let options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &options);

        assert_eq!(result.content_type, "unsupported");
        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_rich_extract_file_too_large() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("big.txt");
        // Создаём файл размером 2 MB
        let content = "x".repeat(2 * 1024 * 1024);
        std::fs::write(&file_path, &content).unwrap();

        // Лимит: 1 MB
        let options = ExtractionOptions {
            max_file_size_mb: 1,
            max_pages_per_pdf: 100,
        };
        let result = extract_rich_content(&file_path, &options);

        assert_eq!(result.error_code.as_deref(), Some("file_too_large"));
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_rich_extract_nonexistent_file() {
        let options = ExtractionOptions::default();
        let result = extract_rich_content(Path::new("/nonexistent/file.txt"), &options);

        assert_eq!(result.error_code.as_deref(), Some("file_not_found"));
    }

    #[test]
    fn test_rich_extract_no_extension() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("noext");
        std::fs::write(&file_path, "some content").unwrap();

        let options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &options);

        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
    }

    #[test]
    fn test_extraction_options_default() {
        let options = ExtractionOptions::default();
        assert_eq!(options.max_pages_per_pdf, 100);
        assert_eq!(options.max_file_size_mb, 50);
    }

    // ====================================================================
    // DOCX XML parsing tests
    // ====================================================================

    #[test]
    fn test_parse_docx_xml_simple() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p>
                    <w:r>
                        <w:t>Hello World</w:t>
                    </w:r>
                </w:p>
                <w:p>
                    <w:r>
                        <w:t>Second paragraph</w:t>
                    </w:r>
                </w:p>
            </w:body>
        </w:document>"#;

        let text = parse_docx_xml(xml);
        assert_eq!(text, "Hello World\nSecond paragraph");
    }

    #[test]
    fn test_parse_docx_xml_with_formatting_runs() {
        let xml = r#"<?xml version="1.0"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p>
                    <w:r><w:t>Bold</w:t></w:r>
                    <w:r><w:t> and </w:t></w:r>
                    <w:r><w:t>italic</w:t></w:r>
                </w:p>
            </w:body>
        </w:document>"#;

        let text = parse_docx_xml(xml);
        assert_eq!(text, "Bold and italic");
    }

    #[test]
    fn test_parse_docx_xml_with_break_and_tab() {
        let xml = r#"<?xml version="1.0"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p>
                    <w:r><w:t>Before</w:t></w:r>
                    <w:r><w:br/></w:r>
                    <w:r><w:t>After break</w:t></w:r>
                </w:p>
                <w:p>
                    <w:r><w:tab/></w:r>
                    <w:r><w:t>Indented</w:t></w:r>
                </w:p>
            </w:body>
        </w:document>"#;

        let text = parse_docx_xml(xml);
        assert_eq!(text, "Before\nAfter break\n\tIndented");
    }

    #[test]
    fn test_parse_docx_xml_empty_paragraphs() {
        let xml = r#"<?xml version="1.0"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p></w:p>
                <w:p>
                    <w:r><w:t>Content</w:t></w:r>
                </w:p>
                <w:p></w:p>
            </w:body>
        </w:document>"#;

        let text = parse_docx_xml(xml);
        // Пустые параграфы не добавляют лишних переносов
        assert_eq!(text, "Content");
    }

    #[test]
    fn test_parse_docx_xml_special_chars() {
        let xml = r#"<?xml version="1.0"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                <w:p>
                    <w:r><w:t>Price: 5 &lt; 10 &amp; 20 &gt; 15</w:t></w:r>
                </w:p>
            </w:body>
        </w:document>"#;

        let text = parse_docx_xml(xml);
        assert_eq!(text, "Price: 5 < 10 & 20 > 15");
    }

    // ====================================================================
    // DOCX full extraction tests (ZIP + XML)
    // ====================================================================

    #[test]
    fn test_docx_extraction_with_real_zip() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.docx");

        // Создаём минимальный валидный DOCX (ZIP-архив)
        let file = std::fs::File::create(&file_path).unwrap();
        let mut zip = zip::ZipWriter::new(file);

        let options =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Stored);

        let xml_content = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:body>
        <w:p><w:r><w:t>Test document content</w:t></w:r></w:p>
        <w:p><w:r><w:t>Second line</w:t></w:r></w:p>
    </w:body>
</w:document>"#;

        zip.start_file("word/document.xml", options).unwrap();
        zip.write_all(xml_content.as_bytes()).unwrap();
        zip.finish().unwrap();

        let extract_options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &extract_options);

        assert_eq!(result.content_type, "docx");
        assert_eq!(result.text, "Test document content\nSecond line");
        assert!(result.error_code.is_none());
    }

    #[test]
    fn test_docx_extraction_invalid_zip() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("invalid.docx");
        std::fs::write(&file_path, "not a zip file").unwrap();

        let options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &options);

        assert_eq!(result.content_type, "docx");
        assert_eq!(result.error_code.as_deref(), Some("extraction_failed"));
    }

    #[test]
    fn test_docx_extraction_missing_document_xml() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("broken.docx");

        // Создаём ZIP без word/document.xml
        let file = std::fs::File::create(&file_path).unwrap();
        let mut zip = zip::ZipWriter::new(file);

        let options =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Stored);

        zip.start_file("other.xml", options).unwrap();
        zip.write_all(b"some content").unwrap();
        zip.finish().unwrap();

        let extract_options = ExtractionOptions::default();
        let result = extract_rich_content(&file_path, &extract_options);

        assert_eq!(result.content_type, "docx");
        assert_eq!(result.error_code.as_deref(), Some("extraction_failed"));
    }

    // Note: PDF extraction tests с реальными PDF-файлами находятся
    // в tests/text_extraction_integration_test.rs
}

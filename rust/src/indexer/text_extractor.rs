//! Извлечение текстового содержимого из файлов.
//!
//! На данном этапе (MVP) поддерживаются только plain-text форматы.
//! В будущем (Фаза 2-3) будут добавлены: PDF, DOCX, XLSX.

use std::path::Path;

use log::debug;

/// Максимальный размер файла для извлечения текста (10 MB).
const MAX_TEXT_FILE_SIZE: u64 = 10 * 1024 * 1024;

/// Расширения файлов, из которых извлекается текстовый контент.
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

/// Пытается извлечь текстовое содержимое файла.
///
/// Возвращает `Some(content)` если файл является текстовым и
/// его размер не превышает `MAX_TEXT_FILE_SIZE`.
/// Возвращает `None` для нетекстовых файлов или при ошибке чтения.
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

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
    fn test_skip_pdf_file() {
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
}

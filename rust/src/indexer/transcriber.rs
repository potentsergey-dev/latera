//! Транскрибация аудио/видео файлов.
//!
//! Модуль предоставляет API для транскрибации медиафайлов с использованием
//! Whisper.cpp (через whisper-rs binding). На текущем этапе реализована
//! stub-версия, которая возвращает заглушку — полноценная интеграция
//! с Whisper.cpp будет подключена после проверки codegen и сборки на CI.
//!
//! Поддерживаемые форматы: wav, mp3, m4a, ogg, flac, mp4, mkv, webm, avi.
//!
//! Лимиты:
//! - `max_media_minutes` — максимальная длительность медиа для обработки
//! - `max_file_size_mb` — максимальный размер файла

use std::path::Path;

use log::debug;

// ============================================================================
// Supported extensions
// ============================================================================

/// Аудио расширения.
const AUDIO_EXTENSIONS: &[&str] = &["wav", "mp3", "m4a", "ogg", "flac", "aac", "wma"];

/// Видео расширения (из которых можно извлечь аудиодорожку).
const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mkv", "webm", "avi", "mov", "wmv"];

// ============================================================================
// Public types
// ============================================================================

/// Опции транскрибации.
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct TranscriptionOptions {
    /// Максимальная длительность медиа для обработки (в минутах).
    /// 0 = транскрибация отключена.
    pub max_media_minutes: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
    /// Язык для транскрибации (ISO 639-1, например "ru", "en").
    /// `None` = автоопределение.
    pub language: Option<String>,
}

impl Default for TranscriptionOptions {
    fn default() -> Self {
        Self {
            max_media_minutes: 60,
            max_file_size_mb: 50,
            language: None,
        }
    }
}

/// Результат транскрибации.
///
/// Всегда возвращается (не `Result`), ошибки кодируются в `error_code`.
#[derive(Clone, Debug)]
pub struct TranscriptionResult {
    /// Расшифрованный текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"audio"`, `"video"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Длительность обработанного медиа в секундах.
    pub duration_seconds: u32,
    /// Код ошибки, если была:
    /// - `None` — успех
    /// - `"file_too_large"` — файл превышает лимит `max_file_size_mb`
    /// - `"media_too_long"` — медиа превышает лимит `max_media_minutes`
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"transcription_disabled"` — транскрибация отключена (`max_media_minutes == 0`)
    /// - `"transcription_failed"` — внутренняя ошибка
    /// - `"file_not_found"` — файл не найден / недоступен
    /// - `"not_implemented"` — Whisper ещё не подключён
    pub error_code: Option<String>,
}

impl TranscriptionResult {
    /// Успешная транскрибация.
    #[allow(dead_code)]
    fn success(text: String, content_type: &str, duration_seconds: u32) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            duration_seconds,
            error_code: None,
        }
    }

    /// Ошибка без текста.
    fn error(content_type: &str, error_code: &str) -> Self {
        Self {
            text: String::new(),
            content_type: content_type.to_string(),
            duration_seconds: 0,
            error_code: Some(error_code.to_string()),
        }
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Проверяет, является ли файл поддерживаемым медиафайлом для транскрибации.
pub fn is_media_file(file_path: &Path) -> bool {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return false,
    };
    AUDIO_EXTENSIONS.contains(&ext.as_str()) || VIDEO_EXTENSIONS.contains(&ext.as_str())
}

/// Определяет тип контента по расширению (`"audio"`, `"video"` или `"unsupported"`).
pub fn media_content_type(file_path: &Path) -> &'static str {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return "unsupported",
    };
    if AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        "audio"
    } else if VIDEO_EXTENSIONS.contains(&ext.as_str()) {
        "video"
    } else {
        "unsupported"
    }
}

/// Транскрибирует аудио/видео файл.
///
/// Текущая реализация — **stub**: выполняет валидацию входных данных
/// (формат, размер файла, лимит длительности), но возвращает
/// `error_code = "not_implemented"` вместо реальной транскрибации.
///
/// Полноценная интеграция с Whisper.cpp будет добавлена после:
/// 1. Добавления `whisper-rs` в Cargo.toml
/// 2. Загрузки модели (ggml-base.bin или аналог)
/// 3. Подключения FFmpeg для конвертации медиа в WAV-PCM
pub fn transcribe_audio(file_path: &Path, options: &TranscriptionOptions) -> TranscriptionResult {
    // Проверяем, не отключена ли транскрибация лимитом
    if options.max_media_minutes == 0 {
        debug!(
            "Transcription disabled (max_media_minutes=0): {}",
            file_path.display()
        );
        return TranscriptionResult::error("unknown", "transcription_disabled");
    }

    // Проверяем расширение файла
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => {
            return TranscriptionResult::error("unsupported", "unsupported_format");
        }
    };

    let content_type = if AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        "audio"
    } else if VIDEO_EXTENSIONS.contains(&ext.as_str()) {
        "video"
    } else {
        return TranscriptionResult::error("unsupported", "unsupported_format");
    };

    // Проверяем существование файла
    let metadata = match std::fs::metadata(file_path) {
        Ok(m) => m,
        Err(e) => {
            debug!("Cannot access file {}: {}", file_path.display(), e);
            return TranscriptionResult::error("unknown", "file_not_found");
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
        return TranscriptionResult::error(content_type, "file_too_large");
    }

    // ========================================================================
    // STUB: Whisper.cpp ещё не подключён.
    //
    // Здесь будет:
    // 1. Конвертация медиа в WAV 16kHz mono PCM (через symphonia или FFmpeg)
    // 2. Проверка длительности vs max_media_minutes
    // 3. Загрузка Whisper модели (кеширование через Lazy)
    // 4. Запуск инференса whisper_full()
    // 5. Сбор текста из сегментов
    // ========================================================================
    debug!(
        "Transcription not yet implemented (Whisper.cpp stub): {}",
        file_path.display()
    );
    TranscriptionResult::error(content_type, "not_implemented")
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn create_temp_file(name: &str, size_bytes: usize) -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(name);
        let mut f = std::fs::File::create(&path).unwrap();
        f.write_all(&vec![0u8; size_bytes]).unwrap();
        (dir, path)
    }

    // ------------------------------------------------------------------
    // is_media_file
    // ------------------------------------------------------------------

    #[test]
    fn test_is_media_file_audio() {
        assert!(is_media_file(Path::new("song.mp3")));
        assert!(is_media_file(Path::new("recording.wav")));
        assert!(is_media_file(Path::new("podcast.m4a")));
        assert!(is_media_file(Path::new("track.ogg")));
        assert!(is_media_file(Path::new("song.flac")));
        assert!(is_media_file(Path::new("audio.aac")));
        assert!(is_media_file(Path::new("clip.wma")));
    }

    #[test]
    fn test_is_media_file_video() {
        assert!(is_media_file(Path::new("video.mp4")));
        assert!(is_media_file(Path::new("movie.mkv")));
        assert!(is_media_file(Path::new("clip.webm")));
        assert!(is_media_file(Path::new("old.avi")));
        assert!(is_media_file(Path::new("screen.mov")));
        assert!(is_media_file(Path::new("rec.wmv")));
    }

    #[test]
    fn test_is_media_file_not_media() {
        assert!(!is_media_file(Path::new("doc.pdf")));
        assert!(!is_media_file(Path::new("file.txt")));
        assert!(!is_media_file(Path::new("image.png")));
        assert!(!is_media_file(Path::new("archive.zip")));
        assert!(!is_media_file(Path::new("noext")));
    }

    // ------------------------------------------------------------------
    // media_content_type
    // ------------------------------------------------------------------

    #[test]
    fn test_media_content_type() {
        assert_eq!(media_content_type(Path::new("a.mp3")), "audio");
        assert_eq!(media_content_type(Path::new("a.wav")), "audio");
        assert_eq!(media_content_type(Path::new("v.mp4")), "video");
        assert_eq!(media_content_type(Path::new("v.mkv")), "video");
        assert_eq!(media_content_type(Path::new("x.txt")), "unsupported");
        assert_eq!(media_content_type(Path::new("noext")), "unsupported");
    }

    // ------------------------------------------------------------------
    // transcribe_audio — validation
    // ------------------------------------------------------------------

    #[test]
    fn test_transcribe_disabled_when_max_minutes_zero() {
        let (_dir, path) = create_temp_file("audio.mp3", 1024);
        let opts = TranscriptionOptions {
            max_media_minutes: 0,
            ..Default::default()
        };
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("transcription_disabled"));
    }

    #[test]
    fn test_transcribe_unsupported_format() {
        let (_dir, path) = create_temp_file("doc.pdf", 1024);
        let opts = TranscriptionOptions::default();
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
    }

    #[test]
    fn test_transcribe_file_not_found() {
        let opts = TranscriptionOptions::default();
        let result = transcribe_audio(Path::new("/nonexistent/audio.mp3"), &opts);
        assert_eq!(result.error_code.as_deref(), Some("file_not_found"));
    }

    #[test]
    fn test_transcribe_file_too_large() {
        // Лимит 1 МБ, файл 2 МБ
        let (_dir, path) = create_temp_file("big.wav", 2 * 1024 * 1024);
        let opts = TranscriptionOptions {
            max_file_size_mb: 1,
            ..Default::default()
        };
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("file_too_large"));
        assert_eq!(result.content_type, "audio");
    }

    #[test]
    fn test_transcribe_stub_returns_not_implemented() {
        let (_dir, path) = create_temp_file("speech.mp3", 1024);
        let opts = TranscriptionOptions::default();
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("not_implemented"));
        assert_eq!(result.content_type, "audio");
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_transcribe_video_stub_returns_not_implemented() {
        let (_dir, path) = create_temp_file("lecture.mp4", 1024);
        let opts = TranscriptionOptions::default();
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("not_implemented"));
        assert_eq!(result.content_type, "video");
    }

    #[test]
    fn test_transcribe_no_extension() {
        let (_dir, path) = create_temp_file("noext", 1024);
        let opts = TranscriptionOptions::default();
        let result = transcribe_audio(&path, &opts);
        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
    }
}

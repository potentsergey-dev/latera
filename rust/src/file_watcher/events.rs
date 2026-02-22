//! Внутренние типы событий file_watcher.
//!
//! Эти типы используются внутри Rust Core и не зависят от FRB.
//! Преобразование в API-типы происходит в `api.rs`.

use std::path::PathBuf;

/// Внутреннее событие: добавлен новый файл.
#[derive(Clone, Debug)]
pub struct InternalFileEvent {
    /// Имя файла.
    pub file_name: String,
    /// Полный путь к файлу.
    pub full_path: PathBuf,
    /// Время события (Unix timestamp в миллисекундах).
    pub occurred_at_ms: i64,
}

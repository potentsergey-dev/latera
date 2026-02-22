use std::path::PathBuf;

/// Единый тип ошибок Rust Core.
///
/// Для FRB-совместимости реализован Display с машиночитаемым форматом.
/// Dart парсит этот формат для восстановления типа ошибки.
#[derive(thiserror::Error, Debug)]
pub enum LateraError {
    #[error("LateraError::DesktopDirNotFound: Desktop directory is not available on this OS/user")]
    DesktopDirNotFound,

    #[error("LateraError::InvalidPath: {0}")]
    InvalidPath(String),

    #[error("LateraError::WatcherAlreadyRunning: Watcher is already running")]
    WatcherAlreadyRunning,

    #[error("LateraError::WatcherNotRunning: Watcher is not running")]
    WatcherNotRunning,

    #[error("LateraError::Io: {0}")]
    Io(#[from] std::io::Error),

    #[error("LateraError::Notify: {0}")]
    Notify(#[from] notify::Error),

    #[error("LateraError::FileNameMissing: Cannot determine file name for path {0:?}")]
    FileNameMissing(PathBuf),

    #[error("LateraError::StreamClosed: Event stream was closed unexpectedly")]
    StreamClosed,

    #[error("LateraError::InitializationFailed: {0}")]
    InitializationFailed(String),
}

impl LateraError {
    /// Возвращает код ошибки для Dart-side маппинга.
    pub fn code(&self) -> &'static str {
        match self {
            LateraError::DesktopDirNotFound => "DESKTOP_DIR_NOT_FOUND",
            LateraError::InvalidPath(_) => "INVALID_PATH",
            LateraError::WatcherAlreadyRunning => "WATCHER_ALREADY_RUNNING",
            LateraError::WatcherNotRunning => "WATCHER_NOT_RUNNING",
            LateraError::Io(_) => "IO_ERROR",
            LateraError::Notify(_) => "NOTIFY_ERROR",
            LateraError::FileNameMissing(_) => "FILE_NAME_MISSING",
            LateraError::StreamClosed => "STREAM_CLOSED",
            LateraError::InitializationFailed(_) => "INITIALIZATION_FAILED",
        }
    }

    /// Проверяет, является ли ошибка recoverable (можно продолжить работу).
    pub fn is_recoverable(&self) -> bool {
        match self {
            LateraError::WatcherAlreadyRunning
            | LateraError::WatcherNotRunning
            | LateraError::StreamClosed => true,
            LateraError::DesktopDirNotFound
            | LateraError::InvalidPath(_)
            | LateraError::Io(_)
            | LateraError::Notify(_)
            | LateraError::FileNameMissing(_)
            | LateraError::InitializationFailed(_) => false,
        }
    }
}

use std::path::PathBuf;

/// Единый тип ошибок Rust Core.
#[derive(thiserror::Error, Debug)]
pub enum LateraError {
  #[error("Desktop directory is not available on this OS/user")]
  DesktopDirNotFound,

  #[error("Invalid path: {0}")]
  InvalidPath(String),

  #[error("Watcher is already running")]
  WatcherAlreadyRunning,

  #[error("Watcher is not running")]
  WatcherNotRunning,

  #[error("I/O error: {0}")]
  Io(#[from] std::io::Error),

  #[error("Notify error: {0}")]
  Notify(#[from] notify::Error),

  #[error("Cannot determine file name for path: {0:?}")]
  FileNameMissing(PathBuf),
}


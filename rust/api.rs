//! FRB API surface.
//!
//! Этот файл является входом для `flutter_rust_bridge_codegen`.
//! Должен оставаться тонким слоем: только типы/функции, которые экспортируются
//! через bridge. Вся логика — в `src/*` модулях.

use once_cell::sync::Lazy;
use std::sync::Mutex;

use crate::error::LateraError;
use crate::file_watcher;
use crate::frb_generated;
use crate::logging;

/// Событие: добавлен новый файл.
///
/// Поля подобраны так, чтобы их было удобно бриджить во Flutter.
#[derive(Clone, Debug)]
pub struct FileAddedEvent {
  pub file_name: String,
  pub full_path: String,
  pub occurred_at_ms: i64,
}

static FILE_ADDED_SINK: Lazy<Mutex<Option<frb_generated::StreamSink<FileAddedEvent>>>> =
  Lazy::new(|| Mutex::new(None));

static WATCHER: Lazy<Mutex<Option<file_watcher::WatcherHandle>>> = Lazy::new(|| Mutex::new(None));

/// Инициализация логирования в Rust.
///
/// Можно вызвать из Flutter сразу после старта.
pub fn init_logging() {
  logging::init_logging();
}

/// Stream событий добавления файла.
///
/// В Dart это будет выглядеть как `Stream<FileAddedEvent> onFileAdded()`.
pub fn on_file_added(sink: frb_generated::StreamSink<FileAddedEvent>) {
  logging::init_logging();
  *FILE_ADDED_SINK.lock().expect("FILE_ADDED_SINK poisoned") = Some(sink);
}

/// Запуск мониторинга.
///
/// - Если `override_path` = `None` → используется дефолтный `Desktop/Latera`.
/// - Если `Some` → должен быть абсолютный путь; директория будет создана при отсутствии.
///
/// Возвращает фактический путь директории наблюдения (для отображения в UI).
pub fn start_watching(override_path: Option<String>) -> Result<String, LateraError> {
  logging::init_logging();

  let mut guard = WATCHER.lock().expect("WATCHER poisoned");
  if guard.is_some() {
    return Err(LateraError::WatcherAlreadyRunning);
  }

  let handle = file_watcher::start_watcher(override_path, |event| {
    // Best-effort emit.
    if let Some(sink) = FILE_ADDED_SINK.lock().expect("FILE_ADDED_SINK poisoned").as_ref() {
      let _ = sink.add(event);
    }
  })?;

  let watch_dir = handle.watch_dir().to_string_lossy().to_string();
  *guard = Some(handle);
  Ok(watch_dir)
}

/// Остановить мониторинг (graceful shutdown).
pub fn stop_watching() -> Result<(), LateraError> {
  logging::init_logging();

  let mut guard = WATCHER.lock().expect("WATCHER poisoned");
  let handle = guard.take().ok_or(LateraError::WatcherNotRunning)?;
  handle.stop()?;
  Ok(())
}


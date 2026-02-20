//! Модуль мониторинга файловой системы.
//!
//! Отвечает за:
//! - определение пути к Desktop
//! - создание дефолтной директории `Desktop/Latera`
//! - запуск `notify` watcher
//! - graceful shutdown

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use log::{debug, error, info, warn};
use notify::{event::CreateKind, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::api::FileAddedEvent;
use crate::error::LateraError;

/// Десктоп-папка для наблюдения по умолчанию (внутри Desktop).
pub const DEFAULT_WATCH_FOLDER_NAME: &str = "Latera";

/// Handle запущенного watcher'а.
pub struct WatcherHandle {
  stop_tx: mpsc::Sender<()>,
  join: Option<thread::JoinHandle<()>>,
  watch_dir: PathBuf,
}

impl WatcherHandle {
  pub fn watch_dir(&self) -> &Path {
    &self.watch_dir
  }

  pub fn stop(mut self) -> Result<(), LateraError> {
    let _ = self.stop_tx.send(());
    if let Some(join) = self.join.take() {
      let _ = join.join();
    }
    Ok(())
  }
}

/// Определить дефолтную директорию наблюдения: `Desktop/Latera`.
/// Если директории нет — создать.
pub fn ensure_default_watch_dir() -> Result<PathBuf, LateraError> {
  let desktop = dirs::desktop_dir().ok_or(LateraError::DesktopDirNotFound)?;
  let watch_dir = desktop.join(DEFAULT_WATCH_FOLDER_NAME);
  std::fs::create_dir_all(&watch_dir)?;
  Ok(watch_dir)
}

fn ensure_override_dir(override_path: &str) -> Result<PathBuf, LateraError> {
  if override_path.trim().is_empty() {
    return Err(LateraError::InvalidPath("empty override_path".to_string()));
  }
  let p = PathBuf::from(override_path);
  if !p.is_absolute() {
    return Err(LateraError::InvalidPath(format!(
      "override_path must be absolute: {override_path}"
    )));
  }
  std::fs::create_dir_all(&p)?;
  Ok(p)
}

/// Запустить watcher.
///
/// `override_path`: абсолютный путь (если указан). Если `None`, используется дефолт `Desktop/Latera`.
/// `on_added`: callback, вызываемый при добавлении нового файла.
pub fn start_watcher(
  override_path: Option<String>,
  on_added: impl Fn(FileAddedEvent) + Send + Sync + 'static,
) -> Result<WatcherHandle, LateraError> {
  let watch_dir = match override_path {
    Some(p) => ensure_override_dir(&p)?,
    None => ensure_default_watch_dir()?,
  };

  info!("Starting watcher for: {}", watch_dir.display());

  let (stop_tx, stop_rx) = mpsc::channel::<()>();
  let (event_tx, event_rx) = mpsc::channel::<Result<notify::Event, notify::Error>>();

  let watch_dir_clone = watch_dir.clone();
  let join = thread::spawn(move || {
    let mut watcher: RecommendedWatcher = match notify::recommended_watcher(move |res| {
      // best-effort send; если receiver уже закрыт — просто игнорируем.
      let _ = event_tx.send(res);
    }) {
      Ok(w) => w,
      Err(e) => {
        error!("Failed to create watcher: {e}");
        return;
      }
    };

    if let Err(e) = watcher.watch(&watch_dir_clone, RecursiveMode::NonRecursive) {
      error!("Failed to watch directory {}: {e}", watch_dir_clone.display());
      return;
    }

    loop {
      // 1) graceful shutdown
      if stop_rx.try_recv().is_ok() {
        info!("Watcher shutdown requested");
        break;
      }

      // 2) обработка событий notify
      match event_rx.recv_timeout(Duration::from_millis(250)) {
        Ok(Ok(event)) => {
          debug!("notify event: {:?}", event.kind);
          if !is_create_file_event(&event.kind) {
            continue;
          }

          for path in event.paths {
            if !is_regular_file(&path) {
              continue;
            }

            match make_file_added_event(&path) {
              Ok(e) => on_added(e),
              Err(err) => warn!("Cannot build FileAddedEvent: {err}"),
            }
          }
        }
        Ok(Err(err)) => {
          warn!("notify error: {err}");
        }
        Err(mpsc::RecvTimeoutError::Timeout) => {
          // тик
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => {
          warn!("notify channel disconnected");
          break;
        }
      }
    }

    info!("Watcher thread finished");
  });

  Ok(WatcherHandle {
    stop_tx,
    join: Some(join),
    watch_dir,
  })
}

fn is_create_file_event(kind: &EventKind) -> bool {
  match kind {
    EventKind::Create(CreateKind::File) => true,
    // Некоторые FS/драйверы могут отдавать CreateKind::Any.
    EventKind::Create(CreateKind::Any) => true,
    // Иногда новое имя появляется как Rename.
    EventKind::Modify(_) => false,
    EventKind::Remove(_) => false,
    EventKind::Access(_) => false,
    EventKind::Other => false,
    EventKind::Any => false,
    EventKind::Create(_) => true,
  }
}

fn is_regular_file(path: &Path) -> bool {
  match std::fs::metadata(path) {
    Ok(m) => m.is_file(),
    Err(_) => false,
  }
}

fn make_file_added_event(path: &Path) -> Result<FileAddedEvent, LateraError> {
  let file_name = path
    .file_name()
    .and_then(|s| s.to_str())
    .ok_or_else(|| LateraError::FileNameMissing(path.to_path_buf()))?
    .to_string();

  let full_path = path.to_string_lossy().to_string();
  let occurred_at_ms = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap_or(Duration::from_millis(0))
    .as_millis() as i64;

  Ok(FileAddedEvent {
    file_name,
    full_path,
    occurred_at_ms,
  })
}


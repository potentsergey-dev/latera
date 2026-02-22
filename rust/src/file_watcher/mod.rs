//! Модуль мониторинга файловой системы.
//!
//! Отвечает за:
//! - определение пути к Desktop
//! - создание дефолтной директории `Desktop/Latera`
//! - запуск `notify` watcher
//! - graceful shutdown
//! - дедупликацию и rate-limiting событий

mod events;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use log::{debug, error, info, warn};
use notify::{event::CreateKind, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

pub use events::InternalFileEvent;

use crate::error::LateraError;

/// Десктоп-папка для наблюдения по умолчанию (внутри Desktop).
pub const DEFAULT_WATCH_FOLDER_NAME: &str = "Latera";

/// Политика сглаживания и backpressure.
///
/// Значения подобраны под desktop сценарий: достаточно отзывчиво для UI,
/// но защищает от burst-событий файловой системы.
const DEDUP_WINDOW: Duration = Duration::from_millis(300);
const RATE_LIMIT_PER_SECOND: u32 = 200;

/// Максимальный размер HashMap для дедупликации.
/// При превышении очищаются устаревшие записи.
const DEDUP_MAP_MAX_SIZE: usize = 1000;

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
        // Отправляем сигнал остановки. Если receiver уже мёртв — это не ошибка,
        // поток уже завершился.
        if let Err(e) = self.stop_tx.send(()) {
            log::warn!("Failed to send stop signal (channel closed): {e}");
            // Не возвращаем ошибку — поток уже не работает
        }

        // Ждём завершения потока. Если поток паниковал — логируем, но не падаем.
        if let Some(join) = self.join.take() {
            match join.join() {
                Ok(()) => {}
                Err(panic_payload) => {
                    log::error!("Watcher thread panicked: {:?}", panic_payload);
                    // Восстанавливаемся после паники, не возвращаем ошибку
                    // так как остановка всё равно произошла
                }
            }
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
    on_added: impl Fn(InternalFileEvent) + Send + Sync + 'static,
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
        // Клонируем sender для использования внутри closure watcher'а
        let event_tx_for_watcher = event_tx.clone();
        let mut watcher: RecommendedWatcher = match notify::recommended_watcher(move |res| {
            // Отправляем событие в канал. Если receiver закрыт — логируем и продолжаем.
            if let Err(e) = event_tx_for_watcher.send(res) {
                debug!("Failed to send notify event (channel closed): {e}");
            }
        }) {
            Ok(w) => w,
            Err(e) => {
                error!("Failed to create watcher: {e}");
                return;
            }
        };

        if let Err(e) = watcher.watch(&watch_dir_clone, RecursiveMode::NonRecursive) {
            error!(
                "Failed to watch directory {}: {e}",
                watch_dir_clone.display()
            );
            return;
        }

        // Burst/дедуп состояние.
        let mut last_seen: HashMap<String, Instant> = HashMap::new();
        let mut second_window_started_at = Instant::now();
        let mut second_event_count: u32 = 0;
        let mut cleanup_counter: u32 = 0;

        loop {
            // 1) graceful shutdown
            if stop_rx.try_recv().is_ok() {
                info!("Watcher shutdown requested");
                break;
            }

            // 2) обработка событий notify
            match event_rx.recv_timeout(Duration::from_millis(50)) {
                Ok(Ok(event)) => {
                    debug!("notify event: {:?}", event.kind);
                    if !is_create_file_event(&event.kind) {
                        continue;
                    }

                    for path in event.paths {
                        if !is_regular_file(&path) {
                            continue;
                        }

                        match make_internal_file_event(&path) {
                            Ok(e) => {
                                // 2.1) дедуп по полному пути (окно 300мс)
                                let key = e.full_path.to_string_lossy().to_string();
                                let now = Instant::now();
                                if let Some(prev) = last_seen.get(&key) {
                                    if now.duration_since(*prev) < DEDUP_WINDOW {
                                        debug!(
                                            "dedup: skipping duplicate event for {}",
                                            e.full_path.display()
                                        );
                                        continue;
                                    }
                                }
                                last_seen.insert(key, now);

                                // 2.1.1) Периодическая очистка устаревших записей
                                // Выполняется каждые 100 событий или при превышении лимита
                                cleanup_counter = cleanup_counter.saturating_add(1);
                                if last_seen.len() > DEDUP_MAP_MAX_SIZE
                                    || cleanup_counter >= 100
                                {
                                    let before = last_seen.len();
                                    last_seen.retain(|_, &mut instant| {
                                        now.duration_since(instant) < DEDUP_WINDOW * 10
                                    });
                                    if before != last_seen.len() {
                                        debug!(
                                            "Dedup map cleaned: {} -> {} entries",
                                            before,
                                            last_seen.len()
                                        );
                                    }
                                    cleanup_counter = 0;
                                }

                                // 2.2) rate-limit: не более 200 событий/сек
                                if second_window_started_at.elapsed() >= Duration::from_secs(1) {
                                    second_window_started_at = Instant::now();
                                    second_event_count = 0;
                                }
                                second_event_count = second_event_count.saturating_add(1);

                                if second_event_count <= RATE_LIMIT_PER_SECOND {
                                    on_added(e);
                                } else {
                                    // При превышении лимита — логируем и пропускаем.
                                    // В будущей версии здесь будет batch.
                                    warn!(
                                        "rate limit exceeded ({} events/sec), dropping event for {}",
                                        second_event_count,
                                        e.full_path.display()
                                    );
                                }
                            }
                            Err(err) => warn!("Cannot build InternalFileEvent: {err}"),
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

fn make_internal_file_event(path: &Path) -> Result<InternalFileEvent, LateraError> {
    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| LateraError::FileNameMissing(path.to_path_buf()))?
        .to_string();

    let full_path = path.to_path_buf();
    let occurred_at_ms = now_ms();

    Ok(InternalFileEvent {
        file_name,
        full_path,
        occurred_at_ms,
    })
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_millis(0))
        .as_millis() as i64
}

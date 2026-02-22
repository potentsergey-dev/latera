//! FRB API surface.
//!
//! Этот файл является входом для `flutter_rust_bridge_codegen`.
//! Должен оставаться тонким слоем: только типы/функции, которые экспортируются
//! через bridge. Вся логика — в `src/*` модулях.
//!
//! NOTE: Новая версия API (FileEvent, ApiVersion, LateraApiError) временно
//! отключена до ручной генерации FRB (codegen падает на Windows с prefix not found).
//! См. планы в `plans/runbook.md`.

use once_cell::sync::Lazy;
use std::sync::Mutex;

use crate::error::LateraError;
use crate::file_watcher;
use crate::frb_generated;
use crate::logging;
use log::warn;

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

fn close_file_added_stream() {
    // FRB stream закрывается при Drop последнего `StreamSink` (см. StreamSinkCloser).
    // Поэтому достаточно вынуть sink из глобального хранилища и дать ему дропнуться.
    // Примечание: recover from poisoned mutex - если предыдущий поток паниковал,
    // мы всё равно можем безопасно извлечь данные.
    let _dropped = FILE_ADDED_SINK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    // _dropped будет дропнут здесь, закрывая stream
    log::debug!("File added stream closed");
}

/// Инициализация логирования в Rust.
///
/// Можно вызвать из Flutter сразу после старта.
pub fn init_logging() {
    logging::init_logging();
}

/// Stream событий добавления файла.
///
/// В Dart это будет выглядеть как `Stream<FileAddedEvent> onFileAdded()`.
///
/// Контракт:
/// - один активный подписчик;
/// - при вызове [`stop_watching`](crate::api::stop_watching) стрим закрывается (onDone во Flutter);
/// - при повторном старте подписка создаётся заново.
pub fn on_file_added(sink: frb_generated::StreamSink<FileAddedEvent>) {
    logging::init_logging();

    // Контракт: один активный подписчик. Если подписчик уже есть — закрываем
    // старый stream и заменяем sink новым.
    // Примечание: recover from poisoned mutex - если предыдущий поток паниковал,
    // мы всё равно можем безопасно продолжить работу.
    let mut guard = FILE_ADDED_SINK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if guard.is_some() {
        warn!("on_file_added called while previous stream is still bound; closing previous stream");
    }
    *guard = Some(sink);
}

/// Запуск мониторинга.
///
/// - Если `override_path` = `None` → используется дефолтный `Desktop/Latera`.
/// - Если `Some` → должен быть абсолютный путь; директория будет создана при отсутствии.
///
/// Возвращает фактический путь директории наблюдения (для отображения в UI).
pub fn start_watching(override_path: Option<String>) -> Result<String, LateraError> {
    logging::init_logging();

    // Примечание: recover from poisoned mutex - если предыдущий поток паниковал,
    // мы всё равно можем безопасно продолжить работу.
    let mut guard = WATCHER
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if guard.is_some() {
        return Err(LateraError::WatcherAlreadyRunning);
    }

    let handle = file_watcher::start_watcher(override_path, |event| {
        // Emit события в stream. Если stream закрыт — логируем и продолжаем.
        if let Some(sink) = FILE_ADDED_SINK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
        {
            if let Err(e) = sink.add(FileAddedEvent {
                file_name: event.file_name,
                full_path: event.full_path.to_string_lossy().to_string(),
                occurred_at_ms: event.occurred_at_ms,
            }) {
                log::warn!("Failed to emit file added event (stream closed): {e}");
            }
        } else {
            log::debug!("File added event dropped (no active stream subscriber)");
        }
    })?;

    let watch_dir = handle.watch_dir().to_string_lossy().to_string();
    *guard = Some(handle);
    Ok(watch_dir)
}

/// Остановить мониторинг (graceful shutdown).
pub fn stop_watching() -> Result<(), LateraError> {
    logging::init_logging();

    // 1) Сначала останавливаем watcher (и ждём завершения треда), чтобы он больше
    // не мог эмитить события.
    // Примечание: recover from poisoned mutex - если предыдущий поток паниковал,
    // мы всё равно можем безопасно продолжить работу.
    let handle = {
        let mut guard = WATCHER
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.take()
    };

    if let Some(h) = handle {
        h.stop()?;
    }

    // 2) Затем закрываем stream (onDone во Flutter) и очищаем sink.
    close_file_added_stream();
    Ok(())
}

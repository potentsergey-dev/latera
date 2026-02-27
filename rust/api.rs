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
use std::path::Path;
use std::sync::Mutex;

use crate::error::LateraError;
use crate::file_watcher;
use crate::frb_generated;
use crate::indexer;
use crate::logging;
use log::warn;

use rusqlite::Connection;

/// Событие: добавлен новый файл.
///
/// Поля подобраны так, чтобы их было удобно бриджить во Flutter.
#[derive(Clone, Debug)]
pub struct FileAddedEvent {
    pub file_name: String,
    pub full_path: String,
    pub occurred_at_ms: i64,
}

/// Событие: файл удалён.
#[derive(Clone, Debug)]
pub struct FileRemovedEvent {
    pub file_name: String,
    pub full_path: String,
    pub occurred_at_ms: i64,
}

static FILE_ADDED_SINK: Lazy<Mutex<Option<frb_generated::StreamSink<FileAddedEvent>>>> =
    Lazy::new(|| Mutex::new(None));

static FILE_REMOVED_SINK: Lazy<Mutex<Option<frb_generated::StreamSink<FileRemovedEvent>>>> =
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

fn close_file_removed_stream() {
    let _dropped = FILE_REMOVED_SINK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    log::debug!("File removed stream closed");
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

/// Stream событий удаления файла.
///
/// В Dart это будет выглядеть как `Stream<FileRemovedEvent> onFileRemoved()`.
pub fn on_file_removed(sink: frb_generated::StreamSink<FileRemovedEvent>) {
    logging::init_logging();

    let mut guard = FILE_REMOVED_SINK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if guard.is_some() {
        warn!("on_file_removed called while previous stream is still bound; closing previous stream");
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

    let handle = file_watcher::start_watcher(
        override_path,
        |event| {
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
        },
        |event| {
            // Emit события удаления в stream.
            if let Some(sink) = FILE_REMOVED_SINK
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .as_ref()
            {
                if let Err(e) = sink.add(FileRemovedEvent {
                    file_name: event.file_name,
                    full_path: event.full_path.to_string_lossy().to_string(),
                    occurred_at_ms: event.occurred_at_ms,
                }) {
                    log::warn!("Failed to emit file removed event (stream closed): {e}");
                }
            } else {
                log::debug!("File removed event dropped (no active stream subscriber)");
            }
        },
    )?;

    let watch_dir = handle.watch_dir().to_string_lossy().to_string();
    *guard = Some(handle);
    Ok(watch_dir)
}

/// Получить дефолтный путь наблюдения (Desktop/Latera).
///
/// Создаёт директорию, если она не существует.
/// Не запускает watcher — только возвращает путь.
///
/// Используется для:
/// - Показа пути в UI до запуска watcher'а
/// - Сохранения пути при первом запуске (onboarding)
pub fn get_default_watch_path() -> Result<String, LateraError> {
    logging::init_logging();
    
    let watch_dir = file_watcher::ensure_default_watch_dir()?;
    Ok(watch_dir.to_string_lossy().to_string())
}

/// Получить дефолтный путь наблюдения (Desktop/Latera) **без** создания директории.
///
/// Важно: функция не трогает файловую систему и не создаёт папку.
/// Используется в онбординге для preview до явного согласия пользователя.
pub fn get_default_watch_path_preview() -> Result<String, LateraError> {
    logging::init_logging();

    let watch_dir = file_watcher::default_watch_dir_preview()?;
    Ok(watch_dir.to_string_lossy().to_string())
}

/// Получить путь, где будет храниться индекс (локально на устройстве).
///
/// Важно: функция **не** создаёт директорию.
/// Нужна, чтобы прозрачно показать пользователю, где лежат служебные данные.
///
/// Путь вычисляется через OS-provided local app data directory (MSIX/sandbox safe).
pub fn get_index_path() -> Result<String, LateraError> {
    logging::init_logging();

    let local_data = dirs::data_local_dir().ok_or(LateraError::DataLocalDirNotFound)?;
    let index_dir = local_data
        .join(file_watcher::DEFAULT_WATCH_FOLDER_NAME)
        .join("index");
    Ok(index_dir.to_string_lossy().to_string())
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
    close_file_removed_stream();
    Ok(())
}

// ============================================================================
// Index API
// ============================================================================

/// Глобальное соединение с БД индекса.
///
/// Инициализируется единожды при вызове [`init_index`].
/// Защищён мьютексом для потокобезопасного доступа.
static INDEX_DB: Lazy<Mutex<Option<Connection>>> = Lazy::new(|| Mutex::new(None));

/// Получить ссылку на подключение к БД.
/// Если БД не инициализирована — возвращает ошибку.
fn with_index_db<F, T>(f: F) -> Result<T, LateraError>
where
    F: FnOnce(&Connection) -> Result<T, LateraError>,
{
    let guard = INDEX_DB
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let conn = guard.as_ref().ok_or(LateraError::IndexNotInitialized)?;
    f(conn)
}

/// Инициализировать индексную БД.
///
/// Вызывается один раз при старте приложения.
/// `db_path` — путь к файлу SQLite (будет создан вместе с директорией).
///
/// Безопасен для повторного вызова — если БД уже открыта, вернёт Ok.
pub fn init_index(db_path: String) -> Result<(), LateraError> {
    logging::init_logging();

    let mut guard = INDEX_DB
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);

    if guard.is_some() {
        log::info!("Index DB already initialized, skipping");
        return Ok(());
    }

    let conn = indexer::init_db(&db_path)?;
    *guard = Some(conn);
    Ok(())
}

/// Результат поиска, экспортируемый через FRB в Dart.
#[derive(Clone, Debug)]
pub struct SearchResultItem {
    pub file_path: String,
    pub file_name: String,
    pub description: String,
    pub snippet: String,
    pub rank: f64,
}

/// Индексировать файл с описанием пользователя.
///
/// Автоматически извлекает текстовое содержимое из поддерживаемых форматов
/// (.txt, .md и др.) и добавляет его в FTS5 индекс.
///
/// Если файл уже есть в индексе — обновляет описание и содержимое.
pub fn index_file_with_description(
    file_path: String,
    file_name: String,
    description: String,
) -> Result<(), LateraError> {
    logging::init_logging();

    // Извлекаем текстовое содержимое, если файл текстовый
    let text_content = indexer::extract_text(Path::new(&file_path));

    with_index_db(|conn| {
        indexer::index_file(
            conn,
            &file_path,
            &file_name,
            &description,
            text_content.as_deref(),
        )?;
        Ok(())
    })
}

/// Поиск файлов по запросу.
///
/// Использует FTS5 полнотекстовый поиск по имени, описанию и содержимому.
/// Результаты упорядочены по BM25 рангу (наиболее релевантные первыми).
pub fn search_files(query: String, limit: u32) -> Result<Vec<SearchResultItem>, LateraError> {
    logging::init_logging();

    with_index_db(|conn| {
        let results = indexer::search(conn, &query, limit as usize)?;
        Ok(results
            .into_iter()
            .map(|r| SearchResultItem {
                file_path: r.file_path,
                file_name: r.file_name,
                description: r.description,
                snippet: r.snippet,
                rank: r.rank,
            })
            .collect())
    })
}

/// Удалить файл из индекса.
pub fn remove_from_index(file_path: String) -> Result<bool, LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::remove_file(conn, &file_path))
}

/// Проверить, проиндексирован ли файл.
pub fn is_file_indexed(file_path: String) -> Result<bool, LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::is_indexed(conn, &file_path))
}

/// Получить количество проиндексированных файлов.
pub fn get_indexed_file_count() -> Result<i64, LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::get_indexed_count(conn))
}

/// Очистить весь индекс.
pub fn clear_file_index() -> Result<(), LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::clear_index(conn))
}

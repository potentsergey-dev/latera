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
            // NOTE: Временно отключено — FRB codegen не генерирует SseEncode
            // для FileRemovedEvent. Будет включено после пересборки bindings.
            log::debug!(
                "File removed event: {} (stream emit disabled pending FRB codegen fix)",
                event.file_name
            );
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
pub(crate) fn with_index_db<F, T>(f: F) -> Result<T, LateraError>
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

// ============================================================================
// Text Extraction API (Phase 1: PDF/DOCX)
// ============================================================================

/// Опции извлечения текста (FRB bridge type).
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct ExtractionOptions {
    /// Максимальное количество страниц PDF для обработки.
    pub max_pages_per_pdf: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
}

/// Результат извлечения текста (FRB bridge type).
#[derive(Clone, Debug)]
pub struct ExtractionResult {
    /// Извлечённый текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"pdf"`, `"docx"`, `"text"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Количество обработанных страниц (для PDF; для остальных — 0).
    pub pages_extracted: u32,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"file_too_large"` — файл превышает лимит
    /// - `"too_many_pages"` — PDF превышает лимит страниц (текст до лимита извлечён)
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"extraction_failed"` — внутренняя ошибка
    /// - `"file_not_found"` — файл не найден
    pub error_code: Option<String>,
}

/// Извлечь текст из файла (PDF text layer, DOCX, plain-text).
///
/// Использует Rust-side extraction с уважением лимитов из `options`.
///
/// В Dart: `ExtractionResult extractTextFromFile(String path, ExtractionOptions options)`.
pub fn extract_text_from_file(path: String, options: ExtractionOptions) -> ExtractionResult {
    logging::init_logging();

    let internal_options = indexer::ExtractionOptions {
        max_pages_per_pdf: options.max_pages_per_pdf,
        max_file_size_mb: options.max_file_size_mb,
    };

    let result = indexer::extract_rich_content(Path::new(&path), &internal_options);

    ExtractionResult {
        text: result.text,
        content_type: result.content_type,
        pages_extracted: result.pages_extracted,
        error_code: result.error_code,
    }
}

// ============================================================================
// Transcription API (Phase 2: Whisper)
// ============================================================================

/// Опции транскрибации (FRB bridge type).
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

/// Результат транскрибации (FRB bridge type).
#[derive(Clone, Debug)]
pub struct TranscriptionResult {
    /// Расшифрованный текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"audio"`, `"video"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Длительность обработанного медиа в секундах.
    pub duration_seconds: u32,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"file_too_large"` — файл превышает лимит
    /// - `"media_too_long"` — медиа превышает лимит длительности
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"transcription_disabled"` — транскрибация отключена (max_media_minutes=0)
    /// - `"transcription_failed"` — внутренняя ошибка
    /// - `"file_not_found"` — файл не найден
    /// - `"not_implemented"` — Whisper ещё не подключён
    pub error_code: Option<String>,
}

/// Транскрибировать аудио/видео файл.
///
/// Использует Rust-side транскрибацию (Whisper.cpp) с уважением лимитов.
///
/// В Dart: `TranscriptionResult transcribeAudio(String path, TranscriptionOptions options)`.
pub fn transcribe_audio(path: String, options: TranscriptionOptions) -> TranscriptionResult {
    logging::init_logging();

    let internal_options = indexer::TranscriptionOptions {
        max_media_minutes: options.max_media_minutes,
        max_file_size_mb: options.max_file_size_mb,
        language: options.language,
    };

    let result = indexer::transcribe_audio(Path::new(&path), &internal_options);

    TranscriptionResult {
        text: result.text,
        content_type: result.content_type,
        duration_seconds: result.duration_seconds,
        error_code: result.error_code,
    }
}

/// Обновить транскрипт файла в индексе.
///
/// Записывает текст транскрибации в отдельную колонку `transcript_text`.
/// Если файл не найден в индексе — операция игнорируется.
pub fn update_transcript(file_path: String, transcript: String) -> Result<(), LateraError> {
    logging::init_logging();
    with_index_db(|conn| {
        indexer::update_transcript_text(conn, &file_path, &transcript)
    })
}

// ============================================================================
// Embeddings API (Phase 3)
// ============================================================================

/// Текстовый чанк (FRB bridge type).
#[derive(Clone, Debug)]
pub struct ApiTextChunk {
    /// Текст чанка.
    pub text: String,
    /// Индекс чанка в документе (0-based).
    pub chunk_index: u32,
    /// Смещение (байтовое) от начала документа.
    pub chunk_offset: u32,
}

/// Результат вычисления эмбеддинга (FRB bridge type).
#[derive(Clone, Debug)]
pub struct ApiEmbeddingVector {
    /// Индекс чанка.
    pub chunk_index: u32,
    /// Вектор эмбеддинга (f32).
    pub vector: Vec<f32>,
}

/// Результат similarity search (FRB bridge type).
#[derive(Clone, Debug)]
pub struct ApiSimilarityResult {
    /// Путь к файлу.
    pub file_path: String,
    /// Имя файла.
    pub file_name: String,
    /// Текст чанка, наиболее похожего на запрос.
    pub chunk_snippet: String,
    /// Смещение чанка в документе.
    pub chunk_offset: u32,
    /// Косинусное сходство (0.0 – 1.0).
    pub score: f64,
}

/// Разбить текст на чанки.
///
/// В Dart: `List<ApiTextChunk> chunkText(String text, int chunkSize, int chunkOverlap)`.
pub fn chunk_text(text: String, chunk_size: u32, chunk_overlap: u32) -> Vec<ApiTextChunk> {
    indexer::chunk_text(&text, chunk_size as usize, chunk_overlap as usize)
        .into_iter()
        .map(|c| ApiTextChunk {
            text: c.text,
            chunk_index: c.chunk_index,
            chunk_offset: c.chunk_offset,
        })
        .collect()
}

/// Вычислить эмбеддинги для набора чанков.
///
/// **Stub**: возвращает детерминированные псевдо-эмбеддинги (hash-based).
/// Полноценная модель будет подключена в будущем.
///
/// В Dart: `List<ApiEmbeddingVector> computeEmbeddings(List<ApiTextChunk> chunks)`.
pub fn compute_embeddings(chunks: Vec<ApiTextChunk>) -> Vec<ApiEmbeddingVector> {
    let internal: Vec<indexer::TextChunk> = chunks
        .into_iter()
        .map(|c| indexer::TextChunk {
            text: c.text,
            chunk_index: c.chunk_index,
            chunk_offset: c.chunk_offset,
        })
        .collect();

    indexer::compute_embeddings(&internal)
        .into_iter()
        .map(|e| ApiEmbeddingVector {
            chunk_index: e.chunk_index,
            vector: e.vector,
        })
        .collect()
}

/// Сохранить чанки и эмбеддинги для файла в БД.
///
/// Удаляет предыдущие эмбеддинги файла перед вставкой.
///
/// В Dart: `void storeChunksAndEmbeddings(String filePath, List<ApiTextChunk> chunks, List<ApiEmbeddingVector> embeddings)`.
pub fn store_chunks_and_embeddings(
    file_path: String,
    chunks: Vec<ApiTextChunk>,
    embeddings: Vec<ApiEmbeddingVector>,
) -> Result<(), LateraError> {
    logging::init_logging();

    with_index_db(|conn| {
        // Получаем file_id
        let file_info = indexer::get_indexed_file(conn, &file_path)?;
        let file_id = match file_info {
            Some(info) => info.id,
            None => return Err(LateraError::InvalidPath(
                format!("File not found in index: {file_path}"),
            )),
        };

        let internal_chunks: Vec<indexer::TextChunk> = chunks
            .iter()
            .map(|c| indexer::TextChunk {
                text: c.text.clone(),
                chunk_index: c.chunk_index,
                chunk_offset: c.chunk_offset,
            })
            .collect();

        let internal_embs: Vec<indexer::EmbeddingVector> = embeddings
            .iter()
            .map(|e| indexer::EmbeddingVector {
                chunk_index: e.chunk_index,
                vector: e.vector.clone(),
            })
            .collect();

        indexer::store_chunks_and_embeddings(conn, file_id, &internal_chunks, &internal_embs)
    })
}

/// Семантический поиск по запросу.
///
/// Вычисляет эмбеддинг запроса и ищет ближайшие чанки в БД.
///
/// В Dart: `List<ApiSimilarityResult> semanticSearch(String query, int topK)`.
pub fn semantic_search(
    query: String,
    top_k: u32,
) -> Result<Vec<ApiSimilarityResult>, LateraError> {
    logging::init_logging();

    with_index_db(|conn| {
        let results = indexer::similarity_search(conn, &query, top_k as usize)?;
        Ok(results
            .into_iter()
            .map(|r| ApiSimilarityResult {
                file_path: r.file_path,
                file_name: r.file_name,
                chunk_snippet: r.chunk_snippet,
                chunk_offset: r.chunk_offset,
                score: r.score,
            })
            .collect())
    })
}

/// Поиск файлов, похожих на указанный.
///
/// Берёт средний эмбеддинг чанков файла и ищет ближайшие в БД.
///
/// В Dart: `List<ApiSimilarityResult> findSimilarFiles(String filePath, int topK)`.
pub fn find_similar_files(
    file_path: String,
    top_k: u32,
) -> Result<Vec<ApiSimilarityResult>, LateraError> {
    logging::init_logging();

    with_index_db(|conn| {
        let results = indexer::find_similar_files(conn, &file_path, top_k as usize)?;
        Ok(results
            .into_iter()
            .map(|r| ApiSimilarityResult {
                file_path: r.file_path,
                file_name: r.file_name,
                chunk_snippet: r.chunk_snippet,
                chunk_offset: r.chunk_offset,
                score: r.score,
            })
            .collect())
    })
}

/// Проверить наличие эмбеддингов для файла.
pub fn has_embeddings(file_path: String) -> Result<bool, LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::has_embeddings(conn, &file_path))
}

/// Получить общее количество эмбеддингов в БД.
pub fn get_embedding_count() -> Result<i64, LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::get_embedding_count(conn))
}

/// Инициализировать semantic-модель (ONNX all-MiniLM-L6-v2).
///
/// Скачивает модель при первом вызове и загружает в память.
/// `data_dir` — путь к папке данных приложения (модель сохраняется
/// в `{data_dir}/models/all-MiniLM-L6-v2/`).
///
/// Тяжёлая операция — рекомендуется вызывать в background isolate.
pub fn init_semantic_model(data_dir: String) -> Result<(), LateraError> {
    logging::init_logging();
    indexer::init_semantic_model(&data_dir)
}

/// Проверить, загружена ли semantic-модель.
pub fn is_semantic_model_ready() -> bool {
    indexer::is_semantic_model_ready()
}

/// Выгрузить semantic-модель из памяти.
pub fn unload_semantic_model() {
    indexer::unload_semantic_model();
}

/// Получить текущую размерность эмбеддингов.
///
/// 384 если модель загружена, 64 (stub) если нет.
pub fn get_embedding_dim() -> u32 {
    indexer::current_embedding_dim() as u32
}

/// Очистить все эмбеддинги из БД.
///
/// Используется при переключении режима (stub → ONNX) для пересчёта
/// с новой размерностью.
pub fn clear_all_embeddings() -> Result<(), LateraError> {
    logging::init_logging();
    with_index_db(|conn| indexer::clear_all_embeddings(conn))
}

// ============================================================================
// RAG API (Phase 4: Local RAG «Спроси папку»)
// ============================================================================

/// Источник ответа RAG (FRB bridge type).
#[derive(Clone, Debug)]
pub struct ApiRagSource {
    /// Путь к файлу-источнику.
    pub file_path: String,
    /// Фрагмент текста чанка (обрезанный сниппет).
    pub chunk_snippet: String,
    /// Смещение (байтовое) чанка в документе.
    pub chunk_offset: u32,
}

/// Результат RAG-запроса (FRB bridge type).
#[derive(Clone, Debug)]
pub struct RagQueryResult {
    /// Сгенерированный ответ.
    pub answer: String,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"no_relevant_chunks"` — не найдено релевантных чанков
    /// - `"empty_question"` — пустой вопрос
    /// - `"query_failed"` — ошибка при выполнении запроса
    pub error_code: Option<String>,
    /// Источники (чанки, из которых сформирован ответ).
    pub sources: Vec<ApiRagSource>,
}

/// Выполнить RAG-запрос «Спроси свою папку».
///
/// Ищет релевантные чанки через similarity search и формирует ответ.
///
/// **Stub**: ответ — конкатенация найденных фрагментов.
/// Полноценная LLM-генерация будет подключена в будущем.
///
/// В Dart: `RagQueryResult ragQuery(String question, int topK)`.
pub fn rag_query(question: String, top_k: u32) -> Result<RagQueryResult, LateraError> {
    logging::init_logging();

    with_index_db(|conn| {
        let result = indexer::rag_query(conn, &question, top_k as usize)?;
        Ok(RagQueryResult {
            answer: result.answer,
            error_code: result.error_code,
            sources: result
                .sources
                .into_iter()
                .map(|s| ApiRagSource {
                    file_path: s.file_path,
                    chunk_snippet: s.chunk_snippet,
                    chunk_offset: s.chunk_offset,
                })
                .collect(),
        })
    })
}

// ============================================================================
// OCR API (Phase 5: Optical Character Recognition)
// ============================================================================

/// Опции OCR (FRB bridge type).
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct OcrOptions {
    /// Максимальное количество страниц скан-PDF для обработки.
    pub max_pages_per_pdf: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
    /// Язык OCR (ISO 639-1, например "rus", "eng").
    /// `None` = автоопределение / eng по умолчанию.
    pub language: Option<String>,
}

/// Результат OCR (FRB bridge type).
#[derive(Clone, Debug)]
pub struct OcrResult {
    /// Распознанный текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"image"`, `"scan_pdf"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Количество обработанных страниц.
    pub pages_processed: u32,
    /// Уверенность распознавания (0.0 – 1.0), `None` при ошибке.
    pub confidence: Option<f64>,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"file_too_large"` — файл превышает лимит
    /// - `"too_many_pages"` — скан-PDF превышает лимит страниц
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"ocr_failed"` — внутренняя ошибка OCR-движка
    /// - `"file_not_found"` — файл не найден
    /// - `"not_implemented"` — OCR ещё не подключён (stub)
    /// - `"empty_image"` — изображение не содержит текста
    pub error_code: Option<String>,
}

/// Извлечь текст из изображения или скан-PDF через OCR.
///
/// Использует Rust-side OCR (Tesseract C FFI / ONNX) с уважением лимитов.
///
/// **Stub**: выполняет валидацию входных данных, но возвращает
/// `error_code = "not_implemented"` до подключения OCR-движка.
///
/// В Dart: `OcrResult ocrExtractText(String path, OcrOptions options)`.
pub fn ocr_extract_text(path: String, options: OcrOptions) -> OcrResult {
    logging::init_logging();

    let internal_options = indexer::OcrOptions {
        max_pages_per_pdf: options.max_pages_per_pdf,
        max_file_size_mb: options.max_file_size_mb,
        language: options.language,
    };

    let result = indexer::ocr_extract_text(Path::new(&path), &internal_options);

    OcrResult {
        text: result.text,
        content_type: result.content_type,
        pages_processed: result.pages_processed,
        confidence: result.confidence,
        error_code: result.error_code,
    }
}

/// Проверить, поддерживается ли файл для OCR.
///
/// В Dart: `bool isOcrSupported(String path)`.
pub fn is_ocr_supported(path: String) -> bool {
    indexer::is_ocr_supported(Path::new(&path))
}

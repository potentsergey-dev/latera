//! Модуль индексации файлов с SQLite FTS5.
//!
//! Отвечает за:
//! - хранение метаданных файлов (путь, имя, описание, текст)
//! - полнотекстовый поиск через FTS5
//! - CRUD операции индекса

pub mod embeddings;
pub mod llm;
pub mod ocr;
pub mod rag;
mod text_extractor;
pub mod transcriber;

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use log::{debug, info, warn};
use rusqlite::{params, Connection};

use crate::error::LateraError;
pub use embeddings::{
    chunk_text, clear_all_embeddings, compute_embeddings, current_embedding_dim,
    find_similar_files, get_embedding_count, has_embeddings, init_embeddings_tables,
    init_semantic_model, is_semantic_model_ready, remove_embeddings_for_file,
    similarity_search, store_chunks_and_embeddings, unload_semantic_model,
    EmbeddingVector, SimilarityResult, TextChunk,
    DEFAULT_CHUNK_OVERLAP, DEFAULT_CHUNK_SIZE, EMBEDDING_DIM,
};
pub use ocr::{is_ocr_supported, ocr_content_type, ocr_extract_text, OcrOptions, OcrResult};
pub use llm::{generate_summary, generate_tags, is_llm_ready, LlmSummaryResult, LlmTagsResult};
pub use rag::{rag_query, rag_query_full_context, RagResult, RagSource};
pub use text_extractor::extract_text;
pub use text_extractor::{extract_rich_content, ExtractionOptions, ExtractionResult};
pub use transcriber::{transcribe_audio, TranscriptionOptions, TranscriptionResult};

/// Результат поиска файла.
#[derive(Clone, Debug)]
pub struct SearchResult {
    pub file_path: String,
    pub file_name: String,
    pub description: String,
    pub snippet: String,
    pub rank: f64,
}

/// Информация о проиндексированном файле.
#[derive(Clone, Debug)]
pub struct IndexedFileInfo {
    pub id: i64,
    pub file_path: String,
    pub file_name: String,
    pub description: String,
    pub indexed_at: i64,
}

/// Инициализирует базу данных индекса.
///
/// Создаёт таблицы `files` и `files_fts` (FTS5 виртуальная таблица),
/// а также триггеры для синхронизации FTS5 content с основной таблицей.
///
/// Безопасно для повторного вызова (IF NOT EXISTS).
pub fn init_db(db_path: &str) -> Result<Connection, LateraError> {
    // Создаём директорию для БД если не существует
    if let Some(parent) = Path::new(db_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    let conn = Connection::open(db_path)?;

    // WAL mode для лучшей concurrent-производительности
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;
    // Включаем foreign keys
    conn.execute_batch("PRAGMA foreign_keys=ON;")?;

    // Основная таблица с метаданными файлов
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY,
            file_path TEXT UNIQUE NOT NULL,
            file_name TEXT NOT NULL,
            description TEXT DEFAULT '',
            text_content TEXT DEFAULT '',
            transcript_text TEXT DEFAULT '',
            indexed_at INTEGER NOT NULL
        );",
    )?;

    // Миграция: добавляем колонку transcript_text если её нет (для существующих БД)
    let has_transcript_col: bool = conn
        .prepare("SELECT COUNT(*) FROM pragma_table_info('files') WHERE name='transcript_text'")
        .and_then(|mut s| s.query_row([], |r| r.get::<_, i64>(0)))
        .unwrap_or(0)
        > 0;
    if !has_transcript_col {
        conn.execute_batch(
            "ALTER TABLE files ADD COLUMN transcript_text TEXT DEFAULT '';",
        )?;
        info!("Migrated: added transcript_text column to files table");
    }

    // FTS5 виртуальная таблица для полнотекстового поиска.
    // content='files' означает external content FTS — FTS индекс ссылается
    // на данные из основной таблицы `files` (не хранит копию).
    // content_rowid='id' связывает FTS записи с основной таблицей.
    conn.execute_batch(
        "CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            file_name,
            description,
            text_content,
            transcript_text,
            content='files',
            content_rowid='id'
        );",
    )?;

    // Триггеры для автоматической синхронизации FTS5 при INSERT/UPDATE/DELETE.
    // Это гарантирует, что FTS5 индекс всегда актуален.
    // NOTE: DROP + CREATE для идемпотентной миграции (добавлена колонка transcript_text).
    conn.execute_batch(
        "DROP TRIGGER IF EXISTS files_ai;
        CREATE TRIGGER files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text)
            VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text);
        END;

        DROP TRIGGER IF EXISTS files_ad;
        CREATE TRIGGER files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text)
            VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text);
        END;

        DROP TRIGGER IF EXISTS files_au;
        CREATE TRIGGER files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text)
            VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text);
            INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text)
            VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text);
        END;",
    )?;

    // Phase 3: таблицы chunks + embeddings
    embeddings::init_embeddings_tables(&conn)?;

    info!("Index database initialized at: {db_path}");
    Ok(conn)
}

/// Индексирует файл с описанием пользователя.
///
/// Если файл уже есть в индексе — обновляет описание и текст.
/// Возвращает rowid записи.
pub fn index_file(
    conn: &Connection,
    file_path: &str,
    file_name: &str,
    description: &str,
    text_content: Option<&str>,
) -> Result<i64, LateraError> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let text = text_content.unwrap_or("");

    // UPSERT: вставляем или обновляем если файл уже есть
    conn.execute(
        "INSERT INTO files (file_path, file_name, description, text_content, indexed_at)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(file_path) DO UPDATE SET
            file_name = excluded.file_name,
            description = excluded.description,
            text_content = excluded.text_content,
            indexed_at = excluded.indexed_at",
        params![file_path, file_name, description, text, now],
    )?;

    let rowid = conn.last_insert_rowid();
    debug!("Indexed file: {file_name} (path={file_path}, rowid={rowid})");
    Ok(rowid)
}

/// Выполняет полнотекстовый поиск по индексу.
///
/// Ищет по имени файла, описанию и текстовому содержимому.
/// Результаты упорядочены по BM25 рангу (наиболее релевантные первыми).
///
/// BM25 веса: description (10.0) > file_name (5.0) > text_content (1.0)
pub fn search(
    conn: &Connection,
    query: &str,
    limit: usize,
) -> Result<Vec<SearchResult>, LateraError> {
    if query.trim().is_empty() {
        return Ok(Vec::new());
    }

    // Подготавливаем запрос для FTS5:
    // - добавляем * для prefix-match (частичные совпадения)
    // - экранируем двойные кавычки
    let fts_query = prepare_fts_query(query);

    if fts_query.is_empty() {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        "SELECT
            f.file_path,
            f.file_name,
            f.description,
            snippet(files_fts, 2, '<b>', '</b>', '...', 32) as snippet,
            bm25(files_fts, 5.0, 10.0, 1.0, 1.0) as rank
        FROM files_fts
        JOIN files f ON f.id = files_fts.rowid
        WHERE files_fts MATCH ?1
        ORDER BY rank
        LIMIT ?2",
    )?;

    let results = stmt
        .query_map(params![fts_query, limit], |row| {
            Ok(SearchResult {
                file_path: row.get(0)?,
                file_name: row.get(1)?,
                description: row.get(2)?,
                snippet: row.get(3)?,
                rank: row.get(4)?,
            })
        })?
        .filter_map(|r| match r {
            Ok(sr) => Some(sr),
            Err(e) => {
                warn!("Error reading search result row: {e}");
                None
            }
        })
        .collect();

    Ok(results)
}

/// Обновляет транскрипт проиндексированного файла.
///
/// Используется при фоновом обогащении контента (транскрибация Whisper).
/// Если файл не найден в индексе — операция игнорируется.
pub fn update_transcript_text(
    conn: &Connection,
    file_path: &str,
    transcript: &str,
) -> Result<(), LateraError> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let rows = conn.execute(
        "UPDATE files SET transcript_text = ?1, indexed_at = ?2 WHERE file_path = ?3",
        params![transcript, now, file_path],
    )?;

    if rows > 0 {
        debug!("Updated transcript for: {file_path} ({} chars)", transcript.len());
    } else {
        debug!("File not found in index for transcript update: {file_path}");
    }
    Ok(())
}

/// Удаляет файл из индекса.
pub fn remove_file(conn: &Connection, file_path: &str) -> Result<bool, LateraError> {
    let rows = conn.execute("DELETE FROM files WHERE file_path = ?1", params![file_path])?;
    if rows > 0 {
        debug!("Removed from index: {file_path}");
        Ok(true)
    } else {
        debug!("File not found in index: {file_path}");
        Ok(false)
    }
}

/// Возвращает количество проиндексированных файлов.
pub fn get_indexed_count(conn: &Connection) -> Result<i64, LateraError> {
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))?;
    Ok(count)
}

/// Очищает весь индекс.
pub fn clear_index(conn: &Connection) -> Result<(), LateraError> {
    conn.execute_batch(
        "DELETE FROM files;
         INSERT INTO files_fts(files_fts) VALUES('rebuild');",
    )?;
    info!("Index cleared");
    Ok(())
}

/// Проверяет, проиндексирован ли файл.
pub fn is_indexed(conn: &Connection, file_path: &str) -> Result<bool, LateraError> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM files WHERE file_path = ?1",
        params![file_path],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

/// Получить информацию о проиндексированном файле.
pub fn get_indexed_file(
    conn: &Connection,
    file_path: &str,
) -> Result<Option<IndexedFileInfo>, LateraError> {
    let mut stmt = conn.prepare(
        "SELECT id, file_path, file_name, description, indexed_at
         FROM files WHERE file_path = ?1",
    )?;

    let mut rows = stmt.query_map(params![file_path], |row| {
        Ok(IndexedFileInfo {
            id: row.get(0)?,
            file_path: row.get(1)?,
            file_name: row.get(2)?,
            description: row.get(3)?,
            indexed_at: row.get(4)?,
        })
    })?;

    match rows.next() {
        Some(Ok(info)) => Ok(Some(info)),
        Some(Err(e)) => Err(LateraError::Sqlite(e)),
        None => Ok(None),
    }
}

/// Подготавливает пользовательский запрос для FTS5.
///
/// - Разбивает на токены
/// - Добавляет `*` для prefix-match
/// - Экранирует специальные символы FTS5
fn prepare_fts_query(query: &str) -> String {
    let tokens: Vec<String> = query
        .split_whitespace()
        .filter(|t| !t.is_empty())
        .map(|token| {
            // Убираем FTS5 спецсимволы
            let clean: String = token
                .chars()
                .filter(|c| c.is_alphanumeric() || *c == '_' || *c == '-')
                .collect();
            if clean.is_empty() {
                String::new()
            } else {
                // Оборачиваем в кавычки и добавляем * для prefix-match
                format!("\"{clean}\"*")
            }
        })
        .filter(|t| !t.is_empty())
        .collect();

    tokens.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_db() -> Connection {
        init_db(":memory:").expect("Failed to create test DB")
    }

    #[test]
    fn test_init_db() {
        let conn = create_test_db();
        // Проверяем, что таблицы созданы
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 0);
    }

    #[test]
    fn test_index_and_search() {
        let conn = create_test_db();

        index_file(
            &conn,
            "/path/to/report.pdf",
            "report.pdf",
            "Квартальный отчёт за Q3 2025",
            None,
        )
        .unwrap();

        index_file(
            &conn,
            "/path/to/notes.txt",
            "notes.txt",
            "Заметки по проекту Latera",
            Some("Текст заметки с ключевыми словами для поиска"),
        )
        .unwrap();

        // Поиск по описанию
        let results = search(&conn, "отчёт", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "report.pdf");

        // Поиск по текстовому содержимому
        let results = search(&conn, "ключевыми", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "notes.txt");

        // Поиск по имени файла
        let results = search(&conn, "report", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "report.pdf");
    }

    #[test]
    fn test_upsert() {
        let conn = create_test_db();

        index_file(&conn, "/path/to/file.txt", "file.txt", "Описание 1", None).unwrap();
        index_file(
            &conn,
            "/path/to/file.txt",
            "file.txt",
            "Обновлённое описание",
            None,
        )
        .unwrap();

        let count = get_indexed_count(&conn).unwrap();
        assert_eq!(count, 1);

        let results = search(&conn, "Обновлённое", 10).unwrap();
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_remove_file() {
        let conn = create_test_db();

        index_file(&conn, "/path/to/file.txt", "file.txt", "Описание", None).unwrap();
        assert!(is_indexed(&conn, "/path/to/file.txt").unwrap());

        remove_file(&conn, "/path/to/file.txt").unwrap();
        assert!(!is_indexed(&conn, "/path/to/file.txt").unwrap());
    }

    #[test]
    fn test_clear_index() {
        let conn = create_test_db();

        index_file(&conn, "/a.txt", "a.txt", "File A", None).unwrap();
        index_file(&conn, "/b.txt", "b.txt", "File B", None).unwrap();
        assert_eq!(get_indexed_count(&conn).unwrap(), 2);

        clear_index(&conn).unwrap();
        assert_eq!(get_indexed_count(&conn).unwrap(), 0);
    }

    #[test]
    fn test_empty_query() {
        let conn = create_test_db();
        let results = search(&conn, "", 10).unwrap();
        assert!(results.is_empty());

        let results = search(&conn, "   ", 10).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_prefix_search() {
        let conn = create_test_db();

        index_file(
            &conn,
            "/path/to/document.pdf",
            "document.pdf",
            "Important document about programming",
            None,
        )
        .unwrap();

        // Prefix search: "doc" should match "document"
        let results = search(&conn, "doc", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "document.pdf");
    }

    #[test]
    fn test_get_indexed_file() {
        let conn = create_test_db();

        index_file(&conn, "/path/file.txt", "file.txt", "Test desc", None).unwrap();

        let info = get_indexed_file(&conn, "/path/file.txt").unwrap();
        assert!(info.is_some());
        let info = info.unwrap();
        assert_eq!(info.file_name, "file.txt");
        assert_eq!(info.description, "Test desc");

        let info = get_indexed_file(&conn, "/nonexistent").unwrap();
        assert!(info.is_none());
    }

    // ------------------------------------------------------------------
    // Phase 2: transcript_text
    // ------------------------------------------------------------------

    #[test]
    fn test_transcript_column_exists() {
        let conn = create_test_db();

        // Проверяем что колонка transcript_text существует
        let has_col: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM pragma_table_info('files') WHERE name='transcript_text'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(has_col, 1);
    }

    #[test]
    fn test_update_transcript_text() {
        let conn = create_test_db();

        index_file(
            &conn,
            "/media/lecture.mp4",
            "lecture.mp4",
            "Lecture on Rust programming",
            None,
        )
        .unwrap();

        update_transcript_text(
            &conn,
            "/media/lecture.mp4",
            "Today we will learn about ownership and borrowing in Rust",
        )
        .unwrap();

        // Проверяем что транскрипт сохранён
        let transcript: String = conn
            .query_row(
                "SELECT transcript_text FROM files WHERE file_path = ?1",
                params!["/media/lecture.mp4"],
                |row| row.get(0),
            )
            .unwrap();
        assert!(transcript.contains("ownership"));
    }

    #[test]
    fn test_search_finds_transcript_text() {
        let conn = create_test_db();

        index_file(
            &conn,
            "/media/podcast.mp3",
            "podcast.mp3",
            "Weekly tech podcast",
            None,
        )
        .unwrap();

        update_transcript_text(
            &conn,
            "/media/podcast.mp3",
            "In this episode we discuss quantum computing breakthroughs",
        )
        .unwrap();

        // Поиск по тексту из транскрипта
        let results = search(&conn, "quantum", 10).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].file_name, "podcast.mp3");
    }

    #[test]
    fn test_update_transcript_nonexistent_file() {
        let conn = create_test_db();

        // Обновление несуществующего файла не должно падать
        update_transcript_text(&conn, "/nonexistent.mp3", "some text").unwrap();
    }

    #[test]
    fn test_transcript_and_text_content_independent() {
        let conn = create_test_db();

        index_file(
            &conn,
            "/mixed/video_notes.mp4",
            "video_notes.mp4",
            "Video with notes",
            Some("Written notes about the video content"),
        )
        .unwrap();

        update_transcript_text(
            &conn,
            "/mixed/video_notes.mp4",
            "Spoken words from the audio track of the video",
        )
        .unwrap();

        // Поиск по text_content
        let results = search(&conn, "Written", 10).unwrap();
        assert_eq!(results.len(), 1);

        // Поиск по transcript_text
        let results = search(&conn, "Spoken", 10).unwrap();
        assert_eq!(results.len(), 1);

        // Оба поиска находят один и тот же файл
        assert_eq!(results[0].file_path, "/mixed/video_notes.mp4");
    }
}

//! Модуль индексации файлов с SQLite FTS5.
//!
//! Отвечает за:
//! - хранение метаданных файлов (путь, имя, описание, текст)
//! - полнотекстовый поиск через FTS5
//! - CRUD операции индекса

mod text_extractor;

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use log::{debug, info, warn};
use rusqlite::{params, Connection};

use crate::error::LateraError;
pub use text_extractor::extract_text;

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
            indexed_at INTEGER NOT NULL
        );",
    )?;

    // FTS5 виртуальная таблица для полнотекстового поиска.
    // content='files' означает external content FTS — FTS индекс ссылается
    // на данные из основной таблицы `files` (не хранит копию).
    // content_rowid='id' связывает FTS записи с основной таблицей.
    conn.execute_batch(
        "CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            file_name,
            description,
            text_content,
            content='files',
            content_rowid='id'
        );",
    )?;

    // Триггеры для автоматической синхронизации FTS5 при INSERT/UPDATE/DELETE.
    // Это гарантирует, что FTS5 индекс всегда актуален.
    conn.execute_batch(
        "CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, file_name, description, text_content)
            VALUES (new.id, new.file_name, new.description, new.text_content);
        END;

        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content)
            VALUES('delete', old.id, old.file_name, old.description, old.text_content);
        END;

        CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content)
            VALUES('delete', old.id, old.file_name, old.description, old.text_content);
            INSERT INTO files_fts(rowid, file_name, description, text_content)
            VALUES (new.id, new.file_name, new.description, new.text_content);
        END;",
    )?;

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
            bm25(files_fts, 5.0, 10.0, 1.0) as rank
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
}

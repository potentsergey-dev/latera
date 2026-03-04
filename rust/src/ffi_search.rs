//! C FFI bridge для семантического поиска — вызывается из Dart через `dart:ffi`.
//!
//! Аналогичен [`ffi_ocr`]: обходим ограничения FRB codegen на Windows,
//! экспортируя C-совместимые функции.
//!
//! **Важно**: Dart-side управляет своим собственным SQLite-подключением,
//! а глобальный `INDEX_DB` в Rust (api.rs) **не инициализируется** из Dart.
//! Поэтому каждая FFI-функция принимает `db_path_ptr` и открывает read-only
//! соединение самостоятельно.
//!
//! Результат возвращается как JSON строка (null-terminated C string).
//! Вызывающая сторона (Dart) должна освободить строку через [`latera_free_cstring`]
//! из `ffi_ocr`.

use std::ffi::{c_char, CStr, CString};

use rusqlite::Connection;

use crate::indexer;

/// Открывает read-only соединение с БД индекса.
///
/// Использует WAL mode для совместного доступа с основным Dart-подключением.
fn open_readonly_db(db_path: &str) -> Result<Connection, crate::error::LateraError> {
    let conn = Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
            | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;
    Ok(conn)
}

/// Семантический поиск по текстовому запросу.
///
/// Вычисляет эмбеддинг запроса (через ту же модель, что использовалась при индексации)
/// и ищет ближайшие чанки в БД.
///
/// # Параметры
/// - `db_path_ptr` — путь к SQLite БД индекса (UTF-8, null-terminated C string)
/// - `query_ptr` — текст запроса (UTF-8, null-terminated C string)
/// - `top_k` — максимальное количество результатов
///
/// # Возвращает
/// JSON строку (null-terminated C string) — массив объектов:
/// ```json
/// [{"file_path":"...","file_name":"...","chunk_snippet":"...","chunk_offset":0,"score":0.85}]
/// ```
///
/// При ошибке возвращает `[]`.
///
/// Вызывающая сторона **ДОЛЖНА** освободить строку через `latera_free_cstring`.
///
/// # Safety
/// - `db_path_ptr` и `query_ptr` должны быть валидными null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_semantic_search(
    db_path_ptr: *const c_char,
    query_ptr: *const c_char,
    top_k: u32,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let db_path = match ptr_to_str(db_path_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };
        let query = match ptr_to_str(query_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };

        if query.trim().is_empty() {
            return "[]".to_string();
        }

        let conn = match open_readonly_db(&db_path) {
            Ok(c) => c,
            Err(e) => {
                log::warn!("FFI semantic_search: cannot open DB {db_path}: {e}");
                return "[]".to_string();
            }
        };

        match indexer::similarity_search(&conn, &query, top_k as usize) {
            Ok(results) => results_to_json(&results),
            Err(e) => {
                log::warn!("FFI semantic_search error: {e}");
                "[]".to_string()
            }
        }
    });

    to_c_string(result.unwrap_or_else(|_| "[]".to_string()))
}

/// Поиск файлов, похожих на указанный.
///
/// # Параметры
/// - `db_path_ptr` — путь к SQLite БД индекса (UTF-8, null-terminated C string)
/// - `file_path_ptr` — абсолютный путь к файлу-источнику (UTF-8, null-terminated C string)
/// - `top_k` — максимальное количество результатов
///
/// # Возвращает
/// JSON строку — массив объектов (аналогично `latera_semantic_search`).
///
/// # Safety
/// - `db_path_ptr` и `file_path_ptr` должны быть валидными null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_find_similar_files(
    db_path_ptr: *const c_char,
    file_path_ptr: *const c_char,
    top_k: u32,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let db_path = match ptr_to_str(db_path_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };
        let file_path = match ptr_to_str(file_path_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };

        let conn = match open_readonly_db(&db_path) {
            Ok(c) => c,
            Err(e) => {
                log::warn!("FFI find_similar_files: cannot open DB {db_path}: {e}");
                return "[]".to_string();
            }
        };

        match indexer::find_similar_files(&conn, &file_path, top_k as usize) {
            Ok(results) => results_to_json(&results),
            Err(e) => {
                log::warn!("FFI find_similar_files error: {e}");
                "[]".to_string()
            }
        }
    });

    to_c_string(result.unwrap_or_else(|_| "[]".to_string()))
}

/// Проверяет, загружена ли ONNX semantic-модель.
///
/// # Возвращает
/// 1 если модель загружена, 0 если нет.
#[no_mangle]
pub extern "C" fn latera_is_semantic_model_ready() -> u32 {
    if indexer::is_semantic_model_ready() { 1 } else { 0 }
}

/// Вычисляет эмбеддинг для одного текста.
///
/// Использует загруженную ONNX-модель (all-MiniLM-L6-v2).
///
/// # Параметры
/// - `text_ptr` — текст для эмбеддинга (UTF-8, null-terminated C string)
///
/// # Возвращает
/// JSON строку — массив f32 значений: `[0.123, -0.456, ...]`
/// При ошибке возвращает `[]`.
///
/// # Safety
/// - `text_ptr` должен быть валидным null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_compute_embedding(
    text_ptr: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let text = match ptr_to_str(text_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };

        if text.trim().is_empty() {
            return "[]".to_string();
        }

        let chunks = vec![indexer::TextChunk {
            text: text.clone(),
            chunk_index: 0,
            chunk_offset: 0,
        }];

        let embeddings = indexer::compute_embeddings(&chunks);
        if embeddings.is_empty() {
            return "[]".to_string();
        }

        embedding_vec_to_json(&embeddings[0].vector)
    });

    to_c_string(result.unwrap_or_else(|_| "[]".to_string()))
}

/// Вычисляет эмбеддинги для нескольких текстов (batch).
///
/// # Параметры
/// - `texts_json_ptr` — JSON массив строк: `["text1", "text2", ...]`
///
/// # Возвращает
/// JSON строку — массив массивов f32: `[[0.1, -0.2, ...], [0.3, ...]]`
///
/// # Safety
/// - `texts_json_ptr` должен быть валидным null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_compute_embeddings_batch(
    texts_json_ptr: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let json_str = match ptr_to_str(texts_json_ptr) {
            Some(s) => s,
            None => return "[]".to_string(),
        };

        let texts = match parse_json_string_array(&json_str) {
            Some(t) => t,
            None => {
                log::warn!("FFI compute_embeddings_batch: failed to parse JSON array");
                return "[]".to_string();
            }
        };

        if texts.is_empty() {
            return "[]".to_string();
        }

        let chunks: Vec<indexer::TextChunk> = texts
            .iter()
            .enumerate()
            .map(|(i, t)| indexer::TextChunk {
                text: t.clone(),
                chunk_index: i as u32,
                chunk_offset: 0,
            })
            .collect();

        let embeddings = indexer::compute_embeddings(&chunks);

        let mut json = String::from("[");
        for (i, emb) in embeddings.iter().enumerate() {
            if i > 0 {
                json.push(',');
            }
            json.push_str(&embedding_vec_to_json(&emb.vector));
        }
        json.push(']');
        json
    });

    to_c_string(result.unwrap_or_else(|_| "[]".to_string()))
}

// ============================================================================
// Helpers
// ============================================================================

/// Безопасное преобразование C-строки в Rust String.
unsafe fn ptr_to_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

/// Конвертирует Rust String в C-строку (*mut c_char).
fn to_c_string(s: String) -> *mut c_char {
    let safe = s.replace('\0', " ");
    match CString::new(safe) {
        Ok(c) => c.into_raw(),
        Err(_) => {
            let fallback = CString::new("[]").unwrap();
            fallback.into_raw()
        }
    }
}

/// Сериализует вектор f32 в JSON массив.
fn embedding_vec_to_json(vec: &[f32]) -> String {
    let mut json = String::from("[");
    for (i, &v) in vec.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push_str(&format!("{v}"));
    }
    json.push(']');
    json
}

/// Парсит JSON массив строк (без serde).
///
/// Ожидает формат: `["text1", "text2", ...]`
fn parse_json_string_array(json: &str) -> Option<Vec<String>> {
    let trimmed = json.trim();
    if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
        return None;
    }
    let inner = &trimmed[1..trimmed.len() - 1];
    if inner.trim().is_empty() {
        return Some(Vec::new());
    }

    let mut result = Vec::new();
    let mut chars = inner.chars().peekable();

    loop {
        // Пропускаем пробелы и запятые
        while let Some(&c) = chars.peek() {
            if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ',' {
                chars.next();
            } else {
                break;
            }
        }

        if chars.peek().is_none() {
            break;
        }

        if chars.peek() != Some(&'"') {
            return None; // ожидали строку
        }
        chars.next(); // пропускаем открывающую кавычку

        let mut s = String::new();
        loop {
            match chars.next() {
                None => return None, // незакрытая строка
                Some('\\') => {
                    match chars.next() {
                        Some('"') => s.push('"'),
                        Some('\\') => s.push('\\'),
                        Some('n') => s.push('\n'),
                        Some('r') => s.push('\r'),
                        Some('t') => s.push('\t'),
                        Some(c) => {
                            s.push('\\');
                            s.push(c);
                        }
                        None => return None,
                    }
                }
                Some('"') => break, // конец строки
                Some(c) => s.push(c),
            }
        }
        result.push(s);
    }

    Some(result)
}

/// Сериализует результаты similarity search в JSON.
fn results_to_json(results: &[indexer::SimilarityResult]) -> String {
    let mut json = String::from("[");
    for (i, r) in results.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push('{');
        json.push_str(&format!(
            "\"file_path\":{},",
            escape_json_string(&r.file_path)
        ));
        json.push_str(&format!(
            "\"file_name\":{},",
            escape_json_string(&r.file_name)
        ));
        json.push_str(&format!(
            "\"chunk_snippet\":{},",
            escape_json_string(&r.chunk_snippet)
        ));
        json.push_str(&format!("\"chunk_offset\":{},", r.chunk_offset));
        json.push_str(&format!("\"score\":{}", r.score));
        json.push('}');
    }
    json.push(']');
    json
}

/// Экранирует строку для вставки в JSON.
fn escape_json_string(s: &str) -> String {
    let mut result = String::with_capacity(s.len() + 2);
    result.push('"');
    for c in s.chars() {
        match c {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                result.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => result.push(c),
        }
    }
    result.push('"');
    result
}

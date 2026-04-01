//! Local RAG — «Спроси свою папку».
//!
//! Phase 4: stub-реализация.
//! Использует similarity_search для поиска релевантных чанков,
//! затем формирует ответ на основе найденного контекста.
//!
//! **Stub**: ответ формируется простой конкатенацией найденных сниппетов.
//! Полноценная LLM-генерация (llama.cpp / ONNX) будет подключена в будущем.
//!
//! ## Архитектура
//!
//! ```text
//! Question  ──► embed(question) ──► similarity_search(top_k)
//!                                         │
//!                                         ▼
//!                                   relevant chunks
//!                                         │
//!                                         ▼
//!                               generate_answer(question, chunks)
//!                                         │
//!                                         ▼
//!                                   RagResult { answer, sources }
//! ```

use log::{debug, info, warn};
use rusqlite::Connection;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::Mutex;

use super::embeddings::{self, SimilarityResult};
use crate::error::LateraError;

// ============================================================================
// Global RAG configuration
// ============================================================================

/// Глобальный лимит генерируемых токенов для RAG.
static RAG_MAX_TOKENS: AtomicU32 = AtomicU32::new(0);

/// Флаг отмены текущего RAG-запроса.
static CANCEL_RAG: AtomicBool = AtomicBool::new(false);

/// Канал для стриминга событий RAG → Dart.
static STREAM_SENDER: Mutex<Option<mpsc::Sender<RagStreamEvent>>> = Mutex::new(None);
static STREAM_RECEIVER: Mutex<Option<mpsc::Receiver<RagStreamEvent>>> = Mutex::new(None);

/// Устанавливает глобальный лимит генерируемых токенов для RAG.
pub fn set_rag_max_tokens(max_tokens: u32) {
    info!("RAG max_tokens set to {}", max_tokens);
    RAG_MAX_TOKENS.store(max_tokens, Ordering::Relaxed);
}

/// Возвращает текущий лимит генерируемых токенов для RAG.
fn get_rag_max_tokens() -> u32 {
    RAG_MAX_TOKENS.load(Ordering::Relaxed)
}

/// Отменяет текущий RAG-запрос.
pub fn cancel_rag_query() {
    info!("RAG: cancel requested");
    CANCEL_RAG.store(true, Ordering::Relaxed);
    // Также отменяем LLM-генерацию, если она активна
    super::llm_engine::cancel_generation();
}

/// Проверяет, запрошена ли отмена.
fn is_cancelled() -> bool {
    CANCEL_RAG.load(Ordering::Relaxed)
}

// ============================================================================
// Streaming
// ============================================================================

/// Событие стриминга RAG-ответа.
#[derive(Clone, Debug)]
pub enum RagStreamEvent {
    /// Фрагмент ответа (один или несколько токенов).
    Token(String),
    /// Запрос завершён. Содержит финальный результат как JSON.
    Done {
        /// JSON-сериализованный RagResult.
        result_json: String,
    },
}

/// Создаёт канал стриминга. Возвращает sender (для rag_query_streaming).
fn init_stream_channel() -> mpsc::Sender<RagStreamEvent> {
    let (tx, rx) = mpsc::channel();
    *STREAM_SENDER.lock().unwrap() = Some(tx.clone());
    *STREAM_RECEIVER.lock().unwrap() = Some(rx);
    tx
}

/// Извлекает следующее событие из канала (неблокирующее).
pub fn poll_stream_event() -> Option<RagStreamEvent> {
    let guard = STREAM_RECEIVER.lock().unwrap();
    if let Some(rx) = guard.as_ref() {
        rx.try_recv().ok()
    } else {
        None
    }
}

/// Запускает RAG-запрос в отдельном потоке со стримингом событий.
///
/// Вызывающая сторона должна затем вызывать `poll_stream_event()`
/// для получения Token/Done событий.
pub fn rag_query_streaming_start(question: String, top_k: usize) {
    CANCEL_RAG.store(false, Ordering::Relaxed);
    let tx = init_stream_channel();

    std::thread::Builder::new()
        .name("rag-stream".into())
        .spawn(move || {
            rag_query_streaming_thread(&question, top_k, &tx);
        })
        .expect("failed to spawn rag-stream thread");
}

/// Рабочий поток стримингового RAG-запроса.
///
/// Фаза 1: Получение контекста из БД (внутри INDEX_DB мьютекса).
/// Фаза 2: Генерация ответа через LLM (ВНЕ мьютекса — не блокирует БД).
fn rag_query_streaming_thread(question: &str, top_k: usize, tx: &mpsc::Sender<RagStreamEvent>) {
    // Фаза 0: пустой вопрос
    if question.trim().is_empty() {
        let r = RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("empty_question".to_string()),
        };
        let _ = tx.send(RagStreamEvent::Done {
            result_json: rag_result_to_json(&r),
        });
        return;
    }

    // Фаза 1: работа с БД (мьютекс INDEX_DB захватывается и ОТПУСКАЕТСЯ здесь)
    let fetch_result = crate::api::with_index_db(|conn| rag_fetch_context(conn, question, top_k));

    let (context, sources) = match fetch_result {
        Ok(Some(data)) => data,
        Ok(None) => {
            let r = RagResult {
                answer: String::new(),
                sources: Vec::new(),
                error_code: Some("no_relevant_chunks".to_string()),
            };
            let _ = tx.send(RagStreamEvent::Done {
                result_json: rag_result_to_json(&r),
            });
            return;
        }
        Err(e) => {
            let r = RagResult {
                answer: String::new(),
                sources: Vec::new(),
                error_code: Some("query_failed".to_string()),
            };
            let _ = tx.send(RagStreamEvent::Done {
                result_json: rag_result_to_json(&r),
            });
            warn!("RAG stream: query failed: {e}");
            return;
        }
    };

    // Проверка отмены между фазами
    if is_cancelled() {
        let cancelled = RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("cancelled".to_string()),
        };
        let _ = tx.send(RagStreamEvent::Done {
            result_json: rag_result_to_json(&cancelled),
        });
        return;
    }

    // Фаза 2: генерация ответа (ВНЕ мьютекса БД — LLM может работать долго)
    let answer = generate_answer(question, &context, sources.len());

    let result = RagResult {
        answer,
        sources,
        error_code: None,
    };

    // Стримим ответ
    if result.has_answer() {
        let _ = tx.send(RagStreamEvent::Token(result.answer.clone()));
    }

    // Отправляем Done
    let _ = tx.send(RagStreamEvent::Done {
        result_json: rag_result_to_json(&result),
    });
}

/// Источник ответа RAG (чанк, из которого взята информация).
#[derive(Clone, Debug)]
pub struct RagSource {
    /// Путь к файлу.
    pub file_path: String,
    /// Фрагмент текста чанка.
    pub chunk_snippet: String,
    /// Смещение (байтовое) чанка в документе.
    pub chunk_offset: u32,
}

/// Результат RAG-запроса.
#[derive(Clone, Debug)]
pub struct RagResult {
    /// Сгенерированный ответ.
    pub answer: String,
    /// Источники (чанки, из которых сформирован ответ).
    pub sources: Vec<RagSource>,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"no_relevant_chunks"` — не найдено релевантных чанков
    /// - `"empty_question"` — пустой вопрос
    /// - `"query_failed"` — ошибка при выполнении запроса
    pub error_code: Option<String>,
}

impl RagResult {
    /// Есть ли ответ.
    pub fn has_answer(&self) -> bool {
        !self.answer.is_empty()
    }
}

/// Сериализует RagResult в JSON строку (для передачи через C FFI).
pub fn rag_result_to_json(result: &RagResult) -> String {
    // Ручная сериализация — без serde, чтобы не добавлять зависимость.
    let sources_json: Vec<String> = result
        .sources
        .iter()
        .map(|s| {
            format!(
                "{{\"file_path\":{},\"chunk_snippet\":{},\"chunk_offset\":{}}}",
                json_escape(&s.file_path),
                json_escape(&s.chunk_snippet),
                s.chunk_offset
            )
        })
        .collect();

    let error_code = match &result.error_code {
        Some(code) => json_escape(code),
        None => "null".to_string(),
    };

    format!(
        "{{\"answer\":{},\"sources\":[{}],\"error_code\":{}}}",
        json_escape(&result.answer),
        sources_json.join(","),
        error_code
    )
}

/// Экранирует строку для JSON.
fn json_escape(s: &str) -> String {
    json_escape_inner(s)
}

/// Публичная версия json_escape для использования из ffi_rag.
pub fn json_escape_pub(s: &str) -> String {
    json_escape_inner(s)
}

fn json_escape_inner(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// ============================================================================
// RAG query
// ============================================================================

/// Выполняет RAG-запрос по индексированным документам.
///
/// 1. Ищет `top_k` наиболее релевантных чанков через similarity search.
/// 2. Формирует ответ из найденного контекста.
///
/// **Stub-реализация**: ответ — конкатенация найденных сниппетов.
/// При подключении LLM контекст будет передаваться как prompt.
///
/// Минимальный порог похожести — `MIN_SIMILARITY_SCORE`.
/// Чанки с score ниже порога отбрасываются.
pub fn rag_query(
    conn: &Connection,
    question: &str,
    top_k: usize,
) -> Result<RagResult, LateraError> {
    if question.trim().is_empty() {
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("empty_question".to_string()),
        });
    }

    info!(
        "RAG query: \"{}\" (top_k={})",
        truncate(question, 80),
        top_k
    );

    // 1. Similarity search — находим релевантные чанки
    let similar = embeddings::similarity_search(conn, question, top_k)?;

    if similar.is_empty() {
        debug!("RAG: no relevant chunks found for query");
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("no_relevant_chunks".to_string()),
        });
    }

    // 2. Фильтруем по минимальному порогу
    let relevant: Vec<&SimilarityResult> = similar
        .iter()
        .filter(|r| r.score >= MIN_SIMILARITY_SCORE)
        .collect();

    if relevant.is_empty() {
        debug!(
            "RAG: all {} chunks below similarity threshold ({})",
            similar.len(),
            MIN_SIMILARITY_SCORE
        );
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("no_relevant_chunks".to_string()),
        });
    }

    // 3. Собираем контекст из релевантных чанков
    let context_parts: Vec<String> = relevant.iter().map(|r| r.chunk_snippet.clone()).collect();

    let context = context_parts.join("\n\n---\n\n");

    // 4. Генерируем ответ (LLM если доступен, иначе stub)
    let answer = generate_answer(question, &context, relevant.len());

    // 5. Собираем источники (дедупликация по file_path)
    let mut seen_paths = std::collections::HashSet::new();
    let sources: Vec<RagSource> = relevant
        .iter()
        .filter(|r| seen_paths.insert(r.file_path.clone()))
        .map(|r| RagSource {
            file_path: r.file_path.clone(),
            chunk_snippet: r.chunk_snippet.clone(),
            chunk_offset: r.chunk_offset,
        })
        .collect();

    info!(
        "RAG query completed: {} sources, answer {} chars",
        sources.len(),
        answer.len()
    );

    Ok(RagResult {
        answer,
        sources,
        error_code: None,
    })
}

/// Выполняет RAG-запрос с расширенным контекстом из полных чанков.
///
/// Использует [`embeddings::similarity_search`] для отбора кандидатов
/// (гибридный scoring: semantic + lexical boost для коротких запросов),
/// затем загружает ПОЛНЫЙ текст чанков из БД для формирования ответа.
pub fn rag_query_full_context(
    conn: &Connection,
    question: &str,
    top_k: usize,
) -> Result<RagResult, LateraError> {
    if question.trim().is_empty() {
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("empty_question".to_string()),
        });
    }

    match rag_fetch_context(conn, question, top_k)? {
        None => Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("no_relevant_chunks".to_string()),
        }),
        Some((context, sources)) => {
            let answer = generate_answer(question, &context, sources.len());
            Ok(RagResult {
                answer,
                sources,
                error_code: None,
            })
        }
    }
}

/// Фаза 1 RAG: только работа с БД (similarity_search + загрузка текстов чанков).
///
/// Возвращает `None` если нет релевантных чанков.
/// Не вызывает LLM — чтобы не держать мьютекс БД во время генерации.
fn rag_fetch_context(
    conn: &Connection,
    question: &str,
    top_k: usize,
) -> Result<Option<(String, Vec<RagSource>)>, LateraError> {
    info!(
        "RAG query (fetch context): \"{}\" (top_k={})",
        truncate(question, 80),
        top_k
    );

    let candidates = embeddings::similarity_search(conn, question, top_k)?;

    if candidates.is_empty() {
        debug!("RAG fetch-context: no relevant candidates from similarity_search");
        return Ok(None);
    }

    info!(
        "RAG fetch-context: {} candidates from similarity_search",
        candidates.len()
    );

    let mut context_parts: Vec<String> = Vec::new();
    let mut sources: Vec<RagSource> = Vec::new();

    for candidate in &candidates {
        let full_text: Option<String> = conn
            .prepare_cached(
                "SELECT c.chunk_text FROM chunks c
                 JOIN files f ON f.id = c.file_id
                 WHERE f.file_path = ?1 AND c.chunk_offset = ?2
                 LIMIT 1",
            )?
            .query_map(
                rusqlite::params![candidate.file_path, candidate.chunk_offset],
                |row| row.get(0),
            )?
            .filter_map(Result::ok)
            .next();

        let text = full_text.unwrap_or_else(|| candidate.chunk_snippet.clone());
        context_parts.push(text);

        sources.push(RagSource {
            file_path: candidate.file_path.clone(),
            chunk_snippet: candidate.chunk_snippet.clone(),
            chunk_offset: candidate.chunk_offset,
        });
    }

    let context = context_parts.join("\n\n---\n\n");
    Ok(Some((context, sources)))
}

// ============================================================================
// Constants
// ============================================================================

/// Минимальный порог cosine similarity для включения чанка в RAG контекст.
///
/// Чанки с score ниже этого значения считаются нерелевантными.
/// Для stub-эмбеддингов используется низкий порог (0.05),
/// при подключении реальной модели можно увеличить до 0.3—0.5.
const MIN_SIMILARITY_SCORE: f64 = 0.05;

// ============================================================================
// Helpers
// ============================================================================

/// Генерирует ответ: через LLM если загружен, иначе stub-конкатенация.
fn generate_answer(question: &str, context: &str, source_count: usize) -> String {
    let max_tokens = get_rag_max_tokens();

    if super::llm_engine::is_llm_ready() {
        info!(
            "RAG: generate_answer (max_tokens={}, llm=active)",
            max_tokens
        );
        let language = detect_question_language(question);
        let system_prompt = super::llm_engine::rag_system_prompt(&language);
        let user_prompt =
            format!("Context from user's files:\n\n{context}\n\nQuestion: {question}");
        match super::llm_engine::generate_with_context(&system_prompt, &user_prompt, max_tokens) {
            Ok(answer) if !answer.is_empty() => return answer,
            Ok(_) => warn!("RAG: LLM returned empty answer, falling back to stub"),
            Err(e) => warn!("RAG: LLM generation failed: {e}, falling back to stub"),
        }
    } else {
        info!("RAG: generate_answer (max_tokens={}, llm=stub)", max_tokens);
    }

    generate_stub_answer(question, context, source_count)
}

/// Простая эвристика определения языка вопроса.
///
/// Если вопрос содержит кириллические символы — «ru», иначе «en».
#[allow(dead_code)]
fn detect_question_language(question: &str) -> String {
    let cyrillic_count = question
        .chars()
        .filter(|c| matches!(*c, '\u{0400}'..='\u{04FF}'))
        .count();
    let total_alpha = question.chars().filter(|c| c.is_alphabetic()).count();
    if total_alpha > 0 && cyrillic_count * 2 > total_alpha {
        "ru".to_string()
    } else {
        "en".to_string()
    }
}

/// Максимальное количество фрагментов в stub-ответе (без LLM).
const MAX_STUB_FRAGMENTS: usize = 3;

/// Максимальная длина одного фрагмента в stub-ответе (символов).
const MAX_STUB_FRAGMENT_LEN: usize = 300;

/// Генерирует stub-ответ на основе контекста.
///
/// Показывает краткую выдержку из топ-3 фрагментов (до 300 символов каждый).
/// Источники (имя файла, позиция) отображаются отдельно в UI как карточки.
fn generate_stub_answer(_question: &str, context: &str, source_count: usize) -> String {
    let fragments: Vec<&str> = context.split("\n\n---\n\n").collect();
    let shown = fragments.len().min(MAX_STUB_FRAGMENTS);
    let mut result = format!(
        "⚠️ Генеративная модель (LLM) не загружена — показаны наиболее релевантные фрагменты ({} из {}).\n",
        shown,
        source_count,
    );
    for (i, fragment) in fragments.iter().take(MAX_STUB_FRAGMENTS).enumerate() {
        let trimmed = fragment.trim();
        if !trimmed.is_empty() {
            let snippet = truncate(trimmed, MAX_STUB_FRAGMENT_LEN);
            result.push_str(&format!("\n{}. {}\n", i + 1, snippet));
        }
    }
    result
}

/// Склоняем слово «фрагмент» по числу.
#[allow(dead_code)]
fn pluralize_fragment(n: usize) -> &'static str {
    let rem100 = n % 100;
    let rem10 = n % 10;
    if (11..=14).contains(&rem100) {
        "фрагментов"
    } else if rem10 == 1 {
        "фрагмент"
    } else if (2..=4).contains(&rem10) {
        "фрагмента"
    } else {
        "фрагментов"
    }
}

/// Извлекает имя файла из полного пути.
#[allow(dead_code)]
fn extract_filename(path: &str) -> &str {
    std::path::Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(path)
}

/// Обрезает строку до указанной длины.
fn truncate(s: &str, max_len: usize) -> String {
    if s.chars().count() <= max_len {
        s.to_string()
    } else {
        let truncated: String = s.chars().take(max_len).collect();
        format!("{truncated}…")
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::indexer;
    use crate::indexer::embeddings::{
        chunk_text, compute_embeddings, init_embeddings_tables, store_chunks_and_embeddings,
        DEFAULT_CHUNK_OVERLAP, DEFAULT_CHUNK_SIZE,
    };

    fn create_test_db() -> Connection {
        let conn = indexer::init_db(":memory:").expect("Failed to create test DB");
        init_embeddings_tables(&conn).expect("Failed to init embeddings tables");
        conn
    }

    /// Индексирует файл с текстом и создаёт эмбеддинги для него.
    fn index_with_embeddings(
        conn: &Connection,
        file_path: &str,
        file_name: &str,
        description: &str,
        text: &str,
    ) {
        indexer::index_file(conn, file_path, file_name, description, Some(text))
            .expect("index_file failed");
        let info = indexer::get_indexed_file(conn, file_path)
            .expect("get_indexed_file failed")
            .expect("file not found");
        let chunks = chunk_text(text, DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let embeddings = compute_embeddings(&chunks);
        store_chunks_and_embeddings(conn, info.id, &chunks, &embeddings).expect("store failed");
    }

    // ------------------------------------------------------------------
    // Basic RAG query
    // ------------------------------------------------------------------

    #[test]
    fn test_rag_query_empty_question() {
        let conn = create_test_db();
        let result = rag_query(&conn, "", 5).unwrap();
        assert_eq!(result.error_code.as_deref(), Some("empty_question"));
        assert!(result.answer.is_empty());
        assert!(result.sources.is_empty());
    }

    #[test]
    fn test_rag_query_whitespace_question() {
        let conn = create_test_db();
        let result = rag_query(&conn, "   ", 5).unwrap();
        assert_eq!(result.error_code.as_deref(), Some("empty_question"));
    }

    #[test]
    fn test_rag_query_no_embeddings() {
        let conn = create_test_db();
        let result = rag_query(&conn, "What is Rust?", 5).unwrap();
        assert_eq!(result.error_code.as_deref(), Some("no_relevant_chunks"));
        assert!(result.answer.is_empty());
        assert!(result.sources.is_empty());
    }

    #[test]
    fn test_rag_query_basic() {
        let conn = create_test_db();

        index_with_embeddings(
            &conn,
            "/docs/rust_guide.txt",
            "rust_guide.txt",
            "Guide to Rust programming",
            "Rust is a systems programming language focused on safety and performance.",
        );

        index_with_embeddings(
            &conn,
            "/docs/cooking.txt",
            "cooking.txt",
            "Cooking recipes",
            "This book contains delicious pasta recipes from Italy.",
        );

        let result = rag_query(&conn, "programming language", 5).unwrap();

        // Stub: должен найти хотя бы один источник
        assert!(
            result.error_code.is_none(),
            "error: {:?}",
            result.error_code
        );
        assert!(!result.answer.is_empty());
        assert!(!result.sources.is_empty());
    }

    #[test]
    fn test_rag_query_returns_sources_with_metadata() {
        let conn = create_test_db();

        index_with_embeddings(
            &conn,
            "/docs/intro.txt",
            "intro.txt",
            "Introduction",
            "Welcome to the introduction chapter of this amazing book about algorithms.",
        );

        let result = rag_query(&conn, "algorithms book", 3).unwrap();

        if result.error_code.is_none() {
            for source in &result.sources {
                assert!(!source.file_path.is_empty());
                assert!(!source.chunk_snippet.is_empty());
                // chunk_offset может быть 0 для первого чанка
            }
        }
    }

    #[test]
    fn test_rag_query_respects_top_k() {
        let conn = create_test_db();

        // Создаём несколько файлов
        for i in 0..5 {
            let path = format!("/docs/file_{i}.txt");
            let name = format!("file_{i}.txt");
            let text = format!("Document number {i} about various topics and research.");
            index_with_embeddings(&conn, &path, &name, "desc", &text);
        }

        let result = rag_query(&conn, "document research", 2).unwrap();

        if result.error_code.is_none() {
            assert!(result.sources.len() <= 2);
        }
    }

    #[test]
    fn test_rag_query_answer_mentions_question() {
        let conn = create_test_db();

        index_with_embeddings(
            &conn,
            "/docs/test.txt",
            "test.txt",
            "Test",
            "This is test content for RAG query verification.",
        );

        let result = rag_query(&conn, "test content", 5).unwrap();

        if result.error_code.is_none() {
            // Stub-ответ должен содержать вопрос
            assert!(result.answer.contains("test content"));
        }
    }

    // ------------------------------------------------------------------
    // Full context RAG query
    // ------------------------------------------------------------------

    #[test]
    fn test_rag_query_full_context_empty_question() {
        let conn = create_test_db();
        let result = rag_query_full_context(&conn, "", 5).unwrap();
        assert_eq!(result.error_code.as_deref(), Some("empty_question"));
    }

    #[test]
    fn test_rag_query_full_context_basic() {
        let conn = create_test_db();

        index_with_embeddings(
            &conn,
            "/docs/manual.txt",
            "manual.txt",
            "User manual",
            "This manual explains how to configure and use the application effectively.",
        );

        let result = rag_query_full_context(&conn, "configure application", 5).unwrap();

        if result.error_code.is_none() {
            assert!(!result.answer.is_empty());
            assert!(!result.sources.is_empty());
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    #[test]
    fn test_pluralize_fragment() {
        assert_eq!(pluralize_fragment(1), "фрагмент");
        assert_eq!(pluralize_fragment(2), "фрагмента");
        assert_eq!(pluralize_fragment(3), "фрагмента");
        assert_eq!(pluralize_fragment(4), "фрагмента");
        assert_eq!(pluralize_fragment(5), "фрагментов");
        assert_eq!(pluralize_fragment(10), "фрагментов");
        assert_eq!(pluralize_fragment(11), "фрагментов");
        assert_eq!(pluralize_fragment(12), "фрагментов");
        assert_eq!(pluralize_fragment(14), "фрагментов");
        assert_eq!(pluralize_fragment(21), "фрагмент");
        assert_eq!(pluralize_fragment(22), "фрагмента");
    }

    #[test]
    fn test_extract_filename() {
        assert_eq!(extract_filename("/path/to/file.txt"), "file.txt");
        assert_eq!(extract_filename("file.txt"), "file.txt");
        assert_eq!(extract_filename("/"), "/");
    }

    #[test]
    fn test_truncate() {
        assert_eq!(truncate("short", 10), "short");
        assert_eq!(truncate("longer text", 6), "longer…");
    }
}

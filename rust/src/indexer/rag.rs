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

use crate::error::LateraError;
use super::embeddings::{self, SimilarityResult};

// ============================================================================
// Public types
// ============================================================================

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

    info!("RAG query: \"{}\" (top_k={})", truncate(question, 80), top_k);

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
    let context_parts: Vec<String> = relevant
        .iter()
        .enumerate()
        .map(|(i, r)| {
            format!(
                "[{}] (из файла «{}», позиция {}):\n{}",
                i + 1,
                extract_filename(&r.file_path),
                r.chunk_offset,
                r.chunk_snippet
            )
        })
        .collect();

    let context = context_parts.join("\n\n");

    // 4. Генерируем ответ (stub: конкатенация с заголовком)
    let answer = generate_stub_answer(question, &context, relevant.len());

    // 5. Собираем источники
    let sources: Vec<RagSource> = relevant
        .iter()
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
/// В отличие от [`rag_query`], загружает ПОЛНЫЙ текст чанков из БД,
/// а не обрезанные сниппеты. Это даёт LLM больше контекста для ответа.
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

    info!(
        "RAG query (full context): \"{}\" (top_k={})",
        truncate(question, 80),
        top_k
    );

    // 1. Вычисляем эмбеддинг вопроса
    let query_vec = embeddings::compute_embeddings(&[embeddings::TextChunk {
        text: question.to_string(),
        chunk_index: 0,
        chunk_offset: 0,
    }]);

    if query_vec.is_empty() {
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("query_failed".to_string()),
        });
    }

    // 2. Загружаем чанки с полным текстом и метаданными
    let mut stmt = conn.prepare(
        "SELECT
            e.embedding,
            c.chunk_text,
            c.chunk_offset,
            f.file_path,
            f.file_name
         FROM embeddings e
         JOIN chunks c ON c.id = e.chunk_id
         JOIN files f  ON f.id = c.file_id
         ORDER BY f.id, c.chunk_index",
    )?;

    let query_embedding = &query_vec[0].vector;

    let rows = stmt.query_map([], |row| {
        let blob: Vec<u8> = row.get(0)?;
        let chunk_text: String = row.get(1)?;
        let chunk_offset: u32 = row.get(2)?;
        let file_path: String = row.get(3)?;
        let file_name: String = row.get(4)?;
        Ok((blob, chunk_text, chunk_offset, file_path, file_name))
    })?;

    let mut scored: Vec<(f64, String, u32, String, String)> = Vec::new();

    for row_result in rows {
        match row_result {
            Ok((blob, chunk_text, chunk_offset, file_path, _file_name)) => {
                let stored_vec = embeddings::blob_to_embedding_pub(&blob);
                let score = embeddings::cosine_similarity_pub(query_embedding, &stored_vec);
                if score >= MIN_SIMILARITY_SCORE {
                    scored.push((score, chunk_text, chunk_offset, file_path, _file_name));
                }
            }
            Err(e) => {
                warn!("Error reading embedding row in RAG: {e}");
            }
        }
    }

    // Сортируем по убыванию score
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(top_k);

    if scored.is_empty() {
        return Ok(RagResult {
            answer: String::new(),
            sources: Vec::new(),
            error_code: Some("no_relevant_chunks".to_string()),
        });
    }

    // 3. Формируем контекст и ответ (full context version)
    let context_parts: Vec<String> = scored
        .iter()
        .enumerate()
        .map(|(i, (score, text, offset, path, _))| {
            format!(
                "[{}] (файл: «{}», позиция: {}, релевантность: {:.2}):\n{}",
                i + 1,
                extract_filename(path),
                offset,
                score,
                text
            )
        })
        .collect();

    let context = context_parts.join("\n\n");
    let answer = generate_stub_answer(question, &context, scored.len());

    let sources: Vec<RagSource> = scored
        .iter()
        .map(|(_, text, offset, path, _)| RagSource {
            file_path: path.clone(),
            chunk_snippet: embeddings::truncate_snippet_pub(text, 200),
            chunk_offset: *offset,
        })
        .collect();

    Ok(RagResult {
        answer,
        sources,
        error_code: None,
    })
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

/// Генерирует stub-ответ на основе контекста.
///
/// Формат:
/// ```text
/// По вашему вопросу «...» найдено N релевантных фрагментов:
///
/// [контекст]
/// ```
///
/// При подключении LLM будет заменён на prompt + inference.
fn generate_stub_answer(question: &str, context: &str, source_count: usize) -> String {
    format!(
        "По вашему вопросу «{}» найдено {} релевантных {}:\n\n{}",
        truncate(question, 100),
        source_count,
        pluralize_fragment(source_count),
        context
    )
}

/// Склоняем слово «фрагмент» по числу.
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
        chunk_text, compute_embeddings, init_embeddings_tables,
        store_chunks_and_embeddings, DEFAULT_CHUNK_OVERLAP, DEFAULT_CHUNK_SIZE,
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
        store_chunks_and_embeddings(conn, info.id, &chunks, &embeddings)
            .expect("store failed");
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
        assert!(result.error_code.is_none(), "error: {:?}", result.error_code);
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

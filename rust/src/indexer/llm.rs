//! Локальный LLM-инференс для генерации описаний и тегов.
//!
//! Использует загруженную ONNX sentence-embedding модель для:
//! - **Extractive summarization**: выбирает ключевые предложения через
//!   sentence embeddings + centrality scoring.
//! - **Keyword extraction**: TF-IDF ранжирование + embedding-based
//!   дедупликация ключевых слов.
//!
//! Архитектура готова к замене на полноценный generative LLM
//! (llama.cpp / ONNX seq2seq) без изменения FFI-контракта.

use log::{debug, info, warn};
use std::collections::HashMap;

use super::embeddings;

// ============================================================================
// Public types
// ============================================================================

/// Результат генерации описания/саммари.
#[derive(Clone, Debug)]
pub struct LlmSummaryResult {
    /// Сгенерированное описание.
    pub summary: String,
    /// Код ошибки (None = успех).
    ///
    /// Возможные значения:
    /// - `"empty_content"` — пустое содержимое
    /// - `"content_too_short"` — содержимое слишком короткое
    /// - `"generation_failed"` — ошибка при генерации
    /// - `"model_not_ready"` — модель не загружена
    pub error_code: Option<String>,
}

/// Результат генерации тегов.
#[derive(Clone, Debug)]
pub struct LlmTagsResult {
    /// Сгенерированные теги.
    pub tags: Vec<String>,
    /// Код ошибки (None = успех).
    pub error_code: Option<String>,
}

// ============================================================================
// Constants
// ============================================================================

/// Минимальная длина контента для саммаризации (символов).
const MIN_CONTENT_LENGTH: usize = 50;

/// Максимальное количество предложений в саммари.
const MAX_SUMMARY_SENTENCES: usize = 3;

/// Максимальное количество тегов.
const MAX_TAGS: usize = 7;

/// Минимальная длина слова для тега.
const MIN_TAG_WORD_LENGTH: usize = 3;

/// Максимальная длина контента, обрабатываемого за раз (символов).
/// Ограничение для производительности на десктопе.
const MAX_CONTENT_LENGTH: usize = 15_000;

// ============================================================================
// Public API
// ============================================================================

/// Генерирует описание/саммари на основе текстового содержимого файла.
///
/// Алгоритм (extractive summarization):
/// 1. Разбивает текст на предложения.
/// 2. Вычисляет sentence embeddings через загруженную ONNX-модель.
/// 3. Рассчитывает centrality score каждого предложения (среднее cosine
///    similarity со всеми остальными предложениями).
/// 4. Выбирает top-N предложений с наибольшим centrality score.
/// 5. Возвращает их в оригинальном порядке.
///
/// При отсутствии модели используется fallback: первые N предложений.
pub fn generate_summary(text_content: &str, file_name: &str) -> LlmSummaryResult {
    let text = truncate_content(text_content);

    if text.trim().is_empty() {
        return LlmSummaryResult {
            summary: String::new(),
            error_code: Some("empty_content".to_string()),
        };
    }

    if text.trim().len() < MIN_CONTENT_LENGTH {
        return LlmSummaryResult {
            summary: String::new(),
            error_code: Some("content_too_short".to_string()),
        };
    }

    info!(
        "Generating summary for \"{}\" ({} chars)",
        file_name,
        text.len()
    );

    let sentences = split_sentences(&text);
    if sentences.is_empty() {
        return LlmSummaryResult {
            summary: String::new(),
            error_code: Some("content_too_short".to_string()),
        };
    }

    // Если мало предложений — возвращаем всё
    if sentences.len() <= MAX_SUMMARY_SENTENCES {
        let summary = sentences.join(" ");
        info!("Summary (short text): {} chars", summary.len());
        return LlmSummaryResult {
            summary,
            error_code: None,
        };
    }

    // Extractive summarization через centrality scoring
    let summary = if embeddings::is_semantic_model_ready() {
        match extractive_summary_via_embeddings(&sentences) {
            Ok(s) => s,
            Err(e) => {
                warn!("Embedding-based summary failed: {e}, fallback to first sentences");
                fallback_summary(&sentences)
            }
        }
    } else {
        debug!("Semantic model not ready, using fallback summary");
        fallback_summary(&sentences)
    };

    info!(
        "Summary generated for \"{}\": {} chars",
        file_name,
        summary.len()
    );

    LlmSummaryResult {
        summary,
        error_code: None,
    }
}

/// Генерирует теги на основе текстового содержимого файла.
///
/// Алгоритм (TF-IDF + embedding dedup):
/// 1. Токенизация и нормализация слов.
/// 2. TF-IDF ранжирование (term frequency × inverse document frequency).
/// 3. Если модель доступна — embedding-based дедупликация
///    (убираем семантически близкие теги).
/// 4. Возвращаем top-N тегов.
pub fn generate_tags(text_content: &str, file_name: &str) -> LlmTagsResult {
    let text = truncate_content(text_content);

    if text.trim().is_empty() {
        return LlmTagsResult {
            tags: Vec::new(),
            error_code: Some("empty_content".to_string()),
        };
    }

    if text.trim().len() < MIN_CONTENT_LENGTH {
        return LlmTagsResult {
            tags: Vec::new(),
            error_code: Some("content_too_short".to_string()),
        };
    }

    info!(
        "Generating tags for \"{}\" ({} chars)",
        file_name,
        text.len()
    );

    let tags = extract_keywords(&text);

    if tags.is_empty() {
        warn!("No tags extracted for \"{}\"", file_name);
        return LlmTagsResult {
            tags: Vec::new(),
            error_code: Some("generation_failed".to_string()),
        };
    }

    info!(
        "Tags generated for \"{}\": {} tags",
        file_name,
        tags.len()
    );

    LlmTagsResult {
        tags,
        error_code: None,
    }
}

/// Проверяет готовность LLM-модуля.
///
/// Для текущей реализации зависит от semantic-модели.
/// При подключении отдельной LLM-модели будет иметь собственную проверку.
pub fn is_llm_ready() -> bool {
    embeddings::is_semantic_model_ready()
}

// ============================================================================
// Extractive summarization
// ============================================================================

/// Extractive summarization через sentence embeddings + centrality scoring.
///
/// Centrality score предложения = среднее cosine similarity
/// со всеми остальными предложениями. Предложения с высоким centrality
/// являются наиболее «центральными» для документа.
fn extractive_summary_via_embeddings(sentences: &[String]) -> Result<String, String> {
    // Вычисляем эмбеддинги предложений
    let chunks: Vec<embeddings::TextChunk> = sentences
        .iter()
        .enumerate()
        .map(|(i, s)| embeddings::TextChunk {
            text: s.clone(),
            chunk_index: i as u32,
            chunk_offset: 0,
        })
        .collect();

    let embedding_vecs = embeddings::compute_embeddings(&chunks);

    if embedding_vecs.len() != sentences.len() {
        return Err(format!(
            "Expected {} embeddings, got {}",
            sentences.len(),
            embedding_vecs.len()
        ));
    }

    // Рассчитываем centrality score для каждого предложения
    let n = sentences.len();
    let mut centrality_scores: Vec<(usize, f64)> = Vec::with_capacity(n);

    for i in 0..n {
        let mut total_sim = 0.0f64;
        let mut count = 0u32;
        for j in 0..n {
            if i != j {
                let sim = cosine_similarity(&embedding_vecs[i].vector, &embedding_vecs[j].vector);
                total_sim += sim;
                count += 1;
            }
        }
        let avg_sim = if count > 0 {
            total_sim / f64::from(count)
        } else {
            0.0
        };
        centrality_scores.push((i, avg_sim));
    }

    // Сортируем по centrality (убывание)
    centrality_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    // Берём top-N и сортируем по оригинальному порядку
    let mut selected: Vec<usize> = centrality_scores
        .iter()
        .take(MAX_SUMMARY_SENTENCES)
        .map(|(idx, _)| *idx)
        .collect();
    selected.sort_unstable();

    let summary = selected
        .iter()
        .map(|&idx| sentences[idx].as_str())
        .collect::<Vec<&str>>()
        .join(" ");

    Ok(summary)
}

/// Fallback: берём первые N предложений.
fn fallback_summary(sentences: &[String]) -> String {
    sentences
        .iter()
        .take(MAX_SUMMARY_SENTENCES)
        .cloned()
        .collect::<Vec<String>>()
        .join(" ")
}

// ============================================================================
// Keyword extraction (TF-IDF)
// ============================================================================

/// Извлекает ключевые слова через TF-IDF ранжирование.
fn extract_keywords(text: &str) -> Vec<String> {
    let words = tokenize_words(text);

    if words.is_empty() {
        return Vec::new();
    }

    // Разбиваем текст на «документы» (абзацы) для IDF
    let paragraphs = split_paragraphs(text);
    let num_docs = paragraphs.len().max(1);

    // Term frequency (в полном тексте)
    let mut tf: HashMap<String, u32> = HashMap::new();
    for word in &words {
        *tf.entry(word.clone()).or_insert(0) += 1;
    }

    // Document frequency
    let mut df: HashMap<String, u32> = HashMap::new();
    for para in &paragraphs {
        let para_words: std::collections::HashSet<String> = tokenize_words(para)
            .into_iter()
            .collect();
        for word in &para_words {
            *df.entry(word.clone()).or_insert(0) += 1;
        }
    }

    // TF-IDF scoring
    let total_words = words.len() as f64;
    let mut tfidf_scores: Vec<(String, f64)> = tf
        .iter()
        .filter(|(word, _)| word.len() >= MIN_TAG_WORD_LENGTH && !is_stopword(word))
        .map(|(word, &count)| {
            let tf_score = f64::from(count) / total_words;
            let df_val = f64::from(*df.get(word).unwrap_or(&1));
            let idf_score = (num_docs as f64 / df_val).ln() + 1.0;
            (word.clone(), tf_score * idf_score)
        })
        .collect();

    tfidf_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    // Если модель доступна — дедуплицируем семантически близкие
    let candidates: Vec<String> = tfidf_scores
        .iter()
        .take(MAX_TAGS * 3) // берём с запасом для дедупликации
        .map(|(word, _)| word.clone())
        .collect();

    if embeddings::is_semantic_model_ready() && candidates.len() > 1 {
        deduplicate_via_embeddings(&candidates)
    } else {
        candidates.into_iter().take(MAX_TAGS).collect()
    }
}

/// Дедупликация тегов через embeddings.
///
/// Убирает семантически близкие теги (cosine similarity > 0.8),
/// оставляя тег с более высоким TF-IDF (т.е. более ранний в списке).
fn deduplicate_via_embeddings(candidates: &[String]) -> Vec<String> {
    let chunks: Vec<embeddings::TextChunk> = candidates
        .iter()
        .enumerate()
        .map(|(i, word)| embeddings::TextChunk {
            text: word.clone(),
            chunk_index: i as u32,
            chunk_offset: 0,
        })
        .collect();

    let embedding_vecs = embeddings::compute_embeddings(&chunks);

    let mut selected: Vec<usize> = Vec::new();
    let similarity_threshold = 0.8;

    'outer: for i in 0..candidates.len() {
        for &j in &selected {
            if i < embedding_vecs.len() && j < embedding_vecs.len() {
                let sim = cosine_similarity(
                    &embedding_vecs[i].vector,
                    &embedding_vecs[j].vector,
                );
                if sim > similarity_threshold {
                    continue 'outer;
                }
            }
        }
        selected.push(i);
        if selected.len() >= MAX_TAGS {
            break;
        }
    }

    selected
        .iter()
        .filter_map(|&i| candidates.get(i).cloned())
        .collect()
}

// ============================================================================
// Text processing helpers
// ============================================================================

/// Разбивает текст на предложения.
///
/// Простой unicode-aware splitter по `.!?` + пробел/конец строки.
fn split_sentences(text: &str) -> Vec<String> {
    let mut sentences = Vec::new();
    let mut current = String::new();

    for ch in text.chars() {
        current.push(ch);
        if (ch == '.' || ch == '!' || ch == '?') && current.trim().len() > 10 {
            let trimmed = current.trim().to_string();
            if !trimmed.is_empty() {
                sentences.push(trimmed);
            }
            current.clear();
        }
    }

    // Остаток
    let trimmed = current.trim().to_string();
    if trimmed.len() > 10 {
        sentences.push(trimmed);
    }

    sentences
}

/// Разбивает текст на абзацы (по двойному переводу строки).
fn split_paragraphs(text: &str) -> Vec<String> {
    text.split("\n\n")
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
        .collect()
}

/// Токенизирует текст в слова (lowercase, только буквы/цифры).
fn tokenize_words(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric() && c != '-')
        .map(|w| w.to_lowercase())
        .filter(|w| w.len() >= MIN_TAG_WORD_LENGTH && !w.chars().all(|c| c.is_ascii_digit()))
        .collect()
}

/// Проверяет, является ли слово стоп-словом.
///
/// Покрывает английские и русские стоп-слова.
fn is_stopword(word: &str) -> bool {
    matches!(
        word,
        // English
        "the" | "and" | "for" | "are" | "but" | "not" | "you" | "all"
        | "can" | "had" | "her" | "was" | "one" | "our" | "out" | "has"
        | "have" | "been" | "from" | "that" | "this" | "with" | "they"
        | "will" | "what" | "when" | "where" | "which" | "their" | "there"
        | "these" | "those" | "then" | "than" | "them" | "each" | "would"
        | "make" | "like" | "just" | "over" | "such" | "into" | "some"
        | "could" | "other" | "about" | "more" | "also" | "very" | "should"
        | "being" | "does" | "doing" | "done" | "only" | "after" | "before"
        // Russian
        | "это" | "как" | "что" | "для" | "или" | "при" | "все" | "его"
        | "они" | "она" | "был" | "уже" | "еще" | "ещё" | "так"
        | "тоже" | "другой" | "другие" | "между" | "через" | "после"
        | "перед" | "более" | "менее" | "также" | "может" | "будет"
        | "были" | "быть" | "если" | "только" | "когда" | "где" | "там"
        | "тут" | "чтобы" | "потому" | "очень" | "самый" | "свой"
        | "который" | "которая" | "которое" | "которые"
        // Common short
        | "http" | "https" | "www" | "com" | "org" | "net"
    )
}

/// Обрезает контент до максимальной длины.
fn truncate_content(text: &str) -> String {
    if text.len() <= MAX_CONTENT_LENGTH {
        text.to_string()
    } else {
        // Обрезаем по границе char, не по байтам
        text.chars().take(MAX_CONTENT_LENGTH).collect()
    }
}

/// Cosine similarity между двумя векторами.
fn cosine_similarity(a: &[f32], b: &[f32]) -> f64 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }

    let mut dot = 0.0f64;
    let mut norm_a = 0.0f64;
    let mut norm_b = 0.0f64;

    for i in 0..a.len() {
        let ai = f64::from(a[i]);
        let bi = f64::from(b[i]);
        dot += ai * bi;
        norm_a += ai * ai;
        norm_b += bi * bi;
    }

    let denom = norm_a.sqrt() * norm_b.sqrt();
    if denom < 1e-12 {
        0.0
    } else {
        dot / denom
    }
}

// ============================================================================
// JSON serialization (for FFI)
// ============================================================================

/// Сериализует `LlmSummaryResult` в JSON.
pub fn summary_result_to_json(result: &LlmSummaryResult) -> String {
    let error_code_json = match &result.error_code {
        Some(code) => format!("\"{}\"", escape_json_string(code)),
        None => "null".to_string(),
    };

    format!(
        "{{\"summary\":\"{}\",\"error_code\":{}}}",
        escape_json_string(&result.summary),
        error_code_json
    )
}

/// Сериализует `LlmTagsResult` в JSON.
pub fn tags_result_to_json(result: &LlmTagsResult) -> String {
    let error_code_json = match &result.error_code {
        Some(code) => format!("\"{}\"", escape_json_string(code)),
        None => "null".to_string(),
    };

    let tags_json: Vec<String> = result
        .tags
        .iter()
        .map(|t| format!("\"{}\"", escape_json_string(t)))
        .collect();

    format!(
        "{{\"tags\":[{}],\"error_code\":{}}}",
        tags_json.join(","),
        error_code_json
    )
}

/// Экранирует спецсимволы для JSON строки.
fn escape_json_string(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            c if c.is_control() => {
                // Unicode escape для control characters
                result.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => result.push(c),
        }
    }
    result
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_sentences() {
        let text = "First sentence. Second one! Third here? Fourth.";
        let sentences = split_sentences(text);
        assert!(sentences.len() >= 2, "Expected at least 2 sentences, got {}: {:?}", sentences.len(), sentences);
    }

    #[test]
    fn test_split_sentences_short() {
        let text = "Hi. No.";
        let sentences = split_sentences(text);
        // Short fragments (<=10 chars) are filtered out
        assert!(sentences.is_empty() || sentences.iter().all(|s| s.len() > 10));
    }

    #[test]
    fn test_tokenize_words() {
        let text = "Hello world! This is a test-document with Numbers123.";
        let words = tokenize_words(text);
        assert!(words.contains(&"hello".to_string()));
        assert!(words.contains(&"world".to_string()));
        assert!(words.contains(&"test-document".to_string()));
        // "is" and "a" are too short (< MIN_TAG_WORD_LENGTH)
    }

    #[test]
    fn test_is_stopword() {
        assert!(is_stopword("the"));
        assert!(is_stopword("это"));
        assert!(!is_stopword("algorithm"));
        assert!(!is_stopword("алгоритм"));
    }

    #[test]
    fn test_generate_summary_empty() {
        let result = generate_summary("", "test.txt");
        assert_eq!(result.error_code, Some("empty_content".to_string()));
        assert!(result.summary.is_empty());
    }

    #[test]
    fn test_generate_summary_too_short() {
        let result = generate_summary("Short text.", "test.txt");
        assert_eq!(result.error_code, Some("content_too_short".to_string()));
    }

    #[test]
    fn test_generate_tags_empty() {
        let result = generate_tags("", "test.txt");
        assert_eq!(result.error_code, Some("empty_content".to_string()));
        assert!(result.tags.is_empty());
    }

    #[test]
    fn test_generate_tags_too_short() {
        let result = generate_tags("Short", "test.txt");
        assert_eq!(result.error_code, Some("content_too_short".to_string()));
    }

    #[test]
    fn test_generate_summary_with_content() {
        let text = "Rust is a systems programming language focused on safety and performance. \
                    It provides memory safety without garbage collection. \
                    The language uses a borrow checker to validate references. \
                    Concurrent programming is made safer through the ownership system. \
                    Rust compiles to native code and has zero-cost abstractions.";
        let result = generate_summary(text, "rust_intro.txt");
        assert!(result.error_code.is_none(), "Error: {:?}", result.error_code);
        assert!(!result.summary.is_empty());
    }

    #[test]
    fn test_generate_tags_with_content() {
        let text = "Machine learning algorithms process large datasets to find patterns. \
                    Neural networks are particularly effective for image recognition tasks. \
                    Deep learning models require significant computational resources. \
                    Training these models often uses GPU acceleration for performance. \
                    Common frameworks include TensorFlow and PyTorch for development.";
        let result = generate_tags(text, "ml_intro.txt");
        assert!(result.error_code.is_none(), "Error: {:?}", result.error_code);
        assert!(!result.tags.is_empty());
    }

    #[test]
    fn test_summary_result_to_json() {
        let result = LlmSummaryResult {
            summary: "Test summary with \"quotes\".".to_string(),
            error_code: None,
        };
        let json = summary_result_to_json(&result);
        assert!(json.contains("Test summary"));
        assert!(json.contains("\\\"quotes\\\""));
        assert!(json.contains("\"error_code\":null"));
    }

    #[test]
    fn test_tags_result_to_json() {
        let result = LlmTagsResult {
            tags: vec!["rust".to_string(), "programming".to_string()],
            error_code: None,
        };
        let json = tags_result_to_json(&result);
        assert!(json.contains("\"rust\""));
        assert!(json.contains("\"programming\""));
        assert!(json.contains("\"error_code\":null"));
    }

    #[test]
    fn test_cosine_similarity_identical() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        let sim = cosine_similarity(&a, &b);
        assert!((sim - 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let a = vec![1.0, 0.0];
        let b = vec![0.0, 1.0];
        let sim = cosine_similarity(&a, &b);
        assert!(sim.abs() < 1e-6);
    }

    #[test]
    fn test_truncate_content() {
        let short = "short text";
        assert_eq!(truncate_content(short), short);

        let long = "a".repeat(MAX_CONTENT_LENGTH + 100);
        let truncated = truncate_content(&long);
        assert_eq!(truncated.len(), MAX_CONTENT_LENGTH);
    }

    #[test]
    fn test_escape_json_string() {
        assert_eq!(escape_json_string("hello"), "hello");
        assert_eq!(escape_json_string("say \"hi\""), "say \\\"hi\\\"");
        assert_eq!(escape_json_string("line\nnew"), "line\\nnew");
        assert_eq!(escape_json_string("back\\slash"), "back\\\\slash");
    }
}

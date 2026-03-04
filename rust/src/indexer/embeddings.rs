//! Embeddings: вычисление и similarity search.
//!
//! Phase 3.5: реальный ONNX-пайплайн на базе all-MiniLM-L6-v2.
//!
//! Текст → HF Tokenizer → ONNX Runtime → mean-pooling → L2-norm → f32 vector.
//!
//! Модель (~80 MB) загружается по требованию при первом вызове
//! [`init_semantic_model`] и сохраняется в папку данных приложения.
//! Если модель не инициализирована — используется stub fallback (hash-based).
//!
//! ## Схема хранения
//!
//! ```text
//! chunks:
//!   id          INTEGER PRIMARY KEY
//!   file_id     INTEGER NOT NULL → files(id) ON DELETE CASCADE
//!   chunk_index INTEGER NOT NULL
//!   chunk_text  TEXT NOT NULL
//!   chunk_offset INTEGER NOT NULL DEFAULT 0
//!
//! embeddings:
//!   id          INTEGER PRIMARY KEY
//!   chunk_id    INTEGER UNIQUE NOT NULL → chunks(id) ON DELETE CASCADE
//!   embedding   BLOB NOT NULL           -- little-endian f32 vector
//! ```

use log::{debug, info, warn};
use once_cell::sync::Lazy;
use ort::session::builder::GraphOptimizationLevel;
use ort::session::Session;
use rusqlite::{params, Connection};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::sync::Mutex;

use crate::error::LateraError;

// ============================================================================
// Constants
// ============================================================================

/// Размерность эмбеддинга (384 для all-MiniLM-L6-v2).
pub const EMBEDDING_DIM: usize = 384;

/// Размерность stub-эмбеддинга (для fallback без модели).
const STUB_EMBEDDING_DIM: usize = 64;

/// Максимальный размер чанка (символов) при разбиении текста.
pub const DEFAULT_CHUNK_SIZE: usize = 500;

/// Перекрытие между соседними чанками (символов).
pub const DEFAULT_CHUNK_OVERLAP: usize = 50;

/// Имя директории модели.
const MODEL_DIR_NAME: &str = "all-MiniLM-L6-v2";

/// Имя файла ONNX-модели.
const MODEL_FILE: &str = "model.onnx";

/// Имя файла токенизатора.
const TOKENIZER_FILE: &str = "tokenizer.json";

/// URL ONNX-модели на Hugging Face.
const MODEL_URL: &str =
    "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx";

/// URL токенизатора на Hugging Face.
const TOKENIZER_URL: &str =
    "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json";

/// Максимальная длина последовательности токенов для модели.
const MAX_SEQ_LENGTH: usize = 256;

// ============================================================================
// Public types (FRB-совместимые определены в api.rs)
// ============================================================================

/// Текстовый чанк для вычисления эмбеддинга.
#[derive(Clone, Debug)]
pub struct TextChunk {
    /// Текст чанка.
    pub text: String,
    /// Индекс чанка в документе (0-based).
    pub chunk_index: u32,
    /// Смещение (байтовое) от начала документа.
    pub chunk_offset: u32,
}

/// Результат вычисления эмбеддинга для одного чанка.
#[derive(Clone, Debug)]
pub struct EmbeddingVector {
    /// Индекс чанка.
    pub chunk_index: u32,
    /// Вектор эмбеддинга (f32, длина = EMBEDDING_DIM).
    pub vector: Vec<f32>,
}

/// Результат similarity search.
#[derive(Clone, Debug)]
pub struct SimilarityResult {
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

// ============================================================================
// Semantic model (ONNX + tokenizer)
// ============================================================================

/// Загруженная semantic-модель.
struct SemanticModel {
    session: Session,
    tokenizer: tokenizers::Tokenizer,
}

// Глобальное состояние модели: None = не загружена.
static SEMANTIC_MODEL: Lazy<Mutex<Option<SemanticModel>>> = Lazy::new(|| Mutex::new(None));

/// Проверяет, загружена ли semantic-модель.
pub fn is_semantic_model_ready() -> bool {
    SEMANTIC_MODEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .is_some()
}

/// Возвращает текущую размерность эмбеддинга.
///
/// Если модель загружена — 384 (all-MiniLM-L6-v2).
/// Если нет — 64 (stub fallback).
pub fn current_embedding_dim() -> usize {
    if is_semantic_model_ready() {
        EMBEDDING_DIM
    } else {
        STUB_EMBEDDING_DIM
    }
}

/// Инициализирует semantic-модель: скачивает (при необходимости) и загружает.
///
/// `data_dir` — корневая директория данных приложения.
/// Модель сохраняется в `{data_dir}/models/all-MiniLM-L6-v2/`.
///
/// Безопасен для повторного вызова — если модель уже загружена, возвращает Ok.
pub fn init_semantic_model(data_dir: &str) -> Result<(), LateraError> {
    {
        let guard = SEMANTIC_MODEL
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if guard.is_some() {
            info!("Semantic model already loaded, skipping");
            return Ok(());
        }
    }

    let model_dir = Path::new(data_dir).join("models").join(MODEL_DIR_NAME);
    std::fs::create_dir_all(&model_dir)?;

    let model_path = model_dir.join(MODEL_FILE);
    let tokenizer_path = model_dir.join(TOKENIZER_FILE);

    // Загрузка файлов, если отсутствуют
    if !model_path.exists() {
        info!("Downloading ONNX model from {MODEL_URL}...");
        download_file(MODEL_URL, &model_path)?;
        info!("Model downloaded to {}", model_path.display());
    }
    if !tokenizer_path.exists() {
        info!("Downloading tokenizer from {TOKENIZER_URL}...");
        download_file(TOKENIZER_URL, &tokenizer_path)?;
        info!("Tokenizer downloaded to {}", tokenizer_path.display());
    }

    // Загрузка ONNX Runtime session
    info!("Loading ONNX model from {}...", model_path.display());
    let session = Session::builder()
        .map_err(|e| LateraError::ModelLoadFailed(format!("Session builder: {e}")))?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| LateraError::ModelLoadFailed(format!("Optimization level: {e}")))?
        .with_intra_threads(2)
        .map_err(|e| LateraError::ModelLoadFailed(format!("Intra threads: {e}")))?
        .commit_from_file(&model_path)
        .map_err(|e| LateraError::ModelLoadFailed(format!("Commit from file: {e}")))?;

    // Загрузка токенизатора
    info!("Loading tokenizer from {}...", tokenizer_path.display());
    let tokenizer = tokenizers::Tokenizer::from_file(&tokenizer_path)
        .map_err(|e| LateraError::ModelLoadFailed(format!("Tokenizer: {e}")))?;

    let mut guard = SEMANTIC_MODEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *guard = Some(SemanticModel { session, tokenizer });

    info!("Semantic model loaded successfully (dim={})", EMBEDDING_DIM);
    Ok(())
}

/// Выгружает semantic-модель из памяти.
pub fn unload_semantic_model() {
    let mut guard = SEMANTIC_MODEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if guard.take().is_some() {
        info!("Semantic model unloaded");
    }
}

/// Скачивает файл по URL и сохраняет на диск.
fn download_file(url: &str, dest: &Path) -> Result<(), LateraError> {
    let resp = ureq::get(url)
        .call()
        .map_err(|e| LateraError::ModelDownloadFailed(format!("{e}")))?;

    let mut reader = resp.into_reader();
    let tmp_path = dest.with_extension("tmp");
    let mut file = std::fs::File::create(&tmp_path)?;
    std::io::copy(&mut reader, &mut file)?;
    std::fs::rename(&tmp_path, dest)?;

    Ok(())
}

// ============================================================================
// Schema initialisation
// ============================================================================

/// Создаёт таблицы `chunks` и `embeddings` в БД.
///
/// Безопасно для повторного вызова (IF NOT EXISTS).
pub fn init_embeddings_tables(conn: &Connection) -> Result<(), LateraError> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS chunks (
            id           INTEGER PRIMARY KEY,
            file_id      INTEGER NOT NULL,
            chunk_index  INTEGER NOT NULL,
            chunk_text   TEXT    NOT NULL,
            chunk_offset INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE,
            UNIQUE(file_id, chunk_index)
        );

        CREATE INDEX IF NOT EXISTS idx_chunks_file_id ON chunks(file_id);

        CREATE TABLE IF NOT EXISTS embeddings (
            id        INTEGER PRIMARY KEY,
            chunk_id  INTEGER UNIQUE NOT NULL,
            embedding BLOB    NOT NULL,
            FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_embeddings_chunk_id ON embeddings(chunk_id);",
    )?;

    info!("Embeddings tables initialized (chunks + embeddings)");
    Ok(())
}

// ============================================================================
// Chunking
// ============================================================================

/// Разбивает текст на чанки фиксированного размера с перекрытием.
///
/// Возвращает вектор [`TextChunk`] с текстом и метаинформацией.
pub fn chunk_text(
    text: &str,
    chunk_size: usize,
    chunk_overlap: usize,
) -> Vec<TextChunk> {
    if text.is_empty() {
        return Vec::new();
    }

    let effective_chunk_size = chunk_size.max(1);
    let effective_overlap = chunk_overlap.min(effective_chunk_size.saturating_sub(1));

    let chars: Vec<char> = text.chars().collect();
    let mut chunks = Vec::new();
    let mut start = 0usize;
    let mut chunk_index = 0u32;

    while start < chars.len() {
        let end = (start + effective_chunk_size).min(chars.len());
        let chunk_text: String = chars[start..end].iter().collect();
        // Byte offset для оригинального текста
        let byte_offset: usize = chars[..start].iter().map(|c| c.len_utf8()).sum();

        chunks.push(TextChunk {
            text: chunk_text,
            chunk_index,
            chunk_offset: byte_offset as u32,
        });

        chunk_index += 1;
        let step = effective_chunk_size.saturating_sub(effective_overlap);
        if step == 0 {
            break;
        }
        start += step;
    }

    chunks
}

// ============================================================================
// Embedding computation (real ONNX or stub fallback)
// ============================================================================

/// Вычисляет эмбеддинги для набора чанков.
///
/// Если semantic-модель загружена — использует ONNX Runtime (all-MiniLM-L6-v2).
/// Иначе — возвращает детерминированные stub-векторы (hash-based, dim=64).
pub fn compute_embeddings(chunks: &[TextChunk]) -> Vec<EmbeddingVector> {
    chunks
        .iter()
        .map(|chunk| {
            let vector = embed_text(&chunk.text);
            EmbeddingVector {
                chunk_index: chunk.chunk_index,
                vector,
            }
        })
        .collect()
}

/// Вычисляет эмбеддинг для одного текста.
///
/// Пытается использовать ONNX-модель. При неудаче или отсутствии модели
/// возвращает stub-вектор.
fn embed_text(text: &str) -> Vec<f32> {
    let mut guard = SEMANTIC_MODEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);

    if let Some(model) = guard.as_mut() {
        match onnx_embed(model, text) {
            Ok(vec) => return vec,
            Err(e) => {
                warn!("ONNX embed failed, falling back to stub: {e}");
            }
        }
    }

    // Fallback: stub embedding
    stub_embed(text)
}

/// Реальное вычисление эмбеддинга через ONNX Runtime.
///
/// Pipeline: tokenize → pad/truncate → run ONNX → mean-pool → L2-norm.
fn onnx_embed(model: &mut SemanticModel, text: &str) -> Result<Vec<f32>, LateraError> {
    let encoding = model
        .tokenizer
        .encode(text, true)
        .map_err(|e| LateraError::EmbeddingComputeFailed(format!("Tokenization: {e}")))?;

    let mut input_ids: Vec<i64> = encoding.get_ids().iter().map(|&id| i64::from(id)).collect();
    let mut attention_mask: Vec<i64> = encoding
        .get_attention_mask()
        .iter()
        .map(|&m| i64::from(m))
        .collect();
    let mut token_type_ids: Vec<i64> = encoding
        .get_type_ids()
        .iter()
        .map(|&t| i64::from(t))
        .collect();

    // Truncate to max sequence length
    let seq_len = input_ids.len().min(MAX_SEQ_LENGTH);
    input_ids.truncate(seq_len);
    attention_mask.truncate(seq_len);
    token_type_ids.truncate(seq_len);

    // Создаём Value через (shape, vec) — совместимо с любой версией ort
    let shape = vec![1_usize, seq_len];
    let input_ids_val = ort::value::Value::from_array(
        (shape.clone(), input_ids),
    )
    .map_err(|e| LateraError::EmbeddingComputeFailed(format!("input_ids value: {e}")))?;
    let attn_mask_clone = attention_mask.clone();
    let attention_mask_val = ort::value::Value::from_array(
        (shape.clone(), attn_mask_clone),
    )
    .map_err(|e| LateraError::EmbeddingComputeFailed(format!("attention_mask value: {e}")))?;
    let token_type_ids_val = ort::value::Value::from_array(
        (shape, token_type_ids),
    )
    .map_err(|e| LateraError::EmbeddingComputeFailed(format!("token_type_ids value: {e}")))?;

    let outputs = model
        .session
        .run(
            ort::inputs! {
                "input_ids" => input_ids_val,
                "attention_mask" => attention_mask_val,
                "token_type_ids" => token_type_ids_val,
            },
        )
        .map_err(|e| LateraError::EmbeddingComputeFailed(format!("session.run: {e}")))?;

    // last_hidden_state: [1, seq_len, 384]
    // try_extract_tensor returns (&Shape, &[f32]) in ort 2.0.0-rc
    let (out_shape, out_data) = outputs[0]
        .try_extract_tensor::<f32>()
        .map_err(|e| LateraError::EmbeddingComputeFailed(format!("extract tensor: {e}")))?;

    // Mean pooling с учётом attention_mask
    // Shape: [1, seq_len, hidden_dim]
    let dim = out_shape.last().copied().unwrap_or(EMBEDDING_DIM as i64) as usize;
    let mut pooled = vec![0.0f32; dim];
    let mut mask_sum = 0.0f32;

    for i in 0..seq_len {
        let mask_val = attention_mask[i] as f32;
        if mask_val > 0.0 {
            let row_start = i * dim;
            for j in 0..dim {
                pooled[j] += out_data[row_start + j] * mask_val;
            }
            mask_sum += mask_val;
        }
    }

    if mask_sum > 0.0 {
        for v in &mut pooled {
            *v /= mask_sum;
        }
    }

    // L2-нормализация
    l2_normalize(&mut pooled);

    Ok(pooled)
}

/// Stub: генерирует детерминированный вектор размерности [`STUB_EMBEDDING_DIM`]
/// из хеша текста. Один и тот же текст всегда даёт один и тот же вектор.
fn stub_embed(text: &str) -> Vec<f32> {
    let mut vec = Vec::with_capacity(STUB_EMBEDDING_DIM);
    for i in 0..STUB_EMBEDDING_DIM {
        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        i.hash(&mut hasher);
        let h = hasher.finish();
        // Нормализуем в диапазон [-1, 1]
        let val = ((h % 10000) as f64 / 5000.0) - 1.0;
        vec.push(val as f32);
    }
    l2_normalize(&mut vec);
    vec
}

/// L2-нормализация вектора in-place.
fn l2_normalize(vec: &mut [f32]) {
    let norm = vec.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        for v in vec.iter_mut() {
            *v /= norm;
        }
    }
}

// ============================================================================
// Storage (chunks + embeddings)
// ============================================================================

/// Сохраняет чанки и их эмбеддинги для файла.
///
/// Удаляет старые чанки/эмбеддинги для `file_id` перед вставкой.
pub fn store_chunks_and_embeddings(
    conn: &Connection,
    file_id: i64,
    chunks: &[TextChunk],
    embeddings: &[EmbeddingVector],
) -> Result<(), LateraError> {
    // Удаляем старые данные (CASCADE удалит embeddings)
    conn.execute("DELETE FROM chunks WHERE file_id = ?1", params![file_id])?;

    let mut chunk_stmt = conn.prepare(
        "INSERT INTO chunks (file_id, chunk_index, chunk_text, chunk_offset)
         VALUES (?1, ?2, ?3, ?4)",
    )?;

    let mut emb_stmt = conn.prepare(
        "INSERT INTO embeddings (chunk_id, embedding)
         VALUES (?1, ?2)",
    )?;

    for (chunk, emb) in chunks.iter().zip(embeddings.iter()) {
        chunk_stmt.execute(params![
            file_id,
            chunk.chunk_index,
            chunk.text,
            chunk.chunk_offset,
        ])?;
        let chunk_id = conn.last_insert_rowid();

        let blob = embedding_to_blob(&emb.vector);
        emb_stmt.execute(params![chunk_id, blob])?;
    }

    debug!(
        "Stored {} chunks + embeddings for file_id={}",
        chunks.len(),
        file_id
    );
    Ok(())
}

/// Удаляет чанки и эмбеддинги для файла.
pub fn remove_embeddings_for_file(
    conn: &Connection,
    file_id: i64,
) -> Result<(), LateraError> {
    conn.execute("DELETE FROM chunks WHERE file_id = ?1", params![file_id])?;
    debug!("Removed chunks/embeddings for file_id={}", file_id);
    Ok(())
}

// ============================================================================
// Similarity search
// ============================================================================

/// Ищет файлы, наиболее семантически похожие на запрос.
///
/// 1. Вычисляет эмбеддинг `query_text` (stub).
/// 2. Загружает все эмбеддинги из БД.
/// 3. Считает косинусное сходство.
/// 4. Возвращает `top_k` результатов.
///
/// **Примечание**: linear scan. При >10k чанков переключить на ANN
/// (sqlite-vss / usearch / HNSW).
pub fn similarity_search(
    conn: &Connection,
    query_text: &str,
    top_k: usize,
) -> Result<Vec<SimilarityResult>, LateraError> {
    if query_text.trim().is_empty() {
        return Ok(Vec::new());
    }

    let query_vec = embed_text(query_text);

    // Загружаем все эмбеддинги с метаданными
    let mut stmt = conn.prepare(
        "SELECT
            e.embedding,
            c.chunk_text,
            c.chunk_offset,
            f.file_path,
            f.file_name,
            f.id as file_id
         FROM embeddings e
         JOIN chunks c ON c.id = e.chunk_id
         JOIN files f  ON f.id = c.file_id
         ORDER BY f.id, c.chunk_index",
    )?;

    let rows = stmt.query_map([], |row| {
        let blob: Vec<u8> = row.get(0)?;
        let chunk_text: String = row.get(1)?;
        let chunk_offset: u32 = row.get(2)?;
        let file_path: String = row.get(3)?;
        let file_name: String = row.get(4)?;
        let file_id: i64 = row.get(5)?;
        Ok((blob, chunk_text, chunk_offset, file_path, file_name, file_id))
    })?;

    let mut scored: Vec<SimilarityResult> = Vec::new();

    for row_result in rows {
        match row_result {
            Ok((blob, chunk_text, chunk_offset, file_path, file_name, _file_id)) => {
                let stored_vec = blob_to_embedding(&blob);
                let score = cosine_similarity(&query_vec, &stored_vec);
                scored.push(SimilarityResult {
                    file_path,
                    file_name,
                    chunk_snippet: truncate_snippet(&chunk_text, 200),
                    chunk_offset,
                    score,
                });
            }
            Err(e) => {
                warn!("Error reading embedding row: {e}");
            }
        }
    }

    // Сортируем по убыванию score, берём top_k
    scored.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(top_k);

    // Дедупликация по file_path (оставляем лучший чанк)
    let mut seen = std::collections::HashSet::new();
    scored.retain(|r| seen.insert(r.file_path.clone()));

    Ok(scored)
}

/// Ищет файлы, похожие на данный файл.
///
/// Берёт эмбеддинги всех чанков указанного файла,
/// выполняет similarity search по каждому и агрегирует результаты.
pub fn find_similar_files(
    conn: &Connection,
    file_path: &str,
    top_k: usize,
) -> Result<Vec<SimilarityResult>, LateraError> {
    // Получаем file_id
    let file_id: Option<i64> = conn
        .prepare("SELECT id FROM files WHERE file_path = ?1")?
        .query_map(params![file_path], |row| row.get(0))?
        .filter_map(Result::ok)
        .next();

    let file_id = match file_id {
        Some(id) => id,
        None => return Ok(Vec::new()),
    };

    // Получаем эмбеддинги чанков этого файла
    let mut stmt = conn.prepare(
        "SELECT e.embedding
         FROM embeddings e
         JOIN chunks c ON c.id = e.chunk_id
         WHERE c.file_id = ?1
         ORDER BY c.chunk_index",
    )?;

    let file_vecs: Vec<Vec<f32>> = stmt
        .query_map(params![file_id], |row| {
            let blob: Vec<u8> = row.get(0)?;
            Ok(blob_to_embedding(&blob))
        })?
        .filter_map(Result::ok)
        .collect();

    if file_vecs.is_empty() {
        return Ok(Vec::new());
    }

    // Средний вектор файла
    let avg_vec = average_vectors(&file_vecs);

    // Загружаем все остальные эмбеддинги
    let mut all_stmt = conn.prepare(
        "SELECT
            e.embedding,
            c.chunk_text,
            c.chunk_offset,
            f.file_path,
            f.file_name
         FROM embeddings e
         JOIN chunks c ON c.id = e.chunk_id
         JOIN files f  ON f.id = c.file_id
         WHERE c.file_id != ?1",
    )?;

    let rows = all_stmt.query_map(params![file_id], |row| {
        let blob: Vec<u8> = row.get(0)?;
        let chunk_text: String = row.get(1)?;
        let chunk_offset: u32 = row.get(2)?;
        let file_path: String = row.get(3)?;
        let file_name: String = row.get(4)?;
        Ok((blob, chunk_text, chunk_offset, file_path, file_name))
    })?;

    let mut scored: Vec<SimilarityResult> = Vec::new();

    for row_result in rows {
        match row_result {
            Ok((blob, chunk_text, chunk_offset, fp, fn_)) => {
                let stored_vec = blob_to_embedding(&blob);
                let score = cosine_similarity(&avg_vec, &stored_vec);
                scored.push(SimilarityResult {
                    file_path: fp,
                    file_name: fn_,
                    chunk_snippet: truncate_snippet(&chunk_text, 200),
                    chunk_offset,
                    score,
                });
            }
            Err(e) => {
                warn!("Error reading embedding row: {e}");
            }
        }
    }

    scored.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(top_k * 2); // запас перед дедупликацией

    // Дедупликация по file_path
    let mut seen = std::collections::HashSet::new();
    scored.retain(|r| seen.insert(r.file_path.clone()));
    scored.truncate(top_k);

    Ok(scored)
}

/// Проверяет, есть ли эмбеддинги для файла.
pub fn has_embeddings(conn: &Connection, file_path: &str) -> Result<bool, LateraError> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*)
         FROM embeddings e
         JOIN chunks c ON c.id = e.chunk_id
         JOIN files f  ON f.id = c.file_id
         WHERE f.file_path = ?1",
        params![file_path],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

/// Возвращает количество чанков с эмбеддингами в БД.
pub fn get_embedding_count(conn: &Connection) -> Result<i64, LateraError> {
    let count: i64 =
        conn.query_row("SELECT COUNT(*) FROM embeddings", [], |row| row.get(0))?;
    Ok(count)
}

// ============================================================================
// Helpers
// ============================================================================

/// Сериализует вектор f32 в BLOB (little-endian).
fn embedding_to_blob(vec: &[f32]) -> Vec<u8> {
    vec.iter().flat_map(|v| v.to_le_bytes()).collect()
}

/// Десериализует BLOB в вектор f32.
fn blob_to_embedding(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|bytes| f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
        .collect()
}

/// Косинусное сходство двух векторов.
fn cosine_similarity(a: &[f32], b: &[f32]) -> f64 {
    let len = a.len().min(b.len());
    if len == 0 {
        return 0.0;
    }

    let mut dot = 0.0f64;
    let mut norm_a = 0.0f64;
    let mut norm_b = 0.0f64;

    for i in 0..len {
        let va = f64::from(a[i]);
        let vb = f64::from(b[i]);
        dot += va * vb;
        norm_a += va * va;
        norm_b += vb * vb;
    }

    let denom = norm_a.sqrt() * norm_b.sqrt();
    if denom < 1e-12 {
        return 0.0;
    }
    (dot / denom).clamp(-1.0, 1.0)
}

/// Средний вектор из набора векторов.
fn average_vectors(vecs: &[Vec<f32>]) -> Vec<f32> {
    if vecs.is_empty() {
        return Vec::new();
    }
    let dim = vecs[0].len();
    let mut avg = vec![0.0f32; dim];
    let count = vecs.len() as f32;

    for v in vecs {
        for (i, val) in v.iter().enumerate() {
            if i < dim {
                avg[i] += val;
            }
        }
    }
    for v in &mut avg {
        *v /= count;
    }
    // L2-нормализация
    l2_normalize(&mut avg);
    avg
}

/// Обрезает текст до `max_len` символов, добавляя "…" при необходимости.
fn truncate_snippet(text: &str, max_len: usize) -> String {
    if text.chars().count() <= max_len {
        text.to_string()
    } else {
        let truncated: String = text.chars().take(max_len).collect();
        format!("{truncated}…")
    }
}

// ============================================================================
// Public wrappers for sibling modules (RAG)
// ============================================================================

/// Public wrapper вокруг [`blob_to_embedding`] для RAG-модуля.
pub fn blob_to_embedding_pub(blob: &[u8]) -> Vec<f32> {
    blob_to_embedding(blob)
}

/// Public wrapper вокруг [`cosine_similarity`] для RAG-модуля.
pub fn cosine_similarity_pub(a: &[f32], b: &[f32]) -> f64 {
    cosine_similarity(a, b)
}

/// Public wrapper вокруг [`truncate_snippet`] для RAG-модуля.
pub fn truncate_snippet_pub(text: &str, max_len: usize) -> String {
    truncate_snippet(text, max_len)
}

/// Public wrapper вокруг [`embed_text`] для RAG-модуля.
pub fn embed_text_pub(text: &str) -> Vec<f32> {
    embed_text(text)
}

/// Удаляет все эмбеддинги из БД.
///
/// Используется при переключении режима (stub → ONNX) для пересчёта
/// с новой размерностью.
pub fn clear_all_embeddings(conn: &Connection) -> Result<(), LateraError> {
    conn.execute_batch("DELETE FROM embeddings; DELETE FROM chunks;")?;
    info!("All embeddings cleared (for re-indexing with new model)");
    Ok(())
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::indexer;

    fn create_test_db() -> Connection {
        let conn = indexer::init_db(":memory:").expect("Failed to create test DB");
        init_embeddings_tables(&conn).expect("Failed to init embeddings tables");
        conn
    }

    // ------------------------------------------------------------------
    // Chunking
    // ------------------------------------------------------------------

    #[test]
    fn test_chunk_text_basic() {
        let text = "Hello world, this is a test string for chunking";
        let chunks = chunk_text(text, 20, 5);
        assert!(!chunks.is_empty());
        assert_eq!(chunks[0].chunk_index, 0);
        assert_eq!(chunks[0].chunk_offset, 0);
        // Все чанки ≤ chunk_size символов
        for c in &chunks {
            assert!(c.text.chars().count() <= 20);
        }
    }

    #[test]
    fn test_chunk_text_empty() {
        let chunks = chunk_text("", 100, 10);
        assert!(chunks.is_empty());
    }

    #[test]
    fn test_chunk_text_short() {
        let text = "short";
        let chunks = chunk_text(text, 100, 10);
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].text, "short");
    }

    #[test]
    fn test_chunk_text_unicode() {
        let text = "Привет мир! Это тестовая строка для чанкинга с юникодом.";
        let chunks = chunk_text(text, 15, 3);
        assert!(!chunks.is_empty());
        // Проверяем что не крашится на многобайтовых символах
        for c in &chunks {
            assert!(c.text.chars().count() <= 15);
        }
    }

    #[test]
    fn test_chunk_overlap() {
        let text = "ABCDEFGHIJ"; // 10 chars
        let chunks = chunk_text(text, 5, 2);
        // step = 5 - 2 = 3
        // chunk 0: ABCDE (start=0)
        // chunk 1: DEFGH (start=3)
        // chunk 2: GHIJ  (start=6)
        // chunk 3: J     (start=9)
        assert_eq!(chunks.len(), 4);
        assert_eq!(chunks[0].text, "ABCDE");
        assert_eq!(chunks[1].text, "DEFGH");
        assert_eq!(chunks[2].text, "GHIJ");
        assert_eq!(chunks[3].text, "J");
    }

    // ------------------------------------------------------------------
    // Embedding computation (stub)
    // ------------------------------------------------------------------

    #[test]
    fn test_compute_embeddings_deterministic() {
        let chunks = vec![TextChunk {
            text: "test".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let emb1 = compute_embeddings(&chunks);
        let emb2 = compute_embeddings(&chunks);
        assert_eq!(emb1[0].vector, emb2[0].vector);
    }

    #[test]
    fn test_compute_embeddings_dimension_stub() {
        // Без загруженной модели используется stub (dim=64)
        let chunks = vec![TextChunk {
            text: "hello".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let emb = compute_embeddings(&chunks);
        assert_eq!(emb[0].vector.len(), STUB_EMBEDDING_DIM);
    }

    #[test]
    fn test_compute_embeddings_normalized() {
        let chunks = vec![TextChunk {
            text: "normalized test".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let emb = compute_embeddings(&chunks);
        let norm: f32 = emb[0].vector.iter().map(|v| v * v).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_compute_embeddings_different_texts() {
        let chunks = vec![
            TextChunk {
                text: "apple".to_string(),
                chunk_index: 0,
                chunk_offset: 0,
            },
            TextChunk {
                text: "banana".to_string(),
                chunk_index: 1,
                chunk_offset: 5,
            },
        ];
        let emb = compute_embeddings(&chunks);
        assert_ne!(emb[0].vector, emb[1].vector);
    }

    // ------------------------------------------------------------------
    // Model readiness
    // ------------------------------------------------------------------

    #[test]
    fn test_model_not_ready_by_default() {
        assert!(!is_semantic_model_ready());
    }

    #[test]
    fn test_current_embedding_dim_stub() {
        assert_eq!(current_embedding_dim(), STUB_EMBEDDING_DIM);
    }

    // ------------------------------------------------------------------
    // L2 normalization
    // ------------------------------------------------------------------

    #[test]
    fn test_l2_normalize() {
        let mut v = vec![3.0f32, 4.0];
        l2_normalize(&mut v);
        let norm: f32 = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 1e-6);
        assert!((v[0] - 0.6).abs() < 1e-6);
        assert!((v[1] - 0.8).abs() < 1e-6);
    }

    #[test]
    fn test_l2_normalize_zero() {
        let mut v = vec![0.0f32, 0.0];
        l2_normalize(&mut v);
        assert_eq!(v, vec![0.0, 0.0]);
    }

    // ------------------------------------------------------------------
    // Serialisation
    // ------------------------------------------------------------------

    #[test]
    fn test_blob_roundtrip() {
        let vec = vec![1.0f32, -0.5, 0.25, 3.14];
        let blob = embedding_to_blob(&vec);
        let restored = blob_to_embedding(&blob);
        assert_eq!(vec, restored);
    }

    #[test]
    fn test_blob_roundtrip_384_dim() {
        let vec: Vec<f32> = (0..384).map(|i| (i as f32) * 0.01).collect();
        let blob = embedding_to_blob(&vec);
        let restored = blob_to_embedding(&blob);
        assert_eq!(vec.len(), restored.len());
        assert_eq!(vec, restored);
    }

    // ------------------------------------------------------------------
    // Cosine similarity
    // ------------------------------------------------------------------

    #[test]
    fn test_cosine_similarity_identical() {
        let v = vec![1.0f32, 0.0, 0.0];
        let score = cosine_similarity(&v, &v);
        assert!((score - 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let a = vec![1.0f32, 0.0, 0.0];
        let b = vec![0.0f32, 1.0, 0.0];
        let score = cosine_similarity(&a, &b);
        assert!(score.abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_opposite() {
        let a = vec![1.0f32, 0.0];
        let b = vec![-1.0f32, 0.0];
        let score = cosine_similarity(&a, &b);
        assert!((score + 1.0).abs() < 1e-6);
    }

    // ------------------------------------------------------------------
    // DB storage
    // ------------------------------------------------------------------

    #[test]
    fn test_store_and_retrieve_embeddings() {
        let conn = create_test_db();

        indexer::index_file(&conn, "/test/doc.txt", "doc.txt", "test doc", Some("hello world"))
            .unwrap();
        let info = indexer::get_indexed_file(&conn, "/test/doc.txt")
            .unwrap()
            .unwrap();

        let chunks = vec![
            TextChunk {
                text: "hello".to_string(),
                chunk_index: 0,
                chunk_offset: 0,
            },
            TextChunk {
                text: "world".to_string(),
                chunk_index: 1,
                chunk_offset: 6,
            },
        ];
        let embs = compute_embeddings(&chunks);

        store_chunks_and_embeddings(&conn, info.id, &chunks, &embs).unwrap();

        assert!(has_embeddings(&conn, "/test/doc.txt").unwrap());
        assert_eq!(get_embedding_count(&conn).unwrap(), 2);
    }

    #[test]
    fn test_replace_embeddings() {
        let conn = create_test_db();

        indexer::index_file(&conn, "/test/doc.txt", "doc.txt", "test doc", None).unwrap();
        let info = indexer::get_indexed_file(&conn, "/test/doc.txt")
            .unwrap()
            .unwrap();

        let chunks_v1 = vec![TextChunk {
            text: "v1".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let embs_v1 = compute_embeddings(&chunks_v1);
        store_chunks_and_embeddings(&conn, info.id, &chunks_v1, &embs_v1).unwrap();
        assert_eq!(get_embedding_count(&conn).unwrap(), 1);

        let chunks_v2 = vec![
            TextChunk {
                text: "v2a".to_string(),
                chunk_index: 0,
                chunk_offset: 0,
            },
            TextChunk {
                text: "v2b".to_string(),
                chunk_index: 1,
                chunk_offset: 3,
            },
        ];
        let embs_v2 = compute_embeddings(&chunks_v2);
        store_chunks_and_embeddings(&conn, info.id, &chunks_v2, &embs_v2).unwrap();
        assert_eq!(get_embedding_count(&conn).unwrap(), 2);
    }

    #[test]
    fn test_remove_embeddings() {
        let conn = create_test_db();

        indexer::index_file(&conn, "/test/doc.txt", "doc.txt", "test doc", None).unwrap();
        let info = indexer::get_indexed_file(&conn, "/test/doc.txt")
            .unwrap()
            .unwrap();

        let chunks = vec![TextChunk {
            text: "text".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let embs = compute_embeddings(&chunks);
        store_chunks_and_embeddings(&conn, info.id, &chunks, &embs).unwrap();
        assert!(has_embeddings(&conn, "/test/doc.txt").unwrap());

        remove_embeddings_for_file(&conn, info.id).unwrap();
        assert!(!has_embeddings(&conn, "/test/doc.txt").unwrap());
    }

    // ------------------------------------------------------------------
    // Similarity search
    // ------------------------------------------------------------------

    #[test]
    fn test_similarity_search_basic() {
        let conn = create_test_db();

        // Файл 1: про программирование
        indexer::index_file(&conn, "/a.txt", "a.txt", "about coding", Some("rust programming language systems"))
            .unwrap();
        let a_info = indexer::get_indexed_file(&conn, "/a.txt").unwrap().unwrap();
        let a_chunks = chunk_text("rust programming language systems", DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let a_embs = compute_embeddings(&a_chunks);
        store_chunks_and_embeddings(&conn, a_info.id, &a_chunks, &a_embs).unwrap();

        // Файл 2: про кулинарию
        indexer::index_file(&conn, "/b.txt", "b.txt", "about cooking", Some("delicious recipes for pasta"))
            .unwrap();
        let b_info = indexer::get_indexed_file(&conn, "/b.txt").unwrap().unwrap();
        let b_chunks = chunk_text("delicious recipes for pasta", DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let b_embs = compute_embeddings(&b_chunks);
        store_chunks_and_embeddings(&conn, b_info.id, &b_chunks, &b_embs).unwrap();

        // Поиск
        let results = similarity_search(&conn, "programming", 5).unwrap();
        assert!(!results.is_empty());
        // Stub: детерминированные, но не семантические — просто проверяем что работает
    }

    #[test]
    fn test_similarity_search_empty_query() {
        let conn = create_test_db();
        let results = similarity_search(&conn, "", 5).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_similarity_search_no_embeddings() {
        let conn = create_test_db();
        let results = similarity_search(&conn, "anything", 5).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_find_similar_files() {
        let conn = create_test_db();

        // Три файла
        indexer::index_file(&conn, "/x.txt", "x.txt", "file x", Some("alpha")).unwrap();
        let x_info = indexer::get_indexed_file(&conn, "/x.txt").unwrap().unwrap();
        let x_chunks = chunk_text("alpha", DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let x_embs = compute_embeddings(&x_chunks);
        store_chunks_and_embeddings(&conn, x_info.id, &x_chunks, &x_embs).unwrap();

        indexer::index_file(&conn, "/y.txt", "y.txt", "file y", Some("beta")).unwrap();
        let y_info = indexer::get_indexed_file(&conn, "/y.txt").unwrap().unwrap();
        let y_chunks = chunk_text("beta", DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let y_embs = compute_embeddings(&y_chunks);
        store_chunks_and_embeddings(&conn, y_info.id, &y_chunks, &y_embs).unwrap();

        indexer::index_file(&conn, "/z.txt", "z.txt", "file z", Some("gamma")).unwrap();
        let z_info = indexer::get_indexed_file(&conn, "/z.txt").unwrap().unwrap();
        let z_chunks = chunk_text("gamma", DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP);
        let z_embs = compute_embeddings(&z_chunks);
        store_chunks_and_embeddings(&conn, z_info.id, &z_chunks, &z_embs).unwrap();

        // Ищем похожие на /x.txt
        let results = find_similar_files(&conn, "/x.txt", 5).unwrap();
        // Должны быть результаты, но без /x.txt
        for r in &results {
            assert_ne!(r.file_path, "/x.txt");
        }
    }

    #[test]
    fn test_find_similar_nonexistent_file() {
        let conn = create_test_db();
        let results = find_similar_files(&conn, "/nonexistent", 5).unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_cascade_delete() {
        let conn = create_test_db();

        indexer::index_file(&conn, "/del.txt", "del.txt", "will be deleted", None).unwrap();
        let info = indexer::get_indexed_file(&conn, "/del.txt").unwrap().unwrap();
        let chunks = vec![TextChunk {
            text: "delete me".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let embs = compute_embeddings(&chunks);
        store_chunks_and_embeddings(&conn, info.id, &chunks, &embs).unwrap();
        assert_eq!(get_embedding_count(&conn).unwrap(), 1);

        // Удаляем файл из основной таблицы → CASCADE удалит chunks → embeddings
        indexer::remove_file(&conn, "/del.txt").unwrap();
        assert_eq!(get_embedding_count(&conn).unwrap(), 0);
    }

    // ------------------------------------------------------------------
    // Clear all embeddings
    // ------------------------------------------------------------------

    #[test]
    fn test_clear_all_embeddings() {
        let conn = create_test_db();

        indexer::index_file(&conn, "/a.txt", "a.txt", "a", None).unwrap();
        let a_info = indexer::get_indexed_file(&conn, "/a.txt").unwrap().unwrap();
        let chunks = vec![TextChunk {
            text: "text a".to_string(),
            chunk_index: 0,
            chunk_offset: 0,
        }];
        let embs = compute_embeddings(&chunks);
        store_chunks_and_embeddings(&conn, a_info.id, &chunks, &embs).unwrap();

        indexer::index_file(&conn, "/b.txt", "b.txt", "b", None).unwrap();
        let b_info = indexer::get_indexed_file(&conn, "/b.txt").unwrap().unwrap();
        store_chunks_and_embeddings(&conn, b_info.id, &chunks, &embs).unwrap();

        assert_eq!(get_embedding_count(&conn).unwrap(), 2);

        clear_all_embeddings(&conn).unwrap();
        assert_eq!(get_embedding_count(&conn).unwrap(), 0);
    }

    // ------------------------------------------------------------------
    // Cosine similarity with different dims
    // ------------------------------------------------------------------

    #[test]
    fn test_cosine_similarity_different_lengths() {
        let a = vec![1.0f32, 0.0, 0.0];
        let b = vec![1.0f32, 0.0];
        let score = cosine_similarity(&a, &b);
        assert!((score - 1.0).abs() < 1e-6);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    #[test]
    fn test_truncate_snippet() {
        assert_eq!(truncate_snippet("short", 10), "short");
        assert_eq!(truncate_snippet("longer text here", 6), "longer…");
    }

    #[test]
    fn test_average_vectors() {
        let vecs = vec![vec![2.0f32, 0.0], vec![0.0f32, 2.0]];
        let avg = average_vectors(&vecs);
        // [1.0, 1.0] → normalized → [0.707, 0.707]
        assert_eq!(avg.len(), 2);
        let norm: f32 = avg.iter().map(|v| v * v).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 0.01);
    }
}

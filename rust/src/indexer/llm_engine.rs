//! Генеративный LLM-движок на базе llama.cpp (GGUF-модели).
//!
//! Управляет жизненным циклом модели:
//! - Загрузка GGUF-модели с диска → инициализация llama.cpp context
//! - Генерация текста с system/user prompt
//! - Выгрузка модели из памяти (TTL-lifecycle)
//!
//! Модель: Qwen2.5-3B-Instruct Q4_K_M (~1.7 ГБ).
//! Формат: GGUF (quantized Q4_K_M).

use log::{debug, info, warn};
use once_cell::sync::Lazy;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::sampling::LlamaSampler;
use llama_cpp_2::{list_llama_ggml_backend_devices, LlamaBackendDeviceType};

use crate::error::LateraError;

// ============================================================================
// Constants
// ============================================================================

/// Имя файла GGUF-модели.
pub const GGUF_MODEL_FILE: &str = "qwen2.5-3b-instruct-q4_k_m.gguf";

/// Первичный URL GGUF-модели (GitHub Releases).
/// Используется Dart-стороной (LlmDownloadService) — не в Rust.
pub const GGUF_MODEL_URL: &str =
    "https://github.com/potentsergey-dev/latera/releases/download/v1.0.0-models/qwen2.5-3b-instruct-q4_k_m.gguf";

/// Резервный URL GGUF-модели (HuggingFace).
/// Используется Dart-стороной (LlmDownloadService) — не в Rust.
pub const GGUF_MODEL_URL_FALLBACK: &str =
    "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true";

/// Максимальное количество токенов в контексте (для 3B модели).
const CONTEXT_SIZE: u32 = 4096;

/// Максимальное количество генерируемых токенов.
const MAX_GENERATION_TOKENS: u32 = 1024;

use std::sync::atomic::{AtomicBool, Ordering};
pub static CANCEL_GENERATION: AtomicBool = AtomicBool::new(false);

pub fn cancel_generation() {
    CANCEL_GENERATION.store(true, Ordering::Relaxed);
}

// ============================================================================
// Global state
// ============================================================================

/// Загруженная LLM-модель и её backend.
struct LoadedLlm {
    backend: LlamaBackend,
    model: LlamaModel,
    model_path: PathBuf,
}

// Глобальное состояние: None = модель не загружена.
static LLM_STATE: Lazy<Mutex<Option<LoadedLlm>>> = Lazy::new(|| Mutex::new(None));

// ============================================================================
// Public API
// ============================================================================

/// Инициализирует генеративную LLM-модель.
///
/// Загружает GGUF-модель из `{data_dir}/models/{GGUF_MODEL_FILE}`.
/// Безопасен для повторного вызова — если модель уже загружена, возвращает Ok.
pub fn init_llm(data_dir: &str) -> Result<(), LateraError> {
    let mut guard = LLM_STATE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);

    if guard.is_some() {
        info!("Generative LLM already loaded, skipping");
        return Ok(());
    }

    let model_path = Path::new(data_dir).join("models").join(GGUF_MODEL_FILE);

    if !model_path.exists() {
        return Err(LateraError::LlmLoadFailed(format!(
            "Model file not found: {}",
            model_path.display()
        )));
    }

    info!("Loading generative LLM from {}...", model_path.display());

    // Инициализируем llama.cpp backend
    let backend = LlamaBackend::init()
        .map_err(|e| LateraError::LlmLoadFailed(format!("Backend init: {e}")))?;

    // Определяем наличие GPU через llama.cpp backend device enumeration
    let devices = list_llama_ggml_backend_devices();
    for d in &devices {
        info!(
            "Backend device: {} — {} (type: {:?}, backend: {}, VRAM: {} MB)",
            d.name,
            d.description,
            d.device_type,
            d.backend,
            d.memory_total / (1024 * 1024)
        );
    }

    let has_gpu = devices.iter().any(|d| {
        matches!(
            d.device_type,
            LlamaBackendDeviceType::Gpu | LlamaBackendDeviceType::IntegratedGpu
        )
    });

    let gpu_layers = if has_gpu {
        info!("GPU device found — offloading all layers to GPU");
        u32::MAX
    } else {
        info!("No GPU device found — running on CPU only");
        0
    };

    // Попытка загрузки модели; при неудаче с GPU — fallback на CPU
    let model = {
        let model_params = LlamaModelParams::default().with_n_gpu_layers(gpu_layers);
        match LlamaModel::load_from_file(&backend, &model_path, &model_params) {
            Ok(m) => m,
            Err(e) if gpu_layers > 0 => {
                warn!("GPU model load failed ({e}), retrying on CPU only...");
                let cpu_params = LlamaModelParams::default().with_n_gpu_layers(0);
                LlamaModel::load_from_file(&backend, &model_path, &cpu_params).map_err(|e2| {
                    LateraError::LlmLoadFailed(format!("Model load failed (GPU: {e}, CPU: {e2})"))
                })?
            }
            Err(e) => {
                return Err(LateraError::LlmLoadFailed(format!("Model load: {e}")));
            }
        }
    };

    info!(
        "Generative LLM loaded: {} (vocab: {} tokens)",
        model_path.display(),
        model.n_vocab()
    );

    *guard = Some(LoadedLlm {
        backend,
        model,
        model_path: model_path.clone(),
    });

    Ok(())
}

/// Выгружает генеративную LLM-модель из памяти.
pub fn unload_llm() {
    let mut guard = LLM_STATE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if guard.take().is_some() {
        info!("Generative LLM unloaded");
    }
}

/// Проверяет, загружена ли генеративная LLM.
pub fn is_llm_ready() -> bool {
    LLM_STATE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .is_some()
}

/// Возвращает путь к файлу модели на диске.
///
/// `data_dir` — папка данных приложения.
pub fn llm_model_path(data_dir: &str) -> PathBuf {
    Path::new(data_dir).join("models").join(GGUF_MODEL_FILE)
}

/// Генерирует текст с заданным system prompt и user prompt.
///
/// Блокирующий вызов — возвращает полный ответ.
/// Для streaming-варианта используйте `generate_streaming()`.
pub fn generate_with_context(
    system_prompt: &str,
    user_prompt: &str,
    max_tokens: u32,
) -> Result<String, LateraError> {
    let guard = LLM_STATE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);

    let loaded = guard.as_ref().ok_or(LateraError::LlmNotLoaded)?;

    let effective_max = if max_tokens == 0 {
        MAX_GENERATION_TOKENS
    } else {
        max_tokens
    };

    // Формируем промпт в формате ChatML (Qwen2.5)
    let full_prompt = format!(
        "<|im_start|>system\n{system_prompt}<|im_end|>\n<|im_start|>user\n{user_prompt}<|im_end|>\n<|im_start|>assistant\n"
    );

    // Определяем количество потоков: половина от доступных, но не меньше 1 и не больше 4.
    // Это не позволяет перегружать старые (и новые) процессоры на 100%.
    let n_threads = std::thread::available_parallelism()
        .map(|n| n.get() as i32)
        .unwrap_or(2)
        .clamp(1, 4);

    debug!(
        "LLM generate: system={} chars, user={} chars, max_tokens={}, threads={}",
        system_prompt.len(),
        user_prompt.len(),
        effective_max,
        n_threads
    );

    // Создаём контекст для инференса
    let ctx_params = LlamaContextParams::default()
        .with_n_ctx(std::num::NonZeroU32::new(CONTEXT_SIZE))
        .with_n_threads(n_threads)
        .with_n_threads_batch(n_threads);

    let mut ctx = loaded
        .model
        .new_context(&loaded.backend, ctx_params)
        .map_err(|e| LateraError::LlmGenerationFailed(format!("Context creation: {e}")))?;

    // Токенизируем промпт
    let tokens = loaded
        .model
        .str_to_token(&full_prompt, llama_cpp_2::model::AddBos::Always)
        .map_err(|e| LateraError::LlmGenerationFailed(format!("Tokenization: {e}")))?;

    if tokens.len() >= CONTEXT_SIZE as usize {
        return Err(LateraError::LlmGenerationFailed(
            "Prompt too long for context window".to_string(),
        ));
    }

    // Сбрасываем флаг отмены перед началом работы
    CANCEL_GENERATION.store(false, Ordering::Relaxed);

    // Размер батча для потоковой обработки промпта
    const PROMPT_BATCH_SIZE: usize = 512;
    let mut batch = LlamaBatch::new(PROMPT_BATCH_SIZE, 1);

    let mut n_cur = 0;

    // Разбиваем токены на чанки, чтобы можно было прервать долгий prompt processing
    for chunk in tokens.chunks(PROMPT_BATCH_SIZE) {
        if CANCEL_GENERATION.load(Ordering::Relaxed) {
            warn!("LLM generation was cancelled during prompt processing");
            return Ok(String::new());
        }

        batch.clear();
        for (i, &token) in chunk.iter().enumerate() {
            let is_last = (n_cur as usize + i) == tokens.len() - 1;
            batch
                .add(token, n_cur + i as i32, &[0], is_last)
                .map_err(|e| LateraError::LlmGenerationFailed(format!("Batch add: {e}")))?;
        }

        ctx.decode(&mut batch)
            .map_err(|e| LateraError::LlmGenerationFailed(format!("Prompt decode: {e}")))?;

        n_cur += chunk.len() as i32;
    }

    // Настраиваем sampler
    let mut sampler = LlamaSampler::chain_simple([
        LlamaSampler::temp(0.3),
        LlamaSampler::top_p(0.9, 1),
        LlamaSampler::greedy(),
    ]);

    // Генерируем токены
    let mut output = String::new();

    let eos_token = loaded.model.token_eos();
    let eot_str = "<|im_end|>";

    // Сбрасываем флаг отмены перед началом генерации
    CANCEL_GENERATION.store(false, Ordering::Relaxed);

    for (n_cur, _) in (tokens.len() as i32..).zip(0..effective_max) {
        // Проверяем флаг отмены
        if CANCEL_GENERATION.load(Ordering::Relaxed) {
            warn!("LLM generation was cancelled");
            break;
        }

        let new_token = sampler.sample(&ctx, -1);

        // Проверяем EOS
        if new_token == eos_token {
            break;
        }

        // Декодируем токен в текст
        let piece_bytes = loaded
            .model
            .token_to_piece_bytes(new_token, 32, false, None)
            .map_err(|e| LateraError::LlmGenerationFailed(format!("Token decode: {e}")))?;

        let piece = String::from_utf8_lossy(&piece_bytes).into_owned();

        output.push_str(&piece);

        // Проверяем end-of-turn маркер ChatML
        if output.ends_with(eot_str) {
            output.truncate(output.len() - eot_str.len());
            break;
        }

        // Добавляем новый токен в batch для следующей итерации
        batch.clear();
        batch
            .add(new_token, n_cur, &[0], true)
            .map_err(|e| LateraError::LlmGenerationFailed(format!("Batch add gen: {e}")))?;

        ctx.decode(&mut batch)
            .map_err(|e| LateraError::LlmGenerationFailed(format!("Token decode: {e}")))?;
    }

    let result = output.trim().to_string();
    debug!("LLM generated {} chars", result.len());
    Ok(result)
}

// ============================================================================
// Language helpers
// ============================================================================

/// Маппит BCP-47 код языка в полное название для промпта.
pub fn language_code_to_name(code: &str) -> &str {
    match code.split('-').next().unwrap_or(code) {
        "en" => "English",
        "ru" => "Russian",
        "de" => "German",
        "es" => "Spanish",
        "pt" => "Portuguese",
        "fr" => "French",
        "zh" => "Chinese",
        "ja" => "Japanese",
        _ => "English",
    }
}

/// Формирует системный промпт для RAG-запроса.
pub fn rag_system_prompt(language: &str) -> String {
    let lang_name = language_code_to_name(language);
    format!(
        "You are a helpful document assistant. \
         Answer the user's question based ONLY on the provided context from their files. \
         If the context does not contain enough information, say so. \
         Answer strictly in {lang_name}. Be concise and accurate."
    )
}

/// Формирует системный промпт для генерации описания файла.
pub fn summary_system_prompt(language: &str) -> String {
    let lang_name = language_code_to_name(language);
    format!(
        "You are a document summarizer. \
         Write a brief 1-3 sentence summary of the provided document content. \
         Answer strictly in {lang_name}. Be concise."
    )
}

/// Формирует системный промпт для генерации тегов.
pub fn tags_system_prompt(language: &str) -> String {
    let lang_name = language_code_to_name(language);
    format!(
        "You are a document tagger. \
         Generate 3-7 relevant tags for the provided document content. \
         Output ONLY a comma-separated list of tags, nothing else. \
         Tags should be in {lang_name}."
    )
}

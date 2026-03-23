//! C FFI bridge для RAG-стриминга — вызывается из Dart через `dart:ffi`.
//!
//! Позволяет запустить RAG-запрос асинхронно и получать события
//! (Token, Done) через poll-модель.
//!
//! Строковые результаты возвращаются как JSON C-строки.
//! Вызывающая сторона (Dart) должна освободить строку через [`latera_free_cstring`]
//! из `ffi_ocr`.

use std::ffi::{c_char, CStr, CString};

use crate::indexer::rag;

/// Запускает RAG-запрос в фоновом потоке со стримингом.
///
/// После вызова, Dart должен поллить `latera_rag_poll_event()` для получения событий.
///
/// # Параметры
/// - `question_ptr` — вопрос пользователя (UTF-8, null-terminated C string)
/// - `top_k` — максимальное количество источников
///
/// # Возвращает
/// 1 = запрос запущен, 0 = ошибка (невалидный question_ptr)
///
/// # Safety
/// `question_ptr` должен быть валидным null-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn latera_rag_query_start(
    question_ptr: *const c_char,
    top_k: u32,
) -> u32 {
    let question = if question_ptr.is_null() {
        return 0;
    } else {
        match CStr::from_ptr(question_ptr).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    rag::rag_query_streaming_start(question, top_k as usize);
    1
}

/// Извлекает следующее событие из стрима (неблокирующее).
///
/// # Возвращает
/// - `null` (0) — нет событий в очереди
/// - JSON строку одного из форматов:
///   - `{"type":"token","text":"..."}`
///   - `{"type":"done","result":{...}}`
///
/// Вызывающая сторона **ДОЛЖНА** освободить строку через `latera_free_cstring`.
#[no_mangle]
pub extern "C" fn latera_rag_poll_event() -> *mut c_char {
    match rag::poll_stream_event() {
        None => std::ptr::null_mut(),
        Some(event) => {
            let json = match event {
                rag::RagStreamEvent::Token(text) => {
                    format!("{{\"type\":\"token\",\"text\":{}}}", rag::json_escape_pub(&text))
                }
                rag::RagStreamEvent::Done { result_json } => {
                    format!("{{\"type\":\"done\",\"result\":{result_json}}}")
                }
            };
            to_c_string(json)
        }
    }
}

/// Отменяет текущий RAG-запрос.
#[no_mangle]
pub extern "C" fn latera_rag_cancel() {
    rag::cancel_rag_query();
}

// ============================================================================
// Helpers
// ============================================================================

/// Конвертирует Rust String в C string pointer.
fn to_c_string(s: String) -> *mut c_char {
    let safe = s.replace('\0', " ");
    match CString::new(safe) {
        Ok(c) => c.into_raw(),
        Err(_) => {
            let fallback =
                CString::new("{\"type\":\"done\",\"result\":{\"answer\":\"\",\"sources\":[],\"error_code\":\"serialization_failed\"}}")
                    .unwrap_or_else(|_| CString::new("{}").unwrap());
            fallback.into_raw()
        }
    }
}

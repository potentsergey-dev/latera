//! C FFI bridge для LLM-инференса — вызывается из Dart через `dart:ffi`.
//!
//! Аналогичен [`ffi_ocr`] и [`ffi_search`]: экспортирует C-совместимые функции
//! для обхода ограничений FRB codegen на Windows.
//!
//! Результат возвращается как JSON строка (null-terminated C string).
//! Вызывающая сторона (Dart) должна освободить строку через [`latera_free_cstring`]
//! из `ffi_ocr`.

use std::ffi::{c_char, CStr, CString};

use crate::indexer::llm;

/// Генерирует описание/саммари для текстового содержимого файла.
///
/// # Параметры
/// - `text_content_ptr` — текстовое содержимое файла (UTF-8, null-terminated C string)
/// - `file_name_ptr` — имя файла для контекста (UTF-8, null-terminated C string)
///
/// # Возвращает
/// JSON строку (null-terminated C string) с полями:
/// ```json
/// {"summary":"...", "error_code": null}
/// ```
///
/// При ошибке `error_code` содержит код ошибки, `summary` пуст.
///
/// Вызывающая сторона **ДОЛЖНА** освободить строку через `latera_free_cstring`.
///
/// # Safety
/// - `text_content_ptr` и `file_name_ptr` должны быть валидными null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_generate_summary(
    text_content_ptr: *const c_char,
    file_name_ptr: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let text_content = match ptr_to_str(text_content_ptr) {
            Some(s) => s,
            None => {
                return llm::summary_result_to_json(&llm::LlmSummaryResult {
                    summary: String::new(),
                    error_code: Some("empty_content".to_string()),
                });
            }
        };

        let file_name = match ptr_to_str(file_name_ptr) {
            Some(s) => s,
            None => String::from("unknown"),
        };

        let llm_result = llm::generate_summary(&text_content, &file_name);
        llm::summary_result_to_json(&llm_result)
    });

    let json = result.unwrap_or_else(|_| {
        llm::summary_result_to_json(&llm::LlmSummaryResult {
            summary: String::new(),
            error_code: Some("generation_failed".to_string()),
        })
    });

    to_c_string(json)
}

/// Генерирует теги для текстового содержимого файла.
///
/// # Параметры
/// - `text_content_ptr` — текстовое содержимое файла (UTF-8, null-terminated C string)
/// - `file_name_ptr` — имя файла для контекста (UTF-8, null-terminated C string)
///
/// # Возвращает
/// JSON строку (null-terminated C string) с полями:
/// ```json
/// {"tags":["tag1","tag2"], "error_code": null}
/// ```
///
/// Вызывающая сторона **ДОЛЖНА** освободить строку через `latera_free_cstring`.
///
/// # Safety
/// - `text_content_ptr` и `file_name_ptr` должны быть валидными null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_generate_tags(
    text_content_ptr: *const c_char,
    file_name_ptr: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        let text_content = match ptr_to_str(text_content_ptr) {
            Some(s) => s,
            None => {
                return llm::tags_result_to_json(&llm::LlmTagsResult {
                    tags: Vec::new(),
                    error_code: Some("empty_content".to_string()),
                });
            }
        };

        let file_name = match ptr_to_str(file_name_ptr) {
            Some(s) => s,
            None => String::from("unknown"),
        };

        let llm_result = llm::generate_tags(&text_content, &file_name);
        llm::tags_result_to_json(&llm_result)
    });

    let json = result.unwrap_or_else(|_| {
        llm::tags_result_to_json(&llm::LlmTagsResult {
            tags: Vec::new(),
            error_code: Some("generation_failed".to_string()),
        })
    });

    to_c_string(json)
}

/// Проверяет готовность LLM-модуля (загружена ли модель).
///
/// # Возвращает
/// 1 если модель загружена, 0 если нет.
#[no_mangle]
pub extern "C" fn latera_is_llm_ready() -> u32 {
    if llm::is_llm_ready() { 1 } else { 0 }
}

// ============================================================================
// Helpers
// ============================================================================

/// Безопасно конвертирует C string pointer в Rust String.
unsafe fn ptr_to_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(String::from)
}

/// Конвертирует Rust String в C string pointer.
///
/// Заменяет внутренние NUL-байты на пробелы для безопасности.
fn to_c_string(s: String) -> *mut c_char {
    let safe = s.replace('\0', " ");
    match CString::new(safe) {
        Ok(c) => c.into_raw(),
        Err(_) => {
            let fallback =
                CString::new("{\"error_code\":\"generation_failed\"}")
                    .unwrap_or_else(|_| CString::new("{}").unwrap());
            fallback.into_raw()
        }
    }
}

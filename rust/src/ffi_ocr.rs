//! C FFI bridge для OCR — вызывается из Dart через `dart:ffi`.
//!
//! Этот модуль предоставляет C-совместимые функции для OCR,
//! обходя ограничения FRB codegen на Windows.
//!
//! Результат возвращается как JSON строка (null-terminated C string).
//! Вызывающая сторона (Dart) должна освободить строку через [`latera_free_cstring`].

use std::ffi::{c_char, CStr, CString};
use std::path::Path;

use crate::indexer::ocr;

/// Извлечь текст из изображения или скан-PDF через Windows OCR.
///
/// # Параметры
/// - `path_ptr` — путь к файлу (UTF-8, null-terminated C string)
/// - `max_pages` — максимальное количество страниц для скан-PDF
/// - `max_size_mb` — максимальный размер файла в MB
/// - `lang_ptr` — язык OCR (BCP-47, null-terminated C string) или null для автоопределения
///
/// # Возвращает
/// JSON строку (null-terminated C string) с полями:
/// `{"text":"...","content_type":"...","pages_processed":N,"confidence":N,"error_code":"..."}`
///
/// Вызывающая сторона **ДОЛЖНА** освободить строку через [`latera_free_cstring`].
///
/// # Safety
/// - `path_ptr` должен быть валидным null-terminated UTF-8 C string
/// - `lang_ptr` может быть null
#[no_mangle]
pub unsafe extern "C" fn latera_ocr_extract_text(
    path_ptr: *const c_char,
    max_pages: u32,
    max_size_mb: u32,
    lang_ptr: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        // Декодируем путь
        let path_str = if path_ptr.is_null() {
            return error_json("unknown", "file_not_found");
        } else {
            match CStr::from_ptr(path_ptr).to_str() {
                Ok(s) => s,
                Err(_) => return error_json("unknown", "file_not_found"),
            }
        };

        // Декодируем язык (опционально)
        let language = if lang_ptr.is_null() {
            None
        } else {
            CStr::from_ptr(lang_ptr).to_str().ok().map(String::from)
        };

        let options = ocr::OcrOptions {
            max_pages_per_pdf: max_pages,
            max_file_size_mb: max_size_mb,
            language,
        };

        let ocr_result = ocr::ocr_extract_text(Path::new(path_str), &options);
        ocr::ocr_result_to_json(&ocr_result)
    });

    let json = match result {
        Ok(json) => json,
        Err(_) => error_json("unknown", "ocr_failed"),
    };

    // Конвертируем в C string (заменяем внутренние нули на пробелы)
    let safe_json = json.replace('\0', " ");
    match CString::new(safe_json) {
        Ok(c) => c.into_raw(),
        Err(_) => {
            let fallback = CString::new(error_json("unknown", "ocr_failed"))
                .unwrap_or_else(|_| CString::new("{}").unwrap());
            fallback.into_raw()
        }
    }
}

/// Проверить, поддерживается ли файл для OCR.
///
/// # Параметры
/// - `path_ptr` — путь к файлу (UTF-8, null-terminated C string)
///
/// # Возвращает
/// 1 если файл поддерживается, 0 если нет.
///
/// # Safety
/// - `path_ptr` должен быть валидным null-terminated UTF-8 C string
#[no_mangle]
pub unsafe extern "C" fn latera_is_ocr_supported(path_ptr: *const c_char) -> i32 {
    if path_ptr.is_null() {
        return 0;
    }

    let path_str = match CStr::from_ptr(path_ptr).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    if ocr::is_ocr_supported(Path::new(path_str)) {
        1
    } else {
        0
    }
}

/// Освободить C string, возвращённую функциями FFI.
///
/// # Safety
/// - `ptr` должен быть получен из [`latera_ocr_extract_text`] или быть null.
/// - Вызывать ровно один раз для каждой полученной строки.
#[no_mangle]
pub unsafe extern "C" fn latera_free_cstring(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Формирует JSON строку ошибки.
fn error_json(content_type: &str, error_code: &str) -> String {
    format!(
        r#"{{"text":"","content_type":"{content_type}","pages_processed":0,"confidence":null,"error_code":"{error_code}"}}"#
    )
}

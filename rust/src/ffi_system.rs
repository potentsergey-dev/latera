//! C FFI bridge для системной информации — вызывается из Dart через `dart:ffi`.

use crate::indexer::rag;
use crate::system_info;

/// Возвращает общий объём физической оперативной памяти в мегабайтах.
#[no_mangle]
pub extern "C" fn latera_get_total_ram_mb() -> u64 {
    system_info::get_total_ram_mb()
}

/// Проверяет поддержку AVX2 процессором.
/// Возвращает 1 (true) или 0 (false).
#[no_mangle]
pub extern "C" fn latera_get_has_avx2() -> u32 {
    if system_info::get_has_avx2() {
        1
    } else {
        0
    }
}

/// Устанавливает глобальный лимит генерируемых токенов для RAG.
///
/// Вызывается из Flutter при инициализации на основе аппаратных возможностей:
/// - Без AVX2: ~100 токенов
/// - С AVX2: ~300 токенов
#[no_mangle]
pub extern "C" fn latera_set_rag_max_tokens(max_tokens: u32) {
    rag::set_rag_max_tokens(max_tokens);
}

/// Проверяет доступность Vulkan runtime на текущей машине.
/// Возвращает 1 (true) или 0 (false).
///
/// На Windows загружает vulkan-1.dll для проверки наличия Vulkan-драйвера.
/// Используется для диагностики — фича vulkan в llama.cpp пока не включена.
#[no_mangle]
pub extern "C" fn latera_get_has_vulkan() -> u32 {
    if system_info::get_has_vulkan() {
        1
    } else {
        0
    }
}

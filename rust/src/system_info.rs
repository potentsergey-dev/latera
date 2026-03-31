//! Утилиты для получения системной информации (RAM и т.д.).

use sysinfo::System;

/// Возвращает общий объём физической оперативной памяти в мегабайтах.
pub fn get_total_ram_mb() -> u64 {
    let sys = System::new_with_specifics(
        sysinfo::RefreshKind::nothing().with_memory(sysinfo::MemoryRefreshKind::everything()),
    );
    sys.total_memory() / (1024 * 1024)
}

/// Проверяет, поддерживает ли текущий процессор набор инструкций AVX2.
///
/// AVX2 критически важен для производительности llama.cpp — при его наличии
/// инференс работает в 3-5 раз быстрее.
#[cfg(target_arch = "x86_64")]
pub fn get_has_avx2() -> bool {
    is_x86_feature_detected!("avx2")
}

#[cfg(not(target_arch = "x86_64"))]
pub fn get_has_avx2() -> bool {
    false
}

/// Проверяет наличие Vulkan runtime (vulkan-1.dll) на текущей машине.
///
/// **Внимание:** эта функция проверяет только наличие DLL, а не реальную
/// способность GPU выполнять Vulkan-вычисления. Для точного определения
/// GPU-поддержки используйте `llama_cpp_2::list_llama_ggml_backend_devices()`.
///
/// Используется для диагностики на Dart-стороне (FFI `latera_get_has_vulkan`).
#[cfg(target_os = "windows")]
pub fn get_has_vulkan() -> bool {
    use std::ffi::c_void;

    // Прямой FFI к kernel32 — не требует дополнительных зависимостей.
    extern "system" {
        fn LoadLibraryA(name: *const u8) -> *mut c_void;
        fn FreeLibrary(handle: *mut c_void) -> i32;
    }

    // vulkan-1.dll поставляется с драйвером GPU (NVIDIA, AMD, Intel)
    // и устанавливается в System32 автоматически.
    let handle = unsafe { LoadLibraryA(b"vulkan-1.dll\0".as_ptr()) };
    if handle.is_null() {
        return false;
    }
    unsafe { FreeLibrary(handle) };
    true
}

#[cfg(not(target_os = "windows"))]
pub fn get_has_vulkan() -> bool {
    false
}

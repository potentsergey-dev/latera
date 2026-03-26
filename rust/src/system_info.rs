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

/// Проверяет доступность Vulkan GPU на текущей машине.
///
/// На Windows пробует загрузить `vulkan-1.dll` (находится в System32 при
/// установленном драйвере с поддержкой Vulkan). Если DLL загружается —
/// считаем, что Vulkan runtime доступен.
///
/// Сейчас фича `vulkan` не включена в сборку, поэтому эта функция служит
/// для диагностики: показывает, готова ли машина к Vulkan-ускорению.
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

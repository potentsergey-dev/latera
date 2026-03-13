//! C FFI bridge для системной информации — вызывается из Dart через `dart:ffi`.

use crate::system_info;

/// Возвращает общий объём физической оперативной памяти в мегабайтах.
#[no_mangle]
pub extern "C" fn latera_get_total_ram_mb() -> u64 {
    system_info::get_total_ram_mb()
}

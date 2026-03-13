//! Утилиты для получения системной информации (RAM и т.д.).

use sysinfo::System;

/// Возвращает общий объём физической оперативной памяти в мегабайтах.
pub fn get_total_ram_mb() -> u64 {
    let sys = System::new_with_specifics(
        sysinfo::RefreshKind::nothing().with_memory(sysinfo::MemoryRefreshKind::everything()),
    );
    sys.total_memory() / (1024 * 1024)
}

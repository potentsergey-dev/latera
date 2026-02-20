use std::sync::Once;

static INIT: Once = Once::new();

/// Инициализировать логирование (idempotent).
///
/// Управление уровнем логов: переменная окружения `RUST_LOG`.
pub fn init_logging() {
  INIT.call_once(|| {
    // Не паникуем, если логгер уже инициализирован.
    let _ = env_logger::builder()
      .format_timestamp_millis()
      .try_init();
  });
}


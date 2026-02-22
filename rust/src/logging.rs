//! Нормализованное логирование для Latera Rust Core.
//!
//! ## Уровни логов
//! - `ERROR`: критические ошибки, требующие внимания
//! - `WARN`:  предупреждения, некритичные проблемы
//! - `INFO`:  важные события жизненного цикла (startup, shutdown, key operations)
//! - `DEBUG`: детальная информация для отладки
//! - `TRACE`: максимально детальный вывод (включая данные)
//!
//! ## Корреляция событий
//! Каждый лог может содержать `correlation_id` для трассировки запросов
//! через границы Rust/Flutter.
//!
//! ## Использование
//! ```ignore
//! use latera_rust::logging::{init_logging, LogContext};
//!
//! init_logging(); // вызывается один раз при старте
//!
//! log::info!(target: "latera::file_watcher", "Starting watcher");
//! log::info!(target: "latera::file_watcher", correlation_id = %ctx.id, "File added");
//! ```

use std::sync::Once;

use log::{Level, LevelFilter};
use std::io::Write;

static INIT: Once = Once::new();

/// Инициализировать логирование (idempotent).
///
/// Управление уровнем логов: переменная окружения `RUST_LOG`.
/// Примеры:
/// - `RUST_LOG=info` — только INFO и выше
/// - `RUST_LOG=latera_rust=debug` — DEBUG для нашего crate
/// - `RUST_LOG=trace` — максимально детальный вывод
pub fn init_logging() {
    INIT.call_once(|| {
        let _ = env_logger::Builder::from_env("RUST_LOG")
            .format(|buf, record| {
                let level = match record.level() {
                    Level::Error => "E",
                    Level::Warn => "W",
                    Level::Info => "I",
                    Level::Debug => "D",
                    Level::Trace => "T",
                };

                let timestamp = chrono_timestamp();
                let target = record.target();

                // Формат: [timestamp] [LEVEL] [target] message
                writeln!(
                    buf,
                    "[{}] [{}] [{}] {}",
                    timestamp,
                    level,
                    target,
                    record.args()
                )
            })
            .filter_module("latera_rust", LevelFilter::Info)
            .filter_module("notify", LevelFilter::Warn)
            .try_init();
    });
}

/// Генерирует timestamp в ISO 8601 формате с миллисекундами.
fn chrono_timestamp() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();

    let secs = now.as_secs();
    let millis = now.subsec_millis();

    // Простая конвертация в читаемый формат без зависимости от chrono
    let hours = (secs / 3600) % 24;
    let minutes = (secs / 60) % 60;
    let seconds = secs % 60;

    format!("{:02}:{:02}:{:02}.{:03}", hours, minutes, seconds, millis)
}

/// Контекст логирования с корреляционным ID.
///
/// Используется для трассировки событий через границы слоёв.
#[derive(Debug, Clone)]
pub struct LogContext {
    /// Уникальный идентификатор для корреляции событий.
    pub correlation_id: String,
    /// Опциональный контекст операции.
    pub operation: Option<String>,
}

impl LogContext {
    /// Создать новый контекст с уникальным correlation_id.
    pub fn new() -> Self {
        Self {
            correlation_id: generate_correlation_id(),
            operation: None,
        }
    }

    /// Создать контекст с указанным operation name.
    pub fn with_operation(operation: impl Into<String>) -> Self {
        Self {
            correlation_id: generate_correlation_id(),
            operation: Some(operation.into()),
        }
    }

    /// Установить operation name.
    pub fn operation(mut self, operation: impl Into<String>) -> Self {
        self.operation = Some(operation.into());
        self
    }
}

impl Default for LogContext {
    fn default() -> Self {
        Self::new()
    }
}

/// Генерирует уникальный correlation ID.
///
/// Формат: `corr_<timestamp_ms>_<random_suffix>`
fn generate_correlation_id() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();

    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);

    format!("corr_{}_{}", timestamp, counter % 10000)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_context_has_correlation_id() {
        let ctx = LogContext::new();
        assert!(ctx.correlation_id.starts_with("corr_"));
    }

    #[test]
    fn test_log_context_with_operation() {
        let ctx = LogContext::with_operation("file_watcher");
        assert!(ctx.correlation_id.starts_with("corr_"));
        assert_eq!(ctx.operation, Some("file_watcher".to_string()));
    }

    #[test]
    fn test_correlation_ids_are_unique() {
        let ctx1 = LogContext::new();
        let ctx2 = LogContext::new();
        assert_ne!(ctx1.correlation_id, ctx2.correlation_id);
    }
}

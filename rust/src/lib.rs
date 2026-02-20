//! Latera Rust Core
//!
//! Этот crate предназначен для локальной бизнес-логики и OS-specific операций.
//! Он не зависит от Flutter. Связь с Flutter осуществляется через FFI,
//! генерируемый `flutter_rust_bridge`.

pub mod error;
pub mod file_watcher;
pub mod frb_generated;
pub mod logging;

// FRB rust-input по требованию лежит в корне `rust/api.rs`.
// Подключаем его как модуль, чтобы он участвовал в сборке crate.
#[path = "../api.rs"]
pub mod api;

pub use api::*;



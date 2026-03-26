//! Latera Rust Core
//!
//! Этот crate предназначен для локальной бизнес-логики и OS-specific операций.
//! Он не зависит от Flutter. Связь с Flutter осуществляется через FFI,
//! генерируемый `flutter_rust_bridge`.

// Allow clippy lints that are noisy for FFI/generated code
#![allow(
    clippy::needless_pass_by_value, // FFI functions require owned types
    clippy::redundant_closure,
    clippy::manual_c_str_literals,
    clippy::same_item_push,
    clippy::needless_borrows_for_generic_args,
    clippy::format_push_string,
    clippy::useless_format
)]

pub mod error;
pub mod ffi_llm;
pub mod ffi_ocr;
pub mod ffi_rag;
pub mod ffi_search;
pub mod ffi_system;
pub mod file_watcher;
pub mod frb_generated;
pub mod indexer;
pub mod logging;
pub mod system_info;

// FRB rust-input по требованию лежит в корне `rust/api.rs`.
// Подключаем его как модуль, чтобы он участвовал в сборке crate.
#[path = "../api.rs"]
pub mod api;

pub use api::*;
pub use logging::{init_logging, LogContext};

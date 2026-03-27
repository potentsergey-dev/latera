//! Latera Rust Core
//!
//! Этот crate предназначен для локальной бизнес-логики и OS-specific операций.
//! Он не зависит от Flutter. Связь с Flutter осуществляется через FFI,
//! генерируемый `flutter_rust_bridge`.

// Allow lints that are noisy for FFI/generated code
#![allow(dead_code)] // Fields/methods used on specific platforms or reserved for future use
#![allow(
    clippy::needless_pass_by_value, // FFI functions require owned types
    clippy::redundant_closure,
    clippy::redundant_closure_for_method_calls,
    clippy::manual_c_str_literals,
    clippy::same_item_push,
    clippy::needless_borrows_for_generic_args,
    clippy::format_push_string,
    clippy::useless_format,
    clippy::cast_precision_loss,
    clippy::manual_div_ceil,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_lossless,
    clippy::uninlined_format_args,
    clippy::single_match_else,
    clippy::match_same_arms,
    clippy::match_like_matches_macro,
    clippy::explicit_iter_loop,
    clippy::if_not_else,
    clippy::too_many_lines,
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::module_name_repetitions,
    clippy::must_use_candidate,
    clippy::return_self_not_must_use,
    clippy::unnecessary_wraps,
    clippy::unused_self,
    clippy::struct_excessive_bools,
    clippy::used_underscore_binding,
    clippy::approx_constant,
    clippy::doc_markdown,
    clippy::items_after_statements,
    clippy::wildcard_imports,
    clippy::redundant_else,
    clippy::implicit_clone,
    clippy::unreadable_literal,
    clippy::trivially_copy_pass_by_ref,
    clippy::option_if_let_else,
    clippy::default_trait_access,
    clippy::semicolon_if_nothing_returned,
    clippy::inconsistent_struct_constructor,
    clippy::manual_let_else,
    clippy::map_unwrap_or,
    clippy::needless_raw_string_hashes,
    clippy::range_plus_one,
    clippy::bool_to_int_with_if,
    clippy::needless_range_loop,
    clippy::filter_map_next
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

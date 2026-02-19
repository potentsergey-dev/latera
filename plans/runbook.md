# Latera — Runbook (Windows-first)

## Требования

- Flutter SDK stable.
- Visual Studio (Desktop development with C++) для Windows.
- Developer Mode (нужен для symlink поддержки плагинов).

## Запуск Flutter

Из корня репозитория:

1) Установить зависимости:

   - `cd flutter`
   - `flutter pub get`

2) Запуск под Windows:

   - `flutter run -d windows`

## Проверка уведомлений

На [`MainScreen`](../flutter/lib/presentation/main_screen.dart:1) есть кнопка **«Тест уведомления»**.

## Следующий шаг: Rust + flutter_rust_bridge

После установки Rust toolchain (rustup + MSVC):

1) Установить codegen:

   - `cargo install flutter_rust_bridge_codegen`

2) Добавить crate в [`rust/`](../rust:1) и файл API [`rust/src/api.rs`](../rust/src/api.rs:1).

3) Генерация биндингов будет оформлена через `dart run flutter_rust_bridge_codegen ...` и зафиксирована здесь после появления Rust API.


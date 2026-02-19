# Latera — архитектурная основа (foundation)

Цель: профессиональная база для desktop-приложения локального поиска.

Текущий статус репозитория:

- Flutter desktop каркас (Windows-first).
- Чистая раскладка слоёв `presentation/application/domain/infrastructure`.
- Инфраструктурный сервис уведомлений через `flutter_local_notifications`.

Rust Core + `flutter_rust_bridge` будут подключены следующим шагом после установки Rust toolchain (rustup/cargo). Сейчас в Flutter используется безопасная `no-op` заглушка watcher, чтобы приложение компилировалось и UI мог развиваться независимо.

## Слои Flutter

Структура:

- [`flutter/lib/presentation/`](../flutter/lib/presentation:1) — UI (виджеты, экраны). Без прямых интеграций.
- [`flutter/lib/application/`](../flutter/lib/application:1) — orchestration/координаторы use-case’ов (подписки на события, политика уведомлений).
- [`flutter/lib/domain/`](../flutter/lib/domain:1) — сущности/контракты (интерфейсы). Без Flutter-плагинов.
- [`flutter/lib/infrastructure/`](../flutter/lib/infrastructure:1) — реализации (плагины, bridge к Rust в будущем).

## Rust Core (план интеграции)

Требования к Rust:

- Полностью локально, без интернета.
- OS-specific операции внутри Rust.
- Определить Desktop path и дефолт `Desktop/Latera` (путь должен быть конфигурируемым, но дефолт выбирается в Rust).
- Создавать папку при отсутствии.
- Наблюдать события `notify` (создание нового файла) и отдавать stream событий во Flutter.
- Graceful shutdown.

Интеграция:

- `flutter_rust_bridge` (runtime)
- `flutter_rust_bridge_codegen` (генерация)

## Расширение (SQLite/FTS5/семантика)

Под дальнейшую эволюцию:

- индексатор файлов (domain/application) → SQLite (infrastructure) → FTS5.
- семантика: локальные эмбеддинги + векторный индекс (в Rust core, без сети).
- Free/Pro: через feature-flags/политику в application слое и разнесённые модули.


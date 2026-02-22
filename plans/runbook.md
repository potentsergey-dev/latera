# Latera — Runbook (Windows-first)

## Требования

- Flutter SDK stable.
- Visual Studio (Desktop development with C++) для Windows.
- Developer Mode (нужен для symlink поддержки плагинов).

## Текущее «зелёное» состояние (фиксируем базу)

Критерии готовности (сейчас уже выполнены):

- Проект собирается и запускается под Windows.
- `file_watcher` в Rust обнаруживает новые файлы в `Desktop/Latera`.
- Flutter получает события в реальном времени.
- Системные уведомления показываются при добавлении файла.

Подтверждённые исправления:

- GUID в `flutter_local_notifications_windows` — без фигурных скобок.
- Устранён race condition инициализации уведомлений (кешированный `Future`).
- Ошибки инициализации корректно отображаются в UI.

## Запуск Flutter

Из корня репозитория:

1) Установить зависимости:

   - `cd flutter`
   - `flutter pub get`

2) Запуск под Windows:

   - `flutter run -d windows`

## Проверка уведомлений

На [`MainScreen`](../flutter/lib/presentation/main_screen.dart:1) есть кнопка **«Тест уведомления»**.

## Спринт 2 дня — Stabilize foundation (план задач)

Цель: укрепить жизненный цикл watcher, устойчивость к burst-событиям, модель ошибок и логирование.

### День 1 — Жизненный цикл + границы API

1) Аудит слоёв Flutter (зависимости):
   - Domain без FRB/Flutter/плагинов.
   - Application только orchestration.

2) Публичные контракты домена:
   - `FileWatcher` (start/stop/stream), `NotificationsService`.
   - Инварианты и политика ошибок.

3) Граница FRB:
   - Единая точка входа Rust Core.
   - Явная модель событий (single + batch).
   - Единая модель ошибок Rust → Dart.

4) Graceful shutdown watcher:
   - start/stop, отмена, гарантированное закрытие Stream.

### День 2 — Устойчивость + наблюдаемость

5) `notify` фильтры/дедуп/батчи:
   - дедуп в окне 300 мс;
   - лимит 200 событий/сек;
   - при превышении — batch-событие до 200 элементов.

6) Логирование:
   - Rust: `log` + единая инициализация;
   - Flutter: единый `Logger` и корреляция событий.

7) Минимальные тесты и smoke:
   - Rust: watcher на временной директории.
   - Flutter: mocked watcher, проверка политики уведомлений.

## Rust + flutter_rust_bridge

Rust crate уже добавлен в [`rust/`](../rust:1). API определён в [`rust/api.rs`](../rust/api.rs:1).

### Установка codegen

```bash
cargo install flutter_rust_bridge_codegen
```

### Быстрая генерация

```powershell
.\scripts\codegen.ps1
```

См. подробности в разделе [Автоматизация FRB Codegen](#автоматизация-frb-codegen).

## FRB граница — целевые контракты (описание без генерации)

### Единая точка входа

- Все публичные типы/функции объявляются в `rust/api.rs`.
- В Rust Core внутренняя логика остаётся в `src/*`.

### Версионирование API

- Функция `get_api_version()` возвращает SemVer (`MAJOR.MINOR.PATCH`).
- Dart проверяет совместимость по `MAJOR`.

### Типы событий

- `FileEvent` (универсальный контейнер для событий)
- `FileEventType`: `Added | Modified | Renamed | Removed`
- `old_path` используется только для `Renamed`

### Ошибки Rust → Dart

- `LateraApiError` = `{ code, message, details }`
- `ErrorCode`: `DesktopDirNotFound | InvalidPath | WatcherAlreadyRunning |
  WatcherNotRunning | Io | Notify | FileNameMissing | Unknown`

### Состояние генерации

> **⚠️ Известная проблема на Windows:** FRB codegen v2.11.1 имеет баг с путями на Windows
> (ошибка `prefix not found` в `compute_mod_from_rust_path`). Это связано с тем, как Windows
> обрабатывает `canonicalize` с префиксом `\\?\`.

**Обходные пути:**

1. **WSL2** — запустить codegen в Windows Subsystem for Linux:
   ```bash
   wsl -d Ubuntu
   cd /mnt/c/Users/voron/Documents/Projects/latera
   ./scripts/codegen.sh
   ```

2. **macOS/Linux** — использовать другую ОС для codegen.

3. **Ручное редактирование** — если изменения в API минимальны, можно отредактировать
   сгенерированные файлы вручную:
   - [`rust/src/frb_generated.rs`](../rust/src/frb_generated.rs)
   - [`flutter/lib/infrastructure/rust/generated/`](../flutter/lib/infrastructure/rust/generated/)

**Текущее состояние:** Файлы уже сгенерированы и работают. Codegen нужен только при изменении API.

## Автоматизация FRB Codegen

### Скрипты

Проект содержит скрипты для автоматизации генерации биндингов:

| Скрипт | Платформа | Описание |
|--------|-----------|----------|
| [`scripts/codegen.ps1`](../scripts/codegen.ps1) | Windows | Генерация FRB биндингов |
| [`scripts/codegen.sh`](../scripts/codegen.sh) | macOS/Linux | Генерация FRB биндингов |
| [`scripts/build.ps1`](../scripts/build.ps1) | Windows | Полная сборка (codegen + Rust + Flutter) |
| [`scripts/build.sh`](../scripts/build.sh) | macOS/Linux | Полная сборка |

### Генерация биндингов (codegen)

**Windows (PowerShell):**

```powershell
# Однократная генерация
.\scripts\codegen.ps1

# Watch-режим (авторегенерация при изменениях)
.\scripts\codegen.ps1 -Watch
```

**macOS/Linux (Bash):**

```bash
# Однократная генерация
./scripts/codegen.sh

# Watch-режим
./scripts/codegen.sh --watch
```

### Полная сборка

**Windows (PowerShell):**

```powershell
# Debug-сборка
.\scripts\build.ps1

# Release-сборка
.\scripts\build.ps1 -Release

# Пропустить этапы
.\scripts\build.ps1 -SkipCodegen    # Без регенерации биндингов
.\scripts\build.ps1 -SkipRust       # Без сборки Rust
.\scripts\build.ps1 -SkipFlutter    # Без сборки Flutter
```

**macOS/Linux (Bash):**

```bash
# Debug-сборка
./scripts/build.sh

# Release-сборка
./scripts/build.sh --release

# Пропустить этапы
./scripts/build.sh --skip-codegen
./scripts/build.sh --skip-rust
./scripts/build.sh --skip-flutter
```

### Ручные команды (справочно)

Если скрипты недоступны, можно запустить codegen вручную:

```bash
cd rust
flutter_rust_bridge_codegen generate --config-file frb_codegen.yaml
```

Или из директории flutter:

```bash
cd flutter
dart run flutter_rust_bridge_codegen generate --config-file ../rust/frb_codegen.yaml
```

### Конфигурация FRB

Конфигурация находится в [`rust/frb_codegen.yaml`](../rust/frb_codegen.yaml):

```yaml
rust_input: "crate::api"                              # Точка входа Rust API
rust_root: "."                                        # Корень Rust crate
dart_output: "../flutter/lib/infrastructure/rust/generated"  # Выход Dart файлов
rust_output: "src/frb_generated.rs"                   # Выход Rust файла
dart_entrypoint_class_name: "RustCore"               # Имя класса в Dart
no_add_mod_to_lib: true                               # Не модифицировать lib.rs
no_web: true                                          # Без web-поддержки
default_dart_async: true                              # Async по умолчанию
type_64bit_int: true                                  # 64-битные int
```

### Требования для codegen

1. **Rust toolchain** — установлен через rustup
2. **flutter_rust_bridge_codegen** — установлен глобально:
   ```bash
   cargo install flutter_rust_bridge_codegen
   ```
3. **Flutter dependencies** — `flutter pub get` выполнен

### Выходные файлы

После успешной генерации:

- **Rust:** [`rust/src/frb_generated.rs`](../rust/src/frb_generated.rs)
- **Dart:** [`flutter/lib/infrastructure/rust/generated/`](../flutter/lib/infrastructure/rust/generated/)
  - `api.dart` — публичное API
  - `frb_generated.dart` — сгенерированные биндинги
  - `frb_generated.io.dart` — IO-реализация
  - `error.dart` — типы ошибок


# Latera Build Scripts

Скрипты для автоматизации сборки и генерации кода.

## Скрипты

| Файл | Описание |
|------|----------|
| `codegen.ps1` / `codegen.sh` | Генерация FRB биндингов |
| `build.ps1` / `build.sh` | Полная сборка проекта |

## Использование

### codegen.ps1 / codegen.sh

Генерирует Dart биндинги из Rust API.

```powershell
# Windows
.\scripts\codegen.ps1           # Однократная генерация
.\scripts\codegen.ps1 -Watch    # Watch-режим
```

```bash
# macOS/Linux
./scripts/codegen.sh            # Однократная генерация
./scripts/codegen.sh --watch    # Watch-режим
```

### build.ps1 / build.sh

Полная сборка: codegen → Rust → Flutter.

```powershell
# Windows
.\scripts\build.ps1                    # Debug
.\scripts\build.ps1 -Release           # Release
.\scripts\build.ps1 -SkipCodegen       # Пропустить codegen
```

```bash
# macOS/Linux
./scripts/build.sh                     # Debug
./scripts/build.sh --release           # Release
./scripts/build.sh --skip-codegen      # Пропустить codegen
```

## Требования

- Rust toolchain (rustup)
- Flutter SDK
- `flutter_rust_bridge_codegen`:
  ```bash
  cargo install flutter_rust_bridge_codegen
  ```

## ⚠️ Известная проблема на Windows

FRB codegen v2.11.1 имеет баг с путями на Windows (ошибка `prefix not found`).

**Обходные пути:**

1. **WSL2** — запустить codegen в Windows Subsystem for Linux:
   ```bash
   wsl -d Ubuntu
   cd /mnt/c/Users/voron/Documents/Projects/latera
   ./scripts/codegen.sh
   ```

2. **macOS/Linux** — использовать другую ОС для codegen.

3. **Ручное редактирование** — если изменения в API минимальны.

См. подробности в [`plans/runbook.md`](../plans/runbook.md).

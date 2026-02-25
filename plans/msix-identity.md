# MSIX Package Identity

Этот документ описывает конфигурацию identity для MSIX-упаковки приложения Latera.

## Обзор

Для корректной работы Windows Store и toast-уведомлений все идентификаторы приложения должны быть синхронизированы.

## Identity Components

### 1. Package Identity (MSIX)

```yaml
# flutter/pubspec.yaml
msix:
  display_name: Latera
  publisher_display_name: Latera Team
  identity_name: com.latera.latera
  publisher: CN=LateraTeam, O=Latera, C=BY
```

### 2. EXE Metadata (Runner.rc)

```rc
VALUE "CompanyName", "Latera Team"
VALUE "FileDescription", "Latera"
VALUE "ProductName", "Latera"
VALUE "LegalCopyright", "Copyright (C) 2026 Latera Team. All rights reserved."
```

### 3. AUMID (Application User Model ID)

```dart
// flutter/lib/infrastructure/notifications/local_notifications_service.dart
const windows = WindowsInitializationSettings(
  appName: 'Latera',
  appUserModelId: 'com.latera.latera',
  guid: '7F4D8B8A-0DB5-4D6B-9F2F-6F4F7D9D9D0E',
);
```

## Package Family Name (PFN)

При упаковке в MSIX Windows вычисляет Package Family Name:

```
PFN = {IdentityName}_{PublisherHash}
```

Пример: `com.latera.latera_abc123def456`

### Важно для toast-уведомлений

- **Unpackaged режим**: Используется `appUserModelId` из настроек плагина
- **Packaged режим (MSIX)**: Плагин автоматически использует PFN

`flutter_local_notifications` для Windows автоматически определяет режим и использует правильный идентификатор.

## Microsoft Store Публикация

### До публикации

Текущая конфигурация использует самоподписанный сертификат:

```
CN=LateraTeam, O=Latera, C=BY
```

### После резервирования в Store

Partner Center назначит:

1. **Identity Name** — может измениться если имя занято
2. **Publisher** — сертификат Store

Пример после публикации:

```yaml
msix:
  identity_name: com.latera.latera  # или назначенный Store
  publisher: CN=...{Store Certificate}
```

### Чеклист для Store

- [ ] Зарезервировать имя приложения в Partner Center
- [ ] Получить Publisher Certificate от Store
- [ ] Обновить `publisher` в pubspec.yaml
- [ ] При необходимости обновить `identity_name`
- [ ] Пересобрать MSIX с новыми параметрами

## Синхронизация Identity

| Компонент | Значение | Файл |
|-----------|----------|------|
| ProductName | `Latera` | Runner.rc, pubspec.yaml |
| CompanyName | `Latera Team` | Runner.rc |
| Identity Name | `com.latera.latera` | pubspec.yaml |
| AUMID | `com.latera.latera` | local_notifications_service.dart |
| Publisher | `CN=LateraTeam, O=Latera, C=BY` | pubspec.yaml |

## Toast-уведомления в MSIX

### Требования Windows

1. AUMID должен соответствовать Package Identity
2. Приложение должно быть зарегистрировано в системе
3. Должны быть настроены capabilities в манифесте

### Текущие capabilities

```yaml
# flutter/pubspec.yaml
msix:
  capabilities: broadFileSystemAccess, picturesLibrary
```

### Проверка работы уведомлений

1. Собрать MSIX: `flutter pub run msix:create`
2. Установить пакет
3. Запустить приложение
4. Триггернуть уведомление
5. Проверить Action Center

## Troubleshooting

### Уведомления не работают в MSIX

1. Проверить, что `identity_name` совпадает с AUMID
2. Убедиться, что Publisher корректен
3. Проверить логи: Event Viewer → Applications and Services → Microsoft → Windows → Apps

### Store отклоняет пакет

Частые причины:
- Неверный Publisher сертификат
- Несоответствие identity_name зарезервированному имени
- Отсутствующие capabilities

## Ссылки

- [Windows App Identity](https://learn.microsoft.com/en-us/windows/win32/appxpkg/app-identity)
- [Package Family Name](https://learn.microsoft.com/en-us/windows/win32/appxpkg/package-family-name)
- [Toast Notifications for Packaged Apps](https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/toast-notifications-overview)
- [MSIX Pub Package](https://pub.dev/packages/msix)

---

# Шаг 3: Подпись и Release Pipeline

## Обзор

Этот раздел описывает процесс подписи MSIX-пакетов и настройки release pipeline для автоматической сборки и публикации.

## Release Pipeline

### Триггеры

Release pipeline запускается автоматически при публикации тега версии:

```bash
# Создание релиза
git tag v1.0.0
git push origin v1.0.0
```

### Этапы Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    Release Pipeline                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Checkout                                                     │
│  2. Setup Rust + Flutter                                         │
│  3. Run FRB Codegen                                              │
│  4. Build Rust (release)                                         │
│  5. Build Flutter Windows (release)                              │
│  6. Decode Certificate from Secrets                              │
│  7. Install Certificate to Store                                 │
│  8. Create & Sign MSIX                                           │
│  9. Run Windows App Certification Kit                            │
│  10. Upload Artifacts                                            │
│  11. Create GitHub Release                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Файлы Pipeline

| Файл | Назначение |
|------|------------|
| `.github/workflows/release.yml` | Release pipeline |
| `.github/workflows/ci.yml` | CI (lint, test, build) |

## Подпись сертификатом

### Типы сертификатов

| Тип | Использование | Получение |
|-----|---------------|-----------|
| **Self-signed** | Тестирование, разработка | `scripts/create-test-cert.ps1` |
| **Store Certificate** | Microsoft Store | Partner Center |
| **EV Code Signing** | Внешнее распространение | DigiCert, Sectigo, GlobalSign |

### Создание тестового сертификата

```powershell
# Создать тестовый сертификат
.\scripts\create-test-cert.ps1

# С указанием пароля
.\scripts\create-test-cert.ps1 -Password "your-secure-password"

# Результат:
# - certs/latera-test.pfx (private key)
# - certs/latera-test.cer (public key)
# - certs/base64-cert.txt (для GitHub Secrets)
```

### Настройка GitHub Secrets

Для работы release pipeline необходимо добавить следующие secrets:

| Secret | Описание | Как получить |
|--------|----------|--------------|
| `BASE64_CERT` | Base64-encoded PFX | `certs/base64-cert.txt` |
| `CERT_PASSWORD` | Пароль сертификата | Задаётся при создании |
| `CERT_SHA1` | SHA1 thumbprint (опционально) | Вывод скрипта создания |

**Добавление secrets:**
1. Repository → Settings → Secrets and variables → Actions
2. New repository secret
3. Добавить `BASE64_CERT` и `CERT_PASSWORD`

### Установка сертификата на тестовых машинах

Для установки self-signed сертификата на целевой машине:

```powershell
# Вариант 1: Через GUI
# Двойной клик на latera-test.cer → Install Certificate → Local Machine → Trusted People

# Вариант 2: Через PowerShell (требует админа)
certutil -addstore "TrustedPeople" latera-test.cer
```

## Воспроизводимость сборки

### Фиксированные версии

```yaml
# .github/workflows/release.yml
env:
  FLUTTER_VERSION: '3.41.1'
  RUST_VERSION: '1.93'
```

### Lock файлы

- `pubspec.lock` — версии Dart/Flutter зависимостей
- `Cargo.lock` — версии Rust зависимостей

### Remap путей

Для детерминированных сборок Rust использует remap:

```yaml
env:
  RUSTFLAGS: "--remap-path-prefix=${{ github.workspace }}=/build"
```

## Windows App Certification Kit (WACK)

### Что проверяет WACK

| Категория | Проверки |
|-----------|----------|
| **App Manifest** | Валидность XML, обязательные поля |
| **Performance** | Время запуска, suspend/resume |
| **Security** | Запрещённые API, capabilities |
| **Compatibility** | Версия OS, архитектура |

### Запуск WACK локально

```powershell
# Требуется Windows SDK
"C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe" test -appx path\to\app.msix -reportoutputpath report.xml
```

### Результаты в CI

- WACK report загружается как artifact
- При провале WACK — предупреждение (не блокирует релиз)
- Для Store submission WACK должен проходить успешно

## Локальная сборка MSIX

### Без подписи (для тестирования)

```powershell
.\scripts\build.ps1 -Release -Msix
```

### С подписью тестовым сертификатом

1. Создать сертификат: `.\scripts\create-test-cert.ps1`
2. Установить в хранилище: сертификат автоматически устанавливается скриптом
3. Собрать: `.\scripts\build.ps1 -Release -Msix`

### Ручная подпись

```powershell
# Подписать существующий MSIX
signtool sign /fd SHA256 /a /f certs\latera-test.pfx /p "password" latera.msix
```

## Чеклист релиза

- [ ] Обновить версию в `pubspec.yaml`
- [ ] Обновить `version` в секции `msix:`
- [ ] Убедиться, что все тесты проходят
- [ ] Создать тег: `git tag v1.0.0`
- [ ] Запушить тег: `git push origin v1.0.0`
- [ ] Дождаться завершения pipeline
- [ ] Проверить GitHub Release
- [ ] Проверить WACK report

## Troubleshooting

### Ошибка: "Certificate not found"

```
Убедитесь, что сертификат установлен в Cert:\CurrentUser\My
и subject совпадает с publisher в pubspec.yaml
```

### Ошибка: "The file is not digitally signed"

```
Установите публичный сертификат (.cer) в Trusted People
на целевой машине
```

### WACK: "Failed - Banned APIs"

```
Проверьте использование запрещённых API:
- Не используйте Win32 API напрямую
- Используйте WinRT API через dart:ffi или плагины
```

### Store: "Invalid package identity name"

```
Identity name должен совпадать с зарезервированным в Partner Center
Обновите identity_name в pubspec.yaml
```

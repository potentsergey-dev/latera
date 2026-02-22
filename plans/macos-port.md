# Latera — План портирования на macOS

Этот документ описывает стратегию портирования Latera с Windows на macOS, включая платформенно-зависимые абстракции, различия в API и требования к подписыванию.

## Статус: Планирование

Целевая платформа: macOS 12+ (Monterey)

---

## 1. Абстракции путей и Desktop

### Текущее состояние (Windows)

В [`rust/src/file_watcher/mod.rs`](../rust/src/file_watcher/mod.rs:58) используется крейт `dirs`:

```rust
pub fn ensure_default_watch_dir() -> Result<PathBuf, LateraError> {
  let desktop = dirs::desktop_dir().ok_or(LateraError::DesktopDirNotFound)?;
  let watch_dir = desktop.join(DEFAULT_WATCH_FOLDER_NAME);
  std::fs::create_dir_all(&watch_dir)?;
  Ok(watch_dir)
}
```

### Кроссплатформенность `dirs`

Крейт `dirs` уже поддерживает macOS из коробки:

| Платформа | `desktop_dir()` возвращает |
|-----------|---------------------------|
| Windows | `C:\Users\{user}\Desktop` |
| macOS | `/Users/{user}/Desktop` |
| Linux | `/home/{user}/Desktop` |

### Особенности macOS

1. **Символические ссылки**: macOS активно использует симлинки (например, iCloud Desktop).
   - Путь может указывать на `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop`
   - Нужно разрешать симлинки через `std::fs::canonicalize()`

2. **Case-insensitive FS (APFS)**: По умолчанию APFS case-insensitive, но имена файлов сохраняются.
   - Дедупликация должна учитывать case-insensitivity на macOS

3. **iCloud Desktop**: Пользователь может включить "Desktop & Documents Folders" в iCloud.
   - Файлы могут быть в cloud-состоянии (не скачаны локально)
   - Нужно проверять `std::fs::metadata` на наличие файла

### Рекомендуемые изменения

```rust
// rust/src/file_watcher/mod.rs

/// Платформенно-зависимое определение Desktop с поддержкой симлинков.
pub fn ensure_default_watch_dir() -> Result<PathBuf, LateraError> {
  let desktop = dirs::desktop_dir().ok_or(LateraError::DesktopDirNotFound)?;
  
  // Разрешаем симлинки (важно для iCloud Desktop на macOS)
  let desktop = std::fs::canonicalize(&desktop)
    .unwrap_or(desktop);
  
  let watch_dir = desktop.join(DEFAULT_WATCH_FOLDER_NAME);
  std::fs::create_dir_all(&watch_dir)?;
  Ok(watch_dir)
}

/// Проверка, что файл реально существует локально (не в cloud).
#[cfg(target_os = "macos")]
fn is_local_file(path: &Path) -> bool {
  use std::os::unix::fs::MetadataExt;
  match std::fs::metadata(path) {
    Ok(m) => {
      // Проверка на "empty" файлы в iCloud (размер 0 + определённые флаги)
      // Полная проверка требует вызова getattrlist()
      m.is_file() && m.size() > 0
    }
    Err(_) => false,
  }
}
```

---

## 2. Различия `notify` на macOS

### Текущее использование

```rust
// rust/src/file_watcher/mod.rs:99
let mut watcher: RecommendedWatcher = notify::recommended_watcher(move |res| {
  let _ = event_tx.send(res);
})?;
```

### Особенности FSEvents (macOS backend)

Крейт `notify` на macOS использует FSEvents, который имеет отличия от Windows:

| Аспект | Windows (ReadDirectoryChangesW) | macOS (FSEvents) |
|--------|--------------------------------|------------------|
| Latency | Мгновенные события | Есть задержка (latency ~0-1 сек) |
| Batch | Одиночные события | Автоматический batch событий |
| Rename | Событие Rename | Может прийти как Create + Delete |
| Recursive | Требует явного флага | Всегда recursive по умолчанию |

### Известные проблемы

1. **Дублирование событий**: FSEvents может отправлять одно событие несколько раз.
   - Текущий дедуп window 300 мс должен помочь, но может потребоваться увеличение

2. **Latency**: FSEvents имеет встроенную задержку для оптимизации.
   - Можно настроить через `Config::default().with_poll_interval(Duration::from_millis(100))`

3. **События при старте**: FSEvents может отправить события о существующих файлах.
   - Нужно фильтровать события по времени создания watcher'а

### Рекомендуемые изменения

```rust
// rust/src/file_watcher/mod.rs

#[cfg(target_os = "macos")]
fn create_watcher(
  event_tx: mpsc::Sender<Result<notify::Event, notify::Error>>,
) -> Result<RecommendedWatcher, notify::Error> {
  use notify::Config;
  
  // Уменьшаем latency для более отзывчивого UI
  let config = Config::default()
    .with_poll_interval(Duration::from_millis(100));
  
  notify::recommended_watcher_with_config(move |res| {
    let _ = event_tx.send(res);
  }, config)
}

#[cfg(not(target_os = "macos"))]
fn create_watcher(
  event_tx: mpsc::Sender<Result<notify::Event, notify::Error>>,
) -> Result<RecommendedWatcher, notify::Error> {
  notify::recommended_watcher(move |res| {
    let _ = event_tx.send(res);
  })
}
```

---

## 3. Уведомления на macOS

### Текущее состояние

[`flutter/lib/infrastructure/notifications/local_notifications_service.dart`](../flutter/lib/infrastructure/notifications/local_notifications_service.dart:170) уже содержит код для macOS:

```dart
final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
if (macos != null) {
  final granted = await macos.requestPermissions(
    alert: true,
    badge: true,
    sound: true,
  );
}
```

### Особенности macOS уведомлений

1. **User Notification Center**: macOS использует UNUserNotificationCenter.
   - Требует entitlements для подписанных приложений
   - Работает только в foreground для unsigned debug builds

2. **Notification Center API**: Начиная с macOS 11, есть ограничения.
   - Требуется `com.apple.security.user-notifications` entitlement для sandboxed apps

3. **Badge**: Установка badge требует отдельного разрешения.
   - Badge отображается на иконке в Dock

4. **Sound**: Системные звуки или кастомные в bundle.
   - Кастомные звуки должны быть в `*.aiff`, `*.wav` или `*.caf` формате

### Требования к entitlements

```xml
<!-- macos/Runner/DebugProfile.entitlements -->
<!-- macos/Runner/Release.entitlements -->
<key>com.apple.security.user-notifications</key>
<true/>
```

### Рекомендуемые изменения

```dart
// flutter/lib/infrastructure/notifications/local_notifications_service.dart

Future<void> _initializePlugin(LogContext ctx) async {
  // macOS требует явные настройки для notification center
  const macosSettings = MacOSInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
  );

  const settings = InitializationSettings(
    windows: windows,
    android: android,
    iOS: darwin,
    macOS: macosSettings, // Обновлённые настройки
  );
  // ...
}
```

---

## 4. Sandbox и Entitlements

### macOS App Sandbox

Для дистрибуции через Mac App Store **обязателен** sandbox. Для direct distribution — опционален, но рекомендуется для notarization.

### Требуемые Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- File Access: Desktop -->
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  
  <!-- Или для полного доступа к Desktop (требует обоснования для App Store) -->
  <key>com.apple.security.files.downloads.read-write</key>
  <true/>
  
  <!-- Notifications -->
  <key>com.apple.security.user-notifications</key>
  <true/>
  
  <!-- Network (если понадобится в будущем) -->
  <!-- <key>com.apple.security.network.client</key> -->
  <!-- <true/> -->
  
  <!-- Disable Library Validation для debug (только DebugProfile.entitlements) -->
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  
  <!-- Allow DYLD environment variables для debug -->
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
</dict>
</plist>
```

### Проблема с Desktop доступом в Sandbox

Sandbox ограничивает доступ к файловой системе. Варианты решения:

#### Вариант A: User-Selected Files (App Store friendly)
1. Пользователь выбирает папку через `NSOpenPanel`
2. Сохраняем security-scoped bookmark
3. Используем bookmark для доступа при последующих запусках

```dart
// Flutter: file_selector package
import 'package:file_selector/file_selector.dart';

Future<String?> selectWatchDirectory() async {
  final String? path = await getDirectoryPath();
  if (path != null) {
    // Сохранить security-scoped bookmark
    await _saveBookmark(path);
  }
  return path;
}
```

#### Вариант B: Hardened Runtime без Sandbox (Direct distribution)
1. Отключаем sandbox
2. Подписываем с hardened runtime
3. Notarize у Apple

### Security-Scoped Bookmarks (для Sandbox)

```swift
// macos/Runner/AppDelegate.swift

func saveBookmark(for url: URL) -> Data? {
  return try? url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
  )
}

func resolveBookmark(_ data: Data) -> URL? {
  var isStale = false
  guard let url = try? URL(
    resolvingBookmarkData: data,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
  ) else { return nil }
  
  if isStale {
    // Bookmark устарел, нужно пересоздать
    return nil
  }
  return url
}
```

---

## 5. Flutter macOS Setup

### Структура проекта

```
flutter/
├── macos/
│   ├── Runner/
│   │   ├── AppDelegate.swift
│   │   ├── Assets.xcassets/
│   │   ├── Base.lproj/
│   │   ├── DebugProfile.entitlements    # Добавить
│   │   ├── Release.entitlements          # Добавить
│   │   ├── Info.plist
│   │   └── Config.xcconfig
│   ├── Runner.xcodeproj/
│   └── Podfile
```

### Создание macOS runner

```bash
cd flutter
flutter create --platforms=macos .
```

### Podfile для macOS

```ruby
# flutter/macos/Podfile
platform :osx, '10.14'

target 'Runner' do
  use_frameworks!
  
  # Flutter local notifications
  pod 'FlutterLocalNotificationsPlugin'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.14'
    end
  end
end
```

### Xcode Configuration

```xcconfig
# macos/Runner/Config.xcconfig
MACOSX_DEPLOYMENT_TARGET = 10.14
CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements
CODE_SIGN_IDENTITY = -
```

---

## 6. Rust macOS Build

### Целевые triple

```bash
# Добавить target
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin  # Apple Silicon

# Сборка
cargo build --target x86_64-apple-darwin --release
cargo build --target aarch64-apple-darwin --release
```

### Universal Binary (опционально)

```bash
# Создать universal binary
lipo -create \
  target/x86_64-apple-darwin/release/liblatera_rust.dylib \
  target/aarch64-apple-darwin/release/liblatera_rust.dylib \
  -output target/universal/liblatera_rust.dylib
```

### FRB Codegen для macOS

```yaml
# rust/frb_codegen.yaml
rust_input:
  - rust/api.rs
dart_output:
  - flutter/lib/infrastructure/rust/generated/
class_name: RustCoreApi
# macOS-specific settings
dart_format_line_length: 80
```

---

## 7. Чеклист портирования

### Подготовка (Pre-port)

- [ ] Создать ветку `feature/macos-port`
- [ ] Установить Xcode 14+
- [ ] Установить Rust targets: `x86_64-apple-darwin`, `aarch64-apple-darwin`
- [ ] Создать macOS runner: `flutter create --platforms=macos .`

### Rust Core

- [ ] Проверить сборку `cargo build --target x86_64-apple-darwin`
- [ ] Добавить платформенно-зависимый код для FSEvents latency
- [ ] Добавить обработку симлинков в `ensure_default_watch_dir`
- [ ] Протестировать `notify` на macOS (интеграционные тесты)
- [ ] Обновить `LateraError` с macOS-специфичными ошибками

### Flutter

- [ ] Добавить `flutter_local_notifications` для macOS в pubspec.yaml
- [ ] Создать `macos/Runner/DebugProfile.entitlements`
- [ ] Создать `macos/Runner/Release.entitlements`
- [ ] Обновить `Info.plist` с разрешениями
- [ ] Настроить `Podfile` для macOS
- [ ] Добавить platform-specific код для security-scoped bookmarks

### Уведомления

- [ ] Протестировать `MacOSFlutterLocalNotificationsPlugin`
- [ ] Добавить `com.apple.security.user-notifications` entitlement
- [ ] Проверить работу уведомлений в sandboxed режиме

### Тестирование

- [ ] Unit-тесты Rust на macOS
- [ ] Интеграционные тесты file watcher
- [ ] UI тесты на macOS
- [ ] Тест на Apple Silicon (M1/M2)
- [ ] Тест на Intel Mac

### Дистрибуция

- [ ] Настроить code signing certificate
- [ ] Настроить notarization workflow
- [ ] Создать DMG installer
- [ ] Протестировать установку на чистой системе

---

## 8. Известные проблемы и решения

### Проблема: FRB codegen падает на macOS

**Симптом**: `flutter_rust_bridge_codegen` падает с ошибкой.

**Решение**: Использовать ручную генерацию или pre-generated bindings.

### Проблема: Sandbox блокирует доступ к Desktop

**Симптом**: `Permission denied` при попытке создать `Desktop/Latera`.

**Решение**: Использовать security-scoped bookmarks или отключить sandbox для direct distribution.

### Проблема: Уведомления не работают в debug

**Симптом**: Уведомления не показываются при запуске через `flutter run`.

**Решение**: Добавить `com.apple.security.user-notifications` entitlement в `DebugProfile.entitlements`.

### Проблема: Library validation error

**Симптом**: Приложение падает при загрузке Rust dylib.

**Решение**: Добавить `com.apple.security.cs.disable-library-validation` entitlement для debug.

---

## 9. Ссылки

- [Apple App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/security/app_sandbox/enabling_app_sandbox/accessing_files_from_the_app_sandbox)
- [flutter_local_notifications macOS](https://pub.dev/packages/flutter_local_notifications#macos)
- [notify crate documentation](https://docs.rs/notify/latest/notify/)
- [dirs crate documentation](https://docs.rs/dirs/latest/dirs/)
- [Flutter macOS desktop support](https://docs.flutter.dev/desktop)

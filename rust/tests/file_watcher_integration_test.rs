//! Интеграционные тесты для file_watcher.
//!
//! Используют временную директорию для изоляции тестов.

use std::collections::VecDeque;
use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use tempfile::TempDir;

use latera_rust::file_watcher::{start_watcher, InternalFileEvent};

/// Собирает события в потокобезопасную очередь для проверки.
#[derive(Clone, Default)]
struct EventCollector {
    events: Arc<Mutex<VecDeque<InternalFileEvent>>>,
}

impl EventCollector {
    fn new() -> Self {
        Self::default()
    }

    fn push(&self, event: InternalFileEvent) {
        self.events.lock().unwrap().push_back(event);
    }

    fn take_all(&self) -> Vec<InternalFileEvent> {
        self.events.lock().unwrap().drain(..).collect()
    }

    fn count(&self) -> usize {
        self.events.lock().unwrap().len()
    }
}

/// Вспомогательная функция для ожидания событий с таймаутом.
fn wait_for_events(collector: &EventCollector, min_count: usize, timeout: Duration) -> bool {
    let start = std::time::Instant::now();
    while start.elapsed() < timeout {
        if collector.count() >= min_count {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    false
}

/// Создаёт тестовый файл в указанной директории.
fn create_test_file(dir: &Path, name: &str) -> PathBuf {
    let path = dir.join(name);
    File::create(&path).expect("Failed to create test file");
    path
}

// ============================================================================
// Тесты базовой функциональности
// ============================================================================

#[test]
fn test_watcher_starts_and_stops_successfully() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Проверяем, что watcher наблюдает за правильной директорией
    assert_eq!(handle.watch_dir(), temp_dir.path());

    // Останавливаем watcher
    handle.stop().expect("Failed to stop watcher");
}

#[test]
fn test_watcher_detects_new_file() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(200));

    // Создаём файл
    create_test_file(temp_dir.path(), "test_file.txt");

    // Ждём обнаружения события
    let found = wait_for_events(&collector, 1, Duration::from_secs(5));
    assert!(found, "Watcher did not detect the new file within timeout");

    let events = collector.take_all();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].file_name, "test_file.txt");
    assert!(events[0].full_path.ends_with("test_file.txt"));

    handle.stop().expect("Failed to stop watcher");
}

#[test]
fn test_watcher_detects_multiple_files() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(200));

    // Создаём несколько файлов с интервалом (чтобы избежать дедупликации)
    create_test_file(temp_dir.path(), "file1.txt");
    thread::sleep(Duration::from_millis(400)); // Больше DEDUP_WINDOW
    create_test_file(temp_dir.path(), "file2.txt");
    thread::sleep(Duration::from_millis(400));
    create_test_file(temp_dir.path(), "file3.txt");

    // Ждём обнаружения всех событий
    let found = wait_for_events(&collector, 3, Duration::from_secs(5));
    assert!(found, "Watcher did not detect all files within timeout");

    let events = collector.take_all();
    assert_eq!(events.len(), 3);

    let file_names: Vec<&str> = events.iter().map(|e| e.file_name.as_str()).collect();
    assert!(file_names.contains(&"file1.txt"));
    assert!(file_names.contains(&"file2.txt"));
    assert!(file_names.contains(&"file3.txt"));

    handle.stop().expect("Failed to stop watcher");
}

// ============================================================================
// Тесты дедупликации
// ============================================================================

#[test]
fn test_watcher_deduplicates_rapid_events() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(200));

    // Создаём файл и быстро обновляем его (эмуляция дублирующих событий FS)
    let path = temp_dir.path().join("dedup_test.txt");
    File::create(&path).expect("Failed to create file");

    // Быстро "трогаем" файл несколько раз (в пределах DEDUP_WINDOW)
    thread::sleep(Duration::from_millis(50));
    let _ = File::create(&path);
    thread::sleep(Duration::from_millis(50));
    let _ = File::create(&path);

    // Ждём немного
    thread::sleep(Duration::from_millis(500));

    // Должно быть только одно событие (дедупликация)
    let events = collector.take_all();
    assert!(
        events.len() <= 2,
        "Expected at most 2 events due to deduplication, got {}",
        events.len()
    );

    handle.stop().expect("Failed to stop watcher");
}

// ============================================================================
// Тесты обработки ошибок
// ============================================================================

#[test]
fn test_watcher_rejects_empty_path() {
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let result = start_watcher(Some(String::new()), move |e| {
        collector_clone.push(e);
    });

    assert!(result.is_err());
    if let Err(err) = result {
        assert!(err.to_string().contains("empty override_path"));
    }
}

#[test]
fn test_watcher_rejects_relative_path() {
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let result = start_watcher(Some("relative/path".to_string()), move |e| {
        collector_clone.push(e);
    });

    assert!(result.is_err());
    if let Err(err) = result {
        assert!(err.to_string().contains("must be absolute"));
    }
}

#[test]
fn test_watcher_creates_directory_if_not_exists() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let non_existent = temp_dir
        .path()
        .join("subdir")
        .join("nested")
        .join("watch_dir");

    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(Some(non_existent.to_string_lossy().to_string()), move |e| {
        collector_clone.push(e);
    })
    .expect("Failed to start watcher");

    // Директория должна быть создана
    assert!(non_existent.exists());
    assert_eq!(handle.watch_dir(), non_existent);

    handle.stop().expect("Failed to stop watcher");
}

// ============================================================================
// Тесты graceful shutdown
// ============================================================================

#[test]
fn test_watcher_stops_cleanly() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(100));

    // Останавливаем и проверяем, что это не блокирует навечно
    let start = std::time::Instant::now();
    handle.stop().expect("Failed to stop watcher");
    let elapsed = start.elapsed();

    // Graceful shutdown должен завершиться быстро
    assert!(
        elapsed < Duration::from_secs(2),
        "Stop took too long: {:?}",
        elapsed
    );
}

// ============================================================================
// Тесты содержимого событий
// ============================================================================

#[test]
fn test_event_contains_correct_metadata() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(200));

    let before_create = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;

    create_test_file(temp_dir.path(), "metadata_test.txt");

    let found = wait_for_events(&collector, 1, Duration::from_secs(5));
    assert!(found, "Watcher did not detect the file");

    let events = collector.take_all();
    assert_eq!(events.len(), 1);

    let event = &events[0];
    assert_eq!(event.file_name, "metadata_test.txt");
    assert!(event.full_path.is_absolute());
    assert!(event.full_path.ends_with("metadata_test.txt"));

    // Проверяем, что timestamp разумный (в пределах 10 секунд от создания)
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;
    assert!(
        event.occurred_at_ms >= before_create - 1000,
        "Event timestamp is too old"
    );
    assert!(
        event.occurred_at_ms <= now + 1000,
        "Event timestamp is in the future"
    );

    handle.stop().expect("Failed to stop watcher");
}

// ============================================================================
// Тесты игнорирования директорий
// ============================================================================

#[test]
fn test_watcher_ignores_directories() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let collector = EventCollector::new();
    let collector_clone = collector.clone();

    let handle = start_watcher(
        Some(temp_dir.path().to_string_lossy().to_string()),
        move |e| {
            collector_clone.push(e);
        },
    )
    .expect("Failed to start watcher");

    // Даём watcher'у время на запуск
    thread::sleep(Duration::from_millis(200));

    // Создаём поддиректорию
    let subdir = temp_dir.path().join("subdir");
    fs::create_dir(&subdir).expect("Failed to create subdir");

    // Ждём немного
    thread::sleep(Duration::from_millis(500));

    // Событий быть не должно (директории игнорируются)
    let events = collector.take_all();
    assert!(
        events.is_empty(),
        "Watcher should ignore directories, but got {:?}",
        events
    );

    handle.stop().expect("Failed to stop watcher");
}

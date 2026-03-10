import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../domain/indexer.dart';
import '../../domain/search_repository.dart';
import '../rust/rust_ocr_service.dart' show RustOcrService;

/// Расширения файлов, из которых извлекается текстовый контент.
///
/// Совпадает со списком в Rust indexer (text_extractor.rs).
const _textExtensions = <String>{
  'txt', 'md', 'markdown', 'rst', 'log', 'csv', 'tsv',
  'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'properties',
  // Исходный код
  'rs', 'dart', 'py', 'js', 'ts', 'java', 'kt', 'c', 'cpp', 'h', 'hpp',
  'cs', 'go', 'rb', 'php', 'swift', 'sh', 'bash', 'ps1', 'bat', 'cmd',
  // Web
  'html', 'htm', 'css', 'scss', 'sass', 'less',
  // Другие текстовые
  'sql', 'graphql', 'proto', 'env',
};

/// Максимальный размер файла для извлечения текста (10 MB).
const _maxTextFileSize = 10 * 1024 * 1024;

/// Размерность вектора эмбеддинга (384 для all-MiniLM-L6-v2, 64 для stub).
/// При вычислении similarity — используем фактическую размерность из BLOB.
// ignore_for_file: unused_element
const _embeddingDimOnnx = 384;
const _embeddingDimStub = 64;

/// SQLite FTS5 реализация индексатора и поискового репозитория.
///
/// Использует тот же SQL-формат, что и Rust indexer, для совместимости
/// при будущем переключении на Rust-backed реализацию.
///
/// Реализует оба интерфейса [Indexer] и [SearchRepository], т.к. они
/// работают с одной и той же БД.
class SqliteIndexService implements Indexer, SearchRepository {
  final Logger _log;
  final String _dbPath;
  Database? _db;

  SqliteIndexService({required Logger logger, required String dbPath})
    : _log = logger,
      _dbPath = dbPath;

  /// Получить открытую БД или бросить исключение.
  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError(
        'Index database is not initialized. Call initialize() first.',
      );
    }
    return db;
  }

  // ====================================================================
  // Indexer implementation
  // ====================================================================

  @override
  Future<void> initialize() async {
    if (_db != null) {
      _log.i('Index DB already initialized, skipping');
      return;
    }

    // Создаём директорию для БД если не существует
    final dir = Directory(p.dirname(_dbPath));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final db = sqlite3.open(_dbPath);

    // WAL mode для лучшей concurrent-производительности
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA foreign_keys=ON;');

    // Основная таблица с метаданными файлов
    db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        file_path TEXT UNIQUE NOT NULL,
        file_name TEXT NOT NULL,
        description TEXT DEFAULT '',
        text_content TEXT DEFAULT '',
        transcript_text TEXT DEFAULT '',
        indexed_at INTEGER NOT NULL
      );
    ''');

    // Миграция: добавляем колонку transcript_text если её нет (для существующих БД)
    final hasTranscriptCol =
        db
                .select(
                  "SELECT COUNT(*) as cnt FROM pragma_table_info('files') WHERE name='transcript_text'",
                )
                .first['cnt']
            as int;
    if (hasTranscriptCol == 0) {
      db.execute(
        "ALTER TABLE files ADD COLUMN transcript_text TEXT DEFAULT '';",
      );
      _log.i('Migrated: added transcript_text column to files table');
    }

    // FTS5 виртуальная таблица для полнотекстового поиска.
    // Миграция: если FTS-таблица существует, но без колонки transcript_text —
    // пересоздаём её (ALTER TABLE не поддерживается для виртуальных FTS5 таблиц).
    var ftsRecreated = false;
    final ftsExists =
        db
                .select(
                  "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='files_fts'",
                )
                .first['cnt']
            as int;
    if (ftsExists > 0) {
      // Проверяем наличие колонок transcript_text и tags в FTS-таблице
      // FTS5 не поддерживает pragma_table_info, поэтому пробуем SELECT
      try {
        db.execute('SELECT transcript_text, tags FROM files_fts LIMIT 0');
      } catch (_) {
        _log.i(
          'Migrating files_fts: adding transcript_text/tags columns (drop + recreate)',
        );
        db.execute('DROP TABLE files_fts;');
        ftsRecreated = true;
      }
    }

    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
        file_name,
        description,
        text_content,
        transcript_text,
        tags,
        content='files',
        content_rowid='id'
      );
    ''');

    // Триггеры для автоматической синхронизации FTS5
    // NOTE: DROP + CREATE для идемпотентной миграции (добавлена колонка transcript_text)
    db.execute('DROP TRIGGER IF EXISTS files_ai;');
    db.execute('''
      CREATE TRIGGER files_ai AFTER INSERT ON files BEGIN
        INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text, tags)
        VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text, new.tags);
      END;
    ''');

    db.execute('DROP TRIGGER IF EXISTS files_ad;');
    db.execute('''
      CREATE TRIGGER files_ad AFTER DELETE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text, tags)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text, old.tags);
      END;
    ''');

    db.execute('DROP TRIGGER IF EXISTS files_au;');
    db.execute('''
      CREATE TRIGGER files_au AFTER UPDATE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text, tags)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text, old.tags);
        INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text, tags)
        VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text, new.tags);
      END;
    ''');

    // Пересинхронизируем FTS с данными из files (нужно после пересоздания FTS-таблицы)
    if (ftsRecreated) {
      db.execute("INSERT INTO files_fts(files_fts) VALUES('rebuild')");
      _log.i('Rebuilt FTS index after migration');
    }

    // === Phase 3: Embeddings tables ===
    db.execute('''
      CREATE TABLE IF NOT EXISTS chunks (
        id INTEGER PRIMARY KEY,
        file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
        chunk_index INTEGER NOT NULL,
        chunk_text TEXT NOT NULL,
        chunk_offset INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS embeddings (
        id INTEGER PRIMARY KEY,
        chunk_id INTEGER NOT NULL UNIQUE REFERENCES chunks(id) ON DELETE CASCADE,
        embedding BLOB NOT NULL
      );
    ''');

    // Миграция: удаляем эмбеддинги, созданные stub (dim=64, blob=256 байт).
    // Настоящие ONNX-эмбеддинги имеют dim=384 (blob=1536 байт).
    // Это позволит ContentEnrichmentCoordinator пересчитать их реальной моделью.
    final wrongDimCount =
        db.select(
              'SELECT COUNT(*) as cnt FROM embeddings WHERE length(embedding) != ?',
              [_embeddingDimOnnx * 4], // 384 floats * 4 bytes
            ).first['cnt']
            as int;
    if (wrongDimCount > 0) {
      _log.i(
        'Purging $wrongDimCount embeddings with wrong dimension (stub migration)',
      );
      db.execute('DELETE FROM embeddings WHERE length(embedding) != ?', [
        _embeddingDimOnnx * 4,
      ]);
      // Также удаляем осиротевшие чанки
      db.execute(
        'DELETE FROM chunks WHERE id NOT IN (SELECT chunk_id FROM embeddings)',
      );
      _log.i(
        'Stub embeddings purged. Files will be re-embedded on next enrichment cycle.',
      );
    }

    // === Phase 4: Inbox (Требуют внимания) ===
    // Миграция: добавляем needs_review и tags колонки
    final hasNeedsReview =
        db
                .select(
                  "SELECT COUNT(*) as cnt FROM pragma_table_info('files') WHERE name='needs_review'",
                )
                .first['cnt']
            as int;
    if (hasNeedsReview == 0) {
      db.execute(
        "ALTER TABLE files ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0;",
      );
      _log.i('Migrated: added needs_review column to files table');
    }

    final hasTagsCol =
        db
                .select(
                  "SELECT COUNT(*) as cnt FROM pragma_table_info('files') WHERE name='tags'",
                )
                .first['cnt']
            as int;
    if (hasTagsCol == 0) {
      db.execute(
        "ALTER TABLE files ADD COLUMN tags TEXT DEFAULT '';",
      );
      _log.i('Migrated: added tags column to files table');
    }

    _db = db;
    _log.i('Index database initialized at: $_dbPath');
  }

  @override
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Извлекаем текстовое содержимое если файл текстовый.
      // Для форматов без прямого чтения (PDF, DOCX) вернётся null —
      // их текст устанавливается отдельно через updateTextContent (обогащение).
      final textContent = await _extractText(filePath);

      // UPSERT: вставляем или обновляем если файл уже есть.
      // При обновлении НЕ затираем text_content если extractor вернул null:
      // текст мог быть уже установлен обогащением (ContentEnrichmentCoordinator).
      if (textContent != null) {
        _database.execute(
          '''INSERT INTO files (file_path, file_name, description, text_content, indexed_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(file_path) DO UPDATE SET
                file_name = excluded.file_name,
                description = excluded.description,
                text_content = excluded.text_content,
                indexed_at = excluded.indexed_at''',
          [filePath, fileName, description, textContent, now],
        );
      } else {
        // Для форматов с внешним обогащением: обновляем только метаданные,
        // text_content оставляем нетронутым (ON CONFLICT не трогает его).
        _database.execute(
          '''INSERT INTO files (file_path, file_name, description, text_content, indexed_at)
             VALUES (?, ?, ?, '', ?)
             ON CONFLICT(file_path) DO UPDATE SET
                file_name = excluded.file_name,
                description = excluded.description,
                indexed_at = excluded.indexed_at''',
          [filePath, fileName, description, now],
        );
      }

      _log.d('Indexed file: $fileName (path=$filePath)');
      return true;
    } catch (e, st) {
      _log.e('Failed to index file: $filePath', error: e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    _database.execute('DELETE FROM files WHERE file_path = ?', [filePath]);
    _log.d('Removed from index: $filePath');
  }

  @override
  Future<void> clearIndex() async {
    _database.execute('DELETE FROM files;');
    _database.execute("INSERT INTO files_fts(files_fts) VALUES('rebuild');");
    _log.i('Index cleared');
  }

  @override
  Future<int> getIndexedCount() async {
    final result = _database.select('SELECT COUNT(*) FROM files');
    return result.first.columnAt(0) as int;
  }

  @override
  Future<bool> isIndexed(String filePath) async {
    final result = _database.select(
      'SELECT COUNT(*) FROM files WHERE file_path = ?',
      [filePath],
    );
    return (result.first.columnAt(0) as int) > 0;
  }

  @override
  Future<void> updateTextContent(String filePath, String textContent) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _database.execute(
      '''UPDATE files SET text_content = ?, indexed_at = ?
         WHERE file_path = ?''',
      [textContent, now, filePath],
    );
    _log.d('Updated text content for: $filePath (${textContent.length} chars)');
  }

  @override
  Future<void> updateTranscriptText(String filePath, String transcript) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _database.execute(
      '''UPDATE files SET transcript_text = ?, indexed_at = ?
         WHERE file_path = ?''',
      [transcript, now, filePath],
    );
    _log.d('Updated transcript for: $filePath (${transcript.length} chars)');
  }

  @override
  Future<String?> getTextContent(String filePath) async {
    final result = _database.select(
      'SELECT description, text_content, transcript_text, tags FROM files WHERE file_path = ? LIMIT 1',
      [filePath],
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final description = row['description'] as String?;
    final textContent = row['text_content'] as String?;
    final transcript = row['transcript_text'] as String?;
    final tags = row['tags'] as String?;

    final buffer = StringBuffer();
    if (description != null && description.isNotEmpty) {
      buffer.writeln(description);
    }
    if (tags != null && tags.isNotEmpty) {
      buffer.writeln(tags);
    }
    if (textContent != null && textContent.isNotEmpty) {
      buffer.writeln(textContent);
    }
    if (transcript != null && transcript.isNotEmpty) {
      buffer.writeln(transcript);
    }

    final fullText = buffer.toString().trim();
    if (fullText.isEmpty) {
      // Пытаемся fallback на чтение как текстовый файл для txt/md и т.д.
      try {
        final file = File(filePath);
        if (await file.exists()) {
          // Читаем только если файл небольшой (до 1МБ), чтобы не уронить память
          if (await file.length() < 1024 * 1024) {
            final content = await file.readAsString();
            return content.trim();
          }
        }
      } catch (_) {
        // Игнорируем ошибки чтения файлов
      }
      return null;
    }

    return fullText;
  }

  @override
  Future<void> updateDescription(String filePath, String description) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _database.execute(
      '''UPDATE files SET description = ?, indexed_at = ?
         WHERE file_path = ?''',
      [description, now, filePath],
    );
    _log.d('Updated description for: $filePath (${description.length} chars)');
  }

  @override
  Future<void> updateTags(String filePath, String tags) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _database.execute(
      '''UPDATE files SET tags = ?, indexed_at = ?
         WHERE file_path = ?''',
      [tags, now, filePath],
    );
    _log.d('Updated tags for: $filePath (tags=$tags)');
  }

  // ====================================================================
  // Indexer — Embeddings (Phase 3)
  // ====================================================================

  @override
  Future<void> storeEmbeddings(
    String filePath, {
    required List<String> chunkTexts,
    required List<int> chunkOffsets,
    required List<List<double>> embeddingVectors,
  }) async {
    assert(chunkTexts.length == embeddingVectors.length);
    assert(chunkTexts.length == chunkOffsets.length);

    // Найти file_id по filePath
    final rows = _database.select('SELECT id FROM files WHERE file_path = ?', [
      filePath,
    ]);
    if (rows.isEmpty) {
      _log.w('storeEmbeddings: file not indexed, skipping: $filePath');
      return;
    }
    final fileId = rows.first['id'] as int;

    // Удалить старые чанки/эмбеддинги (каскадно)
    _database.execute('DELETE FROM chunks WHERE file_id = ?', [fileId]);

    // Вставить чанки и эмбеддинги
    final insertChunk = _database.prepare(
      'INSERT INTO chunks (file_id, chunk_index, chunk_text, chunk_offset) VALUES (?, ?, ?, ?)',
    );
    final insertEmb = _database.prepare(
      'INSERT INTO embeddings (chunk_id, embedding) VALUES (?, ?)',
    );

    try {
      _database.execute('BEGIN TRANSACTION');
      for (var i = 0; i < chunkTexts.length; i++) {
        insertChunk.execute([fileId, i, chunkTexts[i], chunkOffsets[i]]);
        final chunkId = _database.lastInsertRowId;
        final blob = _embeddingToBlob(embeddingVectors[i]);
        insertEmb.execute([chunkId, blob]);
      }
      _database.execute('COMMIT');
      _log.d('Stored ${chunkTexts.length} chunk embeddings for: $filePath');
    } catch (e) {
      _database.execute('ROLLBACK');
      rethrow;
    } finally {
      insertChunk.dispose();
      insertEmb.dispose();
    }
  }

  @override
  Future<bool> hasEmbeddings(String filePath) async {
    final rows = _database.select(
      '''SELECT COUNT(*) as cnt FROM chunks c
         JOIN files f ON f.id = c.file_id
         WHERE f.file_path = ?''',
      [filePath],
    );
    return (rows.first['cnt'] as int) > 0;
  }

  // ====================================================================
  // Indexer — Inbox (Phase 4)
  // ====================================================================

  @override
  Future<bool> indexFileForReview(
    String filePath, {
    required String fileName,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final textContent = await _extractText(filePath);

      if (textContent != null) {
        _database.execute(
          '''INSERT INTO files (file_path, file_name, description, text_content, needs_review, indexed_at)
             VALUES (?, ?, '', ?, 1, ?)
             ON CONFLICT(file_path) DO UPDATE SET
                file_name = excluded.file_name,
                text_content = excluded.text_content,
                needs_review = 1,
                indexed_at = excluded.indexed_at''',
          [filePath, fileName, textContent, now],
        );
      } else {
        _database.execute(
          '''INSERT INTO files (file_path, file_name, description, text_content, needs_review, indexed_at)
             VALUES (?, ?, '', '', 1, ?)
             ON CONFLICT(file_path) DO UPDATE SET
                file_name = excluded.file_name,
                needs_review = 1,
                indexed_at = excluded.indexed_at''',
          [filePath, fileName, now],
        );
      }

      _log.d('Indexed file for review: $fileName (path=$filePath)');
      return true;
    } catch (e, st) {
      _log.e('Failed to index file for review: $filePath', error: e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<List<InboxFile>> getFilesNeedingReview() async {
    final rows = _database.select(
      '''SELECT file_path, file_name, description, tags, indexed_at
         FROM files
         WHERE needs_review = 1
         ORDER BY indexed_at DESC''',
    );
    return rows.map((row) {
      return InboxFile(
        filePath: row['file_path'] as String,
        fileName: row['file_name'] as String,
        description: (row['description'] as String?) ?? '',
        tags: (row['tags'] as String?) ?? '',
        indexedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['indexed_at'] as int) * 1000,
        ),
      );
    }).toList();
  }

  @override
  Future<int> getFilesNeedingReviewCount() async {
    final result = _database.select(
      'SELECT COUNT(*) FROM files WHERE needs_review = 1',
    );
    return result.first.columnAt(0) as int;
  }

  @override
  Future<void> saveFileReview(
    String filePath, {
    required String description,
    required String tags,
  }) async {
    _database.execute(
      '''UPDATE files SET description = ?, tags = ?, needs_review = 0
         WHERE file_path = ?''',
      [description, tags, filePath],
    );
    _log.i('Saved review for: $filePath (desc=${description.length} chars, tags=$tags)');
  }

  @override
  Future<void> markFileEnriched(String filePath) async {
    _database.execute(
      'UPDATE files SET needs_review = 0 WHERE file_path = ? AND needs_review = 1',
      [filePath],
    );
    _log.d('Marked file as enriched (cleared needs_review): $filePath');
  }

  /// Синхронизирует индекс с файловой системой.
  ///
  /// 1. Удаляет из индекса файлы, которых больше нет на диске.
  /// 2. Обнаруживает новые файлы в [watchDir], отсутствующие в индексе.
  ///
  /// Возвращает `SyncResult` со статистикой.
  /// Вызывать один раз при старте приложения (после initialize).
  Future<SyncResult> syncWithFilesystem(String watchDir) async {
    final stopwatch = Stopwatch()..start();
    var removedCount = 0;
    final newFiles = <Map<String, String>>[];

    try {
      // --- Шаг 1: удаляем из индекса файлы, которых нет на диске ---
      final indexed = _database.select(
        'SELECT file_path FROM files',
      );

      for (final row in indexed) {
        final filePath = row['file_path'] as String;
        if (!File(filePath).existsSync()) {
          _database.execute(
            'DELETE FROM files WHERE file_path = ?',
            [filePath],
          );
          removedCount++;
          _log.d('Sync: removed stale file from index: $filePath');
        }
      }

      // --- Шаг 2: ищем новые файлы в watch-директории ---
      final dir = Directory(watchDir);
      if (dir.existsSync()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final path = entity.path;
            final isIndexed = _database.select(
              'SELECT COUNT(*) as cnt FROM files WHERE file_path = ?',
              [path],
            );
            if ((isIndexed.first['cnt'] as int) == 0) {
              final fileName = p.basename(path);
              // Пропускаем desktop.ini и системные файлы
              if (fileName == 'desktop.ini') continue;
              newFiles.add({
                'filePath': path,
                'fileName': fileName,
              });
              _log.d('Sync: discovered new file: $fileName');
            }
          }
        }
      }

      stopwatch.stop();
      _log.i(
        'Filesystem sync completed in ${stopwatch.elapsedMilliseconds}ms: '
        'removed $removedCount stale, found ${newFiles.length} new',
      );
    } catch (e, st) {
      _log.e('Filesystem sync error', error: e, stackTrace: st);
    }

    return SyncResult(
      removedCount: removedCount,
      newFiles: newFiles,
    );
  }

  /// Возвращает список файлов (filePath, fileName), у которых нет эмбеддингов.
  ///
  /// Используется для пересчёта эмбеддингов после миграции stub → ONNX.
  List<Map<String, String>> getFilesWithoutEmbeddings() {
    final rows = _database.select(
      '''SELECT f.file_path, f.file_name FROM files f
         WHERE f.id NOT IN (
           SELECT DISTINCT c.file_id FROM chunks c
           JOIN embeddings e ON e.chunk_id = c.id
         )''',
    );
    return rows
        .map(
          (r) => {
            'filePath': r['file_path'] as String,
            'fileName': r['file_name'] as String,
          },
        )
        .toList();
  }

  // ====================================================================
  // SearchRepository implementation
  // ====================================================================

  @override
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final ftsQuery = _prepareFtsQuery(query);
    if (ftsQuery.isEmpty) {
      return [];
    }

    try {
      final rows = _database.select(
        '''SELECT
              f.file_path,
              f.file_name,
              f.description,
              snippet(files_fts, 2, '<b>', '</b>', '...', 32) as snippet,
              bm25(files_fts, 5.0, 10.0, 1.0, 1.0, 8.0) as rank,
              f.indexed_at
           FROM files_fts
           JOIN files f ON f.id = files_fts.rowid
           WHERE files_fts MATCH ?
           ORDER BY rank
           LIMIT ?''',
        [ftsQuery, limit],
      );

      return rows.map((row) {
        final rank = (row['rank'] as num).toDouble();
        // Нормализуем rank в 0.0-1.0 (BM25 возвращает отрицательные значения,
        // чем меньше — тем лучше)
        final relevance = (1.0 / (1.0 + rank.abs())).clamp(0.0, 1.0);

        return SearchResult(
          filePath: row['file_path'] as String,
          fileName: row['file_name'] as String,
          description: row['description'] as String,
          relevance: relevance,
          snippet: row['snippet'] as String?,
          indexedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['indexed_at'] as int) * 1000,
          ),
        );
      }).toList();
    } catch (e, st) {
      _log.e('Search failed for query: $query', error: e, stackTrace: st);
      return [];
    }
  }

  @override
  Future<IndexedFile?> getIndexedFile(String filePath) async {
    final rows = _database.select(
      '''SELECT file_path, file_name, indexed_at
         FROM files WHERE file_path = ?''',
      [filePath],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    // Получаем размер файла
    final file = File(filePath);
    final sizeBytes = file.existsSync() ? file.lengthSync() : 0;

    return IndexedFile(
      filePath: row['file_path'] as String,
      fileName: row['file_name'] as String,
      sizeBytes: sizeBytes,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['indexed_at'] as int) * 1000,
      ),
    );
  }

  @override
  Future<List<SearchResult>> semanticSearch(
    String query, {
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) return [];

    // Делегируем семантический поиск в Rust через FFI.
    // Rust использует тот же embedding-движок (ONNX или stub), что и при индексации,
    // гарантируя совместимость query-эмбеддинга и хранимых эмбеддингов.
    final results = _RustSemanticSearchFfi.instance.semanticSearch(
      _dbPath,
      query,
      limit,
    );
    if (results != null) {
      _log.d('Semantic search via Rust FFI: ${results.length} results');
      return results;
    }

    // Fallback: если Rust FFI недоступен — возвращаем пустой список
    // (Dart-side stub-эмбеддинги несовместимы с Rust-side, поэтому
    //  старый Dart-only поиск давал нулевые результаты.)
    _log.w('Rust FFI not available for semantic search, returning empty');
    return [];
  }

  @override
  Future<List<SearchResult>> findSimilarFiles(
    String filePath, {
    int limit = 10,
  }) async {
    // Делегируем поиск похожих файлов в Rust через FFI.
    final results = _RustSemanticSearchFfi.instance.findSimilarFiles(
      _dbPath,
      filePath,
      limit,
    );
    if (results != null) {
      _log.d('Find similar files via Rust FFI: ${results.length} results');
      return results;
    }

    _log.w('Rust FFI not available for findSimilarFiles, returning empty');
    return [];
  }

  // ====================================================================
  // Text extraction
  // ====================================================================

  /// Извлекает текстовое содержимое из файла если он текстовый.
  Future<String?> _extractText(String filePath) async {
    try {
      final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
      if (!_textExtensions.contains(ext)) return null;

      final file = File(filePath);
      if (!await file.exists()) return null;
      if (await file.length() > _maxTextFileSize) return null;

      return await file.readAsString();
    } catch (e) {
      _log.d('Failed to extract text from $filePath: $e');
      return null;
    }
  }

  // ====================================================================
  // FTS5 query preparation
  // ====================================================================

  /// Подготавливает пользовательский запрос для FTS5.
  ///
  /// - Разбивает на токены
  /// - Простой стемминг русских окончаний для поиска по корню слова
  /// - Добавляет `*` для prefix-match
  /// - Экранирует специальные символы FTS5
  String _prepareFtsQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((token) {
          // Убираем FTS5 спецсимволы, сохраняя Unicode-буквы и цифры
          // (\p{L} — любая буква, включая кириллицу; \p{N} — цифры)
          var clean = token.replaceAll(
            RegExp(r'[^\p{L}\p{N}_\-]', unicode: true),
            '',
          );
          if (clean.isEmpty) return '';
          // Простой стемминг для русского языка: отсекаем типичные окончания,
          // чтобы «папка», «папки», «папку» все превратились в «папк»
          // и prefix-match «папк*» нашёл все словоформы.
          clean = _stemRussian(clean);
          // Оборачиваем в кавычки и добавляем * для prefix-match
          return '"$clean"*';
        })
        .where((t) => t.isNotEmpty)
        .toList();

    return tokens.join(' ');
  }

  /// Минимальный стеммер для русского языка.
  ///
  /// Отсекает типичные падежные/числовые окончания существительных,
  /// прилагательных и глаголов, оставляя корень длиной ≥ 3 символа.
  /// Для латинских слов возвращает без изменений (FTS prefix-match
  /// и так хорошо работает для английского).
  static final _cyrillicRe = RegExp(r'[\u0400-\u04FF]');
  // Окончания отсортированы от длинных к коротким, чтобы самое длинное
  // совпадение сработало первым.
  static final _ruSuffixRe = RegExp(
    r'(ями|ого|его|ому|ему|ами|ыми|ими|ние|ний|ные|ный|ная|ное|ную|ной|ном|ных|ому|ях|ам|ом|ем|ей|ов|ые|ие|ую|юю|ой|им|ым|ах|а|я|о|е|и|ы|у|ю)$',
    caseSensitive: false,
  );

  static String _stemRussian(String word) {
    if (!_cyrillicRe.hasMatch(word)) return word;
    // Не трогаем слишком короткие слова (корень должен быть ≥ 3 символа)
    if (word.length <= 3) return word;
    final stemmed = word.replaceFirst(_ruSuffixRe, '');
    // Гарантируем минимальную длину корня
    if (stemmed.length < 3) return word;
    return stemmed;
  }

  // ====================================================================
  // Embedding helpers
  // ====================================================================

  /// Конвертирует вектор эмбеддинга в BLOB (little-endian f32).
  Uint8List _embeddingToBlob(List<double> embedding) {
    final bytes = ByteData(embedding.length * 4);
    for (var i = 0; i < embedding.length; i++) {
      bytes.setFloat32(i * 4, embedding[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// Конвертирует BLOB обратно в вектор эмбеддинга.
  List<double> _blobToEmbedding(Uint8List blob) {
    final bytes = ByteData.sublistView(blob);
    final dim = blob.length ~/ 4;
    return List<double>.generate(
      dim,
      (i) => bytes.getFloat32(i * 4, Endian.little),
    );
  }

  /// Косинусное сходство между двумя векторами.
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0.0) return 0.0;
    return dot / denom;
  }

  /// Среднее нескольких векторов.
  List<double> _averageVectors(List<List<double>> vectors) {
    if (vectors.isEmpty) return List.filled(_embeddingDimStub, 0.0);
    final dim = vectors.first.length;
    final avg = List.filled(dim, 0.0);
    for (final v in vectors) {
      for (var i = 0; i < dim; i++) {
        avg[i] += v[i];
      }
    }
    for (var i = 0; i < dim; i++) {
      avg[i] /= vectors.length;
    }
    return avg;
  }

  /// Stub: детерминированный эмбеддинг по хешу текста.
  ///
  /// Используется только до подключения реального inference (Rust core).
  List<double> _stubComputeEmbedding(String text) {
    final hash = text.hashCode;
    final rng = Random(hash);
    final vec = List<double>.generate(
      _embeddingDimStub,
      (_) => rng.nextDouble() * 2 - 1,
    );
    // L2-normalize
    var norm = 0.0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < vec.length; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }

  /// Обрезает текст до maxLen символов.
  String _truncateSnippet(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  // ====================================================================
  // Dispose
  // ====================================================================

  @override
  void dispose() {
    _db?.dispose();
    _db = null;
    _log.i('Index database closed');
  }
}

/// Результат синхронизации индекса с файловой системой.
class SyncResult {
  /// Количество удалённых из индекса файлов (не найдены на диске).
  final int removedCount;

  /// Новые файлы, обнаруженные в watch-папке, но отсутствующие в индексе.
  /// Каждый элемент содержит 'filePath' и 'fileName'.
  final List<Map<String, String>> newFiles;

  const SyncResult({
    required this.removedCount,
    required this.newFiles,
  });
}

// ======================================================================
// FFI вызов Rust для семантического поиска
// ======================================================================

// FFI type definitions — каждая функция принимает db_path первым аргументом
typedef _SemanticSearchC =
    Pointer<Utf8> Function(
      Pointer<Utf8> dbPathPtr,
      Pointer<Utf8> queryPtr,
      Uint32 topK,
    );
typedef _SemanticSearchDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> dbPathPtr,
      Pointer<Utf8> queryPtr,
      int topK,
    );

typedef _FindSimilarFilesC =
    Pointer<Utf8> Function(
      Pointer<Utf8> dbPathPtr,
      Pointer<Utf8> filePathPtr,
      Uint32 topK,
    );
typedef _FindSimilarFilesDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> dbPathPtr,
      Pointer<Utf8> filePathPtr,
      int topK,
    );

typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Singleton обёртка для FFI вызовов семантического поиска в Rust.
///
/// Использует тот же DLL что и OCR (latera_rust.dll).
/// Каждый вызов передаёт путь к БД — Rust открывает read-only соединение.
/// Если DLL не найден — возвращает null, вызывающий код использует fallback.
class _RustSemanticSearchFfi {
  static final _RustSemanticSearchFfi instance = _RustSemanticSearchFfi._();
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _SemanticSearchDart? _semanticSearchFfi;
  _FindSimilarFilesDart? _findSimilarFilesFfi;
  _FreeCStringDart? _freeCStringFfi;
  bool _initialized = false;
  bool _available = false;

  _RustSemanticSearchFfi._();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('Semantic search FFI: resolveLibraryPath() returned null');
      _available = false;
      return;
    }

    _log.d('Semantic search FFI: loading from $libPath');

    try {
      final lib = DynamicLibrary.open(libPath);

      _semanticSearchFfi = lib
          .lookupFunction<_SemanticSearchC, _SemanticSearchDart>(
            'latera_semantic_search',
          );
      _findSimilarFilesFfi = lib
          .lookupFunction<_FindSimilarFilesC, _FindSimilarFilesDart>(
            'latera_find_similar_files',
          );
      _freeCStringFfi = lib.lookupFunction<_FreeCStringC, _FreeCStringDart>(
        'latera_free_cstring',
      );

      _available = true;
      _log.i('Semantic search FFI: loaded successfully');
    } catch (e) {
      _log.e('Semantic search FFI: failed to load functions from $libPath: $e');
      _available = false;
    }
  }

  /// Семантический поиск через Rust FFI.
  ///
  /// [dbPath] — путь к SQLite БД индекса.
  /// Возвращает null если FFI недоступен.
  List<SearchResult>? semanticSearch(String dbPath, String query, int limit) {
    _ensureInitialized();
    if (!_available) return null;

    final dbPathPtr = dbPath.toNativeUtf8();
    final queryPtr = query.toNativeUtf8();
    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);
    try {
      resultPtr = _semanticSearchFfi!(dbPathPtr, queryPtr, limit);
      if (resultPtr.address == 0) return [];
      final jsonStr = resultPtr.toDartString();
      return _parseResults(jsonStr);
    } finally {
      calloc.free(dbPathPtr);
      calloc.free(queryPtr);
      if (resultPtr.address != 0) {
        _freeCStringFfi!(resultPtr);
      }
    }
  }

  /// Поиск похожих файлов через Rust FFI.
  ///
  /// [dbPath] — путь к SQLite БД индекса.
  /// Возвращает null если FFI недоступен.
  List<SearchResult>? findSimilarFiles(
    String dbPath,
    String filePath,
    int limit,
  ) {
    _ensureInitialized();
    if (!_available) return null;

    final dbPathPtr = dbPath.toNativeUtf8();
    final filePathPtr = filePath.toNativeUtf8();
    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);
    try {
      resultPtr = _findSimilarFilesFfi!(dbPathPtr, filePathPtr, limit);
      if (resultPtr.address == 0) return [];
      final jsonStr = resultPtr.toDartString();
      return _parseResults(jsonStr);
    } finally {
      calloc.free(dbPathPtr);
      calloc.free(filePathPtr);
      if (resultPtr.address != 0) {
        _freeCStringFfi!(resultPtr);
      }
    }
  }

  /// Парсит JSON массив результатов из Rust.
  static List<SearchResult> _parseResults(String jsonStr) {
    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return SearchResult(
          filePath: (map['file_path'] as String?) ?? '',
          fileName: (map['file_name'] as String?) ?? '',
          description: '', // Rust similarity_search не возвращает description
          relevance: ((map['score'] as num?) ?? 0.0).toDouble().clamp(0.0, 1.0),
          snippet: map['chunk_snippet'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

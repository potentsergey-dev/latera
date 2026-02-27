import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../domain/indexer.dart';
import '../../domain/search_repository.dart';

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

  SqliteIndexService({
    required Logger logger,
    required String dbPath,
  })  : _log = logger,
        _dbPath = dbPath;

  /// Получить открытую БД или бросить исключение.
  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('Index database is not initialized. Call initialize() first.');
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
        indexed_at INTEGER NOT NULL
      );
    ''');

    // FTS5 виртуальная таблица для полнотекстового поиска
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
        file_name,
        description,
        text_content,
        content='files',
        content_rowid='id'
      );
    ''');

    // Триггеры для автоматической синхронизации FTS5
    db.execute('''
      CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
        INSERT INTO files_fts(rowid, file_name, description, text_content)
        VALUES (new.id, new.file_name, new.description, new.text_content);
      END;
    ''');

    db.execute('''
      CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content);
      END;
    ''');

    db.execute('''
      CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content);
        INSERT INTO files_fts(rowid, file_name, description, text_content)
        VALUES (new.id, new.file_name, new.description, new.text_content);
      END;
    ''');

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

      // Извлекаем текстовое содержимое если файл текстовый
      final textContent = await _extractText(filePath);

      // UPSERT: вставляем или обновляем если файл уже есть
      _database.execute(
        '''INSERT INTO files (file_path, file_name, description, text_content, indexed_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(file_path) DO UPDATE SET
              file_name = excluded.file_name,
              description = excluded.description,
              text_content = excluded.text_content,
              indexed_at = excluded.indexed_at''',
        [filePath, fileName, description, textContent ?? '', now],
      );

      _log.d('Indexed file: $fileName (path=$filePath)');
      return true;
    } catch (e, st) {
      _log.e('Failed to index file: $filePath', error: e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    _database.execute(
      'DELETE FROM files WHERE file_path = ?',
      [filePath],
    );
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
              bm25(files_fts, 5.0, 10.0, 1.0) as rank,
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
  /// - Добавляет `*` для prefix-match
  /// - Экранирует специальные символы FTS5
  String _prepareFtsQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((token) {
          // Убираем FTS5 спецсимволы, сохраняя Unicode-буквы и цифры
          // (\p{L} — любая буква, включая кириллицу; \p{N} — цифры)
          final clean = token.replaceAll(
            RegExp(r'[^\p{L}\p{N}_\-]', unicode: true),
            '',
          );
          if (clean.isEmpty) return '';
          // Оборачиваем в кавычки и добавляем * для prefix-match
          return '"$clean"*';
        })
        .where((t) => t.isNotEmpty)
        .toList();

    return tokens.join(' ');
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

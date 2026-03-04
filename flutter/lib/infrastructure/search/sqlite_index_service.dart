import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
        transcript_text TEXT DEFAULT '',
        indexed_at INTEGER NOT NULL
      );
    ''');

    // Миграция: добавляем колонку transcript_text если её нет (для существующих БД)
    final hasTranscriptCol = db
        .select("SELECT COUNT(*) as cnt FROM pragma_table_info('files') WHERE name='transcript_text'")
        .first['cnt'] as int;
    if (hasTranscriptCol == 0) {
      db.execute("ALTER TABLE files ADD COLUMN transcript_text TEXT DEFAULT '';");
      _log.i('Migrated: added transcript_text column to files table');
    }

    // FTS5 виртуальная таблица для полнотекстового поиска.
    // Миграция: если FTS-таблица существует, но без колонки transcript_text —
    // пересоздаём её (ALTER TABLE не поддерживается для виртуальных FTS5 таблиц).
    var ftsRecreated = false;
    final ftsExists = db
        .select("SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='files_fts'")
        .first['cnt'] as int;
    if (ftsExists > 0) {
      // Проверяем наличие колонки transcript_text в FTS-таблице
      // FTS5 не поддерживает pragma_table_info, поэтому пробуем SELECT
      try {
        db.execute('SELECT transcript_text FROM files_fts LIMIT 0');
      } catch (_) {
        _log.i('Migrating files_fts: adding transcript_text column (drop + recreate)');
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
        content='files',
        content_rowid='id'
      );
    ''');

    // Триггеры для автоматической синхронизации FTS5
    // NOTE: DROP + CREATE для идемпотентной миграции (добавлена колонка transcript_text)
    db.execute('DROP TRIGGER IF EXISTS files_ai;');
    db.execute('''
      CREATE TRIGGER files_ai AFTER INSERT ON files BEGIN
        INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text)
        VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text);
      END;
    ''');

    db.execute('DROP TRIGGER IF EXISTS files_ad;');
    db.execute('''
      CREATE TRIGGER files_ad AFTER DELETE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text);
      END;
    ''');

    db.execute('DROP TRIGGER IF EXISTS files_au;');
    db.execute('''
      CREATE TRIGGER files_au AFTER UPDATE ON files BEGIN
        INSERT INTO files_fts(files_fts, rowid, file_name, description, text_content, transcript_text)
        VALUES('delete', old.id, old.file_name, old.description, old.text_content, old.transcript_text);
        INSERT INTO files_fts(rowid, file_name, description, text_content, transcript_text)
        VALUES (new.id, new.file_name, new.description, new.text_content, new.transcript_text);
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
    final rows = _database.select(
      'SELECT id FROM files WHERE file_path = ?',
      [filePath],
    );
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
              bm25(files_fts, 5.0, 10.0, 1.0, 1.0) as rank,
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
  Future<List<SearchResult>> semanticSearch(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    // Для семантического поиска нужно: 1) вычислить эмбеддинг запроса,
    // 2) сравнить с хранимыми. Пока используем linear scan.
    // NOTE: Подключить реальные эмбеддинги через EmbeddingService (Phase 3+).

    // Загружаем все эмбеддинги с метаданными
    final rows = _database.select('''
      SELECT
        e.embedding,
        c.chunk_text,
        f.file_path,
        f.file_name,
        f.description,
        f.indexed_at
      FROM embeddings e
      JOIN chunks c ON c.id = e.chunk_id
      JOIN files f ON f.id = c.file_id
    ''');

    if (rows.isEmpty) return [];

    // Stub: вычисляем эмбеддинг запроса детерминированно (hash-based)
    final queryEmbedding = _stubComputeEmbedding(query);

    // Считаем cosine similarity для каждого чанка
    final scored = <_ScoredResult>[];
    for (final row in rows) {
      final blob = row['embedding'] as Uint8List;
      final chunkEmb = _blobToEmbedding(blob);
      final sim = _cosineSimilarity(queryEmbedding, chunkEmb);

      scored.add(_ScoredResult(
        filePath: row['file_path'] as String,
        fileName: row['file_name'] as String,
        description: row['description'] as String,
        snippet: _truncateSnippet(row['chunk_text'] as String, 200),
        similarity: sim,
        indexedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['indexed_at'] as int) * 1000,
        ),
      ));
    }

    // Сортируем по similarity DESC, дедуплицируем по file_path (лучший чанк)
    scored.sort((a, b) => b.similarity.compareTo(a.similarity));
    final seen = <String>{};
    final results = <SearchResult>[];
    for (final s in scored) {
      if (seen.contains(s.filePath)) continue;
      seen.add(s.filePath);
      results.add(SearchResult(
        filePath: s.filePath,
        fileName: s.fileName,
        description: s.description,
        relevance: s.similarity.clamp(0.0, 1.0),
        snippet: s.snippet,
        indexedAt: s.indexedAt,
      ));
      if (results.length >= limit) break;
    }

    return results;
  }

  @override
  Future<List<SearchResult>> findSimilarFiles(String filePath, {int limit = 10}) async {
    // Получаем эмбеддинги файла-источника
    final sourceRows = _database.select('''
      SELECT e.embedding
      FROM embeddings e
      JOIN chunks c ON c.id = e.chunk_id
      JOIN files f ON f.id = c.file_id
      WHERE f.file_path = ?
    ''', [filePath]);

    if (sourceRows.isEmpty) return [];

    // Среднее по всем чанкам файла
    final sourceEmbeddings = sourceRows
        .map((r) => _blobToEmbedding(r['embedding'] as Uint8List))
        .toList();
    final avgSource = _averageVectors(sourceEmbeddings);

    // Загружаем эмбеддинги всех остальных файлов
    final allRows = _database.select('''
      SELECT
        e.embedding,
        c.chunk_text,
        f.file_path,
        f.file_name,
        f.description,
        f.indexed_at
      FROM embeddings e
      JOIN chunks c ON c.id = e.chunk_id
      JOIN files f ON f.id = c.file_id
      WHERE f.file_path != ?
    ''', [filePath]);

    if (allRows.isEmpty) return [];

    // Группируем чанки по файлу, считаем среднее и similarity
    final fileChunks = <String, List<List<double>>>{};
    final fileMeta = <String, _ScoredResult>{};

    for (final row in allRows) {
      final fp = row['file_path'] as String;
      final emb = _blobToEmbedding(row['embedding'] as Uint8List);
      fileChunks.putIfAbsent(fp, () => []).add(emb);
      fileMeta.putIfAbsent(
        fp,
        () => _ScoredResult(
          filePath: fp,
          fileName: row['file_name'] as String,
          description: row['description'] as String,
          snippet: _truncateSnippet(row['chunk_text'] as String, 200),
          similarity: 0,
          indexedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['indexed_at'] as int) * 1000,
          ),
        ),
      );
    }

    final scored = <_ScoredResult>[];
    for (final entry in fileChunks.entries) {
      final avg = _averageVectors(entry.value);
      final sim = _cosineSimilarity(avgSource, avg);
      final meta = fileMeta[entry.key]!;
      scored.add(_ScoredResult(
        filePath: meta.filePath,
        fileName: meta.fileName,
        description: meta.description,
        snippet: meta.snippet,
        similarity: sim,
        indexedAt: meta.indexedAt,
      ));
    }

    scored.sort((a, b) => b.similarity.compareTo(a.similarity));

    return scored.take(limit).map((s) => SearchResult(
      filePath: s.filePath,
      fileName: s.fileName,
      description: s.description,
      relevance: s.similarity.clamp(0.0, 1.0),
      snippet: s.snippet,
      indexedAt: s.indexedAt,
    )).toList();
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
    final vec = List<double>.generate(_embeddingDimStub, (_) => rng.nextDouble() * 2 - 1);
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

/// Внутренний класс для промежуточного ранжирования результатов.
class _ScoredResult {
  final String filePath;
  final String fileName;
  final String description;
  final String? snippet;
  final double similarity;
  final DateTime? indexedAt;

  const _ScoredResult({
    required this.filePath,
    required this.fileName,
    required this.description,
    this.snippet,
    required this.similarity,
    this.indexedAt,
  });
}

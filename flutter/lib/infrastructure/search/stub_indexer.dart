import 'package:logger/logger.dart';

import '../../domain/indexer.dart';

/// Заглушка индексатора.
///
/// Это безопасная `no-op` реализация, чтобы проект компилировался без SQLite.
///
/// После подключения SQLite/FTS5 этот класс будет заменён на реализацию,
/// выполняющую реальную индексацию файлов.
class StubIndexer implements Indexer {
  final Logger _log;

  StubIndexer({required Logger logger}) : _log = logger;

  @override
  Future<void> initialize() async {
    _log.w('SQLite is not connected yet. initialize() ignored.');
  }

  @override
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  }) async {
    _log.w(
      'SQLite is not connected yet. indexFile(filePath=$filePath) ignored.',
    );
    return false;
  }

  @override
  Future<void> removeFromIndex(String filePath) async {
    _log.w(
      'SQLite is not connected yet. removeFromIndex(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<void> clearIndex() async {
    _log.w('SQLite is not connected yet. clearIndex() ignored.');
  }

  @override
  Future<int> getIndexedCount() async {
    _log.w('SQLite is not connected yet. getIndexedCount() returning 0.');
    return 0;
  }

  @override
  Future<bool> isIndexed(String filePath) async {
    _log.w(
      'SQLite is not connected yet. isIndexed(filePath=$filePath) returning false.',
    );
    return false;
  }

  @override
  Future<void> updateTextContent(String filePath, String textContent) async {
    _log.w(
      'SQLite is not connected yet. updateTextContent(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<void> updateTranscriptText(String filePath, String transcript) async {
    _log.w(
      'SQLite is not connected yet. updateTranscriptText(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<String?> getTextContent(String filePath) async {
    return null;
  }

  @override
  Future<void> storeEmbeddings(
    String filePath, {
    required List<String> chunkTexts,
    required List<int> chunkOffsets,
    required List<List<double>> embeddingVectors,
  }) async {
    _log.w(
      'SQLite is not connected yet. storeEmbeddings(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<bool> hasEmbeddings(String filePath) async {
    _log.w(
      'SQLite is not connected yet. hasEmbeddings(filePath=$filePath) returning false.',
    );
    return false;
  }

  @override
  Future<bool> indexFileForReview(
    String filePath, {
    required String fileName,
  }) async {
    _log.w(
      'SQLite is not connected yet. indexFileForReview(filePath=$filePath) ignored.',
    );
    return false;
  }

  @override
  Future<List<InboxFile>> getFilesNeedingReview() async {
    return [];
  }

  @override
  Future<int> getFilesNeedingReviewCount() async {
    return 0;
  }

  @override
  Future<void> saveFileReview(
    String filePath, {
    required String description,
    required String tags,
  }) async {
    _log.w(
      'SQLite is not connected yet. saveFileReview(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<void> markFileEnriched(String filePath) async {
    _log.w(
      'SQLite is not connected yet. markFileEnriched(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<void> updateDescription(String filePath, String description) async {
    _log.w(
      'SQLite is not connected yet. updateDescription(filePath=$filePath) ignored.',
    );
  }

  @override
  Future<void> updateTags(String filePath, String tags) async {
    _log.w(
      'SQLite is not connected yet. updateTags(filePath=$filePath) ignored.',
    );
  }

  @override
  void dispose() {
    // No-op
  }
}

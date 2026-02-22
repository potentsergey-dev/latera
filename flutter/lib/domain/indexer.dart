/// Контракт на индексатор файлов.
///
/// Domain слой не зависит от реализации хранения (SQLite, FTS5 и т.д.).
/// Отвечает за индексацию файлов для последующего поиска.
abstract interface class Indexer {
  /// Индексирует один файл по указанному пути.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// Возвращает true, если индексация прошла успешно.
  Future<bool> indexFile(String filePath);

  /// Удаляет файл из индекса.
  ///
  /// [filePath] — абсолютный путь к файлу.
  Future<void> removeFromIndex(String filePath);

  /// Очищает весь индекс.
  Future<void> clearIndex();

  /// Возвращает количество проиндексированных файлов.
  Future<int> getIndexedCount();
}

/// Результат операции индексации.
class IndexResult {
  final bool success;
  final String? error;
  final String filePath;

  const IndexResult({
    required this.success,
    required this.filePath,
    this.error,
  });
}

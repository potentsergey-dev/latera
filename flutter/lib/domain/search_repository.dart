/// Результат поиска файла.
class SearchResult {
  /// Абсолютный путь к файлу.
  final String filePath;

  /// Имя файла.
  final String fileName;

  /// Релевантность результата (0.0 - 1.0).
  final double relevance;

  /// Фрагмент содержимого с совпадением (опционально).
  final String? snippet;

  /// Дата последней модификации файла в индексе.
  final DateTime? indexedAt;

  const SearchResult({
    required this.filePath,
    required this.fileName,
    required this.relevance,
    this.snippet,
    this.indexedAt,
  });
}

/// Информация о проиндексированном файле.
class IndexedFile {
  /// Абсолютный путь к файлу.
  final String filePath;

  /// Имя файла.
  final String fileName;

  /// Размер файла в байтах.
  final int sizeBytes;

  /// Дата добавления в индекс.
  final DateTime indexedAt;

  /// Дата последней модификации файла (на момент индексации).
  final DateTime? modifiedAt;

  const IndexedFile({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.indexedAt,
    this.modifiedAt,
  });
}

/// Контракт на репозиторий поиска.
///
/// Domain слой не зависит от реализации хранения (SQLite, FTS5 и т.д.).
/// Отвечает за поиск файлов по индексу.
abstract interface class SearchRepository {
  /// Выполняет поиск файлов по запросу.
  ///
  /// [query] — поисковый запрос.
  /// [limit] — максимальное количество результатов (по умолчанию 50).
  /// Возвращает список найденных файлов.
  Future<List<SearchResult>> search(String query, {int limit = 50});

  /// Проверяет, проиндексирован ли файл.
  ///
  /// [filePath] — абсолютный путь к файлу.
  Future<bool> isIndexed(String filePath);

  /// Возвращает информацию о проиндексированном файле.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// Возвращает null, если файл не найден в индексе.
  Future<IndexedFile?> getIndexedFile(String filePath);
}

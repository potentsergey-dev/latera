/// Контракт на индексатор файлов.
///
/// Domain слой не зависит от реализации хранения (SQLite, FTS5 и т.д.).
/// Отвечает за индексацию файлов для последующего поиска.
abstract interface class Indexer {
  /// Инициализирует индекс (создаёт БД, таблицы и т.д.).
  ///
  /// Должен быть вызван один раз при старте приложения.
  Future<void> initialize();

  /// Индексирует один файл с описанием пользователя.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [fileName] — имя файла.
  /// [description] — описание от пользователя (основа для поиска).
  /// Возвращает true, если индексация прошла успешно.
  Future<bool> indexFile(
    String filePath, {
    required String fileName,
    required String description,
  });

  /// Удаляет файл из индекса.
  ///
  /// [filePath] — абсолютный путь к файлу.
  Future<void> removeFromIndex(String filePath);

  /// Очищает весь индекс.
  Future<void> clearIndex();

  /// Возвращает количество проиндексированных файлов.
  Future<int> getIndexedCount();

  /// Проверяет, проиндексирован ли файл.
  Future<bool> isIndexed(String filePath);

  /// Освобождает ресурсы (закрывает БД).
  void dispose();
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

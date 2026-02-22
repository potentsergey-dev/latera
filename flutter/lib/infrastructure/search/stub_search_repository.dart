import 'package:logger/logger.dart';

import '../../domain/search_repository.dart';

/// Заглушка репозитория поиска.
///
/// Это безопасная `no-op` реализация, чтобы проект компилировался без SQLite.
///
/// После подключения SQLite/FTS5 этот класс будет заменён на реализацию,
/// выполняющую реальный полнотекстовый поиск.
class StubSearchRepository implements SearchRepository {
  final Logger _log;

  StubSearchRepository({required Logger logger}) : _log = logger;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    _log.w(
      'SQLite is not connected yet. search(query=$query, limit=$limit) returning empty list.',
    );
    return [];
  }

  @override
  Future<bool> isIndexed(String filePath) async {
    _log.w(
      'SQLite is not connected yet. isIndexed(filePath=$filePath) returning false.',
    );
    return false;
  }

  @override
  Future<IndexedFile?> getIndexedFile(String filePath) async {
    _log.w(
      'SQLite is not connected yet. getIndexedFile(filePath=$filePath) returning null.',
    );
    return null;
  }
}

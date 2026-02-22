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
  Future<bool> indexFile(String filePath) async {
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
}

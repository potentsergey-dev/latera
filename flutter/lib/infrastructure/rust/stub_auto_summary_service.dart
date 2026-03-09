import '../../domain/auto_summary.dart';

/// Stub-реализация [AutoSummaryService].
///
/// Возвращает пустой результат для всех файлов.
/// Используется до подключения Rust FRB bindings с LLM-моделью.
///
/// После генерации bindings заменяется на `RustAutoSummaryService`,
/// который вызывает `api::generate_summary` через FRB.
class StubAutoSummaryService implements AutoSummaryService {
  @override
  Future<AutoSummaryResult> generateSummary(
    String textContent, {
    required String fileName,
  }) async {
    if (textContent.trim().isEmpty) {
      return const AutoSummaryResult(
        summary: '',
        errorCode: 'empty_content',
      );
    }

    return const AutoSummaryResult(
      summary: '',
      errorCode: 'not_implemented',
    );
  }
}

import '../../domain/rag.dart';

/// Stub-реализация [RagService].
///
/// Возвращает пустые результаты для всех запросов.
/// Используется до подключения Rust FRB bindings (codegen).
///
/// После генерации bindings заменяется на `RustRagService`,
/// который вызывает `api::rag_query` через FRB.
class StubRagService implements RagService {
  @override
  Future<RagQueryResult> query(
    String question, {
    int topK = 5,
  }) async {
    if (question.trim().isEmpty) {
      return const RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'empty_question',
      );
    }

    // Stub: RAG не реализован, возвращаем «не найдено»
    return const RagQueryResult(
      answer: '',
      sources: [],
      errorCode: 'not_implemented',
    );
  }
}

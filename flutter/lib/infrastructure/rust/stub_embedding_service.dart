import '../../domain/embeddings.dart';

/// Stub-реализация [EmbeddingService].
///
/// Возвращает пустые результаты для всех операций.
/// Используется до подключения Rust FRB bindings (codegen).
///
/// После генерации bindings заменяется на `RustEmbeddingService`,
/// который вызывает `api::compute_embeddings` / `api::similarity_search`
/// через FRB.
class StubEmbeddingService implements EmbeddingService {
  @override
  List<TextChunk> chunkText(
    String text, {
    int chunkSize = 500,
    int chunkOverlap = 50,
  }) {
    if (text.isEmpty) return [];

    final chunks = <TextChunk>[];
    final effectiveChunkSize = chunkSize.clamp(1, text.length);
    final effectiveOverlap = chunkOverlap.clamp(0, effectiveChunkSize - 1);
    var start = 0;
    var index = 0;

    while (start < text.length) {
      final end =
          (start + effectiveChunkSize).clamp(0, text.length);
      chunks.add(TextChunk(
        text: text.substring(start, end),
        chunkIndex: index,
        chunkOffset: start,
      ));
      index++;
      final step = effectiveChunkSize - effectiveOverlap;
      if (step <= 0) break;
      start += step;
    }

    return chunks;
  }

  @override
  Future<List<EmbeddingVector>> computeEmbeddings(
    List<TextChunk> chunks,
  ) async {
    // Stub: возвращает нулевые векторы
    return chunks
        .map((c) => EmbeddingVector(
              chunkIndex: c.chunkIndex,
              vector: List.filled(64, 0.0),
            ))
        .toList();
  }

  @override
  Future<List<SimilarityResult>> similaritySearch(
    String query, {
    int topK = 5,
  }) async {
    // Stub: семантический поиск не реализован
    return [];
  }

  @override
  Future<List<SimilarityResult>> findSimilarFiles(
    String filePath, {
    int topK = 5,
  }) async {
    // Stub: поиск похожих файлов не реализован
    return [];
  }

  @override
  Future<bool> hasEmbeddings(String filePath) async {
    return false;
  }
}

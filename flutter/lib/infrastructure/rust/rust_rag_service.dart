import 'package:logger/logger.dart';

import '../../domain/rag.dart' as domain;
import 'generated/api.dart' as rust_api;

/// Реализация [domain.RagService], использующая Rust core через FRB.
class RustRagService implements domain.RagService {
  final Logger _logger;

  RustRagService({Logger? logger}) : _logger = logger ?? Logger();

  @override
  Future<domain.RagQueryResult> query(
    String question, {
    int topK = 5,
  }) async {
    if (question.trim().isEmpty) {
      return const domain.RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'empty_question',
      );
    }

    try {
      final result = await rust_api.ragQuery(
        question: question,
        topK: topK,
      );

      return domain.RagQueryResult(
        answer: result.answer,
        errorCode: result.errorCode,
        sources: result.sources
            .map((s) => domain.RagSource(
                  filePath: s.filePath,
                  chunkSnippet: s.chunkSnippet,
                  chunkOffset: s.chunkOffset,
                ))
            .toList(),
      );
    } catch (e, st) {
      _logger.e('FRB RAG query failed', error: e, stackTrace: st);
      return const domain.RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'query_failed',
      );
    }
  }
}

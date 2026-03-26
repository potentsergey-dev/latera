import '../../domain/auto_tags.dart';

/// Stub-реализация [AutoTagsService].
///
/// Возвращает пустой результат для всех файлов.
/// Используется до подключения Rust FRB bindings с LLM-моделью.
///
/// После генерации bindings заменяется на `RustAutoTagsService`,
/// который вызывает `api::generate_tags` через FRB.
class StubAutoTagsService implements AutoTagsService {
  @override
  Future<AutoTagsResult> generateTags(
    String textContent, {
    required String fileName,
  }) async {
    if (textContent.trim().isEmpty) {
      return const AutoTagsResult(
        tags: [],
        errorCode: 'empty_content',
      );
    }

    return const AutoTagsResult(
      tags: [],
      errorCode: 'not_implemented',
    );
  }
}

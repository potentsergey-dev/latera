import '../../domain/text_extraction.dart';

/// Stub-реализация [RichTextExtractor].
///
/// Возвращает пустой результат для всех файлов.
/// Используется до подключения Rust FRB bindings (codegen).
///
/// После генерации bindings заменяется на `RustRichTextExtractor`,
/// который вызывает `api::extract_text_from_file` через FRB.
class StubRichTextExtractor implements RichTextExtractor {
  @override
  Future<ExtractionResult> extractText(
    String filePath,
    ExtractionOptions options,
  ) async {
    return const ExtractionResult(
      text: '',
      contentType: 'unsupported',
      pagesExtracted: 0,
      errorCode: 'not_implemented',
    );
  }
}

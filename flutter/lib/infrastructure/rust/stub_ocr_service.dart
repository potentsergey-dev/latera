import '../../domain/ocr.dart';

/// Stub-реализация [OcrService].
///
/// Возвращает `not_implemented` для всех файлов.
/// Используется до подключения Rust FRB bindings (codegen).
///
/// После генерации bindings заменяется на `RustOcrService`,
/// который вызывает `api::ocr_extract_text` через FRB.
class StubOcrService implements OcrService {
  @override
  Future<OcrResult> extractText(
    String filePath,
    OcrOptions options,
  ) async {
    return const OcrResult(
      text: '',
      contentType: 'unsupported',
      pagesProcessed: 0,
      errorCode: 'not_implemented',
    );
  }

  @override
  bool isSupported(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return const {'png', 'jpg', 'jpeg', 'tiff', 'tif', 'bmp', 'webp', 'pdf'}
        .contains(ext);
  }
}

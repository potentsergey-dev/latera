import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/ocr.dart';

void main() {
  group('OcrOptions', () {
    test('constructs with required parameters', () {
      const options = OcrOptions(
        maxPagesPerPdf: 50,
        maxFileSizeMb: 25,
      );

      expect(options.maxPagesPerPdf, 50);
      expect(options.maxFileSizeMb, 25);
      expect(options.language, isNull);
    });

    test('constructs with optional language', () {
      const options = OcrOptions(
        maxPagesPerPdf: 100,
        maxFileSizeMb: 50,
        language: 'rus',
      );

      expect(options.language, 'rus');
    });
  });

  group('OcrResult', () {
    test('isSuccess returns true when errorCode is null', () {
      const result = OcrResult(
        text: 'Hello',
        contentType: 'image',
        pagesProcessed: 1,
        confidence: 0.95,
      );

      expect(result.isSuccess, isTrue);
      expect(result.hasText, isTrue);
    });

    test('isSuccess returns false when errorCode is set', () {
      const result = OcrResult(
        text: '',
        contentType: 'image',
        pagesProcessed: 0,
        errorCode: 'ocr_failed',
      );

      expect(result.isSuccess, isFalse);
      expect(result.hasText, isFalse);
    });

    test('hasText returns false for empty text', () {
      const result = OcrResult(
        text: '',
        contentType: 'image',
        pagesProcessed: 0,
      );

      expect(result.hasText, isFalse);
    });

    test('partial success with warning (too_many_pages)', () {
      const result = OcrResult(
        text: 'Partial OCR text',
        contentType: 'scan_pdf',
        pagesProcessed: 5,
        confidence: 0.8,
        errorCode: 'too_many_pages',
      );

      expect(result.isSuccess, isFalse);
      expect(result.hasText, isTrue);
      expect(result.pagesProcessed, 5);
      expect(result.confidence, 0.8);
      expect(result.errorCode, 'too_many_pages');
    });

    test('toString contains all fields', () {
      const result = OcrResult(
        text: 'Test',
        contentType: 'image',
        pagesProcessed: 1,
        confidence: 0.90,
        errorCode: null,
      );

      final str = result.toString();
      expect(str, contains('image'));
      expect(str, contains('4')); // chars
      expect(str, contains('1')); // pages
      expect(str, contains('0.9')); // confidence
    });

    test('toString with error', () {
      const result = OcrResult(
        text: '',
        contentType: 'image',
        pagesProcessed: 0,
        errorCode: 'not_implemented',
      );

      final str = result.toString();
      expect(str, contains('not_implemented'));
    });
  });

  group('OcrService contract', () {
    test('stub implementation satisfies interface', () {
      // Verify that a simple stub can implement the interface
      final service = _StubOcrService();
      expect(service, isA<OcrService>());
    });
  });
}

/// Minimal stub to verify the interface compiles correctly.
class _StubOcrService implements OcrService {
  @override
  Future<OcrResult> extractText(String filePath, OcrOptions options) async {
    return const OcrResult(
      text: '',
      contentType: 'unsupported',
      pagesProcessed: 0,
      errorCode: 'not_implemented',
    );
  }

  @override
  bool isSupported(String filePath) {
    return false;
  }
}

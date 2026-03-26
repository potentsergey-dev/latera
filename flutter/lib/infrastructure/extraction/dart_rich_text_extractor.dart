import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../domain/text_extraction.dart';

/// Dart-side реализация [RichTextExtractor].
///
/// Используется пока FRB codegen не работает на Windows.
/// Обрабатывает:
/// - **PDF** — через `syncfusion_flutter_pdf` (чистый Dart, text layer)
/// - **DOCX** — через `archive` (ZIP) + XML парсинг
///
/// Поведение совместимо с Rust `extract_text_from_file`:
/// те же коды ошибок, лимиты из [ExtractionOptions].
class DartRichTextExtractor implements RichTextExtractor {
  final Logger _log;

  DartRichTextExtractor({required Logger logger}) : _log = logger;

  /// Расширения PDF.
  static const _pdfExtensions = {'pdf'};

  /// Расширения DOCX.
  static const _docxExtensions = {'docx'};

  @override
  Future<ExtractionResult> extractText(
    String filePath,
    ExtractionOptions options,
  ) async {
    final file = File(filePath);

    // Проверяем существование файла
    if (!await file.exists()) {
      _log.w('File not found: $filePath');
      return const ExtractionResult(
        text: '',
        contentType: 'unknown',
        pagesExtracted: 0,
        errorCode: 'file_not_found',
      );
    }

    // Проверяем размер файла
    final fileSize = await file.length();
    final maxBytes = options.maxFileSizeMb * 1024 * 1024;
    if (fileSize > maxBytes) {
      _log.w('File too large: $filePath ($fileSize bytes > $maxBytes max)');
      return const ExtractionResult(
        text: '',
        contentType: 'unknown',
        pagesExtracted: 0,
        errorCode: 'file_too_large',
      );
    }

    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');

    if (_pdfExtensions.contains(ext)) {
      return _extractPdf(filePath, options);
    }
    if (_docxExtensions.contains(ext)) {
      return _extractDocx(filePath);
    }

    _log.d('Unsupported format: $ext ($filePath)');
    return const ExtractionResult(
      text: '',
      contentType: 'unsupported',
      pagesExtracted: 0,
      errorCode: 'unsupported_format',
    );
  }

  /// Извлечение текста из PDF через syncfusion_flutter_pdf (чистый Dart).
  Future<ExtractionResult> _extractPdf(
    String filePath,
    ExtractionOptions options,
  ) async {
    sf.PdfDocument? doc;
    try {
      _log.d('Opening PDF: $filePath');
      final bytes = await File(filePath).readAsBytes();
      doc = sf.PdfDocument(inputBytes: bytes);

      final totalPages = doc.pages.count;
      _log.d('PDF opened: $totalPages pages');

      final pagesToProcess =
          totalPages < options.maxPagesPerPdf ? totalPages : options.maxPagesPerPdf;

      // Извлекаем текст используя PdfTextExtractor
      final extractor = sf.PdfTextExtractor(doc);
      final buffer = StringBuffer();
      var pagesExtracted = 0;

      for (var i = 0; i < pagesToProcess; i++) {
        try {
          final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
          if (pageText.isNotEmpty) {
            if (buffer.isNotEmpty) {
              buffer.write('\n\n');
            }
            buffer.write(pageText);
          }
          pagesExtracted++;
          _log.d('Page ${i + 1}: ${pageText.length} chars');
        } catch (e) {
          _log.w('Failed to extract text from page ${i + 1}: $e');
          pagesExtracted++;
        }
      }

      final text = buffer.toString().trim();
      _log.i('PDF extraction done: $pagesExtracted pages, ${text.length} chars');

      // Если извлечено 0 символов — PDF может быть image-only
      if (text.isEmpty) {
        _log.w('PDF text extraction resulted in empty text (image-only PDF?)');
        return ExtractionResult(
          text: '',
          contentType: 'pdf',
          pagesExtracted: pagesExtracted,
          errorCode: 'extraction_failed',
        );
      }

      return ExtractionResult(
        text: text,
        contentType: 'pdf',
        pagesExtracted: pagesExtracted,
        errorCode: totalPages > options.maxPagesPerPdf ? 'too_many_pages' : null,
      );
    } catch (e, st) {
      _log.e('PDF extraction failed: $filePath', error: e, stackTrace: st);
      return const ExtractionResult(
        text: '',
        contentType: 'pdf',
        pagesExtracted: 0,
        errorCode: 'extraction_failed',
      );
    } finally {
      doc?.dispose();
    }
  }

  /// Извлечение текста из DOCX (ZIP → word/document.xml → strip XML tags).
  Future<ExtractionResult> _extractDocx(String filePath) async {
    try {
      _log.d('Opening DOCX: $filePath');
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Ищем word/document.xml
      ArchiveFile? docEntry;
      for (final f in archive.files) {
        if (f.name == 'word/document.xml') {
          docEntry = f;
          break;
        }
      }

      if (docEntry == null) {
        _log.w('DOCX missing word/document.xml: $filePath');
        return const ExtractionResult(
          text: '',
          contentType: 'docx',
          pagesExtracted: 0,
          errorCode: 'extraction_failed',
        );
      }

      final xmlContent = String.fromCharCodes(docEntry.content as List<int>);

      // Извлекаем текст из <w:t ...> тегов
      final text = _extractTextFromDocxXml(xmlContent);
      _log.i('DOCX extraction done: ${text.length} chars');

      if (text.isEmpty) {
        _log.w('DOCX text extraction resulted in empty text');
        return const ExtractionResult(
          text: '',
          contentType: 'docx',
          pagesExtracted: 0,
          errorCode: 'extraction_failed',
        );
      }

      return ExtractionResult(
        text: text,
        contentType: 'docx',
        pagesExtracted: 0,
      );
    } catch (e, st) {
      _log.e('DOCX extraction failed: $filePath', error: e, stackTrace: st);
      return const ExtractionResult(
        text: '',
        contentType: 'docx',
        pagesExtracted: 0,
        errorCode: 'extraction_failed',
      );
    }
  }

  /// Парсит word/document.xml и собирает текст.
  String _extractTextFromDocxXml(String xml) {
    final buffer = StringBuffer();

    // Разбиваем на абзацы (<w:p>...</w:p>)
    final paragraphRegex = RegExp(r'<w:p[> ].*?</w:p>', dotAll: true);
    final textRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);

    for (final pMatch in paragraphRegex.allMatches(xml)) {
      final paragraph = pMatch.group(0)!;
      final paragraphBuffer = StringBuffer();

      for (final tMatch in textRegex.allMatches(paragraph)) {
        paragraphBuffer.write(tMatch.group(1));
      }

      if (paragraphBuffer.isNotEmpty) {
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(paragraphBuffer);
      }
    }

    return buffer.toString().trim();
  }
}

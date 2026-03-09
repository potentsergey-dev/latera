import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart';

import '../../domain/auto_summary.dart';
import 'rust_ocr_service.dart' show RustOcrService;

// FFI type definitions
typedef _GenerateSummaryC = Pointer<Utf8> Function(
  Pointer<Utf8> textContentPtr,
  Pointer<Utf8> fileNamePtr,
);
typedef _GenerateSummaryDart = Pointer<Utf8> Function(
  Pointer<Utf8> textContentPtr,
  Pointer<Utf8> fileNamePtr,
);

typedef _IsLlmReadyC = Uint32 Function();
typedef _IsLlmReadyDart = int Function();

typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Реализация [AutoSummaryService], делегирующая генерацию описаний в Rust
/// через C FFI.
///
/// Использует extractive summarization на основе sentence embeddings
/// (ONNX all-MiniLM-L6-v2). При подключении генеративной LLM-модели
/// Rust-side заменится без изменения Dart API.
class RustFfiAutoSummaryService implements AutoSummaryService {
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _GenerateSummaryDart? _generateSummaryFfi;
  _IsLlmReadyDart? _isLlmReadyFfi;
  _FreeCStringDart? _freeCStringFfi;
  bool _initialized = false;
  bool _available = false;

  RustFfiAutoSummaryService();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('RustFfiAutoSummaryService: DLL not found');
      _available = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);

      _generateSummaryFfi =
          lib.lookupFunction<_GenerateSummaryC, _GenerateSummaryDart>(
        'latera_generate_summary',
      );
      _isLlmReadyFfi =
          lib.lookupFunction<_IsLlmReadyC, _IsLlmReadyDart>(
        'latera_is_llm_ready',
      );
      _freeCStringFfi =
          lib.lookupFunction<_FreeCStringC, _FreeCStringDart>(
        'latera_free_cstring',
      );

      _available = true;
      _log.i('RustFfiAutoSummaryService: loaded successfully');
    } catch (e) {
      _log.e('RustFfiAutoSummaryService: failed to load: $e');
      _available = false;
    }
  }

  /// Доступна ли Rust DLL.
  bool get isAvailable {
    _ensureInitialized();
    return _available;
  }

  /// Загружена ли LLM-модель в Rust.
  bool get isModelReady {
    _ensureInitialized();
    if (!_available) return false;
    return _isLlmReadyFfi!() != 0;
  }

  @override
  Future<AutoSummaryResult> generateSummary(
    String textContent, {
    required String fileName,
  }) async {
    _ensureInitialized();

    if (!_available) {
      return const AutoSummaryResult(
        summary: '',
        errorCode: 'not_implemented',
      );
    }

    if (textContent.trim().isEmpty) {
      return const AutoSummaryResult(
        summary: '',
        errorCode: 'empty_content',
      );
    }

    final textPtr = textContent.toNativeUtf8();
    final fileNamePtr = fileName.toNativeUtf8();
    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);

    try {
      resultPtr = _generateSummaryFfi!(textPtr, fileNamePtr);

      if (resultPtr.address == 0) {
        _log.w('RustFfiAutoSummaryService: FFI returned null');
        return const AutoSummaryResult(
          summary: '',
          errorCode: 'generation_failed',
        );
      }

      final jsonStr = resultPtr.toDartString();
      final Map<String, dynamic> data =
          json.decode(jsonStr) as Map<String, dynamic>;

      final summary = data['summary'] as String? ?? '';
      final errorCode = data['error_code'] as String?;

      return AutoSummaryResult(
        summary: summary,
        errorCode: errorCode,
      );
    } catch (e) {
      _log.e('RustFfiAutoSummaryService: generateSummary error: $e');
      return const AutoSummaryResult(
        summary: '',
        errorCode: 'generation_failed',
      );
    } finally {
      calloc.free(textPtr);
      calloc.free(fileNamePtr);
      if (resultPtr.address != 0) {
        _freeCStringFfi!(resultPtr);
      }
    }
  }
}

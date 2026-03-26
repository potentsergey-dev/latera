import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart';

import '../../domain/auto_tags.dart';
import 'rust_ocr_service.dart' show RustOcrService;

// FFI type definitions
typedef _GenerateTagsC = Pointer<Utf8> Function(
  Pointer<Utf8> textContentPtr,
  Pointer<Utf8> fileNamePtr,
);
typedef _GenerateTagsDart = Pointer<Utf8> Function(
  Pointer<Utf8> textContentPtr,
  Pointer<Utf8> fileNamePtr,
);

typedef _IsLlmReadyC = Uint32 Function();
typedef _IsLlmReadyDart = int Function();

typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Реализация [AutoTagsService], делегирующая генерацию тегов в Rust
/// через C FFI.
///
/// Использует TF-IDF keyword extraction с embedding-based дедупликацией.
/// При подключении генеративной LLM-модели Rust-side заменится
/// без изменения Dart API.
class RustFfiAutoTagsService implements AutoTagsService {
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _IsLlmReadyDart? _isLlmReadyFfi;
  bool _initialized = false;
  bool _available = false;

  RustFfiAutoTagsService();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('RustFfiAutoTagsService: DLL not found');
      _available = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);

      _isLlmReadyFfi =
          lib.lookupFunction<_IsLlmReadyC, _IsLlmReadyDart>(
        'latera_is_llm_ready',
      );

      _available = true;
      _log.i('RustFfiAutoTagsService: loaded successfully');
    } catch (e) {
      _log.e('RustFfiAutoTagsService: failed to load: $e');
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
  Future<AutoTagsResult> generateTags(
    String textContent, {
    required String fileName,
  }) async {
    _ensureInitialized();

    if (!_available) {
      return const AutoTagsResult(
        tags: [],
        errorCode: 'not_implemented',
      );
    }

    if (textContent.trim().isEmpty) {
      return const AutoTagsResult(
        tags: [],
        errorCode: 'empty_content',
      );
    }

    // Захватываем путь к DLL — DynamicLibrary нельзя передать в Isolate.
    final libPath = RustOcrService.resolveLibraryPath()!;

    // Выполняем тяжёлый TF-IDF + embedding inference в отдельном Isolate,
    // чтобы не блокировать UI thread.
    try {
      final jsonStr = await Isolate.run(() {
        return _doGenerateTags(
          libraryPath: libPath,
          textContent: textContent,
          fileName: fileName,
        );
      });

      if (jsonStr == null) {
        _log.w('RustFfiAutoTagsService: FFI returned null');
        return const AutoTagsResult(
          tags: [],
          errorCode: 'generation_failed',
        );
      }

      final Map<String, dynamic> data =
          json.decode(jsonStr) as Map<String, dynamic>;

      final tagsRaw = data['tags'] as List<dynamic>? ?? [];
      final tags = tagsRaw.map((t) => t.toString()).toList();
      final errorCode = data['error_code'] as String?;

      return AutoTagsResult(
        tags: tags,
        errorCode: errorCode,
      );
    } catch (e) {
      _log.e('RustFfiAutoTagsService: generateTags error: $e');
      return const AutoTagsResult(
        tags: [],
        errorCode: 'generation_failed',
      );
    }
  }

  /// Статический метод для выполнения в Isolate (не может использовать this).
  static String? _doGenerateTags({
    required String libraryPath,
    required String textContent,
    required String fileName,
  }) {
    final lib = DynamicLibrary.open(libraryPath);
    final generateTags = lib.lookupFunction<
      _GenerateTagsC,
      _GenerateTagsDart
    >('latera_generate_tags');
    final freeCString = lib.lookupFunction<_FreeCStringC, _FreeCStringDart>(
      'latera_free_cstring',
    );

    final textPtr = textContent.toNativeUtf8();
    final fileNamePtr = fileName.toNativeUtf8();
    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);
    try {
      resultPtr = generateTags(textPtr, fileNamePtr);
      if (resultPtr.address == 0) return null;
      return resultPtr.toDartString();
    } finally {
      calloc.free(textPtr);
      calloc.free(fileNamePtr);
      if (resultPtr.address != 0) {
        freeCString(resultPtr);
      }
    }
  }
}

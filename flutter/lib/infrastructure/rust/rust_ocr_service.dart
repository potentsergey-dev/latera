import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../domain/ocr.dart';

// FFI type definitions
typedef _OcrExtractTextC = Pointer<Utf8> Function(
  Pointer<Utf8> pathPtr,
  Uint32 maxPages,
  Uint32 maxSizeMb,
  Pointer<Utf8> langPtr,
);
typedef _OcrExtractTextDart = Pointer<Utf8> Function(
  Pointer<Utf8> pathPtr,
  int maxPages,
  int maxSizeMb,
  Pointer<Utf8> langPtr,
);

typedef _IsOcrSupportedC = Int32 Function(Pointer<Utf8> pathPtr);
typedef _IsOcrSupportedDart = int Function(Pointer<Utf8> pathPtr);

typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Реализация [OcrService] через прямой FFI вызов Rust DLL.
///
/// Обходит ограничения FRB codegen на Windows, вызывая экспортированные
/// C-совместимые функции из `latera_rust.dll` напрямую через `dart:ffi`.
///
/// Результат OCR возвращается как JSON строка, парсится в [OcrResult].
/// Тяжёлая работа (Windows.Media.Ocr) выполняется в отдельном Isolate
/// чтобы не блокировать UI thread.
class RustOcrService implements OcrService {
  final String _libraryPath;

  late final DynamicLibrary _lib;
  late final _IsOcrSupportedDart _isOcrSupportedFfi;

  bool _isInitialized = false;

  RustOcrService({required String libraryPath}) : _libraryPath = libraryPath;

  /// Ленивая инициализация FFI bindings.
  void _ensureInitialized() {
    if (_isInitialized) return;

    _lib = DynamicLibrary.open(_libraryPath);

    _isOcrSupportedFfi = _lib
        .lookupFunction<_IsOcrSupportedC, _IsOcrSupportedDart>(
            'latera_is_ocr_supported');

    _isInitialized = true;
  }

  @override
  Future<OcrResult> extractText(
    String filePath,
    OcrOptions options,
  ) async {
    _ensureInitialized();

    // Захватываем все параметры в локальные переменные,
    // чтобы замыкание НЕ захватывало `this` (содержит DynamicLibrary,
    // который нельзя передать между изолятами).
    final libPath = _libraryPath;
    final maxPages = options.maxPagesPerPdf;
    final maxSizeMb = options.maxFileSizeMb;
    final language = options.language;

    // Выполняем OCR в отдельном Isolate чтобы не блокировать UI
    final result = await Isolate.run(() {
      return _doExtractText(
        libraryPath: libPath,
        filePath: filePath,
        maxPages: maxPages,
        maxSizeMb: maxSizeMb,
        language: language,
      );
    });

    return result;
  }

  @override
  bool isSupported(String filePath) {
    _ensureInitialized();

    final pathPtr = filePath.toNativeUtf8();
    try {
      return _isOcrSupportedFfi(pathPtr) != 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Статический метод для выполнения в Isolate (не может использовать this).
  static OcrResult _doExtractText({
    required String libraryPath,
    required String filePath,
    required int maxPages,
    required int maxSizeMb,
    required String? language,
  }) {
    final lib = DynamicLibrary.open(libraryPath);

    final ocrExtract = lib
        .lookupFunction<_OcrExtractTextC, _OcrExtractTextDart>(
            'latera_ocr_extract_text');

    final freeCString = lib
        .lookupFunction<_FreeCStringC, _FreeCStringDart>(
            'latera_free_cstring');

    final pathPtr = filePath.toNativeUtf8();
    final langPtr = language != null
        ? language.toNativeUtf8()
        : Pointer<Utf8>.fromAddress(0); // null pointer

    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);
    try {
      resultPtr = ocrExtract(pathPtr, maxPages, maxSizeMb, langPtr);

      if (resultPtr.address == 0) {
        return const OcrResult(
          text: '',
          contentType: 'unknown',
          pagesProcessed: 0,
          errorCode: 'ocr_failed',
        );
      }

      final jsonStr = resultPtr.toDartString();
      return _parseOcrResult(jsonStr);
    } finally {
      calloc.free(pathPtr);
      if (language != null) {
        calloc.free(langPtr);
      }
      if (resultPtr.address != 0) {
        freeCString(resultPtr);
      }
    }
  }

  /// Парсит JSON результат из Rust в [OcrResult].
  static OcrResult _parseOcrResult(String jsonStr) {
    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return OcrResult(
        text: (map['text'] as String?) ?? '',
        contentType: (map['content_type'] as String?) ?? 'unknown',
        pagesProcessed: (map['pages_processed'] as int?) ?? 0,
        confidence: map['confidence'] as double?,
        errorCode: map['error_code'] as String?,
      );
    } catch (_) {
      return const OcrResult(
        text: '',
        contentType: 'unknown',
        pagesProcessed: 0,
        errorCode: 'ocr_failed',
      );
    }
  }

  /// Резолвит путь к Rust DLL.
  ///
  /// Повторяет логику из [RustCoreBootstrap] для независимого поиска DLL.
  static String? resolveLibraryPath() {
    if (!Platform.isWindows) return null;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.normalize('$exeDir\\latera_rust.dll'),
      p.normalize(
        '$exeDir\\..\\..\\..\\..\\..\\..\\rust\\target\\release\\latera_rust.dll',
      ),
      p.normalize(
        '$exeDir\\..\\..\\..\\..\\..\\..\\rust\\target\\debug\\latera_rust.dll',
      ),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }
}

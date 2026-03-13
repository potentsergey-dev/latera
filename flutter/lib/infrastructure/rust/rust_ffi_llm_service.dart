import 'dart:ffi';
import 'package:logger/logger.dart';
import '../rust/rust_ocr_service.dart';

typedef _IsLlmReadyC = Int32 Function();
typedef _IsLlmReadyDart = int Function();

class RustFfiLlmService {
  bool _initialized = false;
  bool _available = false;
  late final Logger _log;
  _IsLlmReadyDart? _isLlmReadyFfi;

  RustFfiLlmService({Logger? logger}) : _log = logger ?? Logger();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('RustFfiLlmService: DLL not found');
      _available = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);
      _isLlmReadyFfi = lib.lookupFunction<_IsLlmReadyC, _IsLlmReadyDart>(
        'latera_is_llm_ready',
      );
      _available = true;
      _log.i('RustFfiLlmService: loaded successfully');
    } catch (e) {
      _log.e('RustFfiLlmService: failed to load: $e');
      _available = false;
    }
  }

  bool get isAvailable {
    _ensureInitialized();
    return _available;
  }

  /// Проверяет готовность LLM-модели в Rust.
  bool get isModelReady {
    _ensureInitialized();
    if (!_available) return false;
    return _isLlmReadyFfi!() != 0;
  }
}

import 'dart:ffi';

import 'package:logger/logger.dart';

import 'rust_ocr_service.dart' show RustOcrService;

// FFI type definitions
typedef _GetTotalRamMbC = Uint64 Function();
typedef _GetTotalRamMbDart = int Function();

/// Сервис для получения системной информации через Rust FFI.
class RustFfiSystemService {
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _GetTotalRamMbDart? _getTotalRamMbFfi;
  bool _initialized = false;
  bool _available = false;

  RustFfiSystemService();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('RustFfiSystemService: DLL not found');
      _available = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);

      _getTotalRamMbFfi =
          lib.lookupFunction<_GetTotalRamMbC, _GetTotalRamMbDart>(
        'latera_get_total_ram_mb',
      );

      _available = true;
      _log.i('RustFfiSystemService: loaded successfully');
    } catch (e) {
      _log.e('RustFfiSystemService: failed to load: $e');
      _available = false;
    }
  }

  /// Доступна ли Rust DLL.
  bool get isAvailable {
    _ensureInitialized();
    return _available;
  }

  /// Возвращает общий объём физической оперативной памяти в мегабайтах.
  Future<int> getTotalRamMb() async {
    _ensureInitialized();
    if (!_available) {
      return 0;
    }
    return _getTotalRamMbFfi!();
  }
}

import 'dart:ffi';

import 'package:logger/logger.dart';

import 'rust_ocr_service.dart' show RustOcrService;

// FFI type definitions
typedef _GetTotalRamMbC = Uint64 Function();
typedef _GetTotalRamMbDart = int Function();
typedef _GetHasAvx2C = Uint32 Function();
typedef _GetHasAvx2Dart = int Function();
typedef _SetRagMaxTokensC = Void Function(Uint32 maxTokens);
typedef _SetRagMaxTokensDart = void Function(int maxTokens);
typedef _GetHasVulkanC = Uint32 Function();
typedef _GetHasVulkanDart = int Function();

/// Сервис для получения системной информации через Rust FFI.
class RustFfiSystemService {
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _GetTotalRamMbDart? _getTotalRamMbFfi;
  _GetHasAvx2Dart? _getHasAvx2Ffi;
  _SetRagMaxTokensDart? _setRagMaxTokensFfi;
  _GetHasVulkanDart? _getHasVulkanFfi;
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

      _getHasAvx2Ffi =
          lib.lookupFunction<_GetHasAvx2C, _GetHasAvx2Dart>(
        'latera_get_has_avx2',
      );

      _setRagMaxTokensFfi =
          lib.lookupFunction<_SetRagMaxTokensC, _SetRagMaxTokensDart>(
        'latera_set_rag_max_tokens',
      );

      _getHasVulkanFfi =
          lib.lookupFunction<_GetHasVulkanC, _GetHasVulkanDart>(
        'latera_get_has_vulkan',
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

  /// Проверяет поддержку AVX2 процессором.
  bool getHasAvx2() {
    _ensureInitialized();
    if (!_available) {
      return false;
    }
    return _getHasAvx2Ffi!() != 0;
  }

  /// Устанавливает глобальный лимит генерируемых токенов для RAG.
  void setRagMaxTokens(int maxTokens) {
    _ensureInitialized();
    if (!_available) {
      return;
    }
    _setRagMaxTokensFfi!(maxTokens);
  }

  /// Проверяет доступность Vulkan runtime (vulkan-1.dll) на текущей машине.
  bool getHasVulkan() {
    _ensureInitialized();
    if (!_available) {
      return false;
    }
    return _getHasVulkanFfi!() != 0;
  }
}

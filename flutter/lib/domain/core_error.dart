/// Единая модель ошибок для всего приложения.
///
/// Все ошибки из Rust и Dart маппятся в этот тип.
/// Гарантирует, что контекст ошибки не теряется при пересечении границ FFI.
sealed class CoreError implements Exception {
  /// Человекочитаемое сообщение
  String get message;

  /// Оригинальная ошибка (для логирования и отладки)
  Object? get originalError;

  /// Stack trace оригинальной ошибки
  StackTrace? get stackTrace;

  /// Код ошибки для машинной обработки
  String get code;

  const CoreError();

  @override
  String toString() => 'CoreError($code): $message';
}

/// Ошибки файловой системы
final class FileSystemError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const FileSystemError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'FS_ERROR',
  });

  factory FileSystemError.fromRust(Object error, [StackTrace? st]) {
    return FileSystemError(
      message: _extractRustMessage(error),
      originalError: error,
      stackTrace: st,
      code: _extractRustCode(error),
    );
  }
}

/// Ошибки watcher'а
final class WatcherError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const WatcherError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'WATCHER_ERROR',
  });

  factory WatcherError.alreadyRunning([Object? error]) => WatcherError(
        message: 'Watcher is already running',
        originalError: error,
        code: 'WATCHER_ALREADY_RUNNING',
      );

  factory WatcherError.notRunning([Object? error]) => WatcherError(
        message: 'Watcher is not running',
        originalError: error,
        code: 'WATCHER_NOT_RUNNING',
      );

  factory WatcherError.fromRust(Object error, [StackTrace? st]) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('already running')) {
      return WatcherError.alreadyRunning(error);
    }
    if (errorStr.contains('not running')) {
      return WatcherError.notRunning(error);
    }
    return WatcherError(
      message: _extractRustMessage(error),
      originalError: error,
      stackTrace: st,
      code: _extractRustCode(error),
    );
  }
}

/// Ошибки конфигурации
final class ConfigError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const ConfigError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'CONFIG_ERROR',
  });

  factory ConfigError.invalidPath(String path, [Object? error]) =>
      ConfigError(
        message: 'Invalid path: $path',
        originalError: error,
        code: 'INVALID_PATH',
      );

  factory ConfigError.desktopNotFound([Object? error]) => ConfigError(
        message: 'Desktop directory is not available on this OS/user',
        originalError: error,
        code: 'DESKTOP_DIR_NOT_FOUND',
      );
}

/// Ошибки платформы (неподдерживаемая ОС и т.д.)
final class PlatformError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const PlatformError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'PLATFORM_ERROR',
  });

  factory PlatformError.unsupported([Object? error]) => PlatformError(
        message: 'Unsupported platform for this operation',
        originalError: error,
        code: 'UNSUPPORTED_PLATFORM',
      );
}

/// Ошибки инициализации
final class InitializationError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const InitializationError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'INIT_ERROR',
  });

  factory InitializationError.rustCore([Object? error, StackTrace? st]) =>
      InitializationError(
        message: 'Failed to initialize Rust core',
        originalError: error,
        stackTrace: st,
        code: 'RUST_CORE_INIT_FAILED',
      );
}

/// Ошибки уведомлений
final class NotificationError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const NotificationError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'NOTIFICATION_ERROR',
  });

  factory NotificationError.showFailed(String fileName, [Object? error]) =>
      NotificationError(
        message: 'Failed to show notification for file: $fileName',
        originalError: error,
        code: 'NOTIFICATION_SHOW_FAILED',
      );
}

/// Ошибки потока (stream)
final class StreamError extends CoreError {
  @override
  final String message;
  @override
  final Object? originalError;
  @override
  final StackTrace? stackTrace;
  @override
  final String code;

  const StreamError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.code = 'STREAM_ERROR',
  });

  factory StreamError.disconnected([Object? error]) => StreamError(
        message: 'Stream disconnected unexpectedly',
        originalError: error,
        code: 'STREAM_DISCONNECTED',
      );

  factory StreamError.fromRust(Object error, [StackTrace? st]) => StreamError(
        message: _extractRustMessage(error),
        originalError: error,
        stackTrace: st,
        code: _extractRustCode(error),
      );
}

// Helper functions для извлечения информации из Rust ошибок

String _extractRustMessage(Object error) {
  final str = error.toString();
  // FRB оборачивает ошибки, пытаемся извлечь сообщение
  // Формат: "LateraError::Variant: message" или просто "message"

  // Ищем паттерны LateraError
  final lateraMatch = RegExp(r'LateraError::(\w+)(?::\s*(.+))?')
      .firstMatch(str);
  if (lateraMatch != null) {
    final variant = lateraMatch.group(1) ?? '';
    final msg = lateraMatch.group(2);
    if (msg != null && msg.isNotEmpty) {
      return msg;
    }
    // Конвертируем variant в читаемый текст
    return _variantToMessage(variant);
  }

  // Если паттерн не найден, возвращаем как есть
  return str;
}

String _variantToMessage(String variant) {
  switch (variant) {
    case 'DesktopDirNotFound':
      return 'Desktop directory is not available on this OS/user';
    case 'InvalidPath':
      return 'Invalid path provided';
    case 'WatcherAlreadyRunning':
      return 'Watcher is already running';
    case 'WatcherNotRunning':
      return 'Watcher is not running';
    case 'Io':
      return 'I/O error occurred';
    case 'Notify':
      return 'File system notification error';
    case 'FileNameMissing':
      return 'Cannot determine file name';
    default:
      return variant.replaceAll(RegExp(r'([A-Z])'), ' \$1').trim();
  }
}

String _extractRustCode(Object error) {
  final str = error.toString();
  final match = RegExp(r'LateraError::(\w+)').firstMatch(str);
  if (match != null) {
    return 'RUST_${match.group(1)!.toUpperCase()}';
  }
  return 'RUST_UNKNOWN';
}

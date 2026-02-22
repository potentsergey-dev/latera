import 'package:logger/logger.dart';

/// Конфигурация логирования для Latera.
///
/// ## Уровни логов
/// - `error`: критические ошибки, требующие внимания
/// - `warning`: предупреждения, некритичные проблемы
/// - `info`: важные события жизненного цикла
/// - `debug`: детальная информация для отладки
/// - `trace`: максимально детальный вывод
///
/// ## Корреляция событий
/// Каждый лог может содержать `correlationId` для трассировки запросов
/// через границы Rust/Flutter.
class AppLogger {
  AppLogger._();

  /// Создать настроенный Logger для приложения.
  ///
  /// [isProduction] — если true, отключает debug/trace уровни.
  /// [enableColors] — цветной вывод (отключить для CI/лог-файлов).
  static Logger create({
    bool isProduction = false,
    bool enableColors = true,
  }) {
    return Logger(
      filter: _AppLogFilter(isProduction: isProduction),
      printer: _AppLogPrinter(enableColors: enableColors),
      output: ConsoleOutput(),
    );
  }

  /// Создать Logger для тестов с выводом в память.
  static Logger createForTests(MemoryOutput output) {
    return Logger(
      filter: DevelopmentFilter(),
      printer: PrettyPrinter(methodCount: 0, colors: false),
      output: output,
    );
  }
}

/// Фильтр логов с поддержкой production режима.
class _AppLogFilter extends LogFilter {
  final bool isProduction;

  _AppLogFilter({required this.isProduction});

  @override
  bool shouldLog(LogEvent event) {
    if (isProduction) {
      // В production только warning и выше
      return event.level.index >= Level.warning.index;
    }
    // В debug режиме всё
    return true;
  }
}

/// Кастомный принтер с форматированием.
class _AppLogPrinter extends LogPrinter {
  final bool enableColors;

  _AppLogPrinter({required this.enableColors});

  static final Map<Level, String> _levelEmojis = {
    Level.trace: '🔍',
    Level.debug: '🐛',
    Level.info: '💡',
    Level.warning: '⚠️',
    Level.error: '⛔',
    Level.fatal: '💀',
  };

  static final Map<Level, String> _levelNames = {
    Level.trace: 'TRACE',
    Level.debug: 'DEBUG',
    Level.info: 'INFO',
    Level.warning: 'WARN',
    Level.error: 'ERROR',
    Level.fatal: 'FATAL',
  };

  @override
  List<String> log(LogEvent event) {
    final timestamp = _formatTimestamp(event.time);
    final level = _levelNames[event.level] ?? 'UNKNOWN';
    final emoji = _levelEmojis[event.level] ?? '';

    final header = '[$timestamp] [$level]';

    final message = '$emoji $header ${event.message}';

    final lines = [message];

    if (event.error != null) {
      lines.add('  Error: ${event.error}');
    }

    if (event.stackTrace != null) {
      lines.add('  StackTrace: ${event.stackTrace}');
    }

    return lines;
  }

  String _formatTimestamp(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Контекст логирования с корреляционным ID.
///
/// Используется для трассировки событий через границы слоёв.
class LogContext {
  /// Уникальный идентификатор для корреляции событий.
  final String correlationId;

  /// Опциональный контекст операции.
  final String? operation;

  LogContext._({
    required this.correlationId,
    this.operation,
  });

  /// Создать новый контекст с уникальным correlation_id.
  factory LogContext() {
    return LogContext._(
      correlationId: _generateCorrelationId(),
    );
  }

  /// Создать контекст с указанным operation name.
  factory LogContext.withOperation(String operation) {
    return LogContext._(
      correlationId: _generateCorrelationId(),
      operation: operation,
    );
  }

  /// Создать контекст с существующим correlation ID (из Rust).
  factory LogContext.fromId(String correlationId, {String? operation}) {
    return LogContext._(
      correlationId: correlationId,
      operation: operation,
    );
  }

  /// Установить operation name.
  LogContext withOperationName(String op) {
    return LogContext._(
      correlationId: correlationId,
      operation: op,
    );
  }

  /// Форматированный префикс для логов.
  String get prefix => operation != null
      ? '[$correlationId] [$operation]'
      : '[$correlationId]';

  /// Генерирует уникальный correlation ID.
  ///
  /// Формат: `corr_<timestamp_ms>_<random_suffix>`
  static String _generateCorrelationId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 10000;
    return 'corr_${timestamp}_$random';
  }

  @override
  String toString() => prefix;
}

/// Расширенный Logger с поддержкой LogContext.
extension ContextLogger on Logger {
  /// Логировать INFO с контекстом.
  void infoWithContext(
    String message,
    LogContext? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = context?.prefix ?? '';
    i('$prefix $message'.trim(), error: error, stackTrace: stackTrace);
  }

  /// Логировать ERROR с контекстом.
  void errorWithContext(
    String message,
    LogContext? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = context?.prefix ?? '';
    e('$prefix $message'.trim(), error: error, stackTrace: stackTrace);
  }

  /// Логировать WARNING с контекстом.
  void warnWithContext(
    String message,
    LogContext? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = context?.prefix ?? '';
    w('$prefix $message'.trim(), error: error, stackTrace: stackTrace);
  }

  /// Логировать DEBUG с контекстом.
  void debugWithContext(
    String message,
    LogContext? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = context?.prefix ?? '';
    d('$prefix $message'.trim(), error: error, stackTrace: stackTrace);
  }

  /// Логировать TRACE с контекстом.
  void traceWithContext(
    String message,
    LogContext? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = context?.prefix ?? '';
    t('$prefix $message'.trim(), error: error, stackTrace: stackTrace);
  }
}

import '../l10n/app_localizations.dart';

/// Преобразует техническое сообщение об ошибке в человекочитаемое.
///
/// Распознаёт паттерны ошибок из Rust FFI, сетевые ошибки,
/// и ошибки нехватки ресурсов. Если паттерн не распознан —
/// возвращает оригинальное сообщение.
String friendlyErrorMessage(String rawError, AppLocalizations l10n) {
  final lower = rawError.toLowerCase();

  // Rust: генеративная модель не загружена
  if (lower.contains('llmnotloaded') ||
      lower.contains('llm not loaded') ||
      lower.contains('llm_not_loaded')) {
    return l10n.errorModelNotLoaded;
  }

  // Rust: embedding-модель не загружена
  if (lower.contains('modelnotinitialized') ||
      lower.contains('model not initialized') ||
      lower.contains('model_not_initialized') ||
      lower.contains('semantic model is not loaded')) {
    return l10n.errorModelNotLoaded;
  }

  // Сетевые ошибки
  if (lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('connection timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('handshakeexception') ||
      lower.contains('certificate_verify_failed') ||
      lower.contains('failed host lookup')) {
    return l10n.errorNetworkUnavailable;
  }

  // Нехватка памяти
  if (lower.contains('out of memory') ||
      lower.contains('insufficient memory') ||
      lower.contains('cannot allocate')) {
    return l10n.errorInsufficientRam;
  }

  // Нехватка места на диске
  if (lower.contains('no space left') ||
      lower.contains('disk full') ||
      lower.contains('not enough disk space')) {
    return l10n.errorInsufficientDisk;
  }

  return rawError;
}

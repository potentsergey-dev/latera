/// Контракты для транскрибации аудио/видео файлов (Whisper).
///
/// Domain-слой не зависит от реализации (Rust FRB, stub и т.д.).
/// Тяжёлая обработка выполняется в Rust core.
library;

/// Опции транскрибации.
///
/// Отражает пользовательские лимиты из [AppConfig.effectiveLimits].
class TranscriptionOptions {
  /// Максимальная длительность медиа для обработки (в минутах).
  /// 0 = транскрибация отключена.
  final int maxMediaMinutes;

  /// Максимальный размер файла в мегабайтах.
  final int maxFileSizeMb;

  /// Язык для транскрибации (ISO 639-1, например "ru", "en").
  /// `null` = автоопределение.
  final String? language;

  const TranscriptionOptions({
    required this.maxMediaMinutes,
    required this.maxFileSizeMb,
    this.language,
  });
}

/// Результат транскрибации.
///
/// Всегда возвращается (ошибки кодируются в [errorCode]).
class TranscriptionResult {
  /// Расшифрованный текст (может быть пуст при ошибке).
  final String text;

  /// Тип контента: `"audio"`, `"video"`, `"unsupported"`, `"unknown"`.
  final String contentType;

  /// Длительность обработанного медиа в секундах.
  final int durationSeconds;

  /// Код ошибки, если была:
  /// - `null` — успех
  /// - `"file_too_large"` — файл превышает лимит
  /// - `"media_too_long"` — медиа превышает лимит длительности
  /// - `"unsupported_format"` — формат не поддерживается
  /// - `"transcription_disabled"` — транскрибация отключена (max_media_minutes=0)
  /// - `"transcription_failed"` — внутренняя ошибка
  /// - `"file_not_found"` — файл не найден
  /// - `"not_implemented"` — Whisper ещё не подключён (stub)
  final String? errorCode;

  const TranscriptionResult({
    required this.text,
    required this.contentType,
    required this.durationSeconds,
    this.errorCode,
  });

  /// Успешно ли транскрибация (нет ошибки).
  bool get isSuccess => errorCode == null;

  /// Есть ли расшифрованный текст.
  bool get hasText => text.isNotEmpty;

  @override
  String toString() {
    return 'TranscriptionResult(contentType: $contentType, '
        'chars: ${text.length}, duration: ${durationSeconds}s, '
        'error: $errorCode)';
  }
}

/// Контракт для транскрибации аудио/видео файлов.
///
/// Тяжёлая обработка выполняется в Rust core через FRB (Whisper.cpp).
/// Domain-слой не зависит от реализации.
abstract interface class AudioTranscriber {
  /// Транскрибирует аудио/видео файл с учётом лимитов.
  ///
  /// [filePath] — абсолютный путь к файлу.
  /// [options] — лимиты из конфигурации.
  Future<TranscriptionResult> transcribe(
    String filePath,
    TranscriptionOptions options,
  );
}

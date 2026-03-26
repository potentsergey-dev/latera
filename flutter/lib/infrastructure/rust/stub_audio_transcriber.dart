import '../../domain/transcription.dart';

/// Stub-реализация [AudioTranscriber].
///
/// Возвращает пустой результат для всех файлов.
/// Используется до подключения Rust FRB bindings с Whisper.cpp.
///
/// После генерации bindings заменяется на `RustAudioTranscriber`,
/// который вызывает `api::transcribe_audio` через FRB.
class StubAudioTranscriber implements AudioTranscriber {
  @override
  Future<TranscriptionResult> transcribe(
    String filePath,
    TranscriptionOptions options,
  ) async {
    return const TranscriptionResult(
      text: '',
      contentType: 'unsupported',
      durationSeconds: 0,
      errorCode: 'not_implemented',
    );
  }
}

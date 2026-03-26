import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart';

import '../../domain/rag.dart' as domain;
import 'generated/api.dart' as rust_api;
import 'rust_ocr_service.dart' show RustOcrService;

// C FFI type definitions for RAG streaming
typedef _RagQueryStartC = Uint32 Function(Pointer<Utf8> question, Uint32 topK);
typedef _RagQueryStartDart = int Function(Pointer<Utf8> question, int topK);
typedef _RagPollEventC = Pointer<Utf8> Function();
typedef _RagPollEventDart = Pointer<Utf8> Function();
typedef _RagCancelC = Void Function();
typedef _RagCancelDart = void Function();
typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Реализация [domain.RagService], использующая Rust core.
///
/// - `query()` — через FRB (legacy одноразовый запрос)
/// - `queryStream()` — через C FFI с poll-моделью стриминга
/// - `cancelQuery()` — через C FFI
class RustRagService implements domain.RagService {
  final Logger _logger;

  // C FFI bindings
  _RagQueryStartDart? _ragQueryStartFfi;
  _RagPollEventDart? _ragPollEventFfi;
  _RagCancelDart? _ragCancelFfi;
  _FreeCStringDart? _freeCStringFfi;
  bool _ffiInitialized = false;
  bool _ffiAvailable = false;

  RustRagService({Logger? logger}) : _logger = logger ?? Logger();

  void _ensureFfiInitialized() {
    if (_ffiInitialized) return;
    _ffiInitialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _logger.w('RustRagService: DLL not found for C FFI');
      _ffiAvailable = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);

      _ragQueryStartFfi =
          lib.lookupFunction<_RagQueryStartC, _RagQueryStartDart>(
        'latera_rag_query_start',
      );
      _ragPollEventFfi =
          lib.lookupFunction<_RagPollEventC, _RagPollEventDart>(
        'latera_rag_poll_event',
      );
      _ragCancelFfi = lib.lookupFunction<_RagCancelC, _RagCancelDart>(
        'latera_rag_cancel',
      );
      _freeCStringFfi = lib.lookupFunction<_FreeCStringC, _FreeCStringDart>(
        'latera_free_cstring',
      );

      _ffiAvailable = true;
      _logger.i('RustRagService: C FFI loaded successfully');
    } catch (e) {
      _logger.e('RustRagService: failed to load C FFI: $e');
      _ffiAvailable = false;
    }
  }

  @override
  Future<domain.RagQueryResult> query(
    String question, {
    int topK = 10,
  }) async {
    if (question.trim().isEmpty) {
      return const domain.RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'empty_question',
      );
    }

    try {
      final result = await rust_api.ragQuery(
        question: question,
        topK: topK,
      );

      return domain.RagQueryResult(
        answer: result.answer,
        errorCode: result.errorCode,
        sources: result.sources
            .map((s) => domain.RagSource(
                  filePath: s.filePath,
                  chunkSnippet: s.chunkSnippet,
                  chunkOffset: s.chunkOffset,
                ))
            .toList(),
      );
    } catch (e, st) {
      _logger.e('FRB RAG query failed', error: e, stackTrace: st);
      return const domain.RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'query_failed',
      );
    }
  }

  @override
  Stream<domain.RagStreamEvent> queryStream(
    String question, {
    int topK = 10,
  }) {
    _ensureFfiInitialized();

    final controller = StreamController<domain.RagStreamEvent>();

    if (!_ffiAvailable) {
      // Fallback: use legacy one-shot query
      _fallbackOneShot(controller, question, topK: topK);
      return controller.stream;
    }

    // Start async RAG query via C FFI
    final questionPtr = question.toNativeUtf8();
    try {
      final started = _ragQueryStartFfi!(questionPtr, topK);
      if (started == 0) {
        controller.add(domain.RagDoneEvent(const domain.RagQueryResult(
          answer: '',
          sources: [],
          errorCode: 'query_failed',
        )));
        controller.close();
        return controller.stream;
      }
    } finally {
      calloc.free(questionPtr);
    }

    // Poll for events with a periodic timer
    Timer? pollTimer;
    pollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _pollEvents(controller, pollTimer);
    });

    // Cancel on stream cancellation
    controller.onCancel = () {
      pollTimer?.cancel();
      cancelQuery();
    };

    return controller.stream;
  }

  void _pollEvents(
    StreamController<domain.RagStreamEvent> controller,
    Timer? pollTimer,
  ) {
    // Poll up to 10 events per tick to avoid lag
    for (var i = 0; i < 10; i++) {
      final ptr = _ragPollEventFfi!();
      if (ptr == nullptr) break;

      try {
        final json = ptr.toDartString();
        _freeCStringFfi!(ptr);

        final map = jsonDecode(json) as Map<String, dynamic>;
        final type = map['type'] as String;

        if (type == 'token') {
          final text = map['text'] as String;
          controller.add(domain.RagTokenEvent(text));
        } else if (type == 'done') {
          pollTimer?.cancel();
          final result = _parseDoneResult(map['result'] as Map<String, dynamic>);
          controller.add(domain.RagDoneEvent(result));
          controller.close();
          return;
        }
      } catch (e) {
        _logger.e('RAG poll: failed to parse event', error: e);
      }
    }
  }

  domain.RagQueryResult _parseDoneResult(Map<String, dynamic> json) {
    final answer = json['answer'] as String? ?? '';
    final errorCode = json['error_code'] as String?;
    final sourcesJson = json['sources'] as List<dynamic>? ?? [];

    final sources = sourcesJson
        .cast<Map<String, dynamic>>()
        .map((s) => domain.RagSource(
              filePath: s['file_path'] as String? ?? '',
              chunkSnippet: s['chunk_snippet'] as String? ?? '',
              chunkOffset: (s['chunk_offset'] as num?)?.toInt() ?? 0,
            ))
        .toList();

    return domain.RagQueryResult(
      answer: answer,
      sources: sources,
      errorCode: errorCode,
    );
  }

  /// Fallback для отсутствующего C FFI — используем FRB query.
  Future<void> _fallbackOneShot(
    StreamController<domain.RagStreamEvent> controller,
    String question, {
    int topK = 10,
  }) async {
    final result = await query(question, topK: topK);
    if (result.hasAnswer) {
      controller.add(domain.RagTokenEvent(result.answer));
    }
    controller.add(domain.RagDoneEvent(result));
    await controller.close();
  }

  @override
  void cancelQuery() {
    _ensureFfiInitialized();
    if (_ffiAvailable) {
      _ragCancelFfi!();
    }
  }
}

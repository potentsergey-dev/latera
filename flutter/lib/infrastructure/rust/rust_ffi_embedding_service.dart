import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logger/logger.dart';

import '../../domain/embeddings.dart';
import 'rust_ocr_service.dart' show RustOcrService;

// FFI type definitions
typedef _ComputeEmbeddingsBatchC =
    Pointer<Utf8> Function(Pointer<Utf8> textsJsonPtr);
typedef _ComputeEmbeddingsBatchDart =
    Pointer<Utf8> Function(Pointer<Utf8> textsJsonPtr);

typedef _IsModelReadyC = Uint32 Function();
typedef _IsModelReadyDart = int Function();

typedef _FreeCStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Utf8> ptr);

/// Реализация [EmbeddingService], делегирующая вычисление эмбеддингов в Rust
/// через C FFI.
///
/// Использует ту же ONNX-модель (all-MiniLM-L6-v2), что загружена в Rust core.
/// Это гарантирует совместимость эмбеддингов при индексации и поиске.
class RustFfiEmbeddingService implements EmbeddingService {
  static final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  _ComputeEmbeddingsBatchDart? _computeEmbeddingsBatchFfi;
  _IsModelReadyDart? _isModelReadyFfi;
  _FreeCStringDart? _freeCStringFfi;
  bool _initialized = false;
  bool _available = false;

  RustFfiEmbeddingService();

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    final libPath = RustOcrService.resolveLibraryPath();
    if (libPath == null) {
      _log.w('RustFfiEmbeddingService: DLL not found');
      _available = false;
      return;
    }

    try {
      final lib = DynamicLibrary.open(libPath);

      _computeEmbeddingsBatchFfi = lib
          .lookupFunction<
            _ComputeEmbeddingsBatchC,
            _ComputeEmbeddingsBatchDart
          >('latera_compute_embeddings_batch');
      _isModelReadyFfi = lib.lookupFunction<_IsModelReadyC, _IsModelReadyDart>(
        'latera_is_semantic_model_ready',
      );
      _freeCStringFfi = lib.lookupFunction<_FreeCStringC, _FreeCStringDart>(
        'latera_free_cstring',
      );

      _available = true;
      _log.i('RustFfiEmbeddingService: loaded successfully');
    } catch (e) {
      _log.e('RustFfiEmbeddingService: failed to load: $e');
      _available = false;
    }
  }

  bool get isAvailable {
    _ensureInitialized();
    return _available;
  }

  bool get isModelReady {
    _ensureInitialized();
    if (!_available) return false;
    return _isModelReadyFfi!() != 0;
  }

  @override
  List<TextChunk> chunkText(
    String text, {
    int chunkSize = 500,
    int chunkOverlap = 50,
  }) {
    if (text.isEmpty) return [];

    final chunks = <TextChunk>[];
    final effectiveChunkSize = chunkSize.clamp(1, text.length);
    final effectiveOverlap = chunkOverlap.clamp(0, effectiveChunkSize - 1);
    var start = 0;
    var index = 0;

    while (start < text.length) {
      final end = (start + effectiveChunkSize).clamp(0, text.length);
      chunks.add(
        TextChunk(
          text: text.substring(start, end),
          chunkIndex: index,
          chunkOffset: start,
        ),
      );
      index++;
      final step = effectiveChunkSize - effectiveOverlap;
      if (step <= 0) break;
      start += step;
    }

    return chunks;
  }

  @override
  Future<List<EmbeddingVector>> computeEmbeddings(
    List<TextChunk> chunks,
  ) async {
    _ensureInitialized();
    if (!_available || chunks.isEmpty) {
      return chunks
          .map(
            (c) => EmbeddingVector(
              chunkIndex: c.chunkIndex,
              vector: List.filled(384, 0.0),
            ),
          )
          .toList();
    }

    // Используем batch API для эффективности
    final texts = chunks.map((c) => c.text).toList();
    final textsJson = json.encode(texts);
    final textsPtr = textsJson.toNativeUtf8();
    Pointer<Utf8> resultPtr = Pointer.fromAddress(0);

    try {
      resultPtr = _computeEmbeddingsBatchFfi!(textsPtr);
      if (resultPtr.address == 0) {
        _log.w('RustFfiEmbeddingService: batch returned null');
        return _fallbackEmbeddings(chunks);
      }

      final jsonStr = resultPtr.toDartString();
      final outerList = json.decode(jsonStr) as List<dynamic>;

      if (outerList.length != chunks.length) {
        _log.w(
          'RustFfiEmbeddingService: expected ${chunks.length} embeddings, got ${outerList.length}',
        );
        return _fallbackEmbeddings(chunks);
      }

      return List.generate(chunks.length, (i) {
        final vecData = outerList[i] as List<dynamic>;
        return EmbeddingVector(
          chunkIndex: chunks[i].chunkIndex,
          vector: vecData.map((v) => (v as num).toDouble()).toList(),
        );
      });
    } catch (e) {
      _log.e('RustFfiEmbeddingService: computeEmbeddings error: $e');
      return _fallbackEmbeddings(chunks);
    } finally {
      calloc.free(textsPtr);
      if (resultPtr.address != 0) {
        _freeCStringFfi!(resultPtr);
      }
    }
  }

  List<EmbeddingVector> _fallbackEmbeddings(List<TextChunk> chunks) {
    return chunks
        .map(
          (c) => EmbeddingVector(
            chunkIndex: c.chunkIndex,
            vector: List.filled(384, 0.0),
          ),
        )
        .toList();
  }

  @override
  Future<List<SimilarityResult>> similaritySearch(
    String query, {
    int topK = 5,
  }) async {
    // Семантический поиск делегирован в _RustSemanticSearchFfi (sqlite_index_service.dart)
    return [];
  }

  @override
  Future<List<SimilarityResult>> findSimilarFiles(
    String filePath, {
    int topK = 5,
  }) async {
    // Поиск похожих файлов делегирован в _RustSemanticSearchFfi (sqlite_index_service.dart)
    return [];
  }

  @override
  Future<bool> hasEmbeddings(String filePath) async {
    // Проверяется через SqliteIndexService напрямую
    return false;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Сервис загрузки LLM-моделей (ONNX + GGUF) с отображением прогресса.
class LlmDownloadService {
  /// URL ONNX-модели на Hugging Face (paraphrase-multilingual-MiniLM-L12-v2).
  static const String modelUrl =
      'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/main/onnx/model.onnx';

  /// URL токенизатора на Hugging Face.
  static const String tokenizerUrl =
      'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/main/tokenizer.json';

  /// URL GGUF-модели Qwen2.5-3B-Instruct Q4_K_M (~1.7 ГБ).
  static const String ggufModelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf';

  /// Имя файла GGUF-модели.
  static const String ggufModelFileName = 'qwen2.5-3b-instruct-q4_k_m.gguf';

  /// Минимально необходимое свободное место на диске (2 ГБ).
  static const int minFreeDiskBytes = 2 * 1024 * 1024 * 1024;

  /// Количество попыток скачивания при ошибке сети.
  static const int _maxRetries = 3;

  /// Скачивает файл модели по [url] в [targetPath].
  ///
  /// Возвращает Stream прогресса от 0.0 до 1.0.
  /// При ошибке stream получает error-событие.
  Stream<double> downloadModel(String url, String targetPath) {
    final controller = StreamController<double>();

    () async {
      final dio = Dio();
      try {
        // Создаём директорию, если не существует
        final dir = Directory(targetPath).parent;
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        await dio.download(
          url,
          targetPath,
          onReceiveProgress: (count, totalBytes) {
            if (totalBytes > 0) {
              controller.add(count / totalBytes);
            }
          },
        );
        controller.add(1.0);
      } catch (e, st) {
        controller.addError(e, st);
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Скачивает GGUF-модель в [targetPath], с retry и проверкой диска.
  ///
  /// Поддерживает докачку (resume) через HTTP Range.
  /// Возвращает Stream прогресса от 0.0 до 1.0.
  Stream<double> downloadGgufModel(String targetPath) {
    final controller = StreamController<double>();

    () async {
      try {
        // Проверка свободного места на диске
        final targetDir = Directory(targetPath).parent;
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
        final freeSpace = await _getFreeDiskSpace(targetDir.path);
        if (freeSpace != null && freeSpace < minFreeDiskBytes) {
          throw StateError(
            'Недостаточно места на диске: ${(freeSpace / (1024 * 1024)).round()} МБ '
            '(нужно минимум ${minFreeDiskBytes ~/ (1024 * 1024)} МБ)',
          );
        }

        // Проверяем, есть ли частично скачанный файл для resume
        final tempPath = '$targetPath.part';
        int existingBytes = 0;
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) {
          existingBytes = tempFile.lengthSync();
        }

        for (int attempt = 1; attempt <= _maxRetries; attempt++) {
          final dio = Dio();
          try {
            final headers = <String, dynamic>{};
            if (existingBytes > 0) {
              headers['Range'] = 'bytes=$existingBytes-';
            }

            await dio.download(
              ggufModelUrl,
              tempPath,
              options: Options(headers: headers),
              deleteOnError: false,
              onReceiveProgress: (count, totalBytes) {
                if (totalBytes > 0) {
                  final total = totalBytes + existingBytes;
                  controller.add((count + existingBytes) / total);
                }
              },
            );

            // Скачивание успешно — переименовываем .part → целевой файл
            await tempFile.rename(targetPath);
            controller.add(1.0);
            return;
          } on DioException {
            if (attempt == _maxRetries) {
              // Удаляем partial файл при финальной неудаче
              if (tempFile.existsSync()) tempFile.deleteSync();
              rethrow;
            }
            // Обновляем existingBytes для resume следующей попытки
            if (tempFile.existsSync()) {
              existingBytes = tempFile.lengthSync();
            }
            // Экспоненциальный backoff: 2s, 4s, 8s
            await Future<void>.delayed(
              Duration(seconds: 2 * (1 << (attempt - 1))),
            );
          }
        }
      } catch (e, st) {
        controller.addError(e, st);
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Возвращает свободное место на диске (в байтах) для Windows.
  /// Null если не удалось определить.
  static Future<int?> _getFreeDiskSpace(String path) async {
    try {
      // Извлекаем букву диска (например, "C:")
      final drive = path.length >= 2 && path[1] == ':'
          ? path.substring(0, 2)
          : null;
      if (drive == null) return null;

      final result = await Process.run(
        'wmic',
        ['logicaldisk', 'where', 'DeviceID="$drive"', 'get', 'FreeSpace', '/format:value'],
      );
      if (result.exitCode != 0) return null;

      final match = RegExp(r'FreeSpace=(\d+)').firstMatch(result.stdout as String);
      if (match == null) return null;
      return int.tryParse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  /// Проверяет, достаточно ли свободного места для GGUF-модели.
  static Future<bool> hasEnoughDiskSpace(String targetDir) async {
    final freeSpace = await _getFreeDiskSpace(targetDir);
    return freeSpace == null || freeSpace >= minFreeDiskBytes;
  }
}

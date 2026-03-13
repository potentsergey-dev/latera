import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Сервис загрузки LLM-модели (ONNX) с отображением прогресса.
class LlmDownloadService {
  /// URL ONNX-модели на Hugging Face (all-MiniLM-L6-v2).
  static const String modelUrl =
      'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx';

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
}

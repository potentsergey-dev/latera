import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Сервис загрузки LLM-моделей (ONNX + GGUF) с отображением прогресса.
class LlmDownloadService {
  // -------------------------------------------------------------------------
  // GitHub Releases (первичный источник — менее подвержен блокировкам в
  // корпоративных сетях и лабораториях сертификации).
  // ВАЖНО: перед сборкой убедитесь, что файлы загружены в релиз v1.0.0-models:
  //   model.onnx           (~170 МБ, paraphrase-multilingual-MiniLM-L12-v2)
  //   tokenizer.json       (~5 МБ)
  //   qwen2.5-3b-instruct-q4_k_m.gguf (~1.7 ГБ)
  // -------------------------------------------------------------------------
  static const String _ghBase =
      'https://github.com/potentsergey-dev/latera/releases/download/v1.0.0-models';

  static const String _ghModelUrl = '$_ghBase/model.onnx';
  static const String _ghTokenizerUrl = '$_ghBase/tokenizer.json';
  static const String _ghGgufUrl = '$_ghBase/qwen2.5-3b-instruct-q4_k_m.gguf';

  // -------------------------------------------------------------------------
  // HuggingFace (резервный источник).
  // -------------------------------------------------------------------------
  static const String _hfModelUrl =
      'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/main/onnx/model.onnx?download=true';
  static const String _hfTokenizerUrl =
      'https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2/resolve/main/tokenizer.json?download=true';
  static const String _hfGgufUrl =
      'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true';

  // -------------------------------------------------------------------------
  // Публичные URL (используются вызывающим кодом).
  // -------------------------------------------------------------------------
  /// Первичный URL ONNX-модели.
  static const String modelUrl = _ghModelUrl;

  /// Первичный URL токенизатора.
  static const String tokenizerUrl = _ghTokenizerUrl;

  /// Первичный URL GGUF-модели.
  static const String ggufModelUrl = _ghGgufUrl;

  /// Имя файла GGUF-модели.
  static const String ggufModelFileName = 'qwen2.5-3b-instruct-q4_k_m.gguf';

  /// Минимально необходимое свободное место на диске (2 ГБ).
  static const int minFreeDiskBytes = 2 * 1024 * 1024 * 1024;

  /// Количество попыток скачивания при ошибке сети для каждого URL.
  static const int _maxRetries = 3;

  /// Fallback-URL для каждого первичного URL.
  static const Map<String, String> _urlFallbacks = {
    _ghModelUrl: _hfModelUrl,
    _ghTokenizerUrl: _hfTokenizerUrl,
    _ghGgufUrl: _hfGgufUrl,
  };

  /// Скачивает файл модели по [url] в [targetPath].
  ///
  /// Сначала пробует [url]; если все попытки исчерпаны — автоматически
  /// переключается на fallback-URL (если определён в [_urlFallbacks]).
  /// При переключении на fallback частично скачанный .part-файл удаляется.
  /// Поддерживает докачку (resume) через HTTP Range и 3 попытки с backoff.
  /// Возвращает Stream прогресса от 0.0 до 1.0.
  Stream<double> downloadModel(String url, String targetPath) {
    final urls = [url, if (_urlFallbacks.containsKey(url)) _urlFallbacks[url]!];
    return _downloadWithFallback(urls, targetPath);
  }

  /// Скачивает GGUF-модель в [targetPath], с retry, fallback и проверкой диска.
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

        // Делегируем загрузку общему методу с fallback
        final urls = [
          ggufModelUrl,
          if (_urlFallbacks.containsKey(ggufModelUrl))
            _urlFallbacks[ggufModelUrl]!,
        ];
        await for (final progress in _downloadWithFallback(urls, targetPath)) {
          controller.add(progress);
        }
      } catch (e, st) {
        controller.addError(e, st);
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Внутренний метод загрузки: пробует [urls] по порядку.
  ///
  /// Для каждого URL делает до [_maxRetries] попыток с resume и exponential backoff.
  /// При переходе к следующему URL частично скачанный .part-файл удаляется.
  Stream<double> _downloadWithFallback(List<String> urls, String targetPath) {
    final controller = StreamController<double>();

    () async {
      try {
        final dir = Directory(targetPath).parent;
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        final tempPath = '$targetPath.part';

        for (int urlIndex = 0; urlIndex < urls.length; urlIndex++) {
          final url = urls[urlIndex];

          // При переключении на fallback-URL удаляем .part от предыдущего URL:
          // серверы разные, и частичные данные несовместимы.
          if (urlIndex > 0) {
            final stale = File(tempPath);
            if (stale.existsSync()) stale.deleteSync();
          }

          int existingBytes = 0;
          final tempFile = File(tempPath);
          if (tempFile.existsSync()) {
            existingBytes = tempFile.lengthSync();
          }

          bool success = false;
          for (int attempt = 1; attempt <= _maxRetries; attempt++) {
            // Нет receiveTimeout — большие файлы могут скачиваться долго на
            // медленных соединениях; connectTimeout защищает от зависания.
            final dio = Dio(
              BaseOptions(connectTimeout: const Duration(seconds: 30)),
            );
            try {
              final headers = <String, dynamic>{
                'User-Agent': 'Latera/1.0 (+https://latera.app)',
              };
              if (existingBytes > 0) {
                headers['Range'] = 'bytes=$existingBytes-';
              }

              await dio.download(
                url,
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

              await tempFile.rename(targetPath);
              controller.add(1.0);
              success = true;
              return;
            } on DioException {
              if (attempt == _maxRetries) {
                // Исчерпаны попытки для этого URL; удаляем .part
                if (tempFile.existsSync()) tempFile.deleteSync();
                break; // перейти к следующему URL
              }
              // Resume: обновляем existingBytes из .part-файла
              if (tempFile.existsSync()) {
                existingBytes = tempFile.lengthSync();
              }
              // Экспоненциальный backoff: 2s, 4s, 8s
              await Future<void>.delayed(
                Duration(seconds: 2 * (1 << (attempt - 1))),
              );
            }
          }

          if (success) return;
        }

        // Все URL исчерпаны
        throw Exception('Не удалось загрузить файл: все источники недоступны.');
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

      final result = await Process.run('wmic', [
        'logicaldisk',
        'where',
        'DeviceID="$drive"',
        'get',
        'FreeSpace',
        '/format:value',
      ]);
      if (result.exitCode != 0) return null;

      final match = RegExp(
        r'FreeSpace=(\d+)',
      ).firstMatch(result.stdout as String);
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

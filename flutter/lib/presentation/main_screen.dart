import 'dart:async';

import 'package:flutter/material.dart';

import '../application/file_events_coordinator.dart';
import '../domain/app_config.dart';
import '../domain/core_error.dart';
import 'app_scope.dart';
import 'file_description_dialog.dart';

/// Главный экран.
///
/// Показывает статус наблюдения за папкой, количество проиндексированных
/// файлов и предоставляет доступ к поиску и настройкам.
/// При получении события о новом файле показывает диалог ввода описания.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  FileEventsCoordinator? _coordinator;

  StreamSubscription<FileAddedUiEvent>? _sub;
  StreamSubscription<FileRemovedUiEvent>? _removedSub;
  StreamSubscription<String>? _watchPathChangedSub;
  String _status = 'Инициализация…';
  String? _lastFileName;
  int _indexedCount = 0;
  bool _initialized = false;
  bool _isDescriptionDialogOpen = false;
  final List<FileAddedUiEvent> _pendingFiles = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _coordinator = AppScope.of(context).fileEventsCoordinator;
    unawaited(_init().catchError((Object error, StackTrace st) {
      debugPrint('Unexpected error in _init(): $error\n$st');
      if (mounted) {
        setState(() {
          _status = 'Unexpected error: $error';
        });
      }
    }));
  }

  Future<void> _init() async {
    if (_sub != null) return;
    if (!mounted) return;

    final coordinator = _coordinator;
    if (coordinator == null) return;

    final root = AppScope.of(context);
    try {
      await root.notifications.init();
      if (!mounted) return;

      // Загружаем количество проиндексированных файлов
      await _refreshIndexedCount();
      if (!mounted) return;

      final startResult = await coordinator.start();
      if (!mounted) return;

      if (startResult is CoordinatorStartFailure) {
        root.logger.e('Coordinator start failed', error: startResult.error);
        setState(() {
          _status = 'Ошибка запуска: ${startResult.error.message}';
        });
        return;
      }

      _sub = coordinator.fileAddedEvents.listen(
        (event) {
          root.logger.i('File added: ${event.fileName}');
          if (!mounted) return;
          setState(() {
            _lastFileName = event.fileName;
            _status = 'Новый файл обнаружен';
          });

          // Показываем диалог описания файла
          _showDescriptionDialog(event);
        },
        onError: (Object error, StackTrace st) {
          root.logger.e('Stream error in UI', error: error, stackTrace: st);
          if (!mounted) return;
          setState(() {
            _status = 'Ошибка наблюдения: ${_extractErrorMessage(error)}';
          });
        },
      );

      // Подписываемся на события удаления
      _removedSub = coordinator.fileRemovedEvents.listen(
        (event) {
          root.logger.i('File removed: ${event.fileName}');
          unawaited(_onFileRemoved(event));
        },
      );

      // Подписываемся на смену папки наблюдения
      _watchPathChangedSub = coordinator.watchPathChangedEvents.listen(
        (newWatchDir) {
          root.logger.i('Watch path changed to: $newWatchDir');
          if (!mounted) return;
          setState(() {
            _status = 'Папка изменена. Ожидаю файлы…';
            _lastFileName = null;
            _indexedCount = 0;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _status = 'Готово. Ожидаю файлы…';
      });
    } catch (e, st) {
      root.logger.e('Init failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка инициализации: $e';
      });
    }
  }

  /// Показывает диалог ввода описания для нового файла.
  Future<void> _showDescriptionDialog(FileAddedUiEvent event) async {
    if (!mounted) return;

    // Не индексируем файлы без пути
    final filePath = event.fullPath;
    if (filePath == null || filePath.isEmpty) {
      final root = AppScope.of(context);
      root.logger.w('Skipping file with empty path: ${event.fileName}');
      return;
    }

    // Если диалог уже открыт, добавляем файл в очередь
    if (_isDescriptionDialogOpen) {
      _pendingFiles.add(event);
      return;
    }
    _isDescriptionDialogOpen = true;

    final root = AppScope.of(context);
    try {
      final result = await FileDescriptionDialog.show(
        context,
        fileName: event.fileName,
        filePath: filePath,
      );

      if (result == null) {
        // Пользователь закрыл диалог — индексируем с пустым описанием
        root.logger.d('Description dialog dismissed for ${event.fileName}');
        return;
      }

      // Индексируем файл с описанием
      final success = await root.indexer.indexFile(
        result.filePath,
        fileName: result.fileName,
        description: result.description,
      );

      if (!mounted) return;

      if (success) {
        root.logger.i('File indexed: ${result.fileName}');
        // Запускаем обогащение после индексации — гарантируем, что строка
        // в БД уже существует, и updateTextContent не потеряет текст.
        root.contentEnrichmentCoordinator.enqueueFile(
          result.filePath,
          result.fileName,
        );
        await _refreshIndexedCount();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл проиндексирован: ${result.fileName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        root.logger.w('Failed to index file: ${result.fileName}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка индексации: ${result.fileName}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isDescriptionDialogOpen = false;
      // Обрабатываем следующий файл из очереди
      _processNextPendingFile();
    }
  }

  /// Обрабатывает следующий файл из очереди ожидающих.
  void _processNextPendingFile() {
    if (_pendingFiles.isEmpty) return;
    final nextEvent = _pendingFiles.removeAt(0);
    _showDescriptionDialog(nextEvent);
  }

  /// Обрабатывает событие удаления файла — удаляет из индекса.
  Future<void> _onFileRemoved(FileRemovedUiEvent event) async {
    if (!mounted) return;

    final filePath = event.fullPath;
    if (filePath == null || filePath.isEmpty) return;

    final root = AppScope.of(context);
    try {
      await root.indexer.removeFromIndex(filePath);
      root.logger.i('File removed from index: ${event.fileName}');
      await _refreshIndexedCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Файл удалён из индекса: ${event.fileName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      root.logger.e(
        'Failed to remove file from index: ${event.fileName}',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Обновить счётчик проиндексированных файлов.
  Future<void> _refreshIndexedCount() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    try {
      final count = await root.indexer.getIndexedCount();
      if (mounted) {
        setState(() {
          _indexedCount = count;
        });
      }
    } catch (e) {
      root.logger.w('Failed to get indexed count', error: e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _removedSub?.cancel();
    _removedSub = null;
    _watchPathChangedSub?.cancel();
    _watchPathChangedSub = null;

    final coordinator = _coordinator;
    if (coordinator != null) {
      unawaited(
        coordinator.stop().then((error) {
          if (error != null) {
            debugPrint('Error during coordinator stop: $error');
          }
        }),
      );
    }

    super.dispose();
  }

  String _extractErrorMessage(Object error) {
    if (error is CoreError) {
      return error.message;
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final root = AppScope.of(context);
    final config = root.configService.currentConfig;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Latera'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Поисковая кнопка — основное CTA
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/search');
                },
                icon: const Icon(Icons.search),
                label: const Text('Найти файл'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // RAG кнопка — «Спроси свою папку»
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: config.isFeatureEffectivelyEnabled(ContentFeature.rag)
                    ? () {
                        Navigator.pushNamed(context, '/rag');
                      }
                    : null,
                icon: const Icon(Icons.psychology),
                label: Text(
                  config.isFeatureEffectivelyEnabled(ContentFeature.rag)
                      ? 'Спроси свою папку'
                      : 'Спроси свою папку (выкл.)',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: theme.textTheme.titleSmall,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Статус
            Text(_status, style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 12),

            // Карточки с информацией
            Row(
              children: [
                // Проиндексировано файлов
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 24,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_indexedCount',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Файлов в индексе',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Последний файл
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 24,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lastFileName ?? '—',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            'Последний файл',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Папка наблюдения
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Папка наблюдения',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            config.watchPath ?? 'Не настроена',
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

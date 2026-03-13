import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/file_events_coordinator.dart';
import '../domain/app_config.dart';
import '../domain/core_error.dart';
import '../domain/feature_flags.dart';
import '../domain/license.dart';
import 'app_scope.dart';
import 'processing_status_bar.dart';
import 'widgets/license_badge.dart';

/// Главный экран.
///
/// Показывает статус наблюдения за папкой, количество проиндексированных
/// файлов и предоставляет доступ к поиску и настройкам.
/// Новые файлы тихо индексируются в Inbox (без всплывающих окон).
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
  StreamSubscription<AppConfig>? _configSub;
  String _status = 'Инициализация…';
  String? _lastFileName;
  int _indexedCount = 0;
  int _inboxCount = 0;
  bool _initialized = false;
  Timer? _refreshDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _coordinator = AppScope.of(context).fileEventsCoordinator;

    // Подписываемся на изменения конфигурации, чтобы UI обновлялся
    // при переключении фич (напр. RAG) в настройках.
    _configSub = AppScope.of(context).configService.configChanges.listen((_) {
      if (mounted) setState(() {});
    });

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

      // Загружаем количество проиндексированных файлов и inbox
      await _refreshIndexedCount();
      await _refreshInboxCount();
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

          // Тихо индексируем файл в Inbox (без всплывающих окон)
          unawaited(_silentlyIndexForReview(event));
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

      // Одноразовое уведомление о слабом ПК
      unawaited(_showLowRamNotificationIfNeeded());
    } catch (e, st) {
      root.logger.e('Init failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка инициализации: $e';
      });
    }
  }

  /// Тихо индексирует файл для последующего ревью в Inbox.
  ///
  /// Никаких всплывающих окон — файл сразу попадает в индекс
  /// с пометкой «требует внимания».
  Future<void> _silentlyIndexForReview(FileAddedUiEvent event) async {
    if (!mounted) return;

    final filePath = event.fullPath;
    if (filePath == null || filePath.isEmpty) {
      final root = AppScope.of(context);
      root.logger.w('Skipping file with empty path: ${event.fileName}');
      return;
    }

    final root = AppScope.of(context);
    try {
      // Проверка лимита индексации Basic-режима
      if (!root.licenseCoordinator.isPro &&
          !root.licenseCoordinator.isProTrial) {
        final count = await root.indexer.getIndexedCount();
        if (count >= FreeTierLimits.maxIndexedFiles) {
          root.logger.i(
            'Indexing limit reached ($count), skipping: ${event.fileName}',
          );
          return;
        }
      }

      final success = await root.indexer.indexFileForReview(
        filePath,
        fileName: event.fileName,
      );

      if (!mounted) return;

      if (success) {
        root.logger.i('File indexed for review: ${event.fileName}');
        // Запускаем обогащение контента (text extraction, embeddings и т.д.)
        root.contentEnrichmentCoordinator.enqueueFile(
          filePath,
          event.fileName,
        );
        _scheduleCounterRefresh();
      } else {
        root.logger.w('Failed to index file for review: ${event.fileName}');
      }
    } catch (e, st) {
      root.logger.e(
        'Error indexing file for review: ${event.fileName}',
        error: e,
        stackTrace: st,
      );
    }
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
      _scheduleCounterRefresh();
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

  /// Обновить счётчик файлов, требующих внимания.
  Future<void> _refreshInboxCount() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    try {
      final count = await root.indexer.getFilesNeedingReviewCount();
      if (mounted) {
        setState(() {
          _inboxCount = count;
        });
      }
    } catch (e) {
      root.logger.w('Failed to get inbox count', error: e);
    }
  }

  /// Дебаунс обновления счётчиков при массовом добавлении/удалении файлов.
  ///
  /// При burst-событиях (11 файлов за раз) запускает один refresh
  /// через 300 мс после последнего события, вместо 22 синхронных запросов.
  void _scheduleCounterRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () async {
      await _refreshIndexedCount();
      await _refreshInboxCount();
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _sub?.cancel();
    _sub = null;
    _removedSub?.cancel();
    _removedSub = null;
    _watchPathChangedSub?.cancel();
    _watchPathChangedSub = null;
    _configSub?.cancel();
    _configSub = null;

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

  /// Показывает одноразовое уведомление, если ПК имеет мало RAM.
  Future<void> _showLowRamNotificationIfNeeded() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    if (!root.isHardwareConstrained) return;

    final prefs = await SharedPreferences.getInstance();
    const key = 'latera_low_ram_notified';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'На вашем ПК обнаружено менее 6 ГБ ОЗУ. Приложение работает в режиме Basic '
          'с отключёнными ресурсоёмкими функциями. Для режима PRO и локального AI '
          'рекомендуется увеличить объём ОЗУ.',
        ),
        duration: Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          LicenseBadge(licenseCoordinator: root.licenseCoordinator),
          const SizedBox(width: 8),
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

            // Кнопка Inbox — «Требуют внимания»
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.pushNamed(context, '/inbox');
                  // Обновляем счётчики после возврата из Inbox
                  unawaited(_refreshIndexedCount());
                  unawaited(_refreshInboxCount());
                },
                icon: const Icon(Icons.inbox_outlined),
                label: Text(
                  _inboxCount > 0
                      ? 'Требуют внимания ($_inboxCount)'
                      : 'Требуют внимания',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: theme.textTheme.titleSmall,
                  side: _inboxCount > 0
                      ? BorderSide(color: theme.colorScheme.primary, width: 2)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // RAG кнопка — «Спроси свою папку»
            Builder(
              builder: (context) {
                final isBasic = root.licenseCoordinator.currentLicense.mode ==
                    LicenseMode.basic;
                final isEnabled =
                    !isBasic && config.isFeatureEffectivelyEnabled(ContentFeature.rag);

                return Opacity(
                  opacity: isBasic ? 0.5 : 1.0,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isEnabled
                          ? () {
                              Navigator.pushNamed(context, '/rag');
                            }
                          : isBasic
                              ? () {
                                  // В Basic-режиме открываем RAG-экран с заглушкой
                                  Navigator.pushNamed(context, '/rag');
                                }
                              : null,
                      icon: Icon(isBasic ? Icons.lock_outline : Icons.psychology),
                      label: Text(
                        isBasic
                            ? 'Спроси свою папку (PRO)'
                            : config.isFeatureEffectivelyEnabled(ContentFeature.rag)
                                ? 'Спроси свою папку'
                                : 'Спроси свою папку (выкл.)',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Статус
            Text(_status, style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 12),

            // Прогресс обработки файлов (pill + status bar)
            ProcessingStatusBar(
              progressStream:
                  root.contentEnrichmentCoordinator.progressStream,
              initialProgress:
                  root.contentEnrichmentCoordinator.currentProgress,
            ),
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

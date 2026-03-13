import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../application/file_events_coordinator.dart';
import '../../../domain/app_config.dart';
import '../../../domain/core_error.dart';
import '../../../domain/feature_flags.dart';
import '../../app_scope.dart';
import '../../processing_status_bar.dart';

/// Главная страница (Windows-версия, встроена в NavigationView).
///
/// Аналог [MainScreen] из Material-версии, но использует fluent_ui виджеты.
/// Не имеет собственного Scaffold/AppBar — встраивается как page в NavigationPane.
class WindowsMainPage extends fluent.StatefulWidget {
  const WindowsMainPage({super.key});

  @override
  fluent.State<WindowsMainPage> createState() => _WindowsMainPageState();
}

class _WindowsMainPageState extends fluent.State<WindowsMainPage> {
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

      _removedSub = coordinator.fileRemovedEvents.listen(
        (event) {
          root.logger.i('File removed: ${event.fileName}');
          unawaited(_onFileRemoved(event));
        },
      );

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

  Future<void> _silentlyIndexForReview(FileAddedUiEvent event) async {
    if (!mounted) return;

    final filePath = event.fullPath;
    if (filePath == null || filePath.isEmpty) return;

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
        root.contentEnrichmentCoordinator.enqueueFile(
          filePath,
          event.fileName,
        );
        _scheduleCounterRefresh();
      }
    } catch (e, st) {
      root.logger.e(
        'Error indexing file for review: ${event.fileName}',
        error: e,
        stackTrace: st,
      );
    }
  }

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
      fluent.displayInfoBar(context, builder: (context, close) {
        return fluent.InfoBar(
          title: Text('Файл удалён из индекса: ${event.fileName}'),
          severity: fluent.InfoBarSeverity.info,
          onClose: close,
        );
      });
    } catch (e, st) {
      root.logger.e(
        'Failed to remove file from index: ${event.fileName}',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _refreshIndexedCount() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    try {
      final count = await root.indexer.getIndexedCount();
      if (mounted) setState(() => _indexedCount = count);
    } catch (e) {
      root.logger.w('Failed to get indexed count', error: e);
    }
  }

  Future<void> _refreshInboxCount() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    try {
      final count = await root.indexer.getFilesNeedingReviewCount();
      if (mounted) setState(() => _inboxCount = count);
    } catch (e) {
      root.logger.w('Failed to get inbox count', error: e);
    }
  }

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
    _sub?.cancel();
    _removedSub?.cancel();
    _watchPathChangedSub?.cancel();
    _configSub?.cancel();

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
    if (error is CoreError) return error.message;
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
    fluent.displayInfoBar(
      context,
      duration: const Duration(seconds: 10),
      builder: (context, close) {
        return fluent.InfoBar(
          title: const Text('Недостаточно ОЗУ'),
          content: const Text(
            'На вашем ПК обнаружено менее 6 ГБ ОЗУ. Приложение работает в режиме Basic '
            'с отключёнными ресурсоёмкими функциями. Для режима PRO и локального AI '
            'рекомендуется увеличить объём ОЗУ.',
          ),
          severity: fluent.InfoBarSeverity.warning,
          onClose: close,
        );
      },
    );
  }

  @override
  Widget build(fluent.BuildContext context) {
    final root = AppScope.of(context);
    final config = root.configService.currentConfig;
    final theme = fluent.FluentTheme.of(context);

    return fluent.ScaffoldPage.scrollable(
      header: fluent.PageHeader(
        title: const Text('Главная'),
      ),
      children: [
        // Статус
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _status,
            style: theme.typography.body?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ),

        // Прогресс обработки файлов
        ProcessingStatusBar(
          progressStream:
              root.contentEnrichmentCoordinator.progressStream,
          initialProgress:
              root.contentEnrichmentCoordinator.currentProgress,
        ),

        const SizedBox(height: 16),

        // Карточки с информацией
        Row(
          children: [
            // Проиндексировано файлов
            Expanded(
              child: fluent.Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 24,
                      color: theme.accentColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_indexedCount',
                      style: theme.typography.title?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Файлов в индексе',
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Требуют внимания
            Expanded(
              child: fluent.Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 24,
                      color: _inboxCount > 0
                          ? theme.accentColor
                          : theme.inactiveColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_inboxCount',
                      style: theme.typography.title?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Требуют внимания',
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Последний файл
            Expanded(
              child: fluent.Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 24,
                      color: theme.inactiveColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastFileName ?? '—',
                      style: theme.typography.body?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      'Последний файл',
                      style: theme.typography.caption,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Папка наблюдения
        fluent.Card(
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 20,
                color: theme.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Папка наблюдения',
                      style: theme.typography.caption,
                    ),
                    Text(
                      config.watchPath ?? 'Не настроена',
                      style: theme.typography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

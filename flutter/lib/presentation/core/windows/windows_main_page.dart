import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../application/file_events_coordinator.dart';
import '../../../domain/app_config.dart';
import '../../../domain/core_error.dart';
import '../../../domain/feature_flags.dart';
import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../model_download_failure_banner.dart';
import '../../processing_status_bar.dart';

// ---------------------------------------------------------------------------
// Status semantic model — translated in build() so language switches instantly
// ---------------------------------------------------------------------------

sealed class _HomeStatus {
  const _HomeStatus();
}

final class _HomeStatusInitializing extends _HomeStatus {
  const _HomeStatusInitializing();
}

final class _HomeStatusReady extends _HomeStatus {
  const _HomeStatusReady();
}

final class _HomeStatusNewFile extends _HomeStatus {
  const _HomeStatusNewFile();
}

final class _HomeStatusFolderChanged extends _HomeStatus {
  const _HomeStatusFolderChanged();
}

final class _HomeStatusWatchError extends _HomeStatus {
  const _HomeStatusWatchError(this.message);
  final String message;
}

final class _HomeStatusStartError extends _HomeStatus {
  const _HomeStatusStartError(this.message);
  final String message;
}

final class _HomeStatusInitError extends _HomeStatus {
  const _HomeStatusInitError(this.message);
  final String message;
}

/// Главная страница (Windows-версия, встроена в NavigationView).
///
/// Аналог [MainScreen] из Material-версии, но использует fluent_ui виджеты.
/// Не имеет собственного Scaffold/AppBar — встраивается как page в NavigationPane.
class WindowsMainPage extends fluent.StatefulWidget {
  const WindowsMainPage({super.key});

  @override
  fluent.State<WindowsMainPage> createState() => _WindowsMainPageState();
}

class _WindowsMainPageState extends fluent.State<WindowsMainPage>
    with WindowListener {
  FileEventsCoordinator? _coordinator;

  StreamSubscription<FileAddedUiEvent>? _sub;
  StreamSubscription<FileRemovedUiEvent>? _removedSub;
  StreamSubscription<String>? _watchPathChangedSub;
  StreamSubscription<AppConfig>? _configSub;
  _HomeStatus _status = const _HomeStatusInitializing();
  bool _windowWasHidden = false;
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

    windowManager.addListener(this);
    _coordinator = AppScope.of(context).fileEventsCoordinator;

    _configSub = AppScope.of(context).configService.configChanges.listen((_) {
      if (mounted) setState(() {});
    });

    unawaited(
      _init().catchError((Object error, StackTrace st) {
        debugPrint('Unexpected error in _init(): $error\n$st');
        if (mounted) {
          setState(() {
            _status = _HomeStatusInitError(error.toString());
          });
        }
      }),
    );
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

      // Подписываемся на broadcast-потоки событий координатора.
      _sub = coordinator.fileAddedEvents.listen(
        (event) {
          root.logger.i('File added: ${event.fileName}');
          if (!mounted) return;
          setState(() {
            _lastFileName = event.fileName;
            _status = const _HomeStatusNewFile();
          });
          unawaited(_silentlyIndexForReview(event));
        },
        onError: (Object error, StackTrace st) {
          root.logger.e('Stream error in UI', error: error, stackTrace: st);
          if (!mounted) return;
          setState(() {
            _status = _HomeStatusWatchError(_extractErrorMessage(error));
          });
        },
      );

      _removedSub = coordinator.fileRemovedEvents.listen((event) {
        root.logger.i('File removed: ${event.fileName}');
        unawaited(_onFileRemoved(event));
      });

      _watchPathChangedSub = coordinator.watchPathChangedEvents.listen((
        newWatchDir,
      ) {
        root.logger.i('Watch path changed to: $newWatchDir');
        if (!mounted) return;
        setState(() {
          _status = const _HomeStatusFolderChanged();
          _lastFileName = null;
          _indexedCount = 0;
        });
      });

      // Если координатор уже запущен (напр. после возврата на вкладку),
      // не перезапускаем — просто обновляем счётчики.
      if (coordinator.isRunning) {
        await _refreshIndexedCount();
        await _refreshInboxCount();
        if (!mounted) return;
        setState(() {
          _status = const _HomeStatusReady();
        });
      } else {
        final startResult = await coordinator.start();
        if (!mounted) return;

        if (startResult is CoordinatorStartFailure) {
          root.logger.e('Coordinator start failed', error: startResult.error);
          setState(() {
            _status = _HomeStatusStartError(startResult.error.message);
          });
          return;
        }

        // Обновляем счётчики после initial scan (который происходит внутри start()).
        await _refreshIndexedCount();
        await _refreshInboxCount();

        if (!mounted) return;
        setState(() {
          _status = const _HomeStatusReady();
        });
      }

      // Одноразовое уведомление о слабом ПК
      unawaited(_showLowRamNotificationIfNeeded());
    } catch (e, st) {
      root.logger.e('Init failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _status = _HomeStatusInitError(e.toString());
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
        root.contentEnrichmentCoordinator.enqueueFile(filePath, event.fileName);
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
      fluent.displayInfoBar(
        context,
        builder: (context, close) {
          return fluent.InfoBar(
            title: Text(
              AppLocalizations.of(
                context,
              )!.homeFileRemovedFromIndex(event.fileName),
            ),
            severity: fluent.InfoBarSeverity.info,
            onClose: close,
          );
        },
      );
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
    windowManager.removeListener(this);
    // НЕ останавливаем coordinator — его жизненный цикл привязан к AppScope,
    // а не к этой странице. При навигации между вкладками координатор
    // продолжает работать, чтобы не пересканировать файлы при возврате.
    super.dispose();
  }

  String _extractErrorMessage(Object error) {
    if (error is CoreError) return error.message;
    return error.toString();
  }

  // === WindowListener ===

  /// X нажат — TrayService скроет окно в трей. Помечаем, чтобы при
  /// восстановлении обновить счётчики файлов.
  @override
  void onWindowClose() {
    _windowWasHidden = true;
  }

  /// Окно получило фокус — если до этого было скрыто через трей, обновляем счётчики файлов.
  @override
  void onWindowFocus() {
    if (!_initialized || !mounted || !_windowWasHidden) return;
    _windowWasHidden = false;
    _scheduleCounterRefresh();
  }

  String _localizeStatus(AppLocalizations l10n) => switch (_status) {
    _HomeStatusInitializing() => l10n.homeStatusInitializing,
    _HomeStatusReady() => l10n.homeStatusReady,
    _HomeStatusNewFile() => l10n.homeStatusNewFileDetected,
    _HomeStatusFolderChanged() => l10n.homeStatusFolderChanged,
    _HomeStatusWatchError(:final message) => l10n.homeStatusWatchError(message),
    _HomeStatusStartError(:final message) => l10n.homeStatusStartError(message),
    _HomeStatusInitError(:final message) => l10n.homeStatusInitError(message),
  };

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
          title: Text(AppLocalizations.of(context)!.homeLowRamTitle),
          content: Text(AppLocalizations.of(context)!.homeLowRamBody),
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

    final l10n = AppLocalizations.of(context)!;

    return fluent.ScaffoldPage.scrollable(
      header: fluent.PageHeader(title: Text(l10n.homeTitle)),
      children: [
        // Статус
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _localizeStatus(l10n),
            style: theme.typography.body?.copyWith(color: theme.inactiveColor),
          ),
        ),

        // Прогресс обработки файлов
        ProcessingStatusBar(
          progressStream: root.contentEnrichmentCoordinator.progressStream,
          initialProgress: root.contentEnrichmentCoordinator.currentProgress,
        ),
        const SizedBox(height: 8),

        // Баннер ошибки загрузки AI-модели (если есть)
        const ModelDownloadFailureBanner(),
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
                      l10n.homeFilesInIndex,
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
                      l10n.homeNeedsAttention,
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
                    Text(l10n.homeLastFile, style: theme.typography.caption),
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
              Icon(Icons.folder_outlined, size: 20, color: theme.accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.homeWatchFolder, style: theme.typography.caption),
                    Text(
                      config.watchPath ?? l10n.homeNotConfigured,
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../application/file_events_coordinator.dart';
import '../domain/core_error.dart';
import 'app_scope.dart';

/// Главный экран.
///
/// В текущей foundation-версии watcher — заглушка.
/// После добавления Rust toolchain будет подключён реальный stream из Rust
/// через flutter_rust_bridge.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  FileEventsCoordinator? _coordinator;

  StreamSubscription<FileAddedUiEvent>? _sub;
  String _status = 'Инициализация…';
  String? _lastFileName;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Защита от повторной инициализации (didChangeDependencies может вызываться多次)
    if (_initialized) return;
    _initialized = true;

    // Получаем Composition Root из AppScope
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
    // Защита от повторной инициализации
    if (_sub != null) return;

    // Проверяем mounted перед использованием context
    if (!mounted) return;

    final coordinator = _coordinator;
    if (coordinator == null) {
      // Координатор не инициализирован - не должно происходить при корректном использовании
      return;
    }

    final root = AppScope.of(context);
    try {
      await root.notifications.init();
      
      // Проверяем mounted после первого await
      if (!mounted) return;
      
      final startResult = await coordinator.start();

      // Проверяем mounted после второго await
      if (!mounted) return;

      // Обрабатываем результат запуска координатора
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
            _status = 'Получено событие добавления файла';
          });

          // Foreground UX: быстрый in-app pop-up.
          // Проверяем mounted повторно перед использованием context
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Новый файл: ${event.fileName}')),
          );
        },
        onError: (Object error, StackTrace st) {
          root.logger.e('Stream error in UI', error: error, stackTrace: st);
          if (!mounted) return;
          setState(() {
            _status = 'Ошибка наблюдения: ${_extractErrorMessage(error)}';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _status = 'Готово. Ожидаю события…';
      });
    } catch (e, st) {
      root.logger.e('Init failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка инициализации: $e';
      });
    }
  }

  @override
  void dispose() {
    // Синхронно отменяем подписку (неблокирующая операция)
    _sub?.cancel();
    _sub = null;

    // Останавливаем coordinator (но не dispose - это делается на уровне AppScope)
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

  /// Извлекает читаемое сообщение из ошибки.
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
            // Статус
            Text(_status, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            
            // Информация о папке наблюдения
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Папка наблюдения',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            config.watchPath ?? 'Не настроена',
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            Text('Последний файл: ${_lastFileName ?? '—'}'),
            const SizedBox(height: 24),
            
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      await root.notifications.showFileAdded(fileName: 'test.txt');
                    } catch (e) {
                      root.logger.w('Test notification failed', error: e);
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('Ошибка уведомления: ${_extractErrorMessage(e)}')),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications),
                  label: const Text('Тест уведомления'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/settings');
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Настройки'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

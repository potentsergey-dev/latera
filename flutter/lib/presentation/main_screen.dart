import 'dart:async';

import 'package:flutter/material.dart';

import '../application/file_events_coordinator.dart';
import '../infrastructure/di/app_composition_root.dart';

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
  late final AppCompositionRoot _root;
  late final FileEventsCoordinator _coordinator;

  StreamSubscription<FileAddedUiEvent>? _sub;
  String _status = 'Инициализация…';
  String? _lastFileName;

  @override
  void initState() {
    super.initState();
    _root = AppCompositionRoot.create();
    _coordinator = _root.fileEventsCoordinator;

    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _root.notifications.init();
      final startResult = await _coordinator.start();

      // Обрабатываем результат запуска координатора
      if (startResult is CoordinatorStartFailure) {
        _root.logger.e('Coordinator start failed', error: startResult.error);
        if (!mounted) return;
        setState(() {
          _status = 'Ошибка запуска: ${startResult.error.message}';
        });
        return;
      }

      _sub = _coordinator.fileAddedEvents.listen((event) {
        _root.logger.i('File added: ${event.fileName}');
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
      });

      if (!mounted) return;
      setState(() {
        _status = 'Готово. Ожидаю события…';
      });
    } catch (e, st) {
      _root.logger.e('Init failed', error: e, stackTrace: st);
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

    // Останавливаем coordinator асинхронно с логированием ошибок
    // Используем unawaited + then вместо ignore() для обработки ошибок
    unawaited(
      _coordinator.stop().then((error) {
        if (error != null) {
          _root.logger.w('Error during coordinator stop: $error');
        }
      }),
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latera'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Последний файл: ${_lastFileName ?? '—'}'),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    await _root.notifications.showFileAdded(fileName: 'test.txt');
                  },
                  icon: const Icon(Icons.notifications),
                  label: const Text('Тест уведомления'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

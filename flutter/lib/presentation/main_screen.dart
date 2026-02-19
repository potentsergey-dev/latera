import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

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
  late final Logger _log;
  late final AppCompositionRoot _root;
  late final FileEventsCoordinator _coordinator;

  StreamSubscription<FileAddedUiEvent>? _sub;
  String _status = 'Инициализация…';
  String? _lastFileName;

  @override
  void initState() {
    super.initState();
    _log = Logger();
    _root = AppCompositionRoot.create(logger: _log);
    _coordinator = _root.fileEventsCoordinator;

    unawaited(_init());
  }

  Future<void> _init() async {
    await _root.notifications.init();
    await _coordinator.start();

    _sub = _coordinator.fileAddedEvents.listen((event) {
      _log.i('File added: ${event.fileName}');
      if (!mounted) return;
      setState(() {
        _lastFileName = event.fileName;
        _status = 'Получено событие добавления файла';
      });

      // Foreground UX: быстрый in-app pop-up.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Новый файл: ${event.fileName}')),
      );
    });

    if (!mounted) return;
    setState(() {
      _status = 'Готово. Ожидаю события…';
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_coordinator.stop());
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


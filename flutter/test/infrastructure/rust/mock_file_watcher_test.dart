import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/core_error.dart';
import 'package:latera/domain/file_added_event.dart';
import 'package:latera/domain/file_watcher.dart';

/// Мок для [FileWatcher] с расширенным функционалом для тестирования.
///
/// Используется для тестирования компонентов, зависящих от FileWatcher,
/// без необходимости реального Rust FFI.
class MockFileWatcher implements FileWatcher {
  final StreamController<FileAddedEvent> _controller =
      StreamController<FileAddedEvent>.broadcast();

  bool _isWatching = false;
  String? _currentPath;
  final List<FileAddedEvent> _emittedEvents = [];

  /// Флаг: был ли вызван startWatching.
  @override
  bool get isWatching => _isWatching;

  /// Последний переданный путь.
  String? get currentPath => _currentPath;

  /// Все эмитированные события.
  List<FileAddedEvent> get emittedEvents => List.unmodifiable(_emittedEvents);

  @override
  Stream<FileAddedEvent> get fileAddedEvents => _controller.stream;

  /// Эмулирует обнаружение нового файла.
  void simulateFileAdded({
    required String fileName,
    String? fullPath,
    DateTime? occurredAt,
  }) {
    if (!_isWatching) {
      throw StateError('Watcher is not started');
    }

    final event = FileAddedEvent(
      fileName: fileName,
      fullPath: fullPath ?? '/test/$fileName',
      occurredAt: occurredAt ?? DateTime.now(),
    );

    _emittedEvents.add(event);
    _controller.add(event);
  }

  /// Эмулирует обнаружение нескольких файлов.
  void simulateFilesAdded(List<String> fileNames) {
    for (final fileName in fileNames) {
      simulateFileAdded(fileName: fileName);
    }
  }

  @override
  Future<WatchResult> startWatching({String? overridePath}) async {
    if (_isWatching) {
      return WatchFailure(WatcherError.alreadyRunning());
    }
    _isWatching = true;
    _currentPath = overridePath;
    return WatchSuccess(overridePath ?? '/mock/watch/dir');
  }

  @override
  Future<CoreError?> stopWatching() async {
    _isWatching = false;
    _currentPath = null;
    return null;
  }

  /// Закрывает стрим контроллер.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Сбрасывает состояние мока.
  void reset() {
    _isWatching = false;
    _currentPath = null;
    _emittedEvents.clear();
  }
}

void main() {
  group('MockFileWatcher', () {
    late MockFileWatcher mockWatcher;

    setUp(() {
      mockWatcher = MockFileWatcher();
    });

    tearDown(() async {
      await mockWatcher.dispose();
    });

    group('startWatching', () {
      test('should set isWatching to true', () async {
        final result = await mockWatcher.startWatching();
        expect(mockWatcher.isWatching, true);
        expect(result, isA<WatchSuccess>());
      });

      test('should store override path', () async {
        final result =
            await mockWatcher.startWatching(overridePath: '/custom/path');
        expect(mockWatcher.currentPath, '/custom/path');
        expect(result, isA<WatchSuccess>());
        expect((result as WatchSuccess).watchDir, '/custom/path');
      });

      test('should return failure if already watching', () async {
        await mockWatcher.startWatching();
        final result = await mockWatcher.startWatching();
        expect(result, isA<WatchFailure>());
        expect((result as WatchFailure).error, isA<WatcherError>());
      });
    });

    group('stopWatching', () {
      test('should set isWatching to false', () async {
        await mockWatcher.startWatching();
        final error = await mockWatcher.stopWatching();
        expect(mockWatcher.isWatching, false);
        expect(error, isNull);
      });

      test('should clear current path', () async {
        await mockWatcher.startWatching(overridePath: '/test/path');
        await mockWatcher.stopWatching();
        expect(mockWatcher.currentPath, isNull);
      });
    });

    group('simulateFileAdded', () {
      test('should emit event to stream', () async {
        await mockWatcher.startWatching();

        final events = <FileAddedEvent>[];
        final subscription = mockWatcher.fileAddedEvents.listen(events.add);

        mockWatcher.simulateFileAdded(fileName: 'test.txt');

        await Future.delayed(const Duration(milliseconds: 10));

        expect(events.length, 1);
        expect(events.first.fileName, 'test.txt');

        await subscription.cancel();
      });

      test('should throw if not watching', () {
        expect(
          () => mockWatcher.simulateFileAdded(fileName: 'test.txt'),
          throwsA(isA<StateError>()),
        );
      });

      test('should store emitted events', () async {
        await mockWatcher.startWatching();

        mockWatcher.simulateFileAdded(fileName: 'file1.txt');
        mockWatcher.simulateFileAdded(fileName: 'file2.txt');

        expect(mockWatcher.emittedEvents.length, 2);
        expect(
          mockWatcher.emittedEvents.map((e) => e.fileName),
          ['file1.txt', 'file2.txt'],
        );
      });

      test('should use custom fullPath if provided', () async {
        await mockWatcher.startWatching();

        mockWatcher.simulateFileAdded(
          fileName: 'test.txt',
          fullPath: '/custom/path/test.txt',
        );

        expect(
          mockWatcher.emittedEvents.first.fullPath,
          '/custom/path/test.txt',
        );
      });

      test('should use custom occurredAt if provided', () async {
        await mockWatcher.startWatching();

        final customTime = DateTime(2024, 1, 15, 10, 30);
        mockWatcher.simulateFileAdded(
          fileName: 'test.txt',
          occurredAt: customTime,
        );

        expect(mockWatcher.emittedEvents.first.occurredAt, customTime);
      });
    });

    group('simulateFilesAdded', () {
      test('should emit multiple events', () async {
        await mockWatcher.startWatching();

        final events = <FileAddedEvent>[];
        final subscription = mockWatcher.fileAddedEvents.listen(events.add);

        mockWatcher.simulateFilesAdded(['file1.txt', 'file2.txt', 'file3.txt']);

        await Future.delayed(const Duration(milliseconds: 10));

        expect(events.length, 3);

        await subscription.cancel();
      });
    });

    group('reset', () {
      test('should clear all state', () async {
        await mockWatcher.startWatching(overridePath: '/test');
        mockWatcher.simulateFileAdded(fileName: 'test.txt');

        mockWatcher.reset();

        expect(mockWatcher.isWatching, false);
        expect(mockWatcher.currentPath, isNull);
        expect(mockWatcher.emittedEvents, isEmpty);
      });
    });

    group('broadcast stream', () {
      test('should support multiple listeners', () async {
        await mockWatcher.startWatching();

        final events1 = <FileAddedEvent>[];
        final events2 = <FileAddedEvent>[];

        final sub1 = mockWatcher.fileAddedEvents.listen(events1.add);
        final sub2 = mockWatcher.fileAddedEvents.listen(events2.add);

        mockWatcher.simulateFileAdded(fileName: 'test.txt');

        await Future.delayed(const Duration(milliseconds: 10));

        expect(events1.length, 1);
        expect(events2.length, 1);

        await sub1.cancel();
        await sub2.cancel();
      });
    });
  });

  group('FileWatcher interface contract', () {
    test('FileWatcher should be an interface', () {
      // Проверяем, что MockFileWatcher реализует FileWatcher
      final FileWatcher watcher = MockFileWatcher();
      expect(watcher, isA<FileWatcher>());
    });

    test('fileAddedEvents should be a broadcast stream', () async {
      final watcher = MockFileWatcher();
      await watcher.startWatching();

      // Broadcast stream позволяет множественные подписки
      final sub1 = watcher.fileAddedEvents.listen((_) {});
      final sub2 = watcher.fileAddedEvents.listen((_) {});

      // Не должно бросить исключение
      await sub1.cancel();
      await sub2.cancel();
      await watcher.stopWatching();
      await watcher.dispose();
    });
  });
}

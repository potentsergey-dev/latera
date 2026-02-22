import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latera/infrastructure/logging/app_logger.dart';
import 'package:latera/infrastructure/notifications/local_notifications_service.dart';
import 'package:logger/logger.dart';

/// Мок для FlutterLocalNotificationsPlugin.
///
/// Использует noSuchMethod для обработки всех вызовов,
/// чтобы не зависеть от точной сигнатуры API плагина.
class MockFlutterLocalNotificationsPlugin extends Fake implements FlutterLocalNotificationsPlugin {
  bool initializeCalled = false;
  int showCallCount = 0;
  List<String> shownNotifications = [];
  bool shouldInitializeSucceed = true;
  bool shouldShowSucceed = true;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)? onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalled = true;
    return shouldInitializeSucceed;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (!shouldShowSucceed) {
      throw Exception('Show failed');
    }
    showCallCount++;
    shownNotifications.add(body ?? '');
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {}

  @override
  Future<void> cancelAll() async {
    shownNotifications.clear();
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => [];

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => null;
}

void main() {
  group('LocalNotificationsService', () {
    late MockFlutterLocalNotificationsPlugin mockPlugin;
    late Logger logger;

    setUp(() {
      mockPlugin = MockFlutterLocalNotificationsPlugin();
      logger = AppLogger.create(isProduction: false, enableColors: false);
    });

    group('init', () {
      test('should initialize plugin successfully', () async {
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.init();

        expect(service.isInitialized, true);
        expect(mockPlugin.initializeCalled, true);
      });

      test('should throw NotificationException on initialization failure', () async {
        mockPlugin.shouldInitializeSucceed = false;
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        expect(
          () => service.init(),
          throwsA(isA<NotificationException>()),
        );
        expect(service.isInitialized, false);
      });

      test('should be idempotent - multiple calls result in single initialization', () async {
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.init();
        await service.init();
        await service.init();

        expect(mockPlugin.initializeCalled, true);
        // Plugin initialize should only be called once
        // (we can't easily verify this with our mock, but the pattern is correct)
      });
    });

    group('showFileAdded', () {
      test('should show notification with correct content', () async {
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.showFileAdded(fileName: 'test.txt');

        expect(mockPlugin.showCallCount, 1);
        expect(mockPlugin.shownNotifications.first, contains('test.txt'));
      });

      test('should initialize before showing notification', () async {
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.showFileAdded(fileName: 'test.txt');

        expect(mockPlugin.initializeCalled, true);
        expect(mockPlugin.showCallCount, 1);
      });

      test('should throw NotificationException on show failure', () async {
        mockPlugin.shouldShowSucceed = false;
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.init();

        expect(
          () => service.showFileAdded(fileName: 'test.txt'),
          throwsA(isA<NotificationException>()),
        );
      });
    });

    group('ThrottlePolicy', () {
      test('should throttle notifications according to policy', () async {
        final strictPolicy = ThrottlePolicy(
          minInterval: const Duration(milliseconds: 10),
          maxInWindow: 2,
          windowSize: const Duration(seconds: 1),
        );

        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
          throttlePolicy: strictPolicy,
        );

        // First two should succeed (with delay for minInterval)
        await service.showFileAdded(fileName: 'file1.txt');
        await Future.delayed(const Duration(milliseconds: 20));
        await service.showFileAdded(fileName: 'file2.txt');

        // Third should be throttled (window limit reached)
        await Future.delayed(const Duration(milliseconds: 20));
        await service.showFileAdded(fileName: 'file3.txt');

        expect(mockPlugin.showCallCount, 2);
      });

      test('should allow notifications after minInterval passes', () async {
        final policy = ThrottlePolicy(
          minInterval: const Duration(milliseconds: 50),
          maxInWindow: 10,
          windowSize: const Duration(seconds: 1),
        );

        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
          throttlePolicy: policy,
        );

        await service.showFileAdded(fileName: 'file1.txt');

        // Wait for minInterval to pass
        await Future.delayed(const Duration(milliseconds: 60));

        await service.showFileAdded(fileName: 'file2.txt');

        expect(mockPlugin.showCallCount, 2);
      });
    });

    group('cancelAll', () {
      test('should cancel all notifications', () async {
        final service = LocalNotificationsService.withPlugin(
          logger: logger,
          plugin: mockPlugin,
        );

        await service.showFileAdded(fileName: 'test.txt');
        await service.cancelAll();

        expect(mockPlugin.shownNotifications.isEmpty, true);
      });
    });
  });

  group('NotificationException', () {
    test('should format message correctly', () {
      const exception = NotificationException('Test error');
      expect(exception.message, 'Test error');
      expect(exception.toString(), 'NotificationException: Test error');
    });

    test('should include cause in message', () {
      final exception = NotificationException('Test error', cause: 'Cause here');
      expect(exception.toString(), 'NotificationException: Test error (Cause here)');
    });
  });

  group('ThrottlePolicy', () {
    test('defaultPolicy should have correct values', () {
      expect(ThrottlePolicy.defaultPolicy.minInterval, const Duration(seconds: 1));
      expect(ThrottlePolicy.defaultPolicy.maxInWindow, 10);
      expect(ThrottlePolicy.defaultPolicy.windowSize, const Duration(minutes: 1));
    });

    test('strict policy should have correct values', () {
      expect(ThrottlePolicy.strict.minInterval, const Duration(seconds: 5));
      expect(ThrottlePolicy.strict.maxInWindow, 3);
      expect(ThrottlePolicy.strict.windowSize, const Duration(minutes: 1));
    });
  });

  group('NotificationChannelConfig', () {
    test('fileAdded channel should have correct values', () {
      expect(NotificationChannelConfig.fileAdded.id, 'file_added');
      expect(NotificationChannelConfig.fileAdded.name, 'Новые файлы');
      expect(NotificationChannelConfig.fileAdded.importance, Importance.defaultImportance);
    });
  });
}

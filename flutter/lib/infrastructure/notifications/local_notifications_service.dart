import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import '../../domain/notifications_service.dart';
import '../logging/app_logger.dart';

/// Исключения сервиса уведомлений.
class NotificationException implements Exception {
  final String message;
  final Object? cause;

  const NotificationException(this.message, {this.cause});

  @override
  String toString() => 'NotificationException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Конфигурация каналов уведомлений.
class NotificationChannelConfig {
  final String id;
  final String name;
  final String description;
  final Importance importance;

  const NotificationChannelConfig({
    required this.id,
    required this.name,
    required this.description,
    this.importance = Importance.defaultImportance,
  });

  /// Канал для уведомлений о файлах.
  static const fileAdded = NotificationChannelConfig(
    id: 'file_added',
    name: 'Новые файлы',
    description: 'Уведомления о добавлении новых файлов',
    importance: Importance.defaultImportance,
  );
}

/// Политика троттлинга уведомлений.
class ThrottlePolicy {
  /// Минимальный интервал между уведомлениями одного типа.
  final Duration minInterval;

  /// Максимальное количество уведомлений в окне.
  final int maxInWindow;

  /// Размер окна для подсчёта уведомлений.
  final Duration windowSize;

  const ThrottlePolicy({
    required this.minInterval,
    required this.maxInWindow,
    required this.windowSize,
  });

  /// Дефолтная политика: не более 10 уведомлений в минуту,
  /// минимальный интервал 1 секунда.
  static const defaultPolicy = ThrottlePolicy(
    minInterval: Duration(seconds: 1),
    maxInWindow: 10,
    windowSize: Duration(minutes: 1),
  );

  /// Строгая политика: не более 3 уведомлений в минуту.
  static const strict = ThrottlePolicy(
    minInterval: Duration(seconds: 5),
    maxInWindow: 3,
    windowSize: Duration(minutes: 1),
  );
}

/// Сервис системных уведомлений.
///
/// Инкапсулирует `flutter_local_notifications`, чтобы application слой
/// не зависел от API плагина.
///
/// ## Production-фичи:
/// - Проверка и запрос permissions
/// - Каналы уведомлений (Android/Windows)
/// - Обработка ошибок с детальными сообщениями
/// - Троттлинг для защиты от спама
class LocalNotificationsService implements NotificationsService {
  final Logger _log;
  final FlutterLocalNotificationsPlugin _plugin;
  final ThrottlePolicy _throttlePolicy;

  /// Кешированный Future инициализации — гарантирует, что `_plugin.initialize`
  /// вызывается ровно один раз, даже при параллельных вызовах [init]/[showFileAdded].
  Future<void>? _initFuture;

  /// Флаг успешной инициализации.
  bool _isInitialized = false;

  /// Очередь timestamps для троттлинга.
  final Queue<DateTime> _notificationTimestamps = Queue();

  /// Последний показ уведомления по типу.
  final Map<String, DateTime> _lastNotificationByType = {};

  /// Счётчик для генерации ID уведомлений.
  int _notificationIdCounter = 0;

  LocalNotificationsService({
    required Logger logger,
    ThrottlePolicy? throttlePolicy,
  })  : _log = logger,
        _throttlePolicy = throttlePolicy ?? ThrottlePolicy.defaultPolicy,
        _plugin = FlutterLocalNotificationsPlugin();

  /// Создать сервис с кастомным плагином (для тестов).
  @visibleForTesting
  LocalNotificationsService.withPlugin({
    required Logger logger,
    required FlutterLocalNotificationsPlugin plugin,
    ThrottlePolicy? throttlePolicy,
  })  : _log = logger,
        _plugin = plugin,
        _throttlePolicy = throttlePolicy ?? ThrottlePolicy.defaultPolicy;

  @override
  Future<void> init() {
    if (_isInitialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    final ctx = LogContext.withOperation('notifications.init');

    try {
      // 1. Проверка и запрос permissions
      await _requestPermissions(ctx);

      // 2. Инициализация плагина
      await _initializePlugin(ctx);

      _isInitialized = true;
      _log.infoWithContext('Local notifications initialized', ctx);
    } catch (e, st) {
      _log.errorWithContext('Failed to initialize notifications', ctx, error: e, stackTrace: st);
      // Сбрасываем Future чтобы позволить повторную попытку инициализации
      _initFuture = null;
      throw NotificationException('Не удалось инициализировать уведомления', cause: e);
    }
  }

  Future<void> _requestPermissions(LogContext ctx) async {
    _log.debugWithContext('Requesting notification permissions', ctx);

    // Windows не требует явных permissions.
    // Для Android/iOS/macOS запрашиваем.
    try {
      // Android 13+ требует POST_NOTIFICATIONS permission
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        _log.debugWithContext('Android notification permission: $granted', ctx);
      }

      // iOS/macOS
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        _log.debugWithContext('iOS notification permission: $granted', ctx);
      }

      final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (macos != null) {
        final granted = await macos.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        _log.debugWithContext('macOS notification permission: $granted', ctx);
      }
    } catch (e) {
      // Не критично, если permissions не удалось запросить
      _log.warnWithContext('Could not request permissions (non-critical)', ctx, error: e);
    }
  }

  Future<void> _initializePlugin(LogContext ctx) async {
    // Требования Windows плагина: appName/appUserModelId/guid.
    //
    // appUserModelId должен соответствовать идентификатору приложения.
    // В будущем можно вынести в конфигурацию/брендинг.
    const windows = WindowsInitializationSettings(
      appName: 'Latera',
      appUserModelId: 'com.latera.latera',
      // Постоянный GUID приложения для уведомлений Windows.
      // Можно сгенерировать один раз (например через PowerShell New-Guid).
      guid: '7F4D8B8A-0DB5-4D6B-9F2F-6F4F7D9D9D0E',
    );

    // Android настройки с каналом
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS настройки
    const darwin = DarwinInitializationSettings();

    const settings = InitializationSettings(
      windows: windows,
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    final result = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (result != true) {
      throw NotificationException('Plugin initialization returned false');
    }

    _log.debugWithContext('Plugin initialized successfully', ctx);
  }

  void _onNotificationTapped(NotificationResponse response) {
    final ctx = LogContext.withOperation('notification.tapped');
    _log.infoWithContext(
      'Notification tapped: id=${response.id}, payload=${response.payload}',
      ctx,
    );
  }

  @override
  Future<void> showFileAdded({required String fileName}) async {
    await init();

    final ctx = LogContext.withOperation('notification.showFileAdded');

    // Проверка троттлинга
    if (!_shouldShowNotification('file_added')) {
      _log.debugWithContext('Notification throttled', ctx);
      return;
    }

    try {
      final id = _getNextNotificationId();

      final details = _buildNotificationDetails();

      await _plugin.show(
        id: id,
        title: 'Новый файл добавлен',
        body: 'Новый файл добавлен: $fileName',
        notificationDetails: details,
        payload: 'file_added:$fileName',
      );

      _recordNotification('file_added');
      _log.infoWithContext('Notification shown: $fileName', ctx);
    } catch (e, st) {
      _log.errorWithContext('Failed to show notification', ctx, error: e, stackTrace: st);
      throw NotificationException('Не удалось показать уведомление', cause: e);
    }
  }

  /// Проверить, можно ли показать уведомление (троттлинг).
  bool _shouldShowNotification(String type) {
    final now = DateTime.now();

    // 1. Проверка минимального интервала
    final lastTime = _lastNotificationByType[type];
    if (lastTime != null) {
      final elapsed = now.difference(lastTime);
      if (elapsed < _throttlePolicy.minInterval) {
        return false;
      }
    }

    // 2. Очистка старых timestamps
    final windowStart = now.subtract(_throttlePolicy.windowSize);
    while (_notificationTimestamps.isNotEmpty && _notificationTimestamps.first.isBefore(windowStart)) {
      _notificationTimestamps.removeFirst();
    }

    // 3. Проверка лимита в окне
    if (_notificationTimestamps.length >= _throttlePolicy.maxInWindow) {
      return false;
    }

    return true;
  }

  /// Записать факт показа уведомления.
  void _recordNotification(String type) {
    final now = DateTime.now();
    _notificationTimestamps.add(now);
    _lastNotificationByType[type] = now;
  }

  /// Получить следующий ID уведомления.
  int _getNextNotificationId() {
    _notificationIdCounter = (_notificationIdCounter + 1) % 1000000;
    return _notificationIdCounter;
  }

  /// Построить детали уведомления.
  NotificationDetails _buildNotificationDetails() {
    return NotificationDetails(
      windows: const WindowsNotificationDetails(
        subtitle: 'Latera',
      ),
      android: AndroidNotificationDetails(
        NotificationChannelConfig.fileAdded.id,
        NotificationChannelConfig.fileAdded.name,
        channelDescription: NotificationChannelConfig.fileAdded.description,
        importance: NotificationChannelConfig.fileAdded.importance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  /// Проверить, инициализирован ли сервис.
  bool get isInitialized => _isInitialized;

  /// Отменить все уведомления.
  Future<void> cancelAll() async {
    final ctx = LogContext.withOperation('notification.cancelAll');
    try {
      await _plugin.cancelAll();
      _log.infoWithContext('All notifications cancelled', ctx);
    } catch (e, st) {
      _log.errorWithContext('Failed to cancel notifications', ctx, error: e, stackTrace: st);
    }
  }

  /// Получить количество активных уведомлений (для тестов).
  @visibleForTesting
  int get pendingNotificationCount => _notificationTimestamps.length;
}

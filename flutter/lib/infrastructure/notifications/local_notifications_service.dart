import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

/// Сервис системных уведомлений.
///
/// Инкапсулирует `flutter_local_notifications`, чтобы application слой
/// не зависел от API плагина.
class LocalNotificationsService {
  final Logger _log;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Кешированный Future инициализации — гарантирует, что `_plugin.initialize`
  /// вызывается ровно один раз, даже при параллельных вызовах [init]/[showFileAdded].
  Future<void>? _initFuture;

  LocalNotificationsService({required Logger logger}) : _log = logger;

  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
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
    const settings = InitializationSettings(windows: windows);

    await _plugin.initialize(settings: settings);
    _log.i('Local notifications initialized');
  }

  Future<void> showFileAdded({required String fileName}) async {
    await init();

    const details = NotificationDetails(
      windows: WindowsNotificationDetails(),
    );

    await _plugin.show(
      id: 1,
      title: 'Новый файл добавлен',
      body: 'Новый файл добавлен: $fileName',
      notificationDetails: details,
    );
  }
}

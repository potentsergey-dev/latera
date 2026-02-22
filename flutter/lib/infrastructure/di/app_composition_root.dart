import 'package:logger/logger.dart';

import '../../application/file_events_coordinator.dart';
import '../../application/license_coordinator.dart';
import '../../domain/app_config.dart';
import '../../domain/feature_flags.dart';
import '../../domain/file_watcher.dart';
import '../../domain/license_service.dart';
import '../../domain/notifications_service.dart';
import '../config/stub_config_service.dart';
import '../licensing/stub_feature_flags.dart';
import '../licensing/stub_license_service.dart';
import '../logging/app_logger.dart';
import '../notifications/local_notifications_service.dart';
import '../rust/rust_file_watcher_frb.dart';

/// Конфигурация окружения приложения.
enum AppEnvironment {
  development,
  production,
}

/// Composition Root (точка сборки зависимостей).
///
/// Централизованная точка создания и конфигурации всех зависимостей приложения.
/// Следует принципу Dependency Injection через конструктор.
class AppCompositionRoot {
  // === Domain Services ===
  final NotificationsService notifications;
  final FileWatcher fileWatcher;
  final LicenseService licenseService;
  final FeatureFlags featureFlags;
  final ConfigService configService;

  // === Application Coordinators ===
  final FileEventsCoordinator fileEventsCoordinator;
  final LicenseCoordinator licenseCoordinator;

  // === Infrastructure ===
  final Logger logger;

  AppCompositionRoot._({
    required this.notifications,
    required this.fileWatcher,
    required this.licenseService,
    required this.featureFlags,
    required this.configService,
    required this.fileEventsCoordinator,
    required this.licenseCoordinator,
    required this.logger,
  });

  /// Создать Composition Root с настройками окружения.
  ///
  /// [environment] — окружение (development/production).
  /// [enableLogColors] — цветной вывод логов (отключить для CI).
  ///
  /// Точки расширения для Free/Pro:
  /// - LicenseService: определяет доступные функции
  /// - FeatureFlags: проверяет доступность по ID
  /// - ConfigService: хранит пользовательские настройки
  static AppCompositionRoot create({
    AppEnvironment environment = AppEnvironment.development,
    bool enableLogColors = true,
  }) {
    final isProduction = environment == AppEnvironment.production;

    // === Infrastructure Layer ===
    final logger = AppLogger.create(
      isProduction: isProduction,
      enableColors: enableLogColors,
    );

    // Domain services (interfaces)
    final notifications = LocalNotificationsService(logger: logger);
    final watcher = RustFileWatcherFrb(logger: logger);

    // Licensing & Configuration (stub implementations)
    final licenseService = StubLicenseService(logger: logger);
    final featureFlags = StubFeatureFlags(
      logger: logger,
      licenseService: licenseService,
    );
    final configService = StubConfigService(logger: logger);

    // === Application Layer ===
    final fileEventsCoordinator = FileEventsCoordinator(
      logger: logger,
      watcher: watcher,
      notifications: notifications,
    );

    final licenseCoordinator = LicenseCoordinator(
      logger: logger,
      licenseService: licenseService,
      featureFlags: featureFlags,
    );

    return AppCompositionRoot._(
      notifications: notifications,
      fileWatcher: watcher,
      licenseService: licenseService,
      featureFlags: featureFlags,
      configService: configService,
      fileEventsCoordinator: fileEventsCoordinator,
      licenseCoordinator: licenseCoordinator,
      logger: logger,
    );
  }

  /// Освободить ресурсы.
  Future<void> dispose() async {
    logger.i('Disposing AppCompositionRoot');

    // Останавливаем coordinator первым (останавливает watcher и закрывает streams)
    await fileEventsCoordinator.stop();

    // Dispose stub services
    if (licenseService is StubLicenseService) {
      (licenseService as StubLicenseService).dispose();
    }
    if (featureFlags is StubFeatureFlags) {
      (featureFlags as StubFeatureFlags).dispose();
    }
    if (configService is StubConfigService) {
      (configService as StubConfigService).dispose();
    }
  }
}

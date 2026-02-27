import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/file_events_coordinator.dart';
import '../../application/license_coordinator.dart';
import '../../domain/app_config.dart';
import '../../domain/feature_flags.dart';
import '../../domain/file_watcher.dart';
import '../../domain/indexer.dart';
import '../../domain/license_service.dart';
import '../../domain/notifications_service.dart';
import '../../domain/search_repository.dart';
import '../config/shared_preferences_config_service.dart';
import '../licensing/stub_feature_flags.dart';
import '../licensing/stub_license_service.dart';
import '../logging/app_logger.dart';
import '../notifications/local_notifications_service.dart';
import '../rust/rust_file_watcher_frb.dart';
import '../search/sqlite_index_service.dart';

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
  final Indexer indexer;
  final SearchRepository searchRepository;

  // === Application Coordinators ===
  final FileEventsCoordinator fileEventsCoordinator;
  final LicenseCoordinator licenseCoordinator;

  // === Infrastructure ===
  final Logger logger;

  /// Ссылка на SqliteIndexService для dispose.
  final SqliteIndexService? _sqliteIndexService;

  bool _isDisposed = false;

  AppCompositionRoot._({
    required this.notifications,
    required this.fileWatcher,
    required this.licenseService,
    required this.featureFlags,
    required this.configService,
    required this.indexer,
    required this.searchRepository,
    required this.fileEventsCoordinator,
    required this.licenseCoordinator,
    required this.logger,
    SqliteIndexService? sqliteIndexService,
  }) : _sqliteIndexService = sqliteIndexService;

  /// Создать Composition Root с настройками окружения.
  ///
  /// [environment] — окружение (development/production).
  /// [enableLogColors] — цветной вывод логов (отключить для CI).
  ///
  /// Точки расширения для Free/Pro:
  /// - LicenseService: определяет доступные функции
  /// - FeatureFlags: проверяет доступность по ID
  /// - ConfigService: хранит пользовательские настройки
  ///
  /// Асинхронный метод, так как требует инициализации SharedPreferences.
  static Future<AppCompositionRoot> create({
    AppEnvironment environment = AppEnvironment.development,
    bool enableLogColors = true,
  }) async {
    final isProduction = environment == AppEnvironment.production;

    // === Infrastructure Layer ===
    final logger = AppLogger.create(
      isProduction: isProduction,
      enableColors: enableLogColors,
    );

    // Domain services (interfaces)
    final notifications = LocalNotificationsService(logger: logger);
    final watcher = RustFileWatcherFrb(logger: logger);

    // Licensing (stub implementations)
    final licenseService = StubLicenseService(logger: logger);
    final featureFlags = StubFeatureFlags(
      logger: logger,
      licenseService: licenseService,
    );

    // Configuration (persistent implementation)
    final configService = SharedPreferencesConfigService(logger: logger);
    await configService.initialize();
    await configService.load();

    // SQLite FTS5 Index Service (implements both Indexer and SearchRepository)
    final appDataDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDataDir.path, 'Latera', 'index', 'latera_index.db');
    final sqliteIndexService = SqliteIndexService(
      logger: logger,
      dbPath: dbPath,
    );
    await sqliteIndexService.initialize();

    // === Application Layer ===
    final fileEventsCoordinator = FileEventsCoordinator(
      logger: logger,
      watcher: watcher,
      notifications: notifications,
      configService: configService,
      indexer: sqliteIndexService,
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
      indexer: sqliteIndexService,
      searchRepository: sqliteIndexService,
      fileEventsCoordinator: fileEventsCoordinator,
      licenseCoordinator: licenseCoordinator,
      logger: logger,
      sqliteIndexService: sqliteIndexService,
    );
  }

  /// Освободить ресурсы.
  ///
  /// Безопасен для многократного вызова — последующие вызовы игнорируются.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    logger.i('Disposing AppCompositionRoot');

    // Dispose coordinator (останавливает watcher и закрывает streams)
    await fileEventsCoordinator.dispose();

    // Dispose SQLite index service
    _sqliteIndexService?.dispose();

    // Dispose stub services
    if (licenseService is StubLicenseService) {
      (licenseService as StubLicenseService).dispose();
    }
    if (featureFlags is StubFeatureFlags) {
      (featureFlags as StubFeatureFlags).dispose();
    }
    // Dispose config service
    if (configService is SharedPreferencesConfigService) {
      (configService as SharedPreferencesConfigService).dispose();
    }
  }
}

import 'package:logger/logger.dart';

import '../../application/file_events_coordinator.dart';
import '../../domain/file_watcher.dart';
import '../notifications/local_notifications_service.dart';
import '../rust/rust_file_watcher_frb.dart';

/// Composition Root (точка сборки зависимостей).
class AppCompositionRoot {
  final LocalNotificationsService notifications;
  final FileWatcher fileWatcher;
  final FileEventsCoordinator fileEventsCoordinator;

  AppCompositionRoot._({
    required this.notifications,
    required this.fileWatcher,
    required this.fileEventsCoordinator,
  });

  static AppCompositionRoot create({required Logger logger}) {
    final notifications = LocalNotificationsService(logger: logger);
    final watcher = RustFileWatcherFrb(logger: logger);

    final coordinator = FileEventsCoordinator(
      logger: logger,
      watcher: watcher,
      notifications: notifications,
    );

    return AppCompositionRoot._(
      notifications: notifications,
      fileWatcher: watcher,
      fileEventsCoordinator: coordinator,
    );
  }
}


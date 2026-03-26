import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/license.dart';
import 'package:latera/infrastructure/licensing/local_license_service.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Logger logger;

  setUp(() {
    logger = Logger(level: Level.off);
  });

  group('LocalLicenseService', () {
    test('first launch sets install date and returns proTrial', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      final license = service.currentLicense;
      expect(license.mode, LicenseMode.proTrial);
      expect(license.isPro, isTrue);
      expect(license.isProTrial, isTrue);
      expect(license.isFree, isFalse);
      expect(license.trialExpiresAt, isNotNull);
    });

    test('install date 4 days ago returns basic', () async {
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));
      SharedPreferences.setMockInitialValues({
        'latera_install_date': fourDaysAgo.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      final license = service.currentLicense;
      expect(license.mode, LicenseMode.basic);
      expect(license.isPro, isFalse);
      expect(license.isFree, isTrue);
    });

    test('install date 1 day ago returns proTrial', () async {
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'latera_install_date': oneDayAgo.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      final license = service.currentLicense;
      expect(license.mode, LicenseMode.proTrial);
      expect(license.isProTrial, isTrue);
    });

    test('pro purchased returns pro regardless of install date', () async {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({
        'latera_install_date': tenDaysAgo.toIso8601String(),
        'latera_is_pro_purchased': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      final license = service.currentLicense;
      expect(license.mode, LicenseMode.pro);
      expect(license.isPro, isTrue);
      expect(license.isProTrial, isFalse);
      expect(license.isFree, isFalse);
    });

    test('activateProPurchase switches to pro mode', () async {
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));
      SharedPreferences.setMockInitialValues({
        'latera_install_date': fourDaysAgo.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      expect(service.currentLicense.mode, LicenseMode.basic);

      await service.activateProPurchase();

      expect(service.currentLicense.mode, LicenseMode.pro);
      expect(service.currentLicense.isPro, isTrue);
    });

    test('refreshLicense re-computes license and emits on stream', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      final licenses = <License>[];
      service.licenseChanges.listen(licenses.add);

      final refreshed = await service.refreshLicense();
      expect(refreshed.mode, service.currentLicense.mode);
      await Future<void>.delayed(Duration.zero);
      expect(licenses, isNotEmpty);
    });

    test('deactivateLicense removes pro purchase', () async {
      SharedPreferences.setMockInitialValues({
        'latera_install_date':
            DateTime.now().subtract(const Duration(days: 10)).toIso8601String(),
        'latera_is_pro_purchased': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final service = LocalLicenseService(logger: logger, prefs: prefs);
      await service.initialize();

      expect(service.currentLicense.mode, LicenseMode.pro);

      await service.deactivateLicense();

      // Trial expired (10 days ago), so should be basic
      expect(service.currentLicense.mode, LicenseMode.basic);
    });
  });
}

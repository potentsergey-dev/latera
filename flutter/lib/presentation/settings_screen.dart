import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/license_coordinator.dart';
import '../domain/app_config.dart';
import '../domain/license.dart';
import '../infrastructure/licensing/store_purchase_service.dart';
import '../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'widgets/license_badge.dart';

/// Экран настроек приложения.
///
/// Позволяет пользователю:
/// - Выбрать папку для наблюдения
/// - Включить/отключить уведомления
/// - Управлять функциями обработки контента
/// - Включить режим экономии ресурсов
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ConfigService _configService;
  late final LicenseCoordinator _licenseCoordinator;
  late final StorePurchaseService _storePurchaseService;
  AppConfig _config = const AppConfig();
  bool _isLoading = false;
  bool _isPurchasing = false;
  String? _error;
  bool _folderExists = false;
  bool _initialized = false;
  String _appVersion = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _configService = AppScope.of(context).configService;
    _licenseCoordinator = AppScope.of(context).licenseCoordinator;
    _storePurchaseService = AppScope.of(context).storePurchaseService;
    _loadConfig();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    }
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final config = await _configService.load();
      await _checkFolderExists(config.watchPath);
      if (mounted) {
        setState(() {
          _config = config;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkFolderExists(String? path) async {
    if (path == null || path.isEmpty) {
      _folderExists = false;
      return;
    }
    try {
      _folderExists = await FileSystemEntity.isDirectory(path);
    } catch (_) {
      _folderExists = false;
    }
  }

  Future<void> _selectFolder() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.settingsSelectFolder,
        initialDirectory: _config.watchPath,
      );

      if (result != null && mounted) {
        await _configService.updateValue(watchPath: result);
        await _checkFolderExists(result);
        setState(() {
          _config = _config.copyWith(watchPath: result);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.settingsFolderChanged(result))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsFolderPickError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final path = _config.watchPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.settingsFolderNotSelected),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      if (Platform.isWindows) {
        final exists = await Directory(path).exists();
        if (!exists && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.settingsFolderNotExists(path)),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (_containsDangerousChars(path)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.settingsPathDangerousChars),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        await Process.start(
          'explorer.exe',
          [path],
          mode: ProcessStartMode.detached,
        );
      } else {
        final uri = Uri.directory(path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.settingsOpenFolderError(path)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsOpenFolderError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _containsDangerousChars(String path) {
    final dangerousPattern = RegExp(r'[<>|&^"]');
    return dangerousPattern.hasMatch(path);
  }

  Future<void> _toggleNotifications(bool value) async {
    await _configService.updateValue(notificationsEnabled: value);
    setState(() {
      _config = _config.copyWith(notificationsEnabled: value);
    });
  }

  Future<void> _toggleResourceSaver(bool value) async {
    await _configService.updateValue(resourceSaverEnabled: value);
    setState(() {
      _config = _config.copyWith(resourceSaverEnabled: value);
    });
  }

  Future<void> _toggleOfficeDocs(bool value) async {
    await _configService.updateValue(enableOfficeDocs: value);
    setState(() {
      _config = _config.copyWith(enableOfficeDocs: value);
    });
  }

  Future<void> _toggleOcr(bool value) async {
    await _configService.updateValue(enableOcr: value);
    setState(() {
      _config = _config.copyWith(enableOcr: value);
    });
  }

  Future<void> _toggleEmbeddings(bool value) async {
    await _configService.updateValue(enableEmbeddings: value);
    setState(() {
      _config = _config.copyWith(enableEmbeddings: value);
    });
  }

  Future<void> _toggleTranscription(bool value) async {
    await _configService.updateValue(enableTranscription: value);
    setState(() {
      _config = _config.copyWith(enableTranscription: value);
    });
  }

  Future<void> _toggleRag(bool value) async {
    await _configService.updateValue(enableRag: value);
    setState(() {
      _config = _config.copyWith(enableRag: value);
    });
  }

  Future<void> _toggleAutoSummary(bool value) async {
    await _configService.updateValue(enableAutoSummary: value);
    setState(() {
      _config = _config.copyWith(enableAutoSummary: value);
    });
  }

  Future<void> _toggleAutoTags(bool value) async {
    await _configService.updateValue(enableAutoTags: value);
    setState(() {
      _config = _config.copyWith(enableAutoTags: value);
    });
  }

  Future<void> _resetSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsResetConfirmTitle),
        content: Text(l10n.settingsResetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.buttonReset),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _configService.reset();
      await _loadConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsResetDone)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(l10n.settingsLoadError),
                      const SizedBox(height: 8),
                      Text(_error!, 
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadConfig,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.buttonRetry),
                      ),
                    ],
                  ),
                )
              : _buildContent(l10n),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === Папка для наблюдения ===
          _buildSection(
            title: l10n.settingsSectionWatchFolder,
            children: [
              _buildCurrentPathTile(l10n),
              _buildSelectFolderTile(l10n),
              _buildOpenFolderTile(l10n),
            ],
          ),

          const Divider(),

          // === Уведомления ===
          _buildSection(
            title: l10n.settingsSectionNotifications,
            children: [
              _buildNotificationsToggle(l10n),
            ],
          ),

          const Divider(),

          // === Производительность ===
          _buildSection(
            title: l10n.settingsSectionPerformance,
            children: [
              _buildResourceSaverToggle(l10n),
            ],
          ),

          const Divider(),

          // === Обработка содержимого ===
          _buildSection(
            title: l10n.settingsSectionContentProcessing,
            children: [
              _buildContentFeatureToggle(
                icon: Icons.description_outlined,
                title: l10n.settingsTextExtraction,
                subtitle: l10n.settingsTextExtractionHint,
                value: _config.enableOfficeDocs,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs),
                onChanged: _toggleOfficeDocs,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
              _buildContentFeatureToggle(
                icon: Icons.document_scanner_outlined,
                title: l10n.settingsOcr,
                subtitle: l10n.settingsOcrHint,
                value: _config.enableOcr,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.ocr),
                onChanged: _toggleOcr,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
              _buildContentFeatureToggle(
                icon: Icons.hub_outlined,
                title: l10n.settingsSemanticSearch,
                subtitle: l10n.settingsSemanticSearchHint,
                value: _config.enableEmbeddings,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.embeddings),
                onChanged: _toggleEmbeddings,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),

              _buildContentFeatureToggle(
                icon: Icons.mic_outlined,
                title: l10n.settingsTranscription,
                subtitle: l10n.settingsTranscriptionHint,
                value: _config.enableTranscription,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.transcription),
                onChanged: _toggleTranscription,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
              _buildContentFeatureToggle(
                icon: Icons.chat_outlined,
                title: l10n.settingsRag,
                subtitle: l10n.settingsRagHint,
                value: _config.enableRag,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.rag),
                onChanged: _toggleRag,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
              _buildContentFeatureToggle(
                icon: Icons.auto_awesome_outlined,
                title: l10n.settingsAutoDescriptions,
                subtitle: l10n.settingsAutoDescriptionsHint,
                value: _config.enableAutoSummary,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary),
                onChanged: _toggleAutoSummary,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
              _buildContentFeatureToggle(
                icon: Icons.label_outlined,
                title: l10n.settingsAutoTags,
                subtitle: l10n.settingsAutoTagsHint,
                value: _config.enableAutoTags,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoTags),
                onChanged: _toggleAutoTags,
                comingSoonLabel: l10n.settingsComingSoon,
                disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
              ),
            ],
          ),

          const Divider(),

          // === Лицензия ===
          _buildLicenseSection(),

          const Divider(),

          // === Дополнительно ===
          _buildSection(
            title: l10n.settingsSectionAdvanced,
            children: [
              _buildResetTile(l10n),
              _buildVersionTile(l10n),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseSection() {
    final license = _licenseCoordinator.currentLicense;
    final isConstrained = _licenseCoordinator.isHardwareConstrained;

    final String description;
    final bool showBuyButton;

    switch (license.mode) {
      case LicenseMode.pro:
        description = 'Лицензия PRO активна. Все функции доступны без ограничений.';
        showBuyButton = false;
      case LicenseMode.proTrial:
        final remaining = _licenseCoordinator.trialTimeRemaining;
        final days = (remaining?.inDays ?? 0) + 1;
        description =
            'Пробный период PRO (осталось $days дн.). Все функции доступны. '
            'После окончания триала приложение перейдёт в режим Basic '
            'с ограничениями на количество файлов и функции.';
        showBuyButton = true;
      case LicenseMode.basic:
        description =
            'Бесплатная версия с ограничениями: лимит на количество '
            'файлов в индексе, отключены ресурсоёмкие функции (семантический '
            'поиск, автоописания, транскрипция).';
        showBuyButton = true;
    }

    return _buildSection(
      title: 'Лицензия',
      children: [
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: Row(
            children: [
              Text('Текущий режим: '),
              LicenseBadge(licenseCoordinator: _licenseCoordinator),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(description),
          ),
        ),
        if (isConstrained)
          ListTile(
            leading: Icon(Icons.memory, color: Theme.of(context).colorScheme.error),
            title: const Text('Аппаратные ограничения'),
            subtitle: const Text(
              'Обнаружено менее 6 ГБ ОЗУ. PRO-функции недоступны '
              'независимо от статуса лицензии.',
            ),
          ),
        if (showBuyButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isPurchasing ? null : _handleBuyPro,
                icon: _isPurchasing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  _isPurchasing ? 'Обработка...' : 'Купить PRO — разовая покупка',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleBuyPro() async {
    setState(() => _isPurchasing = true);
    try {
      final result = await _storePurchaseService.buyPro();
      if (!mounted) return;

      if (result.isSuccess) {
        await _licenseCoordinator.activateProPurchase();
        await _licenseCoordinator.refreshLicense();
        if (!mounted) return;
        setState(() {});
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.verified, color: Colors.green, size: 48),
            title: const Text('PRO-версия активирована!'),
            content: const Text('Спасибо за покупку. Все PRO-функции теперь доступны.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else if (result.isError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.status == PurchaseStatus.storeUnavailable
                  ? 'Магазин Microsoft Store недоступен. '
                      'Убедитесь, что приложение установлено из Store.'
                  : 'Ошибка покупки: ${result.errorMessage ?? "неизвестная ошибка"}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      // isCancelled — ничего не делаем
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildCurrentPathTile(AppLocalizations l10n) {
    final path = _config.watchPath;
    final displayPath = path ?? l10n.settingsNotConfigured;
    
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(l10n.settingsCurrentPath),
      subtitle: Text(
        displayPath,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: path == null 
            ? Theme.of(context).colorScheme.outline
            : null,
        ),
      ),
    );
  }

  Widget _buildSelectFolderTile(AppLocalizations l10n) {
    final isBasic =
        _licenseCoordinator.currentLicense.mode == LicenseMode.basic;

    return ListTile(
      leading: const Icon(Icons.create_new_folder_outlined),
      title: Text(l10n.settingsSelectFolder),
      subtitle: Text(
        isBasic ? '${l10n.settingsSelectFolderHint} • Доступно в PRO' : l10n.settingsSelectFolderHint,
      ),
      trailing: isBasic
          ? Tooltip(
              message: 'Доступно в PRO',
              child: Icon(Icons.lock_outline,
                  size: 20, color: Theme.of(context).disabledColor),
            )
          : const Icon(Icons.chevron_right),
      enabled: !isBasic,
      onTap: isBasic ? null : _selectFolder,
    );
  }

  Widget _buildOpenFolderTile(AppLocalizations l10n) {
    final path = _config.watchPath;
    final canOpen = path != null && path.isNotEmpty && _folderExists;
    
    return ListTile(
      leading: Icon(
        Icons.open_in_new,
        color: canOpen ? null : Theme.of(context).disabledColor,
      ),
      title: Text(
        l10n.settingsOpenInExplorer,
        style: TextStyle(
          color: canOpen ? null : Theme.of(context).disabledColor,
        ),
      ),
      subtitle: Text(
        canOpen 
          ? l10n.settingsOpenInExplorerHint
          : l10n.settingsSelectFolderFirst,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      trailing: canOpen ? const Icon(Icons.chevron_right) : null,
      enabled: canOpen,
      onTap: canOpen ? _openFolder : null,
    );
  }

  Widget _buildNotificationsToggle(AppLocalizations l10n) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: Text(l10n.settingsShowNotifications),
      subtitle: Text(l10n.settingsShowNotificationsHint),
      value: _config.notificationsEnabled,
      onChanged: _toggleNotifications,
    );
  }

  Widget _buildResourceSaverToggle(AppLocalizations l10n) {
    return SwitchListTile(
      secondary: Icon(
        Icons.battery_saver,
        color: _config.resourceSaverEnabled
            ? Theme.of(context).colorScheme.tertiary
            : null,
      ),
      title: Text(l10n.settingsResourceSaver),
      subtitle: Text(
        _config.resourceSaverEnabled
            ? l10n.settingsResourceSaverOnHint
            : l10n.settingsResourceSaverOffHint,
      ),
      value: _config.resourceSaverEnabled,
      onChanged: _toggleResourceSaver,
    );
  }

  /// Переключатель контент-функции с учётом режима экономии.
  Widget _buildContentFeatureToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool effectiveValue,
    required ValueChanged<bool> onChanged,
    required String comingSoonLabel,
    required String disabledBySaverLabel,
    bool comingSoon = false,
  }) {
    final isOverriddenByResourceSaver =
        _config.resourceSaverEnabled && value && !effectiveValue;

    return SwitchListTile(
      secondary: Icon(
        icon,
        color: comingSoon ? Theme.of(context).disabledColor : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(title)),
          if (comingSoon) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                comingSoonLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        isOverriddenByResourceSaver
            ? '$subtitle \u2022 $disabledBySaverLabel'
            : subtitle,
        style: TextStyle(
          color: isOverriddenByResourceSaver
              ? Theme.of(context).colorScheme.outline
              : null,
        ),
      ),
      value: effectiveValue,
      onChanged: comingSoon ? null : onChanged,
    );
  }

  Widget _buildResetTile(AppLocalizations l10n) {
    return ListTile(
      leading: Icon(
        Icons.restore,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        l10n.settingsResetSettings,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      subtitle: Text(l10n.settingsResetHint),
      onTap: _resetSettings,
    );
  }

  Widget _buildVersionTile(AppLocalizations l10n) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(l10n.settingsVersion),
      subtitle: Text(_appVersion.isEmpty ? '...' : _appVersion),
    );
  }
}

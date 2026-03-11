import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../domain/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';

/// Страница настроек (Windows-версия).
///
/// Использует fluent_ui виджеты для нативного WinUI 3 вида.
class WindowsSettingsPage extends fluent.StatefulWidget {
  const WindowsSettingsPage({super.key});

  @override
  fluent.State<WindowsSettingsPage> createState() =>
      _WindowsSettingsPageState();
}

class _WindowsSettingsPageState extends fluent.State<WindowsSettingsPage> {
  late final ConfigService _configService;
  AppConfig _config = const AppConfig();
  bool _isLoading = false;
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
          fluent.displayInfoBar(context, builder: (context, close) {
            return fluent.InfoBar(
              title: Text(l10n.settingsFolderChanged(result)),
              severity: fluent.InfoBarSeverity.success,
              onClose: close,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        fluent.displayInfoBar(context, builder: (context, close) {
          return fluent.InfoBar(
            title: Text(l10n.settingsFolderPickError(e.toString())),
            severity: fluent.InfoBarSeverity.error,
            onClose: close,
          );
        });
      }
    }
  }

  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final path = _config.watchPath;
    if (path == null || path.isEmpty) return;

    try {
      final exists = await Directory(path).exists();
      if (!exists && mounted) {
        fluent.displayInfoBar(context, builder: (context, close) {
          return fluent.InfoBar(
            title: Text(l10n.settingsFolderNotExists(path)),
            severity: fluent.InfoBarSeverity.error,
            onClose: close,
          );
        });
        return;
      }

      if (_containsDangerousChars(path)) {
        if (mounted) {
          fluent.displayInfoBar(context, builder: (context, close) {
            return fluent.InfoBar(
              title: Text(l10n.settingsPathDangerousChars),
              severity: fluent.InfoBarSeverity.error,
              onClose: close,
            );
          });
        }
        return;
      }

      await Process.start(
        'explorer.exe',
        [path],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      if (mounted) {
        fluent.displayInfoBar(context, builder: (context, close) {
          return fluent.InfoBar(
            title: Text(l10n.settingsOpenFolderError(e.toString())),
            severity: fluent.InfoBarSeverity.error,
            onClose: close,
          );
        });
      }
    }
  }

  bool _containsDangerousChars(String path) {
    final dangerousPattern = RegExp(r'[<>|&^"]');
    return dangerousPattern.hasMatch(path);
  }

  Future<void> _updateConfig({
    bool? notificationsEnabled,
    bool? resourceSaverEnabled,
    bool? enableOfficeDocs,
    bool? enableOcr,
    bool? enableEmbeddings,
    bool? enableTranscription,
    bool? enableRag,
    bool? enableAutoSummary,
    bool? enableAutoTags,
  }) async {
    if (notificationsEnabled != null) {
      await _configService.updateValue(notificationsEnabled: notificationsEnabled);
      setState(() => _config = _config.copyWith(notificationsEnabled: notificationsEnabled));
    }
    if (resourceSaverEnabled != null) {
      await _configService.updateValue(resourceSaverEnabled: resourceSaverEnabled);
      setState(() => _config = _config.copyWith(resourceSaverEnabled: resourceSaverEnabled));
    }
    if (enableOfficeDocs != null) {
      await _configService.updateValue(enableOfficeDocs: enableOfficeDocs);
      setState(() => _config = _config.copyWith(enableOfficeDocs: enableOfficeDocs));
    }
    if (enableOcr != null) {
      await _configService.updateValue(enableOcr: enableOcr);
      setState(() => _config = _config.copyWith(enableOcr: enableOcr));
    }
    if (enableEmbeddings != null) {
      await _configService.updateValue(enableEmbeddings: enableEmbeddings);
      setState(() => _config = _config.copyWith(enableEmbeddings: enableEmbeddings));
    }
    if (enableTranscription != null) {
      await _configService.updateValue(enableTranscription: enableTranscription);
      setState(() => _config = _config.copyWith(enableTranscription: enableTranscription));
    }
    if (enableRag != null) {
      await _configService.updateValue(enableRag: enableRag);
      setState(() => _config = _config.copyWith(enableRag: enableRag));
    }
    if (enableAutoSummary != null) {
      await _configService.updateValue(enableAutoSummary: enableAutoSummary);
      setState(() => _config = _config.copyWith(enableAutoSummary: enableAutoSummary));
    }
    if (enableAutoTags != null) {
      await _configService.updateValue(enableAutoTags: enableAutoTags);
      setState(() => _config = _config.copyWith(enableAutoTags: enableAutoTags));
    }
  }

  Future<void> _resetSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await fluent.showDialog<bool>(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: Text(l10n.settingsResetConfirmTitle),
        content: Text(l10n.settingsResetConfirmBody),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.buttonCancel),
          ),
          fluent.FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: fluent.ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                fluent.Colors.red,
              ),
            ),
            child: Text(l10n.buttonReset),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _configService.reset();
      await _loadConfig();
      if (mounted) {
        fluent.displayInfoBar(context, builder: (context, close) {
          return fluent.InfoBar(
            title: Text(l10n.settingsResetDone),
            severity: fluent.InfoBarSeverity.success,
            onClose: close,
          );
        });
      }
    }
  }

  @override
  Widget build(fluent.BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = fluent.FluentTheme.of(context);

    if (_isLoading) {
      return const Center(child: fluent.ProgressRing());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(l10n.settingsLoadError),
            const SizedBox(height: 8),
            Text(_error!, style: theme.typography.caption),
            const SizedBox(height: 16),
            fluent.FilledButton(
              onPressed: _loadConfig,
              child: Text(l10n.buttonRetry),
            ),
          ],
        ),
      );
    }

    return fluent.ScaffoldPage.scrollable(
      header: fluent.PageHeader(
        title: Text(l10n.settingsTitle),
      ),
      children: [
        // === Папка для наблюдения ===
        _buildSectionHeader(l10n.settingsSectionWatchFolder, theme),
        _buildFolderCard(l10n, theme),
        const SizedBox(height: 24),

        // === Уведомления ===
        _buildSectionHeader(l10n.settingsSectionNotifications, theme),
        _buildToggleCard(
          icon: Icons.notifications_outlined,
          title: l10n.settingsShowNotifications,
          subtitle: l10n.settingsShowNotificationsHint,
          value: _config.notificationsEnabled,
          onChanged: (v) => _updateConfig(notificationsEnabled: v),
        ),
        const SizedBox(height: 24),

        // === Производительность ===
        _buildSectionHeader(l10n.settingsSectionPerformance, theme),
        _buildToggleCard(
          icon: Icons.battery_saver,
          title: l10n.settingsResourceSaver,
          subtitle: _config.resourceSaverEnabled
              ? l10n.settingsResourceSaverOnHint
              : l10n.settingsResourceSaverOffHint,
          value: _config.resourceSaverEnabled,
          onChanged: (v) => _updateConfig(resourceSaverEnabled: v),
        ),
        const SizedBox(height: 24),

        // === Обработка содержимого ===
        _buildSectionHeader(l10n.settingsSectionContentProcessing, theme),
        _buildFeatureToggle(
          icon: Icons.description_outlined,
          title: l10n.settingsTextExtraction,
          subtitle: l10n.settingsTextExtractionHint,
          value: _config.enableOfficeDocs,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs),
          onChanged: (v) => _updateConfig(enableOfficeDocs: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.document_scanner_outlined,
          title: l10n.settingsOcr,
          subtitle: l10n.settingsOcrHint,
          value: _config.enableOcr,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.ocr),
          onChanged: (v) => _updateConfig(enableOcr: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.hub_outlined,
          title: l10n.settingsSemanticSearch,
          subtitle: l10n.settingsSemanticSearchHint,
          value: _config.enableEmbeddings,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.embeddings),
          onChanged: (v) => _updateConfig(enableEmbeddings: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.mic_outlined,
          title: l10n.settingsTranscription,
          subtitle: l10n.settingsTranscriptionHint,
          value: _config.enableTranscription,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.transcription),
          onChanged: (v) => _updateConfig(enableTranscription: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.chat_outlined,
          title: l10n.settingsRag,
          subtitle: l10n.settingsRagHint,
          value: _config.enableRag,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.rag),
          onChanged: (v) => _updateConfig(enableRag: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.auto_awesome_outlined,
          title: l10n.settingsAutoDescriptions,
          subtitle: l10n.settingsAutoDescriptionsHint,
          value: _config.enableAutoSummary,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary),
          onChanged: (v) => _updateConfig(enableAutoSummary: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        _buildFeatureToggle(
          icon: Icons.label_outlined,
          title: l10n.settingsAutoTags,
          subtitle: l10n.settingsAutoTagsHint,
          value: _config.enableAutoTags,
          effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoTags),
          onChanged: (v) => _updateConfig(enableAutoTags: v),
          disabledBySaverLabel: l10n.settingsDisabledByResourceSaver,
        ),
        const SizedBox(height: 24),

        // === Дополнительно ===
        _buildSectionHeader(l10n.settingsSectionAdvanced, theme),
        fluent.Card(
          child: Column(
            children: [
              fluent.ListTile.selectable(
                leading: Icon(Icons.restore, color: fluent.Colors.red),
                title: Text(
                  l10n.settingsResetSettings,
                  style: TextStyle(color: fluent.Colors.red),
                ),
                subtitle: Text(l10n.settingsResetHint),
                onPressed: _resetSettings,
                selected: false,
              ),
              fluent.ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.settingsVersion),
                subtitle: Text(_appVersion.isEmpty ? '...' : _appVersion),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(String title, fluent.FluentThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.typography.bodyStrong?.copyWith(
          color: theme.accentColor,
        ),
      ),
    );
  }

  Widget _buildFolderCard(AppLocalizations l10n, fluent.FluentThemeData theme) {
    final path = _config.watchPath;
    final canOpen = path != null && path.isNotEmpty && _folderExists;

    return fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Текущий путь
          Row(
            children: [
              Icon(Icons.folder_outlined, color: theme.accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsCurrentPath,
                        style: theme.typography.bodyStrong),
                    Text(
                      path ?? l10n.settingsNotConfigured,
                      style: theme.typography.caption,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Кнопки
          Row(
            children: [
              fluent.FilledButton(
                onPressed: _selectFolder,
                child: Row(
                  children: [
                    const Icon(Icons.create_new_folder_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.settingsSelectFolder),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              fluent.Button(
                onPressed: canOpen ? _openFolder : null,
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.settingsOpenInExplorer),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return fluent.Card(
      child: fluent.ListTile.selectable(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: fluent.ToggleSwitch(
          checked: value,
          onChanged: onChanged,
        ),
        selected: false,
      ),
    );
  }

  Widget _buildFeatureToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool effectiveValue,
    required ValueChanged<bool> onChanged,
    required String disabledBySaverLabel,
  }) {
    final isOverriddenByResourceSaver =
        _config.resourceSaverEnabled && value && !effectiveValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: fluent.Card(
        child: fluent.ListTile.selectable(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(
            isOverriddenByResourceSaver
                ? '$subtitle \u2022 $disabledBySaverLabel'
                : subtitle,
          ),
          trailing: fluent.ToggleSwitch(
            checked: effectiveValue,
            onChanged: onChanged,
          ),
          selected: false,
        ),
      ),
    );
  }
}

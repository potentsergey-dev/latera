import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_config.dart';
import 'app_scope.dart';

/// Экран настроек приложения.
///
/// Позволяет пользователю:
/// - Выбрать папку для наблюдения
/// - Включить/отключить уведомления
/// - Открыть папку в проводнике
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ConfigService _configService;
  AppConfig _config = const AppConfig();
  bool _isLoading = false;
  String? _error;
  bool _folderExists = false;
  bool _initialized = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    // ConfigService будет получен в didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Защита от повторной инициализации (didChangeDependencies может вызываться многократно)
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
      // Асинхронная проверка существования папки
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

  /// Асинхронно проверяет существование папки.
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
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для наблюдения',
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
            SnackBar(
              content: Text('Папка изменена: $result'),
              action: SnackBarAction(
                label: 'OK',
                onPressed: () {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора папки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openFolder() async {
    final path = _config.watchPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Папка не выбрана'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // На Windows используем explorer.exe для надёжного открытия папки
    // url_launcher с Uri.directory может не работать корректно
    try {
      if (Platform.isWindows) {
        // Проверяем существование папки перед открытием
        final exists = await Directory(path).exists();
        if (!exists && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Папка не существует: $path'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Валидация пути: защита от потенциально опасных символов
        // explorer.exe принимает путь как аргумент, поэтому проверяем
        // на наличие символов, которые могут быть интерпретированы shell
        if (_containsDangerousChars(path)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Путь содержит недопустимые символы'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Используем Process.start вместо Process.run для большего контроля
        // и избегаем shell interpretation
        await Process.start(
          'explorer.exe',
          [path],
          mode: ProcessStartMode.detached,
        );
      } else {
        // На других платформах используем url_launcher
        final uri = Uri.directory(path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось открыть папку: $path'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия папки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Проверяет путь на наличие потенциально опасных символов.
  ///
  /// Explorer.exe принимает путь как аргумент командной строки,
  /// поэтому некоторые символы могут быть интерпретированы некорректно.
  bool _containsDangerousChars(String path) {
    // Проверяем на символы, которые могут вызвать проблемы
    // в командной строке Windows
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

  Future<void> _toggleTranscription(bool value) async {
    await _configService.updateValue(enableTranscription: value);
    setState(() {
      _config = _config.copyWith(enableTranscription: value);
    });
  }

  Future<void> _toggleEmbeddings(bool value) async {
    await _configService.updateValue(enableEmbeddings: value);
    setState(() {
      _config = _config.copyWith(enableEmbeddings: value);
    });
  }

  Future<void> _toggleSemanticSimilarity(bool value) async {
    await _configService.updateValue(enableSemanticSimilarity: value);
    setState(() {
      _config = _config.copyWith(enableSemanticSimilarity: value);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить настройки?'),
        content: const Text(
          'Все настройки будут возвращены к значениям по умолчанию. '
          'Папка наблюдения будет сброшена.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _configService.reset();
      await _loadConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сброшены')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, 
                        size: 48, 
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text('Ошибка загрузки настроек'),
                      const SizedBox(height: 8),
                      Text(_error!, 
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadConfig,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === Папка для наблюдения ===
          _buildSection(
            title: 'Папка для наблюдения',
            children: [
              _buildCurrentPathTile(),
              _buildSelectFolderTile(),
              _buildOpenFolderTile(),
            ],
          ),

          const Divider(),

          // === Уведомления ===
          _buildSection(
            title: 'Уведомления',
            children: [
              _buildNotificationsToggle(),
            ],
          ),

          const Divider(),

          // === Производительность ===
          _buildSection(
            title: 'Производительность',
            children: [
              _buildResourceSaverToggle(),
            ],
          ),

          const Divider(),

          // === Обработка содержимого ===
          _buildSection(
            title: 'Обработка содержимого',
            children: [
              _buildContentFeatureToggle(
                icon: Icons.description_outlined,
                title: 'Извлечение текста из документов',
                subtitle: 'Поиск по содержимому PDF, DOCX и др.',
                value: _config.enableOfficeDocs,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs),
                onChanged: _toggleOfficeDocs,
              ),
              _buildContentFeatureToggle(
                icon: Icons.document_scanner_outlined,
                title: 'Распознавание текста (OCR)',
                subtitle: 'Текст со скриншотов, сканов и фото',
                value: _config.enableOcr,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.ocr),
                onChanged: _toggleOcr,
              ),
              _buildContentFeatureToggle(
                icon: Icons.mic_outlined,
                title: 'Транскрибация медиа',
                subtitle: 'Поиск по аудио и видео (Whisper)',
                value: _config.enableTranscription,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.transcription),
                onChanged: _toggleTranscription,
              ),
              _buildContentFeatureToggle(
                icon: Icons.hub_outlined,
                title: 'Семантический поиск',
                subtitle: 'Поиск похожих документов по смыслу',
                value: _config.enableEmbeddings,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.embeddings),
                onChanged: _toggleEmbeddings,
              ),
              _buildContentFeatureToggle(
                icon: Icons.find_replace_outlined,
                title: 'Похожие файлы',
                subtitle: 'Рекомендации похожих документов',
                value: _config.enableSemanticSimilarity,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity),
                onChanged: _toggleSemanticSimilarity,
              ),
              _buildContentFeatureToggle(
                icon: Icons.chat_outlined,
                title: 'Спроси свою папку (RAG)',
                subtitle: 'Чат с ответами по файлам',
                value: _config.enableRag,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.rag),
                onChanged: _toggleRag,
                comingSoon: true,
              ),
              _buildContentFeatureToggle(
                icon: Icons.auto_awesome_outlined,
                title: 'Автоматические описания',
                subtitle: 'Автосаммари документов',
                value: _config.enableAutoSummary,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary),
                onChanged: _toggleAutoSummary,
                comingSoon: true,
              ),
              _buildContentFeatureToggle(
                icon: Icons.label_outlined,
                title: 'Автоматические теги',
                subtitle: 'Автоприсвоение тегов по содержимому',
                value: _config.enableAutoTags,
                effectiveValue: _config.isFeatureEffectivelyEnabled(ContentFeature.autoTags),
                onChanged: _toggleAutoTags,
                comingSoon: true,
              ),
            ],
          ),

          const Divider(),

          // === Дополнительно ===
          _buildSection(
            title: 'Дополнительно',
            children: [
              _buildResetTile(),
              _buildVersionTile(),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildCurrentPathTile() {
    final path = _config.watchPath;
    final displayPath = path ?? 'Не настроена';
    
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: const Text('Текущий путь'),
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

  Widget _buildSelectFolderTile() {
    return ListTile(
      leading: const Icon(Icons.create_new_folder_outlined),
      title: const Text('Выбрать папку'),
      subtitle: const Text('Укажите папку для отслеживания новых файлов'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _selectFolder,
    );
  }

  Widget _buildOpenFolderTile() {
    final path = _config.watchPath;
    final canOpen = path != null && path.isNotEmpty && _folderExists;
    
    return ListTile(
      leading: Icon(
        Icons.open_in_new,
        color: canOpen ? null : Theme.of(context).disabledColor,
      ),
      title: Text(
        'Открыть в проводнике',
        style: TextStyle(
          color: canOpen ? null : Theme.of(context).disabledColor,
        ),
      ),
      subtitle: Text(
        canOpen 
          ? 'Открыть папку в файловом менеджере'
          : 'Выберите папку для наблюдения',
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      trailing: canOpen ? const Icon(Icons.chevron_right) : null,
      enabled: canOpen,
      onTap: canOpen ? _openFolder : null,
    );
  }

  Widget _buildNotificationsToggle() {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Показывать уведомления'),
      subtitle: const Text('Уведомления о новых файлах в папке'),
      value: _config.notificationsEnabled,
      onChanged: _toggleNotifications,
    );
  }

  Widget _buildResourceSaverToggle() {
    return SwitchListTile(
      secondary: Icon(
        Icons.battery_saver,
        color: _config.resourceSaverEnabled
            ? Theme.of(context).colorScheme.tertiary
            : null,
      ),
      title: const Text('Экономия ресурсов'),
      subtitle: Text(
        _config.resourceSaverEnabled
            ? 'Тяжёлые функции отключены, лимиты уменьшены'
            : 'Отключите ресурсоёмкие функции для слабых ПК',
      ),
      value: _config.resourceSaverEnabled,
      onChanged: _toggleResourceSaver,
    );
  }

  /// Переключатель контент-функции с учётом режима экономии.
  ///
  /// [comingSoon] — функция ещё не реализована (показать бейдж).
  /// [effectiveValue] — реальное состояние с учётом режима экономии.
  Widget _buildContentFeatureToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool effectiveValue,
    required ValueChanged<bool> onChanged,
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
                'скоро',
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
            ? '$subtitle • отключено режимом экономии'
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

  Widget _buildResetTile() {
    return ListTile(
      leading: Icon(
        Icons.restore,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Сбросить настройки',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      subtitle: const Text('Вернуть все настройки к значениям по умолчанию'),
      onTap: _resetSettings,
    );
  }

  Widget _buildVersionTile() {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Версия'),
      subtitle: Text(_appVersion.isEmpty ? '...' : _appVersion),
    );
  }
}

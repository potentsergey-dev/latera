import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../infrastructure/rust/generated/api.dart';
import '../infrastructure/rust/rust_core.dart';
import '../l10n/app_localizations.dart';
import 'app_scope.dart';

/// Экран онбординга для первого запуска.
///
/// Позволяет пользователю:
/// - Узнать, что отслеживает приложение
/// - Увидеть информацию о приватности и хранении данных
/// - Выбрать папку для наблюдения
///
/// Важно: папка НЕ создаётся до нажатия кнопки «Начать работу».
/// Создание происходит позже при вызове start_watching на MainScreen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? _selectedPath;
  String? _defaultPath;
  String? _indexPath;
  bool _isProcessing = false;
  bool _useDefaultPath = false;
  bool _isLoadingDefault = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    if (mounted) {
      setState(() {
        _isLoadingDefault = true;
        _loadError = null;
        _defaultPath = null;
        _indexPath = null;
      });
    }

    try {
      await RustCoreBootstrap.ensureInitialized();

      if (!RustCoreBootstrap.isInitialized) {
        throw StateError('RustCore failed to initialize');
      }

      // Оба вызова НЕ создают директории — только возвращают пути
      final results = await Future.wait([
        getDefaultWatchPathPreview(),
        getIndexPath(),
      ]);

      if (mounted) {
        setState(() {
          _defaultPath = results[0];
          _indexPath = results[1];
          _isLoadingDefault = false;
        });
      }
    } catch (e, st) {
      debugPrint('Failed to load paths: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoadingDefault = false;
        });
      }
    }
  }

  Future<void> _selectFolder() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.onboardingSelectFolder,
      );

      if (result != null) {
        setState(() {
          _selectedPath = result;
          _useDefaultPath = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.onboardingFolderPickError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _continue() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final l10n = AppLocalizations.of(context)!;
      final root = AppScope.of(context);
      final configService = root.configService;

      final pathToSave =
          _selectedPath ?? (_useDefaultPath ? _defaultPath : null);

      if (_useDefaultPath && _defaultPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.onboardingDefaultPathUnavailable),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

      // Сохраняем путь — папка ещё НЕ создаётся.
      // Создание произойдёт при start_watching на MainScreen.
      if (pathToSave != null) {
        await configService.updateValue(watchPath: pathToSave);
      }

      await configService.completeOnboarding();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.onboardingSaveError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _useDefault() {
    setState(() {
      _useDefaultPath = true;
      _selectedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // === Логотип и заголовок ===
                  Icon(
                    Icons.folder_outlined,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.onboardingTitle,
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.onboardingDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // === Что отслеживает приложение ===
                  _buildInfoCard(
                    icon: Icons.visibility_outlined,
                    title: l10n.onboardingWhatTracksTitle,
                    items: [
                      l10n.onboardingWhatTracksItem1,
                      l10n.onboardingWhatTracksItem2,
                      l10n.onboardingWhatTracksItem3,
                    ],
                  ),

                  const SizedBox(height: 12),

                  // === Конфиденциальность ===
                  _buildInfoCard(
                    icon: Icons.shield_outlined,
                    title: l10n.onboardingPrivacyTitle,
                    items: [
                      l10n.onboardingPrivacyItem1,
                      l10n.onboardingPrivacyItem2,
                    ],
                    accentColor: colorScheme.tertiary,
                  ),

                  const SizedBox(height: 12),

                  // === Где хранятся данные ===
                  _buildDataStorageCard(),

                  const SizedBox(height: 24),

                  // === Выбор папки ===
                  _buildFolderSelection(),

                  const SizedBox(height: 24),

                  // === Кнопки ===
                  _buildButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Карточка с иконкой, заголовком и списком bullet-пунктов.
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required List<String> items,
    Color? accentColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accentColor ?? colorScheme.primary;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: color)),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Карточка «Где хранятся данные» с путём индекса из Rust API.
  Widget _buildDataStorageCard() {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.onboardingDataStorageTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Индекс
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.onboardingIndexLocation} ',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: _isLoadingDefault
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _indexPath ?? '—',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.outline),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                  ),
                ],
              ),
            ),
            // Настройки
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                l10n.onboardingSettingsStorage,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderSelection() {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // Показываем ошибку загрузки
    if (_loadError != null) {
      return Card(
        elevation: 0,
        color: Colors.red.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                l10n.onboardingLoadError(_loadError!),
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoadingDefault = true;
                    _loadError = null;
                  });
                  _loadPaths();
                },
                icon: const Icon(Icons.refresh),
                label: Text(l10n.buttonRetry),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  l10n.onboardingFolderSectionTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Кнопка выбора папки
            InkWell(
              onTap: _selectFolder,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedPath != null
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedPath != null
                          ? Icons.check_circle
                          : Icons.create_new_folder_outlined,
                      color: _selectedPath != null
                          ? Colors.green
                          : colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedPath ?? l10n.onboardingSelectFolder,
                        style: TextStyle(
                          color:
                              _selectedPath != null ? null : colorScheme.outline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Опция «Использовать по умолчанию»
            InkWell(
              onTap: _isLoadingDefault ? null : _useDefault,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _useDefaultPath
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _useDefaultPath
                          ? Icons.check_circle
                          : Icons.folder_special_outlined,
                      color:
                          _useDefaultPath ? Colors.green : colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.onboardingUseDefault),
                          if (_isLoadingDefault)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Text(
                              _defaultPath ?? 'Desktop/Latera',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    final l10n = AppLocalizations.of(context)!;
    final canContinue =
        _selectedPath != null || (_useDefaultPath && _defaultPath != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: canContinue && !_isProcessing ? _continue : null,
          icon: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          label:
              Text(_isProcessing ? l10n.onboardingLoading : l10n.onboardingStartButton),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingChangeLater,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

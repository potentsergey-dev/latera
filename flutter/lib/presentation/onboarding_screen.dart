import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../infrastructure/rust/generated/api.dart';
import '../infrastructure/rust/rust_core.dart';
import 'app_scope.dart';

/// Экран онбординга для первого запуска.
///
/// Позволяет пользователю:
/// - Выбрать папку для наблюдения
/// - Понять основные функции приложения
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? _selectedPath;
  String? _defaultPath;
  bool _isProcessing = false;
  bool _useDefaultPath = false;
  bool _isLoadingDefault = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDefaultPath();
  }

  Future<void> _loadDefaultPath() async {
    // Сбрасываем состояние перед новой попыткой (в т.ч. при нажатии «Повторить»)
    if (mounted) {
      setState(() {
        _isLoadingDefault = true;
        _loadError = null;
        _defaultPath = null;
      });
    }

    try {
      // Инициализируем Rust Core если ещё не инициализирован
      await RustCoreBootstrap.ensureInitialized();
      
      // Проверяем что инициализация прошла успешно перед вызовом API
      if (!RustCoreBootstrap.isInitialized) {
        throw StateError('RustCore failed to initialize');
      }
      
      // Получаем preview дефолтного пути из Rust (НЕ создаёт директорию)
      // Это важно для приватности: показываем путь до согласия пользователя
      final defaultPath = await getDefaultWatchPathPreview();
      
      if (mounted) {
        setState(() {
          _defaultPath = defaultPath;
          _isLoadingDefault = false;
        });
      }
    } catch (e, st) {
      debugPrint('Failed to load default watch path: $e\n$st');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoadingDefault = false;
        });
      }
    }
  }

  Future<void> _selectFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для наблюдения',
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
            content: Text('Ошибка выбора папки: $e'),
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
      final root = AppScope.of(context);
      final configService = root.configService;

      // Определяем путь для сохранения
      final pathToSave = _selectedPath ?? (_useDefaultPath ? _defaultPath : null);
      
      // Защита: если выбран дефолтный путь, но он не загружен - показать ошибку
      if (_useDefaultPath && _defaultPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось получить путь по умолчанию. Выберите папку вручную.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }
      
      // Сначала сохраняем путь (если выбран)
      if (pathToSave != null) {
        await configService.updateValue(watchPath: pathToSave);
      }

      // Только после успешного сохранения отмечаем onboarding
      await configService.completeOnboarding();

      if (mounted) {
        // Переходим на главный экран
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения настроек: $e'),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    'Добро пожаловать в Latera',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Приложение для отслеживания новых файлов в папке.\n'
                    'Выберите папку, которую хотите наблюдать:',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // === Выбор папки ===
                  _buildFolderSelection(),

                  const SizedBox(height: 32),

                  // === Информация о приватности ===
                  _buildPrivacyInfo(),

                  const SizedBox(height: 32),

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

  Widget _buildFolderSelection() {
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
                'Ошибка загрузки: $_loadError',
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
                  _loadDefaultPath();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
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
                Icon(
                  Icons.folder_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Папка для наблюдения',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
                        _selectedPath ?? 'Нажмите для выбора папки',
                        style: TextStyle(
                          color: _selectedPath != null 
                            ? null 
                            : colorScheme.outline,
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

            // Опция "Использовать по умолчанию"
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
                      color: _useDefaultPath 
                        ? Colors.green 
                        : colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Использовать по умолчанию'),
                          if (_isLoadingDefault)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
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

  Widget _buildPrivacyInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.security,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Приложение отслеживает только выбранную вами папку. '
              'Данные не покидают ваше устройство.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    final canContinue = _selectedPath != null || (_useDefaultPath && _defaultPath != null);

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
          label: Text(_isProcessing ? 'Загрузка...' : 'Начать работу'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Папку можно изменить позже в настройках',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

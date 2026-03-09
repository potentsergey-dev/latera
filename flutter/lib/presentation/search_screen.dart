import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_config.dart';
import '../domain/search_repository.dart';
import 'app_scope.dart';
import 'file_description_dialog.dart';

/// Экран поиска файлов.
///
/// Пользователь вводит поисковый запрос, результаты обновляются
/// с debounce 300ms. Результаты показываются в виде карточек
/// с именем файла, описанием и фрагментом совпадения.
///
/// Поддерживает два режима:
/// - FTS5 (полнотекстовый) — по умолчанию
/// - Семантический (vector) — при включённом переключателе
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _error;

  /// Текущий режим поиска: true = семантический (vector), false = FTS5.
  bool _useSemanticSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    // Автофокус
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadSemanticSearchPreference();
    });
  }

  /// Загружает предпочтение семантического поиска из конфига.
  void _loadSemanticSearchPreference() {
    final root = AppScope.of(context);
    final config = root.configService.currentConfig;
    setState(() {
      _useSemanticSearch = config.isFeatureEffectivelyEnabled(ContentFeature.embeddings);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final root = AppScope.of(context);
      final List<SearchResult> results;

      if (_useSemanticSearch) {
        // Семантический поиск по эмбеддингам
        results = await root.searchRepository.semanticSearch(query);
      } else {
        // FTS5 полнотекстовый поиск (fallback)
        results = await root.searchRepository.search(query);
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  Future<void> _openFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Файл не найден на диске'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Открываем файл через системный обработчик
    final uri = Uri.file(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть файл: нет подходящего приложения'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Находит файлы, похожие на выбранный.
  Future<void> _findSimilarFiles(String filePath) async {
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final root = AppScope.of(context);
      final results = await root.searchRepository.findSimilarFiles(filePath);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });

      // Обновляем текст поиска чтобы показать контекст
      final fileName = filePath.split(Platform.pathSeparator).last;
      _searchController.removeListener(_onSearchChanged);
      _searchController.text = 'Похожие на: $fileName';
      _searchController.addListener(_onSearchChanged);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSearching = false;
        _hasSearched = true;
      });
    }
  }

  Future<void> _editDescription(SearchResult result) async {
    final newDesc = await FileDescriptionDialog.show(
      context,
      fileName: result.fileName,
      filePath: result.filePath,
      initialDescription: result.description,
    );

    if (newDesc != null && mounted) {
      final root = AppScope.of(context);
      try {
        await root.indexer.saveFileReview(
          result.filePath,
          description: newDesc.description,
          tags: '', // Заглушка, если теги не редактируются в этом диалоге
        );

        // Пересчитываем эмбеддинги по обновлённому описанию
        root.contentEnrichmentCoordinator.enqueueReEmbedding(
          result.filePath,
          result.fileName,
        );

        // Показываем toast
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Описание сохранено')),
          );
        }

        // Обновляем результаты поиска
        _performSearch(_searchController.text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка сохранения: $e')),
          );
        }
      }
    }
  }

  Future<void> _openContainingFolder(String filePath) async {
    // Открываем папку, содержащую файл, и выделяем файл
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else {
      final dir = File(filePath).parent.path;
      final uri = Uri.directory(dir);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск файлов'),
        actions: [
          // Переключатель FTS5 / Семантический поиск
          Tooltip(
            message: _useSemanticSearch
                ? 'Семантический поиск (по смыслу)'
                : 'Полнотекстовый поиск (FTS5)',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _useSemanticSearch ? Icons.hub : Icons.text_fields,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Switch.adaptive(
                  value: _useSemanticSearch,
                  onChanged: (value) {
                    setState(() {
                      _useSemanticSearch = value;
                    });
                    // Перезапустить поиск с новым режимом
                    if (_searchController.text.isNotEmpty) {
                      _performSearch(_searchController.text);
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Поисковая строка
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: _useSemanticSearch
                    ? 'Опишите что ищете…'
                    : 'Введите ключевые слова…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),

          // Индикатор загрузки
          if (_isSearching)
            const LinearProgressIndicator(),

          // Результаты
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Ошибка поиска', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Введите запрос для поиска',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _useSemanticSearch
                  ? 'Семантический поиск по смыслу документов'
                  : 'Поиск по имени файла, описанию и содержимому',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Ничего не найдено',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Попробуйте другие ключевые слова',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SearchResultCard(
          result: result,
          onTap: () => _openFile(result.filePath),
          onOpenFolder: () => _openContainingFolder(result.filePath),
          onFindSimilar: () => _findSimilarFiles(result.filePath),
          onEditDescription: () => _editDescription(result),
          showSimilarButton: _useSemanticSearch,
        );
      },
    );
  }
}

/// Карточка результата поиска.
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onFindSimilar;
  final VoidCallback onEditDescription;
  final bool showSimilarButton;

  const _SearchResultCard({
    required this.result,
    required this.onTap,
    required this.onOpenFolder,
    required this.onFindSimilar,
    required this.onEditDescription,
    this.showSimilarButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок: иконка + имя файла + кнопка папки
              Row(
                children: [
                  Icon(
                    _getFileIcon(result.fileName),
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.fileName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showSimilarButton)
                    IconButton(
                      icon: const Icon(Icons.hub_outlined, size: 18),
                      tooltip: 'Найти похожие файлы',
                      onPressed: onFindSimilar,
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Редактировать описание',
                    onPressed: onEditDescription,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    tooltip: 'Открыть папку',
                    onPressed: onOpenFolder,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              // Описание
              if (result.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  result.description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Snippet (фрагмент совпадения из текста)
              if (result.snippet != null && result.snippet!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  // Убираем HTML-теги из snippet для plain-text отображения
                  result.snippet!
                      .replaceAll('<b>', '')
                      .replaceAll('</b>', ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Relevance badge (для семантического поиска)
              if (result.relevance > 0 && result.relevance < 1.0) ...[                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${(result.relevance * 100).toStringAsFixed(0)}% совпадение',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Путь к файлу
              const SizedBox(height: 4),
              Text(
                result.filePath,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.article_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' => Icons.image_outlined,
      'mp4' || 'avi' || 'mov' || 'mkv' => Icons.video_file_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audio_file_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'txt' || 'md' || 'rst' => Icons.text_snippet_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

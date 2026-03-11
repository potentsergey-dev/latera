import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/app_config.dart';
import '../../../domain/search_repository.dart';
import '../../app_scope.dart';

/// Страница поиска файлов (Windows-версия).
class WindowsSearchPage extends fluent.StatefulWidget {
  const WindowsSearchPage({super.key});

  @override
  fluent.State<WindowsSearchPage> createState() => _WindowsSearchPageState();
}

class _WindowsSearchPageState extends fluent.State<WindowsSearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _error;
  bool _useSemanticSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadSemanticSearchPreference();
    });
  }

  void _loadSemanticSearchPreference() {
    final root = AppScope.of(context);
    final config = root.configService.currentConfig;
    setState(() {
      _useSemanticSearch =
          config.isFeatureEffectivelyEnabled(ContentFeature.embeddings);
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
        results = await root.searchRepository.semanticSearch(query);
      } else {
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
      fluent.displayInfoBar(context, builder: (context, close) {
        return fluent.InfoBar(
          title: const Text('Файл не найден на диске'),
          severity: fluent.InfoBarSeverity.warning,
          onClose: close,
        );
      });
      return;
    }
    final uri = Uri.file(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

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

  @override
  Widget build(fluent.BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: const Text('Поиск файлов'),
        commandBar: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _useSemanticSearch ? 'Семантический' : 'Полнотекстовый',
              style: theme.typography.caption,
            ),
            const SizedBox(width: 8),
            fluent.ToggleSwitch(
              checked: _useSemanticSearch,
              onChanged: (value) {
                setState(() => _useSemanticSearch = value);
                if (_searchController.text.isNotEmpty) {
                  _performSearch(_searchController.text);
                }
              },
            ),
          ],
        ),
      ),
      content: Column(
        children: [
          // Поисковая строка
          Padding(
            padding: const EdgeInsets.all(16),
            child: fluent.TextBox(
              controller: _searchController,
              focusNode: _focusNode,
              placeholder: _useSemanticSearch
                  ? 'Опишите что ищете…'
                  : 'Введите ключевые слова…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.search, size: 18),
              ),
              suffix: _searchController.text.isNotEmpty
                  ? fluent.IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),

          // Прогресс
          if (_isSearching) const fluent.ProgressBar(),

          // Результаты
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(fluent.FluentThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text('Ошибка поиска', style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(_error!, style: theme.typography.caption),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text('Введите запрос для поиска', style: theme.typography.body),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text('Ничего не найдено', style: theme.typography.subtitle),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: fluent.Card(
            child: fluent.ListTile.selectable(
              leading: Icon(
                _getFileIcon(result.fileName),
                color: theme.accentColor,
              ),
              title: Text(result.fileName),
              subtitle: Text(
                result.description.isNotEmpty
                    ? result.description
                    : result.filePath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fluent.IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    onPressed: () => _openFile(result.filePath),
                  ),
                  fluent.IconButton(
                    icon: const Icon(Icons.people_outline, size: 16),
                    onPressed: () => _findSimilarFiles(result.filePath),
                  ),
                ],
              ),
              onPressed: () => _openFile(result.filePath),
              selected: false,
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.article_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' =>
        Icons.image_outlined,
      'mp4' || 'avi' || 'mov' || 'mkv' => Icons.video_file_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audio_file_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'txt' || 'md' || 'rst' => Icons.text_snippet_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

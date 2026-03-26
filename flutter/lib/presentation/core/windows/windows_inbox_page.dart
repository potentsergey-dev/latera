import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/indexer.dart';
import '../../app_scope.dart';

/// Страница «Входящие» / Inbox (Windows-версия).
///
/// Master-Detail layout: слева — список файлов, справа — детали.
class WindowsInboxPage extends fluent.StatefulWidget {
  const WindowsInboxPage({super.key});

  @override
  fluent.State<WindowsInboxPage> createState() => _WindowsInboxPageState();
}

class _WindowsInboxPageState extends fluent.State<WindowsInboxPage> {
  List<InboxFile> _files = [];
  InboxFile? _selectedFile;
  bool _isLoading = true;
  bool _isSaving = false;

  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFiles();
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    final root = AppScope.of(context);
    try {
      final files = await root.indexer.getFilesNeedingReview();
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoading = false;
        if (_selectedFile != null &&
            !files.any((f) => f.filePath == _selectedFile!.filePath)) {
          _selectedFile = null;
          _descriptionController.clear();
          _tagsController.clear();
        }
      });
    } catch (e) {
      root.logger.e('Failed to load inbox files', error: e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _selectFile(InboxFile file) {
    setState(() {
      _selectedFile = file;
      _descriptionController.text = file.description;
      _tagsController.text = file.tags;
    });
  }

  Future<void> _saveReview() async {
    final selected = _selectedFile;
    if (selected == null) return;

    setState(() => _isSaving = true);

    final root = AppScope.of(context);
    try {
      await root.indexer.saveFileReview(
        selected.filePath,
        description: _descriptionController.text.trim(),
        tags: _tagsController.text.trim(),
      );

      root.contentEnrichmentCoordinator.enqueueReEmbedding(
        selected.filePath,
        selected.fileName,
      );

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _selectedFile = null;
        _descriptionController.clear();
        _tagsController.clear();
      });

      await _loadFiles();
    } catch (e, st) {
      root.logger.e('Failed to save review', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      fluent.displayInfoBar(context, builder: (context, close) {
        return fluent.InfoBar(
          title: Text('Ошибка сохранения: $e'),
          severity: fluent.InfoBarSeverity.error,
          onClose: close,
        );
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

  @override
  Widget build(fluent.BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    if (_isLoading) {
      return const Center(child: fluent.ProgressRing());
    }

    if (_files.isEmpty) {
      return _buildEmptyState(theme);
    }

    return Row(
      children: [
        // Master: список файлов
        SizedBox(
          width: 300,
          child: _buildFileList(theme),
        ),
        const fluent.Divider(direction: Axis.vertical),
        // Detail: панель свойств
        Expanded(
          child: _selectedFile != null
              ? _buildDetailPanel(theme)
              : _buildNoSelectionState(theme),
        ),
      ],
    );
  }

  Widget _buildEmptyState(fluent.FluentThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: theme.accentColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text('Все файлы обработаны', style: theme.typography.subtitle),
          const SizedBox(height: 4),
          Text(
            'Новые файлы появятся здесь автоматически',
            style: theme.typography.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelectionState(fluent.FluentThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 48, color: theme.inactiveColor),
          const SizedBox(height: 16),
          Text('Выберите файл из списка', style: theme.typography.body),
        ],
      ),
    );
  }

  Widget _buildFileList(fluent.FluentThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFile?.filePath == file.filePath;

        return fluent.ListTile.selectable(
          selected: isSelected,
          onPressed: () => _selectFile(file),
          leading: Icon(
            _getFileIcon(file.fileName),
            size: 20,
          ),
          title: Text(
            file.fileName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: Text(
            _formatDate(file.indexedAt),
            style: theme.typography.caption,
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel(fluent.FluentThemeData theme) {
    final file = _selectedFile!;
    final ext = file.fileName.split('.').last.toLowerCase();
    final isImage = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'}.contains(ext);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок файла
          Row(
            children: [
              Icon(
                _getFileIcon(file.fileName),
                size: 28,
                color: theme.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: theme.typography.subtitle?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file.filePath,
                      style: theme.typography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              fluent.IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openFile(file.filePath),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Превью изображения
          if (isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Image.file(
                  File(file.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    height: 120,
                    color: theme.inactiveColor.withValues(alpha: 0.1),
                    child: Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 48, color: theme.inactiveColor),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Описание
          Text('Описание', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          fluent.TextBox(
            controller: _descriptionController,
            maxLines: 4,
            placeholder: 'Добавьте описание файла для улучшения поиска…',
          ),
          const SizedBox(height: 16),

          // Теги
          Text('Теги', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          fluent.TextBox(
            controller: _tagsController,
            placeholder: 'Введите теги через запятую…',
          ),
          const SizedBox(height: 24),

          // Кнопка сохранения
          SizedBox(
            width: double.infinity,
            child: fluent.FilledButton(
              onPressed: _isSaving ? null : _saveReview,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: fluent.ProgressRing(strokeWidth: 2),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check, size: 18),
                    ),
                  Text(_isSaving ? 'Сохранение…' : 'Сохранить'),
                ],
              ),
            ),
          ),
        ],
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
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' =>
        Icons.image_outlined,
      'mp4' || 'avi' || 'mov' || 'mkv' => Icons.video_file_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audio_file_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
    if (diff.inDays < 1) return '${diff.inHours} ч. назад';
    if (diff.inDays < 7) return '${diff.inDays} дн. назад';
    return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/indexer.dart';
import 'app_scope.dart';

/// Экран «Требуют внимания» — Inbox для нераспознанных файлов.
///
/// Паттерн Master-Detail:
/// — Слева: список файлов, ожидающих описания.
/// — Справа: панель свойств (превью, описание, теги, кнопка «Сохранить»).
///
/// При сохранении описания файл убирается из списка.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
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
        // Если выбранный файл пропал из списка — сбрасываем выбор
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
      setState(() {
        _isLoading = false;
      });
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

      // Пересчитываем только эмбеддинги (описание/теги уже сохранены)
      root.contentEnrichmentCoordinator.enqueueReEmbedding(
        selected.filePath,
        selected.fileName,
      );

      root.logger.i('Review saved for: ${selected.fileName}');

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _selectedFile = null;
        _descriptionController.clear();
        _tagsController.clear();
      });

      // Перезагружаем список
      await _loadFiles();
    } catch (e, st) {
      root.logger.e('Failed to save review', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сохранения: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    final uri = Uri.file(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Требуют внимания (${_files.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? _buildEmptyState(theme)
              : _buildMasterDetail(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Все файлы обработаны',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Новые файлы появятся здесь автоматически',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterDetail(ThemeData theme) {
    return Row(
      children: [
        // === Master: список файлов ===
        SizedBox(
          width: 300,
          child: _buildFileList(theme),
        ),
        const VerticalDivider(width: 1),
        // === Detail: панель свойств ===
        Expanded(
          child: _selectedFile != null
              ? _buildDetailPanel(theme)
              : _buildNoSelectionState(theme),
        ),
      ],
    );
  }

  Widget _buildFileList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFile?.filePath == file.filePath;
        return _InboxFileListTile(
          file: file,
          isSelected: isSelected,
          onTap: () => _selectFile(file),
        );
      },
    );
  }

  Widget _buildNoSelectionState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Выберите файл из списка',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(ThemeData theme) {
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
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file.filePath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Открыть файл',
                onPressed: () => _openFile(file.filePath),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Превью изображения
          if (isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Image.file(
                  File(file.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Файловая информация
          _FileInfoCard(file: file, theme: theme),
          const SizedBox(height: 24),

          // Описание
          Text('Описание', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Добавьте описание файла для улучшения поиска…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Теги
          Text('Теги', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              hintText: 'Введите теги через запятую…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Кнопка сохранения
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveReview,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSaving ? 'Сохранение…' : 'Сохранить'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
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
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' => Icons.image_outlined,
      'mp4' || 'avi' || 'mov' || 'mkv' => Icons.video_file_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audio_file_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'txt' || 'md' || 'rst' => Icons.text_snippet_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

/// Элемент списка файлов в Master-панели.
class _InboxFileListTile extends StatelessWidget {
  final InboxFile file;
  final bool isSelected;
  final VoidCallback onTap;

  const _InboxFileListTile({
    required this.file,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = file.fileName.split('.').last.toLowerCase();

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                _getFileIcon(ext),
                size: 20,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      _formatDate(file.indexedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String ext) {
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.article_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'webp' => Icons.image_outlined,
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

/// Карточка информации о файле.
class _FileInfoCard extends StatelessWidget {
  final InboxFile file;
  final ThemeData theme;

  const _FileInfoCard({
    required this.file,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final fileOnDisk = File(file.filePath);
    final exists = fileOnDisk.existsSync();
    final sizeStr = exists ? _formatSize(fileOnDisk.lengthSync()) : 'Файл не найден';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _infoChip(Icons.storage_outlined, sizeStr),
            const SizedBox(width: 16),
            _infoChip(
              Icons.schedule_outlined,
              _formatDate(file.indexedAt),
            ),
            if (!exists) ...[
              const SizedBox(width: 16),
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.error,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

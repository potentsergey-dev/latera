import 'package:flutter/material.dart';

/// Диалог ввода описания файла.
///
/// Показывается когда новый файл обнаружен в наблюдаемой папке.
/// Пользователь вводит описание, по которому файл будет найден при поиске.
///
/// Возвращает [FileDescriptionResult] с описанием или null если отменено.
class FileDescriptionDialog extends StatefulWidget {
  /// Имя файла для отображения в заголовке.
  final String fileName;

  /// Полный путь к файлу (для отображения).
  final String filePath;

  /// Начальное описание (если редактируем существующее).
  final String? initialDescription;

  const FileDescriptionDialog({
    super.key,
    required this.fileName,
    required this.filePath,
    this.initialDescription,
  });

  /// Показать диалог и получить результат.
  ///
  /// Возвращает [FileDescriptionResult] с описанием или null если пользователь
  /// отменил ввод.
  static Future<FileDescriptionResult?> show(
    BuildContext context, {
    required String fileName,
    required String filePath,
    String? initialDescription,
  }) {
    return showDialog<FileDescriptionResult>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть тапом вне диалога
      builder: (context) => FileDescriptionDialog(
        fileName: fileName,
        filePath: filePath,
        initialDescription: initialDescription,
      ),
    );
  }

  @override
  State<FileDescriptionDialog> createState() => _FileDescriptionDialogState();
}

class _FileDescriptionDialogState extends State<FileDescriptionDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDescription ?? '');
    // Автофокус на поле ввода
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSave() {
    final description = _controller.text.trim();
    Navigator.of(context).pop(
      FileDescriptionResult(
        description: description,
        fileName: widget.fileName,
        filePath: widget.filePath,
      ),
    );
  }

  void _onSkip() {
    // Сохраняем с пустым описанием (файл всё равно индексируется по имени)
    Navigator.of(context).pop(
      FileDescriptionResult(
        description: '',
        fileName: widget.fileName,
        filePath: widget.filePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Новый файл')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Имя файла
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _getFileIcon(widget.fileName),
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Подсказка
            Text(
              'Введите описание файла для поиска:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),

            // Поле ввода описания
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Например: квартальный отчёт за Q3 2025',
                border: const OutlineInputBorder(),
                helperText:
                    'По этому описанию вы сможете потом найти файл',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _controller.clear(),
                ),
              ),
              onSubmitted: (_) => _onSave(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onSkip,
          child: const Text('Пропустить'),
        ),
        FilledButton.icon(
          onPressed: _onSave,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Сохранить'),
        ),
      ],
    );
  }

  /// Подбирает иконку по расширению файла.
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

/// Результат диалога ввода описания файла.
class FileDescriptionResult {
  /// Описание, введённое пользователем (может быть пустым).
  final String description;

  /// Имя файла.
  final String fileName;

  /// Полный путь к файлу.
  final String filePath;

  const FileDescriptionResult({
    required this.description,
    required this.fileName,
    required this.filePath,
  });
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../application/content_enrichment_coordinator.dart';

/// Локализованное название типа задачи обогащения.
String _jobTypeLabel(EnrichmentJobType type) {
  switch (type) {
    case EnrichmentJobType.textExtraction:
      return 'извлечение текста';
    case EnrichmentJobType.transcription:
      return 'транскрипция';
    case EnrichmentJobType.embeddings:
      return 'эмбеддинги';
    case EnrichmentJobType.ocr:
      return 'распознавание (OCR)';
    case EnrichmentJobType.autoSummary:
      return 'описание';
    case EnrichmentJobType.autoTags:
      return 'теги';
    case EnrichmentJobType.llmModelDownload:
      return 'Загрузка AI-модели…';
  }
}

/// Виджет статусной строки обработки файлов (Вариант 1 + 3).
///
/// Показывает анимированный баннер с прогресс-баром, когда в очереди
/// `ContentEnrichmentCoordinator` есть задачи. Плавно исчезает при
/// завершении всех задач.
class ProcessingStatusBar extends StatefulWidget {
  /// Stream прогресса из [ContentEnrichmentCoordinator.progressStream].
  final Stream<EnrichmentProgress> progressStream;

  /// Начальный снимок прогресса (из [ContentEnrichmentCoordinator.currentProgress]).
  final EnrichmentProgress initialProgress;

  const ProcessingStatusBar({
    super.key,
    required this.progressStream,
    required this.initialProgress,
  });

  @override
  State<ProcessingStatusBar> createState() => _ProcessingStatusBarState();
}

class _ProcessingStatusBarState extends State<ProcessingStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  StreamSubscription<EnrichmentProgress>? _sub;
  EnrichmentProgress _progress = const EnrichmentProgress();

  @override
  void initState() {
    super.initState();
    _progress = widget.initialProgress;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    if (_progress.isProcessing) {
      _animController.value = 1.0;
    }

    _sub = widget.progressStream.listen(_onProgress);
  }

  @override
  void didUpdateWidget(covariant ProcessingStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressStream != widget.progressStream) {
      _sub?.cancel();
      _sub = widget.progressStream.listen(_onProgress);
    }
  }

  void _onProgress(EnrichmentProgress p) {
    if (!mounted) return;
    setState(() {
      _progress = p;
    });
    if (p.isProcessing) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SizeTransition(
        sizeFactor: _fadeAnimation,
        axisAlignment: -1.0,
        child: _buildBar(context),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final remaining = _progress.activeCount + _progress.pendingCount;
    final progressValue = _progress.progress;
    final isLlmDownload =
        _progress.currentJobType == EnrichmentJobType.llmModelDownload;

    // Текст текущей операции
    String detailText;
    if (isLlmDownload) {
      detailText = 'all-MiniLM-L6-v2 · sentence-embeddings';
    } else if (_progress.currentFileName != null &&
        _progress.currentJobType != null) {
      final typeLabel = _jobTypeLabel(_progress.currentJobType!);
      detailText = '$typeLabel: ${_progress.currentFileName}';
    } else if (_progress.currentFileName != null) {
      detailText = _progress.currentFileName!;
    } else {
      detailText = 'подготовка…';
    }

    // Заголовок и счётчик
    final headerText =
        isLlmDownload ? 'Загрузка AI-модели' : 'Обработка файлов';
    final counterText = isLlmDownload
        ? '${_progress.completedCount}%'
        : '${_progress.completedCount} из ${_progress.totalEnqueued}'
            '${remaining > 0 ? '  ·  $remaining осталось' : ''}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Верхняя строка: иконка + счётчики
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                headerText,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                counterText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSecondaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Прогресс-бар
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 4,
              backgroundColor: colors.onSecondaryContainer.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(colors.primary),
            ),
          ),
          const SizedBox(height: 4),
          // Нижняя строка: текущая операция
          Text(
            detailText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSecondaryContainer.withValues(alpha: 0.7),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

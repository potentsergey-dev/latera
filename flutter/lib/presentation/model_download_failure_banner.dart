import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../infrastructure/di/app_composition_root.dart';
import 'app_scope.dart';

/// Баннер ошибки загрузки AI-модели с кнопкой «Повторить».
///
/// Слушает [ModelDownloadTracker.changes] и показывает компактный
/// Alert с описанием ошибки и кнопкой retry.
/// Автоматически исчезает, когда статус меняется на downloading/ready.
class ModelDownloadFailureBanner extends StatefulWidget {
  const ModelDownloadFailureBanner({super.key});

  @override
  State<ModelDownloadFailureBanner> createState() =>
      _ModelDownloadFailureBannerState();
}

class _ModelDownloadFailureBannerState
    extends State<ModelDownloadFailureBanner> {
  StreamSubscription<void>? _sub;
  AppCompositionRoot? _root;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = AppScope.of(context);
    if (!identical(root, _root)) {
      _sub?.cancel();
      _root = root;
      _sub = root.modelDownloadTracker.changes.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    if (root == null) return const SizedBox.shrink();

    final tracker = root.modelDownloadTracker;
    final embFailed = tracker.embeddingStatus == ModelStatus.failed;
    final ggufFailed = tracker.ggufStatus == ModelStatus.failed;

    if (!embFailed && !ggufFailed) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (embFailed)
          _FailureCard(
            title: l10n.downloadFailedTitle,
            detail: l10n.downloadFailedEmbedding,
            retryLabel: l10n.downloadRetryButton,
            onRetry: root.retryEmbeddingDownload,
            colors: colors,
            theme: theme,
          ),
        if (embFailed && ggufFailed) const SizedBox(height: 8),
        if (ggufFailed)
          _FailureCard(
            title: l10n.downloadFailedTitle,
            detail: l10n.downloadFailedGguf,
            retryLabel: l10n.downloadRetryButton,
            onRetry: root.retryGgufDownload,
            colors: colors,
            theme: theme,
          ),
      ],
    );
  }
}

class _FailureCard extends StatelessWidget {
  final String title;
  final String detail;
  final String retryLabel;
  final VoidCallback onRetry;
  final ColorScheme colors;
  final ThemeData theme;

  const _FailureCard({
    required this.title,
    required this.detail,
    required this.retryLabel,
    required this.onRetry,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer.withValues(alpha: 0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/app_config.dart';
import '../domain/license.dart';
import '../domain/rag.dart';
import '../l10n/app_localizations.dart';
import 'app_scope.dart';
import 'friendly_error.dart';

/// Экран «Спроси свою папку» (Local RAG).
///
/// Пользователь задаёт вопрос, релевантные фрагменты
/// из проиндексированных документов формируют ответ.
class RagScreen extends StatefulWidget {
  const RagScreen({super.key});

  @override
  State<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends State<RagScreen> {
  final _questionController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  RagQueryResult? _result;
  bool _isQuerying = false;
  String? _error;
  String _streamingAnswer = '';
  StreamSubscription<RagStreamEvent>? _streamSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _questionController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelQuery() {
    final root = AppScope.of(context);
    root.ragService.cancelQuery();
    _streamSub?.cancel();
    _streamSub = null;
    if (mounted) {
      setState(() {
        _isQuerying = false;
      });
    }
  }

  Future<void> _performQuery() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _isQuerying = true;
      _error = null;
      _result = null;
      _streamingAnswer = '';
    });

    try {
      final root = AppScope.of(context);
      final config = root.configService.currentConfig;

      // Check whether RAG is enabled
      if (!config.isFeatureEffectivelyEnabled(ContentFeature.rag)) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isQuerying = false;
          _error = config.resourceSaverEnabled
              ? l10n.ragDisabledResourceSaver
              : l10n.ragDisabledSettings;
        });
        return;
      }

      final stream = root.ragService.queryStream(question, topK: 5);
      _streamSub = stream.listen(
        (event) {
          if (!mounted) return;
          switch (event) {
            case RagTokenEvent(:final text):
              setState(() {
                _streamingAnswer += text;
              });
              // Автопрокрутка при получении токенов
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                  );
                }
              });
            case RagDoneEvent(:final result):
              setState(() {
                _result = result;
                _isQuerying = false;
                _streamingAnswer = '';
              });
          }
        },
        onError: (e) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = friendlyErrorMessage(e.toString(), l10n);
            _isQuerying = false;
          });
        },
        onDone: () {
          _streamSub = null;
        },
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _error = friendlyErrorMessage(e.toString(), l10n);
        _isQuerying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final licenseCoordinator = AppScope.of(context).licenseCoordinator;
    final isBasic = licenseCoordinator.currentLicense.mode == LicenseMode.basic;

    if (isBasic) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.ragTitle), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.ragTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.ragProRequired,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/settings');
                  },
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(l10n.ragLearnAboutPro),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ragTitle), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // === Question input ===
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: l10n.ragPlaceholder,
                      prefixIcon: const Icon(Icons.psychology),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _performQuery(),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                if (_isQuerying)
                  FilledButton.tonalIcon(
                    onPressed: _cancelQuery,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.ragStop),
                  )
                else
                  FilledButton.icon(
                    onPressed: _performQuery,
                    icon: const Icon(Icons.send),
                    label: Text(l10n.ragAsk),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // === Result ===
            Expanded(child: _buildResultArea(theme, l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultArea(ThemeData theme, AppLocalizations l10n) {
    // Ошибка
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Initial state
    if (_result == null && !_isQuerying) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.ragInitialHint,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.ragInitialSubhint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Загрузка / стриминг
    if (_isQuerying) {
      if (_streamingAnswer.isNotEmpty) {
        // Показываем ответ по мере генерации
        return SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.ragGenerating,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _streamingAnswer,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.ragSearching),
          ],
        ),
      );
    }

    // No result / error code
    if (_result != null && !_result!.hasAnswer) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              _ragErrorMessage(_result!.errorCode, l10n),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Ответ с источниками
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ответ
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_quote,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.ragResult,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _result!.answer,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          // Sources
          if (_result!.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.ragSourcesCount(_result!.sourceCount),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ..._result!.sources.map((source) => _SourceCard(source: source)),
          ],

          // Report inappropriate content button (required by Store policy 11.16)
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showReportDialog(context, l10n),
              icon: const Icon(Icons.flag_outlined, size: 16),
              label: Text(
                l10n.ragReportContent,
                style: theme.textTheme.bodySmall,
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportDialog(
      BuildContext context, AppLocalizations l10n) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ragReportDialogTitle),
        content: Text(l10n.ragReportDialogBody),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: 'laterateam@gmail.com',
                queryParameters: {
                  'subject': 'Latera: Report inappropriate AI content',
                },
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Open email client'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ragReportDialogOk),
          ),
        ],
      ),
    );
  }

  String _ragErrorMessage(String? errorCode, AppLocalizations l10n) {
    return switch (errorCode) {
      'empty_question' => l10n.ragErrorEmptyQuestion,
      'no_relevant_chunks' => l10n.ragErrorNoChunks,
      'query_failed' => l10n.ragErrorQueryFailed,
      _ => l10n.ragErrorUnknown,
    };
  }
}

/// Карточка источника (чанка).
class _SourceCard extends StatelessWidget {
  final RagSource source;

  const _SourceCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = source.filePath.split(RegExp(r'[/\\]')).last;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              source.chunkSnippet,
              style: theme.textTheme.bodySmall,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

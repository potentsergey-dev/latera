import 'dart:io';
import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../domain/app_config.dart';
import '../../../domain/rag.dart';
import '../../../infrastructure/di/app_composition_root.dart';
import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../friendly_error.dart';

/// Страница RAG «Спроси свою папку» (Windows-версия).
class WindowsRagPage extends fluent.StatefulWidget {
  const WindowsRagPage({super.key});

  @override
  fluent.State<WindowsRagPage> createState() => _WindowsRagPageState();
}

class _WindowsRagPageState extends fluent.State<WindowsRagPage> {
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

      // Гарантируем, что LLM загружена (перезагружаем если TTL выгрузил)
      await root.ensureLlmReady();

      final stream = root.ragService.queryStream(question, topK: 10);
      _streamSub = stream.listen(
        (event) {
          if (!mounted) return;
          switch (event) {
            case RagTokenEvent(:final text):
              setState(() {
                _streamingAnswer += text;
              });
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
  Widget build(fluent.BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: Text(AppLocalizations.of(context)!.ragTitle),
      ),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Предупреждение о недоступности LLM
            _buildLlmStatusBanner(theme),
            // Поле ввода вопроса
            Row(
              children: [
                Expanded(
                  child: fluent.TextBox(
                    controller: _questionController,
                    focusNode: _focusNode,
                    placeholder: AppLocalizations.of(context)!.ragPlaceholder,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.psychology, size: 18),
                    ),
                    onSubmitted: (_) => _performQuery(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isQuerying)
                  fluent.Button(
                    onPressed: _cancelQuery,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.stop, size: 16),
                        ),
                        Text(AppLocalizations.of(context)!.ragStop),
                      ],
                    ),
                  )
                else
                  fluent.FilledButton(
                    onPressed: _performQuery,
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.send, size: 16),
                        ),
                        Text(AppLocalizations.of(context)!.ragAsk),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Результат
            Expanded(child: _buildResultArea(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildLlmStatusBanner(fluent.FluentThemeData theme) {
    final root = AppScope.of(context);
    final status = root.modelDownloadTracker.ggufStatus;
    if (status == ModelStatus.ready) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final String message;
    final fluent.InfoBarSeverity severity;
    switch (status) {
      case ModelStatus.loadedSlowCpu:
        message = l10n.ragSlowCpuWarning;
        severity = fluent.InfoBarSeverity.warning;
      case ModelStatus.skippedLowRam:
        message = l10n.ragLowRamWarning;
        severity = fluent.InfoBarSeverity.warning;
      case ModelStatus.skippedLowDisk:
        message = l10n.ragLowDiskWarning;
        severity = fluent.InfoBarSeverity.warning;
      case ModelStatus.downloading:
        message = l10n.ragModelDownloading;
        severity = fluent.InfoBarSeverity.info;
      case ModelStatus.failed:
        message = l10n.ragModelFailed;
        severity = fluent.InfoBarSeverity.warning;
      default:
        message = l10n.ragModelNotLoaded;
        severity = fluent.InfoBarSeverity.warning;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: fluent.InfoBar(
        title: Text(
          status == ModelStatus.loadedSlowCpu
              ? l10n.ragSlowMode
              : l10n.ragLimitedMode,
        ),
        content: Text(message),
        severity: severity,
        isLong: true,
      ),
    );
  }

  Widget _buildResultArea(fluent.FluentThemeData theme) {
    // Ошибка
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Начальное состояние
    if (_result == null && !_isQuerying) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.ragInitialHint,
              style: theme.typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.ragInitialSubhint,
              style: theme.typography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Загрузка / стриминг
    if (_isQuerying) {
      if (_streamingAnswer.isNotEmpty) {
        return SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fluent.Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote,
                          size: 18,
                          color: theme.accentColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.ragGenerating,
                          style: theme.typography.bodyStrong,
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: fluent.ProgressRing(strokeWidth: 2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_streamingAnswer, style: theme.typography.body),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      final root = AppScope.of(context);
      final isSlowCpu =
          root.modelDownloadTracker.ggufStatus == ModelStatus.loadedSlowCpu;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const fluent.ProgressRing(),
            const SizedBox(height: 16),
            Text(
              isSlowCpu
                  ? AppLocalizations.of(context)!.ragGeneratingSlowCpu
                  : AppLocalizations.of(context)!.ragSearching,
            ),
          ],
        ),
      );
    }

    // Нет результатов
    if (_result != null && !_result!.hasAnswer) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.inactiveColor),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.ragNoAnswer,
              style: theme.typography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Ответ
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ответ
          fluent.Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.format_quote,
                      size: 18,
                      color: theme.accentColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.ragResult,
                      style: theme.typography.bodyStrong,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_result!.answer, style: theme.typography.body),
              ],
            ),
          ),

          // Источники
          if (_result!.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.ragSources,
              style: theme.typography.bodyStrong,
            ),
            const SizedBox(height: 8),
            for (final source in _result!.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: fluent.Card(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.filePath.split(Platform.pathSeparator).last,
                        style: theme.typography.bodyStrong,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source.chunkSnippet,
                        style: theme.typography.caption,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

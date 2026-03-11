import 'dart:io';
import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../domain/app_config.dart';
import '../../../domain/rag.dart';
import '../../app_scope.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performQuery() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _isQuerying = true;
      _error = null;
      _result = null;
    });

    try {
      final root = AppScope.of(context);
      final config = root.configService.currentConfig;

      if (!config.isFeatureEffectivelyEnabled(ContentFeature.rag)) {
        setState(() {
          _isQuerying = false;
          _error = config.resourceSaverEnabled
              ? 'RAG отключён в режиме экономии ресурсов'
              : 'RAG отключён в настройках';
        });
        return;
      }

      final result = await root.ragService.query(question, topK: 5);

      if (!mounted) return;
      setState(() {
        _result = result;
        _isQuerying = false;
      });

      if (result.hasAnswer) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isQuerying = false;
      });
    }
  }

  @override
  Widget build(fluent.BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    return fluent.ScaffoldPage(
      header: const fluent.PageHeader(
        title: Text('Спроси свою папку'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Поле ввода вопроса
            Row(
              children: [
                Expanded(
                  child: fluent.TextBox(
                    controller: _questionController,
                    focusNode: _focusNode,
                    placeholder: 'Задайте вопрос по вашим документам…',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.psychology, size: 18),
                    ),
                    onSubmitted: (_) => _performQuery(),
                  ),
                ),
                const SizedBox(width: 8),
                fluent.FilledButton(
                  onPressed: _isQuerying ? null : _performQuery,
                  child: Row(
                    children: [
                      if (_isQuerying)
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
                          child: Icon(Icons.send, size: 16),
                        ),
                      const Text('Спросить'),
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
            Icon(Icons.auto_awesome,
                size: 64, color: theme.accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Задайте вопрос по проиндексированным документам',
              style: theme.typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'RAG найдёт релевантные фрагменты и сформирует ответ',
              style: theme.typography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Загрузка
    if (_isQuerying) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            fluent.ProgressRing(),
            SizedBox(height: 16),
            Text('Ищу ответ в ваших документах…'),
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
              'Не удалось найти ответ',
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
                    Icon(Icons.auto_awesome, size: 18, color: theme.accentColor),
                    const SizedBox(width: 8),
                    Text('Ответ', style: theme.typography.bodyStrong),
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
            Text('Источники', style: theme.typography.bodyStrong),
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

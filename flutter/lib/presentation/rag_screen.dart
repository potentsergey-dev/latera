import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/app_config.dart';
import '../domain/license.dart';
import '../domain/rag.dart';
import 'app_scope.dart';

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

      // Проверяем, включён ли RAG
      if (!config.isFeatureEffectivelyEnabled(ContentFeature.rag)) {
        setState(() {
          _isQuerying = false;
          _error = config.resourceSaverEnabled
              ? 'RAG отключён в режиме экономии ресурсов'
              : 'RAG отключён в настройках';
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
          setState(() {
            _error = e.toString();
            _isQuerying = false;
          });
        },
        onDone: () {
          _streamSub = null;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isQuerying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final licenseCoordinator = AppScope.of(context).licenseCoordinator;
    final isBasic =
        licenseCoordinator.currentLicense.mode == LicenseMode.basic;

    if (isBasic) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Спроси свою папку'),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 64,
                    color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  'Функция «Спроси свою папку»',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Доступно в PRO',
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
                  label: const Text('Узнать о PRO'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Спроси свою папку'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // === Поле ввода вопроса ===
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Задайте вопрос по вашим документам…',
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
                    label: const Text('Стоп'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _performQuery,
                    icon: const Icon(Icons.send),
                    label: const Text('Спросить'),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // === Результат ===
            Expanded(
              child: _buildResultArea(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultArea(ThemeData theme) {
    // Ошибка
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 48, color: theme.colorScheme.error),
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

    // Начальное состояние
    if (_result == null && !_isQuerying) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome,
                size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Задайте вопрос по проиндексированным документам',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Поиск покажет релевантные фрагменты из ваших документов',
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
                          Icon(Icons.format_quote,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Генерация ответа…',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
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
            Icon(Icons.search_off,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              _ragErrorMessage(_result!.errorCode),
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
                      Icon(Icons.format_quote,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Результат',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
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

          // Источники
          if (_result!.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Источники (${_result!.sourceCount})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ..._result!.sources.map((source) => _SourceCard(source: source)),
          ],
        ],
      ),
    );
  }

  String _ragErrorMessage(String? errorCode) {
    return switch (errorCode) {
      'empty_question' => 'Введите вопрос',
      'no_relevant_chunks' =>
        'Релевантных фрагментов не найдено.\n'
            'Попробуйте переформулировать вопрос или проиндексируйте больше документов.',
      'not_implemented' =>
        'RAG ещё не подключён (stub-режим).\n'
            'Подключение появится после генерации FRB bindings.',
      'query_failed' => 'Ошибка при выполнении запроса',
      _ => 'Не удалось получить ответ',
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
                Icon(Icons.description,
                    size: 16, color: theme.colorScheme.secondary),
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

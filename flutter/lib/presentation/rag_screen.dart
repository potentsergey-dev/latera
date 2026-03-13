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

      final result = await root.ragService.query(question, topK: 5);

      if (!mounted) return;
      setState(() {
        _result = result;
        _isQuerying = false;
      });

      // Прокручиваем к ответу
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
                FilledButton.icon(
                  onPressed: _isQuerying ? null : _performQuery,
                  icon: _isQuerying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
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
              'RAG найдёт релевантные фрагменты и сформирует ответ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
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
                      Icon(Icons.auto_awesome,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Ответ',
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

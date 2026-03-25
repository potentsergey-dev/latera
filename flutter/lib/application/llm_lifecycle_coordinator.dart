import 'dart:async';

import 'package:logger/logger.dart';

import '../infrastructure/rust/generated/api.dart' as rust_api;

/// Координатор жизненного цикла генеративной LLM.
///
/// Управляет TTL (Time To Live) — выгружает модель из памяти
/// после [idleTimeout] бездействия. Это позволяет освобождать ~2 ГБ RAM
/// когда пользователь не пользуется RAG/генерацией.
///
/// Использование:
/// ```dart
/// coordinator.touch(); // помечает модель как "используется"
/// // ... через 3 минуты без touch() — unload
/// ```
class LlmLifecycleCoordinator {
  final Logger _logger;
  final Duration idleTimeout;

  Timer? _idleTimer;
  bool _isLoaded = false;

  LlmLifecycleCoordinator({
    required Logger logger,
    this.idleTimeout = const Duration(minutes: 3),
  }) : _logger = logger;

  /// Возвращает true, если генеративная LLM сейчас загружена в память.
  bool get isLoaded => _isLoaded;

  /// Помечает LLM как «используется» — перезапускает таймер idle.
  ///
  /// Вызывать перед каждым RAG-запросом, генерацией саммари/тегов.
  void touch() {
    _idleTimer?.cancel();
    _isLoaded = true;
    _idleTimer = Timer(idleTimeout, _onIdleTimeout);
  }

  /// Вызывается по истечении idle таймера.
  void _onIdleTimeout() {
    _logger.i('LLM idle timeout ($idleTimeout) — unloading generative model');
    _isLoaded = false;
    rust_api.unloadLlm();
    _logger.d('LLM unloaded via FFI');
  }

  /// Принудительно выгружает LLM (вызывается при dispose приложения).
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_isLoaded) {
      _isLoaded = false;
      rust_api.unloadLlm();
      _logger.d('LLM disposed via FFI');
    }
  }
}

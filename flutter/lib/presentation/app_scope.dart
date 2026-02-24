import 'package:flutter/material.dart';

import '../infrastructure/di/app_composition_root.dart';

/// InheritedWidget для предоставления AppCompositionRoot всему дереву виджетов.
///
/// Используется вместо создания Composition Root в StatefulWidget,
/// чтобы гарантировать:
/// - Едиственный экземпляр на всё время жизни приложения
/// - Корректное освобождение ресурсов при завершении
/// - Доступ из любого виджета через [AppScope.of]
class AppScope extends InheritedWidget {
  final AppCompositionRoot root;

  const AppScope({
    super.key,
    required this.root,
    required super.child,
  });

  /// Получить AppCompositionRoot из контекста.
  ///
  /// Бросает [StateError] если AppScope не найден в дереве.
  static AppCompositionRoot of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null) {
      throw StateError('AppScope not found in widget tree');
    }
    return scope.root;
  }

  /// Попытаться получить AppCompositionRoot из контекста.
  ///
  /// Возвращает null если AppScope не найден.
  static AppCompositionRoot? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    return scope?.root;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    // root не должен меняться, поэтому уведомления не требуются
    return false;
  }
}

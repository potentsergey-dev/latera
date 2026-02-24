import 'dart:async';

import 'package:flutter/material.dart';

import '../infrastructure/di/app_composition_root.dart';
import 'app_scope.dart';
import 'main_screen.dart';

/// Корневой виджет приложения.
///
/// Создаёт [AppCompositionRoot] и оборачивает всё приложение в [AppScope].
/// Освобождает ресурсы при завершении через [dispose].
class LateraApp extends StatefulWidget {
  const LateraApp({super.key});

  @override
  State<LateraApp> createState() => _LateraAppState();
}

class _LateraAppState extends State<LateraApp> with WidgetsBindingObserver {
  late final AppCompositionRoot _root;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _root = AppCompositionRoot.create();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При полном отключении приложения освобождаем ресурсы
    if (state == AppLifecycleState.detached) {
      _root.dispose().ignore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Освобождаем ресурсы при dispose виджета
    // unawaited используется т.к. State.dispose() не может быть async
    unawaited(_root.dispose().catchError((e, st) {
      debugPrint('Error during AppCompositionRoot dispose: $e\n$st');
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6));

    return AppScope(
      root: _root,
      child: MaterialApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}

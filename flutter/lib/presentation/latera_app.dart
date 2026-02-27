import 'dart:async';

import 'package:flutter/material.dart';

import '../infrastructure/di/app_composition_root.dart';
import 'app_scope.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

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
  AppCompositionRoot? _root;
  bool _isLoading = true;
  bool _needsOnboarding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRoot();
  }

  Future<void> _initRoot() async {
    try {
      final root = await AppCompositionRoot.create();
      
      // Проверяем, нужен ли онбординг
      final needsOnboarding = !root.configService.isOnboardingCompleted;
      
      if (mounted) {
        setState(() {
          _root = root;
          _needsOnboarding = needsOnboarding;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('Failed to initialize AppCompositionRoot: $e\n$st');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При полном отключении приложения освобождаем ресурсы
    if (state == AppLifecycleState.detached) {
      _root?.dispose().ignore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Освобождаем ресурсы при dispose виджета
    // unawaited используется т.к. State.dispose() не может быть async
    if (_root != null) {
      unawaited(_root!.dispose().catchError((e, st) {
        debugPrint('Error during AppCompositionRoot dispose: $e\n$st');
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6));

    // Показываем загрузку
    if (_isLoading) {
      return MaterialApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    // Показываем ошибку
    if (_error != null) {
      return MaterialApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Ошибка инициализации',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      _initRoot();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Нормальное состояние с навигацией
    return AppScope(
      root: _root!,
      child: MaterialApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
        ),
        initialRoute: _needsOnboarding ? '/onboarding' : '/main',
        routes: {
          '/onboarding': (context) => const OnboardingScreen(),
          '/main': (context) => const MainScreen(),
          '/search': (context) => const SearchScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

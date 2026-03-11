import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../infrastructure/di/app_composition_root.dart';
import '../infrastructure/tray/tray_service.dart';
import 'app_scope.dart';
import 'core/platform_info.dart';
import 'core/theme/app_theme.dart';
import 'core/windows/windows_navigation_shell.dart';
import 'inbox_screen.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';
import 'rag_screen.dart';
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
  TrayService? _trayService;
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

      // Инициализируем системный трей
      final tray = TrayService();
      await tray.initialize(onQuitRequested: _onQuitRequested);
      
      if (mounted) {
        setState(() {
          _root = root;
          _trayService = tray;
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

  /// Вызывается при выборе «Выход» в меню трея.
  void _onQuitRequested() {
    unawaited(_shutdown());
  }

  Future<void> _shutdown() async {
    await _trayService?.destroy();
    if (_root != null) {
      await _root!.dispose().catchError((e, st) {
        debugPrint('Error during AppCompositionRoot dispose: $e\n$st');
      });
    }
    exit(0);
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
    if (_trayService != null) {
      unawaited(_trayService!.destroy().catchError((e, st) {
        debugPrint('Error during TrayService destroy: $e\n$st');
      }));
    }
    if (_root != null) {
      unawaited(_root!.dispose().catchError((e, st) {
        debugPrint('Error during AppCompositionRoot dispose: $e\n$st');
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Показываем загрузку
    if (_isLoading) {
      return _buildLoadingApp();
    }

    // Показываем ошибку
    if (_error != null) {
      return _buildErrorApp();
    }

    // Нормальное состояние — разветвление по платформе
    return AppScope(
      root: _root!,
      child: PlatformInfo.isWindows
          ? _buildWindowsApp()
          : _buildMaterialApp(),
    );
  }

  // ─── Windows (Fluent UI) ───

  Widget _buildWindowsApp() {
    return fluent.FluentApp(
      title: 'Latera',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.fluentTheme,
      darkTheme: AppTheme.fluentDarkTheme,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          _updateTrayMenu(context);
          if (_needsOnboarding) {
            return const OnboardingScreen();
          }
          return const WindowsNavigationShell();
        },
      ),
    );
  }

  // ─── Material (Linux / macOS / fallback) ───

  Widget _buildMaterialApp() {
    return MaterialApp(
      title: 'Latera',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.materialTheme,
      darkTheme: AppTheme.materialDarkTheme,
      themeMode: ThemeMode.system,
      initialRoute: _needsOnboarding ? '/onboarding' : '/main',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/main': (context) => const MainScreen(),
        '/search': (context) => const SearchScreen(),
        '/inbox': (context) => const InboxScreen(),
        '/rag': (context) => const RagScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
      builder: (context, child) {
        _updateTrayMenu(context);
        return child!;
      },
    );
  }

  // ─── Loading / Error (используют Material для простоты) ───

  Widget _buildLoadingApp() {
    if (PlatformInfo.isWindows) {
      return fluent.FluentApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fluentTheme,
        home: const fluent.ScaffoldPage(
          content: Center(child: fluent.ProgressRing()),
        ),
      );
    }

    return MaterialApp(
      title: 'Latera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.materialTheme,
      home: const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildErrorApp() {
    if (PlatformInfo.isWindows) {
      return fluent.FluentApp(
        title: 'Latera',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fluentTheme,
        home: fluent.ScaffoldPage(
          content: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(fluent.FluentIcons.error, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Ошибка инициализации',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fluent.Colors.grey[120]),
                  ),
                  const SizedBox(height: 24),
                  fluent.FilledButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      _initRoot();
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(fluent.FluentIcons.refresh, size: 16),
                        SizedBox(width: 8),
                        Text('Повторить'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final colorScheme = ColorScheme.fromSeed(seedColor: AppTheme.accentColor);
    return MaterialApp(
      title: 'Latera',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
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

  void _updateTrayMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n != null && _trayService != null) {
      _trayService!.updateMenu(
        showLabel: l10n.trayShowWindow,
        quitLabel: l10n.trayQuit,
      );
    }
  }
}

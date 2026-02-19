import 'package:flutter/material.dart';

import 'main_screen.dart';

/// Корневой виджет приложения.
class LateraApp extends StatelessWidget {
  const LateraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6));

    return MaterialApp(
      title: 'Latera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}


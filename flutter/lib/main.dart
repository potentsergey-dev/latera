import 'package:flutter/material.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'presentation/latera_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Загружаем системный акцентный цвет (Windows / macOS)
  await SystemTheme.accentColor.load();

  // window_manager нужно инициализировать ДО runApp,
  // чтобы перехватить закрытие окна.
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(800, 500),
    title: 'Latera',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const LateraApp());
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Управляет системным треем и поведением окна при закрытии.
///
/// При закрытии окна приложение сворачивается в трей, а не завершается.
/// Двойной клик по иконке трея возвращает окно.
/// Пункт меню «Выход» полностью завершает приложение.
class TrayService with TrayListener, WindowListener {
  TrayService();

  VoidCallback? _onQuitRequested;

  bool _isInitialized = false;

  /// Инициализирует трей и window_manager.
  ///
  /// [onQuitRequested] вызывается при выборе «Выход» в меню трея.
  Future<void> initialize({required VoidCallback onQuitRequested}) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _onQuitRequested = onQuitRequested;

    // --- window_manager ---
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    // --- tray_manager ---
    await _setupTray();
    trayManager.addListener(this);
  }

  Future<void> _setupTray() async {
    // Используем .ico из ресурсов Runner-а — путь относительно exe.
    String iconPath;
    if (Platform.isWindows) {
      iconPath = 'windows/runner/resources/app_icon.ico';
    } else {
      iconPath = 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png';
    }

    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Latera');
  }

  /// Обновляет контекстное меню трея (нужно вызывать после получения l10n).
  Future<void> updateMenu({
    required String showLabel,
    required String quitLabel,
  }) async {
    final menu = Menu(items: [
      MenuItem(key: 'show', label: showLabel),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: quitLabel),
    ]);
    await trayManager.setContextMenu(menu);
  }

  // === TrayListener ===

  @override
  void onTrayIconMouseDown() {
    // Двойной клик не поддерживается на всех платформах —
    // используем одинарный для показа окна.
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
      case 'quit':
        _quit();
    }
  }

  // === WindowListener ===

  @override
  void onWindowClose() {
    // Сворачиваем в трей вместо закрытия.
    windowManager.hide();
  }

  // === Helpers ===

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  void _quit() {
    _onQuitRequested?.call();
  }

  /// Полностью закрыть приложение (вызывается из dispose).
  Future<void> destroy() async {
    if (!_isInitialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

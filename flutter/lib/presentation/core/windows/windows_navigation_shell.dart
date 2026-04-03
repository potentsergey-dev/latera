import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import 'windows_main_page.dart';
import 'windows_inbox_page.dart';
import 'windows_search_page.dart';
import 'windows_rag_page.dart';
import 'windows_settings_page.dart';

/// Корневой shell навигации для Windows 11.
///
/// Использует [fluent.NavigationView] с боковой панелью (NavigationPane)
/// в стиле WinUI 3 (Mica-фон, акриловые эффекты).
class WindowsNavigationShell extends fluent.StatefulWidget {
  final bool showOnboarding;

  const WindowsNavigationShell({super.key, this.showOnboarding = false});

  @override
  fluent.State<WindowsNavigationShell> createState() =>
      _WindowsNavigationShellState();
}

class _WindowsNavigationShellState
    extends fluent.State<WindowsNavigationShell> {
  int _selectedIndex = 0;

  @override
  Widget build(fluent.BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return fluent.NavigationView(
      pane: fluent.NavigationPane(
        selected: _selectedIndex,
        onChanged: (index) => setState(() => _selectedIndex = index),
        displayMode: fluent.PaneDisplayMode.compact,
        items: [
          fluent.PaneItem(
            icon: const Icon(Icons.home_outlined),
            title: Text(l10n.navHome),
            body: const WindowsMainPage(),
          ),
          fluent.PaneItem(
            icon: const Icon(Icons.search),
            title: Text(l10n.navSearch),
            body: const WindowsSearchPage(),
          ),
          fluent.PaneItem(
            icon: const Icon(Icons.inbox_outlined),
            title: Text(l10n.navInbox),
            body: const WindowsInboxPage(),
            infoBadge: _buildInboxBadge(),
          ),
          fluent.PaneItem(
            icon: const Icon(Icons.psychology_outlined),
            title: const Text('RAG'),
            body: const WindowsRagPage(),
          ),
        ],
        footerItems: [
          fluent.PaneItem(
            icon: const Icon(Icons.settings_outlined),
            title: Text(l10n.navSettings),
            body: const WindowsSettingsPage(),
          ),
        ],
      ),
    );
  }

  /// Бейдж для кнопки Inbox с количеством файлов, требующих внимания.
  Widget? _buildInboxBadge() {
    // Бейдж будет обновляться через stream — пока возвращаем null.
    // Конкретная реализация будет в WindowsInboxPage.
    return null;
  }
}

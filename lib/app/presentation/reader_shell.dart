import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/router/route_names.dart';

/// 主页面 Shell，负责底部 Tab 导航。
///
/// 这个组件只处理当前路由对应哪个 Tab，以及点击 Tab 后跳转到哪个根路径。
class ReaderShell extends StatelessWidget {
  const ReaderShell({required this.child, super.key});

  /// 当前路由匹配到的页面，由 go_router 注入。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(location),
        onDestinationSelected: (index) => _goToTab(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '书库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  int _selectedIndex(String location) {
    if (location.startsWith(RoutePaths.settings)) return 1;
    return 0;
  }

  void _goToTab(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(RoutePaths.library);
      case 1:
        context.go(RoutePaths.settings);
    }
  }
}

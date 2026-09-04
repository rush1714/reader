import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';

/// 主页面 Shell，负责底部 Tab 导航。
///
/// 底部导航不使用选中背景，只通过图标和文字颜色表达当前 Tab。
class ReaderShell extends ConsumerWidget {
  const ReaderShell({required this.child, super.key});

  /// 当前路由匹配到的页面，由 go_router 注入。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final isReader = location.startsWith('/reader/');
    final libraryState = ref.watch(libraryViewModelProvider).value;

    return Scaffold(
      body: child,
      bottomNavigationBar: isReader
          ? null
          : _BottomTabs(
              selectedIndex: _selectedIndex(location),
              onSelected: (index) => _goToTab(context, index, libraryState?.books ?? const []),
            ),
    );
  }

  int _selectedIndex(String location) {
    if (location.startsWith(RoutePaths.settings)) return 2;
    return 0;
  }

  void _goToTab(BuildContext context, int index, List<Book> books) {
    switch (index) {
      case 0:
        context.go(RoutePaths.library);
      case 1:
        final book = _currentBook(books);
        if (book == null) {
          context.go(RoutePaths.library);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('先导入一本书，再进入阅读。')),
          );
          return;
        }
        context.go(RoutePaths.readerForBook(book.id));
      case 2:
        context.go(RoutePaths.settings);
    }
  }

  Book? _currentBook(List<Book> books) {
    if (books.isEmpty) return null;
    for (final book in books) {
      if (book.readingProgress > 0 || book.lastReadAt != null || book.currentChapterIndex > 0) {
        return book;
      }
    }
    return books.first;
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.52)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 8, 34, 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomTabItem(
                selected: selectedIndex == 0,
                icon: Icons.auto_stories_outlined,
                selectedIcon: Icons.auto_stories,
                label: '书库',
                onTap: () => onSelected(0),
              ),
              _BottomTabItem(
                selected: selectedIndex == 1,
                icon: Icons.chrome_reader_mode_outlined,
                selectedIcon: Icons.chrome_reader_mode_rounded,
                label: '阅读',
                onTap: () => onSelected(1),
              ),
              _BottomTabItem(
                selected: selectedIndex == 2,
                icon: Icons.tune_outlined,
                selectedIcon: Icons.tune,
                label: '设置',
                onTap: () => onSelected(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: -0.1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 25),
              const SizedBox(height: 3),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

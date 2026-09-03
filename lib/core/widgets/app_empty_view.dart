import 'package:flutter/material.dart';

/// 通用空状态视图。
///
/// 用于书库为空、章节为空、设置项暂无可选声音等轻量场景。
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  /// 空状态提示文案。
  final String message;

  /// 空状态图标。
  final IconData icon;

  /// 可选操作按钮。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

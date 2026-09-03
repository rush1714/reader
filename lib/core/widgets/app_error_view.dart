import 'package:flutter/material.dart';

/// 通用错误状态视图。
///
/// 页面层只负责展示错误与重试入口，错误映射和恢复逻辑应留在 ViewModel 或 Repository。
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.error,
    this.onRetry,
    super.key,
  });

  /// 需要展示的错误对象。
  final Object error;

  /// 可选重试回调。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

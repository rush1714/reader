import 'package:flutter/material.dart';

/// App 共享文字样式。
///
/// 页面应优先结合 `Theme.of(context).textTheme` 使用这些样式，保持风格统一。
abstract final class AppTextStyles {
  /// 分区标题。
  static const sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  /// 阅读正文的基础样式，实际字号由阅读器设置动态覆盖。
  static const readerBody = TextStyle(
    height: 1.75,
    letterSpacing: 0.2,
  );
}

import 'package:flutter/material.dart';

/// App 统一颜色入口。
///
/// 第一版只维护阅读器需要的种子色和少量阅读背景色，避免提前引入复杂设计系统。
abstract final class AppColors {
  /// 主题种子色，来自图书 Logo 的蓝色。
  static const seed = Color(0xFF2957D8);

  /// 明亮模式下的阅读纸张色。
  static const readingPaperLight = Color(0xFFFFFBF2);

  /// 深色模式下的阅读背景色。
  static const readingPaperDark = Color(0xFF111827);
}

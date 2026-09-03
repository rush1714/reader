import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 主题配置入口。
///
/// Feature 页面应优先使用 `Theme.of(context)`，不要各自维护割裂的颜色体系。
abstract final class AppTheme {
  /// 明亮主题。
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: AppColors.seed);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }

  /// 深色主题。
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
}

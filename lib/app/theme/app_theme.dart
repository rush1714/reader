import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 主题配置入口。
///
/// Feature 页面应优先使用 `Theme.of(context)`，不要各自维护割裂的颜色体系。
abstract final class AppTheme {
  /// 明亮主题：羊皮暖黄。
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.parchmentAccent,
      brightness: Brightness.light,
      surface: AppColors.parchmentBackground,
    ).copyWith(
      primary: AppColors.parchmentAccent,
      onPrimary: AppColors.parchmentCard,
      primaryContainer: AppColors.parchmentSurface,
      onPrimaryContainer: AppColors.parchmentAccent,
      secondary: const Color(0xFF8C5B32),
      surface: AppColors.parchmentBackground,
      surfaceContainerHighest: AppColors.parchmentSurface,
      onSurface: AppColors.parchmentText,
      onSurfaceVariant: AppColors.parchmentMuted,
      outline: AppColors.parchmentBorder,
    );

    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.parchmentBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.parchmentBackground,
        foregroundColor: AppColors.parchmentText,
      ),
      cardTheme: _cardTheme(AppColors.parchmentCard, AppColors.parchmentBorder),
    );
  }

  /// 深色主题：雅致深蓝。
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.navyAccent,
      brightness: Brightness.dark,
      surface: AppColors.navyBackground,
    ).copyWith(
      primary: AppColors.navyAccent,
      onPrimary: AppColors.navyBackground,
      primaryContainer: AppColors.navySurface,
      onPrimaryContainer: AppColors.navyText,
      secondary: const Color(0xFF7DD3FC),
      surface: AppColors.navyBackground,
      surfaceContainerHighest: AppColors.navyCard,
      onSurface: AppColors.navyText,
      onSurfaceVariant: const Color(0xFF94A3B8),
      outline: const Color(0xFF2E5282),
    );

    return _baseTheme(colorScheme).copyWith(
      scaffoldBackgroundColor: AppColors.navyBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.navyBackground,
        foregroundColor: AppColors.navyText,
      ),
      cardTheme: _cardTheme(AppColors.navyCard, const Color(0xFF2E5282)),
    );
  }

  static ThemeData _baseTheme(ColorScheme colorScheme) {
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'System',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.72)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.outline.withValues(alpha: 0.36),
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.outline.withValues(alpha: 0.32),
      ),
    );
  }

  static CardThemeData _cardTheme(Color color, Color borderColor) {
    return CardThemeData(
      clipBehavior: Clip.antiAlias,
      color: color,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor.withValues(alpha: 0.72)),
      ),
    );
  }
}

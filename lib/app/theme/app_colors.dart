import 'package:flutter/material.dart';

/// App 统一颜色入口。
///
/// 主题以羊皮暖黄和雅致深蓝为核心，尽量贴近纸书阅读的温润质感。
abstract final class AppColors {
  /// 深蓝主题种子色。
  static const seed = Color(0xFF153443);

  /// 羊皮暖黄背景。
  static const parchmentBackground = Color(0xFFF5EFE3);

  /// 羊皮卡片色。
  static const parchmentCard = Color(0xFFFAF7F0);

  /// 羊皮浅底色。
  static const parchmentSurface = Color(0xFFEDE5D6);

  /// 羊皮主文字色。
  static const parchmentText = Color(0xFF2C2825);

  /// 羊皮次级文字色。
  static const parchmentMuted = Color(0xFF6E665E);

  /// 羊皮暖棕强调色。
  static const parchmentAccent = Color(0xFF6C4A2D);

  /// 羊皮边框色。
  static const parchmentBorder = Color(0xFFE3D8C6);

  /// 复古金色。
  static const parchmentGold = Color(0xFFCBB279);

  /// 深蓝背景。
  static const navyBackground = Color(0xFF0F172A);

  /// 深蓝阅读纸张色。
  static const navyReader = Color(0xFF1E3A5F);

  /// 深蓝卡片色。
  static const navyCard = Color(0xFF1E293B);

  /// 深蓝浅表面色。
  static const navySurface = Color(0xFF243B53);

  /// 深蓝强调色。
  static const navyAccent = Color(0xFF38BDF8);

  /// 深蓝文字色。
  static const navyText = Color(0xFFE2E8F0);

  /// 明亮模式下的阅读纸张色。
  static const readingPaperLight = parchmentBackground;

  /// 深色模式下的阅读背景色。
  static const readingPaperDark = navyReader;
}

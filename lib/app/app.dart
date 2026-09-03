import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/app/router/app_router.dart';
import 'package:reader_app/app/theme/app_theme.dart';
import 'package:reader_app/features/settings/data/settings_repository.dart';

/// Reader App 的应用根组件。
///
/// 根组件只承载 App 级配置，例如路由、主题和全局 Material 配置。
/// 书库、阅读器和语音逻辑都放在各自 Feature 中，避免入口层持续膨胀。
class ReaderApp extends ConsumerWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(readerSettingsProvider).value;

    return MaterialApp.router(
      title: 'Reader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings?.themeMode ?? ThemeMode.system,
      routerConfig: router,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/presentation/reader_shell.dart';
import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/features/library/presentation/library_page.dart';
import 'package:reader_app/features/reader/presentation/reader_page.dart';
import 'package:reader_app/features/settings/presentation/settings_page.dart';

/// 提供全局 GoRouter 实例。
///
/// 路由属于 App 层职责，Feature 只提供页面，不在 Repository 或 Service 中做跳转。
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.library,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ReaderShell(child: child),
        routes: [
          GoRoute(
            name: RouteNames.library,
            path: RoutePaths.library,
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            name: RouteNames.reader,
            path: RoutePaths.reader,
            builder: (context, state) => ReaderPage(
              bookId: state.pathParameters['bookId'] ?? '',
            ),
          ),
          GoRoute(
            name: RouteNames.settings,
            path: RoutePaths.settings,
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});

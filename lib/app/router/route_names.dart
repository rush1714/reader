/// App 内所有路由名称的集中定义。
abstract final class RouteNames {
  static const library = 'library';
  static const reader = 'reader';
  static const settings = 'settings';
}

/// App 内所有路由路径的集中定义。
abstract final class RoutePaths {
  static const library = '/library';
  static const reader = '/reader/:bookId';
  static const settings = '/settings';

  /// 根据图书 ID 构造阅读页路径。
  static String readerForBook(String bookId) => '/reader/$bookId';
}

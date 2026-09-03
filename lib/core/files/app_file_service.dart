import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 提供本地文件服务。
final appFileServiceProvider = Provider<AppFileService>((ref) {
  return const AppFileService();
});

/// App 私有文件目录管理服务。
///
/// 导入书籍时会把用户选择的文件复制到 App 文档目录，后续阅读不再依赖原文件位置。
class AppFileService {
  const AppFileService();

  /// 将外部文件复制到 App 私有书籍目录。
  Future<String> copyBookFile({
    required String sourcePath,
    required String bookId,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const FileSystemException('找不到选择的文件');
    }

    final directory = await _booksDirectory();
    final extension = p.extension(sourcePath).toLowerCase();
    final targetPath = p.join(directory.path, '$bookId$extension');
    await source.copy(targetPath);
    return targetPath;
  }

  /// 删除导入后的书籍文件。
  Future<void> deleteBookFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _booksDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'books'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}

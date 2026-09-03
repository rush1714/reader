import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';

/// 解析完成但尚未写入书库的一本书。
///
/// Parser 负责从外部文件生成该对象，Repository 负责复制文件并持久化。
class ImportedBook {
  const ImportedBook({
    required this.title,
    required this.author,
    required this.format,
    required this.chapters,
  });

  /// 书名。
  final String title;

  /// 作者。
  final String author;

  /// 文件格式。
  final BookFormat format;

  /// 解析出的章节草稿。
  final List<ImportedChapter> chapters;
}

/// 尚未入库的章节草稿。
class ImportedChapter {
  const ImportedChapter({
    required this.title,
    required this.content,
  });

  /// 章节标题。
  final String title;

  /// 章节正文纯文本。
  final String content;

  /// 转换为可持久化章节。
  BookChapter toChapter({
    required String id,
    required String bookId,
    required int chapterIndex,
  }) {
    return BookChapter(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex,
      title: title,
      content: content,
    );
  }
}

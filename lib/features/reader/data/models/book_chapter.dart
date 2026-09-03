/// 一本书中的单个章节。
///
/// 章节正文保存在 SQLite 中，阅读页按当前章节加载，避免一次性把整本书放进 UI 状态。
class BookChapter {
  const BookChapter({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    required this.content,
  });

  /// 本地章节 ID。
  final String id;

  /// 所属图书 ID。
  final String bookId;

  /// 从 0 开始的章节序号。
  final int chapterIndex;

  /// 章节标题。
  final String title;

  /// 章节纯文本内容。
  final String content;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'title': title,
      'content': content,
    };
  }

  factory BookChapter.fromMap(Map<String, Object?> map) {
    return BookChapter(
      id: map['id']! as String,
      bookId: map['bookId']! as String,
      chapterIndex: map['chapterIndex']! as int,
      title: map['title']! as String,
      content: map['content']! as String,
    );
  }
}

/// 章节目录项。
///
/// 目录只需要标题和序号，不加载正文，避免打开目录时占用过多内存。
class ChapterSummary {
  const ChapterSummary({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
  });

  /// 本地章节 ID。
  final String id;

  /// 所属图书 ID。
  final String bookId;

  /// 从 0 开始的章节序号。
  final int chapterIndex;

  /// 章节标题。
  final String title;

  factory ChapterSummary.fromMap(Map<String, Object?> map) {
    return ChapterSummary(
      id: map['id']! as String,
      bookId: map['bookId']! as String,
      chapterIndex: map['chapterIndex']! as int,
      title: map['title']! as String,
    );
  }
}

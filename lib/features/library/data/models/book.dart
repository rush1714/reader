/// 图书文件类型。
enum BookFormat {
  /// EPUB 电子书。
  epub,

  /// 纯文本或 Markdown 文档。
  text,
}

/// 本地书库中的一本书。
///
/// 该模型只描述本机持久化后的书籍元数据，不直接持有章节正文，避免列表页加载过多内容。
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.filePath,
    required this.importedAt,
    required this.chapterCount,
    required this.currentChapterIndex,
  });

  /// 本地唯一 ID。
  final String id;

  /// 书名。
  final String title;

  /// 作者，无法解析时使用“未知作者”。
  final String author;

  /// 文件格式。
  final BookFormat format;

  /// 复制到 App 文档目录后的文件路径。
  final String filePath;

  /// 导入时间。
  final DateTime importedAt;

  /// 章节数量。
  final int chapterCount;

  /// 最近阅读章节索引。
  final int currentChapterIndex;

  Book copyWith({
    String? title,
    String? author,
    int? chapterCount,
    int? currentChapterIndex,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format,
      filePath: filePath,
      importedAt: importedAt,
      chapterCount: chapterCount ?? this.chapterCount,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format.name,
      'filePath': filePath,
      'importedAt': importedAt.toIso8601String(),
      'chapterCount': chapterCount,
      'currentChapterIndex': currentChapterIndex,
    };
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id']! as String,
      title: map['title']! as String,
      author: map['author']! as String,
      format: _formatFromName(map['format']! as String),
      filePath: map['filePath']! as String,
      importedAt: DateTime.parse(map['importedAt']! as String),
      chapterCount: map['chapterCount']! as int,
      currentChapterIndex: map['currentChapterIndex']! as int,
    );
  }

  static BookFormat _formatFromName(String name) {
    for (final value in BookFormat.values) {
      if (value.name == name) return value;
    }
    return BookFormat.text;
  }
}

/// 图书格式展示文案。
extension BookFormatLabel on BookFormat {
  String get label {
    return switch (this) {
      BookFormat.epub => 'EPUB',
      BookFormat.text => '文档',
    };
  }
}

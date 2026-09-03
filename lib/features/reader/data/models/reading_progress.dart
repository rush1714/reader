/// 图书阅读进度。
///
/// 第一版记录当前章节和粗粒度进度百分比。后续如需精确恢复滚动位置，可以扩展
/// `scrollOffset` 或 EPUB CFI 等字段。
class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.progress,
    required this.updatedAt,
  });

  /// 所属图书 ID。
  final String bookId;

  /// 当前章节索引。
  final int chapterIndex;

  /// 整本书进度，范围 0.0 - 1.0。
  final double progress;

  /// 更新时间。
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'progress': progress,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromMap(Map<String, Object?> map) {
    return ReadingProgress(
      bookId: map['bookId']! as String,
      chapterIndex: map['chapterIndex']! as int,
      progress: (map['progress']! as num).toDouble(),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
    );
  }
}

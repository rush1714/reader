/// 图书阅读进度。
///
/// 除当前章节和整本书进度外，还会记录章节内的滚动位置，以便重新打开应用时恢复到
/// 上次阅读的位置。
class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.progress,
    required this.updatedAt,
    this.scrollOffset = 0,
    this.chapterProgress = 0,
  });

  /// 所属图书 ID。
  final String bookId;

  /// 当前章节索引。
  final int chapterIndex;

  /// 整本书进度，范围 0.0 - 1.0。
  final double progress;

  /// 当前章节的滚动像素位置。
  final double scrollOffset;

  /// 当前章节内的相对阅读进度，范围 0.0 - 1.0。
  final double chapterProgress;

  /// 更新时间。
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'progress': progress,
      'scrollOffset': scrollOffset,
      'chapterProgress': chapterProgress,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromMap(Map<String, Object?> map) {
    return ReadingProgress(
      bookId: map['bookId']! as String,
      chapterIndex: map['chapterIndex']! as int,
      progress: (map['progress']! as num).toDouble(),
      scrollOffset: (map['scrollOffset'] as num?)?.toDouble() ?? 0,
      chapterProgress: (map['chapterProgress'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse(map['updatedAt']! as String),
    );
  }
}

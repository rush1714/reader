import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/core/storage/app_database.dart';
import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/data/library_repository.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';

/// 提供阅读器仓库。
final readerRepositoryProvider = Provider<ReaderRepository>((ref) {
  return ReaderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(libraryRepositoryProvider),
  );
});

/// 阅读器数据仓库。
///
/// 负责按章节加载正文和保存阅读进度。阅读页不直接查询 SQLite。
class ReaderRepository {
  const ReaderRepository(
    this._database,
    this._libraryRepository,
  );

  final AppDatabase _database;
  final LibraryRepository _libraryRepository;

  /// 加载图书元数据。
  Future<Book?> getBook(String bookId) {
    return _libraryRepository.getBook(bookId);
  }

  /// 加载章节目录。
  Future<List<ChapterSummary>> listChapters(String bookId) async {
    final db = await _database.database;
    final rows = await db.query(
      'chapters',
      columns: ['id', 'bookId', 'chapterIndex', 'title'],
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterIndex ASC',
    );
    return rows.map(ChapterSummary.fromMap).toList();
  }

  /// 加载指定章节。
  Future<BookChapter?> getChapter({
    required String bookId,
    required int chapterIndex,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'chapters',
      where: 'bookId = ? AND chapterIndex = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookChapter.fromMap(rows.first);
  }

  /// 加载阅读进度。
  Future<ReadingProgress?> getProgress(String bookId) async {
    final db = await _database.database;
    final rows = await db.query(
      'reading_progress',
      where: 'bookId = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReadingProgress.fromMap(rows.first);
  }

  /// 保存当前章节进度。
  Future<void> saveProgress({
    required Book book,
    required int chapterIndex,
  }) {
    final progress = book.chapterCount <= 1 ? 1.0 : chapterIndex / (book.chapterCount - 1);
    return _libraryRepository.updateCurrentChapter(
      bookId: book.id,
      chapterIndex: chapterIndex,
      progress: progress.clamp(0, 1),
    );
  }
}

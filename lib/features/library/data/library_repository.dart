import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:reader_app/core/files/app_file_service.dart';
import 'package:reader_app/core/storage/app_database.dart';
import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/data/services/book_parser_service.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';

/// 提供书籍解析器。
final bookParserServiceProvider = Provider<BookParserService>((ref) {
  return const BookParserService();
});

/// 提供书库仓库。
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appFileServiceProvider),
    ref.watch(bookParserServiceProvider),
  );
});

/// 本地书库仓库。
///
/// 负责导入、查询、删除图书，以及协调文件系统、解析器和 SQLite。页面不直接操作文件或 SQL。
class LibraryRepository {
  LibraryRepository(this._database, this._fileService, this._parser);

  final AppDatabase _database;
  final AppFileService _fileService;
  final BookParserService _parser;
  final Uuid _uuid = const Uuid();

  /// 查询书库图书列表。
  Future<List<Book>> listBooks() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
SELECT
  books.*,
  reading_progress.progress AS readingProgress,
  reading_progress.updatedAt AS lastReadAt
FROM books
LEFT JOIN reading_progress ON reading_progress.bookId = books.id
ORDER BY COALESCE(reading_progress.updatedAt, books.importedAt) DESC
''');
    return rows.map(Book.fromMap).toList();
  }

  /// 根据 ID 查询图书。
  Future<Book?> getBook(String bookId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
SELECT
  books.*,
  reading_progress.progress AS readingProgress,
  reading_progress.updatedAt AS lastReadAt
FROM books
LEFT JOIN reading_progress ON reading_progress.bookId = books.id
WHERE books.id = ?
LIMIT 1
''',
      [bookId],
    );
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  /// 从外部文件导入图书。
  Future<Book> importBook(String sourcePath) async {
    final imported = await _parser.parse(sourcePath);
    final bookId = _uuid.v4();
    final copiedPath = await _fileService.copyBookFile(
      sourcePath: sourcePath,
      bookId: bookId,
    );

    final book = Book(
      id: bookId,
      title: imported.title,
      author: imported.author,
      format: imported.format,
      filePath: copiedPath,
      importedAt: DateTime.now(),
      chapterCount: imported.chapters.length,
      currentChapterIndex: 0,
    );

    final progress = ReadingProgress(
      bookId: bookId,
      chapterIndex: 0,
      progress: 0,
      updatedAt: DateTime.now(),
    );

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert('books', book.toMap());
      await txn.insert('reading_progress', progress.toMap());
      for (var i = 0; i < imported.chapters.length; i += 1) {
        final chapter = imported.chapters[i].toChapter(
          id: _uuid.v4(),
          bookId: bookId,
          chapterIndex: i,
        );
        await txn.insert('chapters', chapter.toMap());
      }
    });

    return book;
  }

  /// 删除图书和对应章节。
  Future<void> deleteBook(Book book) async {
    final db = await _database.database;
    await db.delete('books', where: 'id = ?', whereArgs: [book.id]);
    await _fileService.deleteBookFile(book.filePath);
  }

  /// 更新图书最近阅读章节。
  Future<void> updateCurrentChapter({
    required String bookId,
    required int chapterIndex,
    required double progress,
    required double scrollOffset,
    required double chapterProgress,
  }) async {
    final db = await _database.database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.update(
        'books',
        {'currentChapterIndex': chapterIndex},
        where: 'id = ?',
        whereArgs: [bookId],
      );
      await txn.insert(
        'reading_progress',
        ReadingProgress(
          bookId: bookId,
          chapterIndex: chapterIndex,
          progress: progress,
          scrollOffset: scrollOffset,
          chapterProgress: chapterProgress,
          updatedAt: now,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';
import 'package:reader_app/features/reader/presentation/reader_view_model.dart';

void main() {
  test('ReaderState progress uses completed current chapter ratio', () {
    final book = Book(
      id: 'book-1',
      title: '测试书籍',
      author: '未知作者',
      format: BookFormat.text,
      filePath: '/tmp/book.txt',
      importedAt: DateTime(2026),
      chapterCount: 10,
      currentChapterIndex: 0,
    );

    final state = ReaderState(
      book: book,
      chapter: const BookChapter(
        id: 'chapter-1',
        bookId: 'book-1',
        chapterIndex: 0,
        title: '第一章',
        content: '正文',
      ),
      chapters: const [],
    );

    expect(state.progress, 0.1);
  });

  test('ReaderState progress reaches one on the last chapter', () {
    final book = Book(
      id: 'book-1',
      title: '测试书籍',
      author: '未知作者',
      format: BookFormat.text,
      filePath: '/tmp/book.txt',
      importedAt: DateTime(2026),
      chapterCount: 10,
      currentChapterIndex: 9,
    );

    final state = ReaderState(
      book: book,
      chapter: const BookChapter(
        id: 'chapter-10',
        bookId: 'book-1',
        chapterIndex: 9,
        title: '第十章',
        content: '正文',
      ),
      chapters: const [],
    );

    expect(state.progress, 1);
  });

  test('ReaderState exposes saved chapter scroll position', () {
    final book = Book(
      id: 'book-1',
      title: '测试书籍',
      author: '未知作者',
      format: BookFormat.text,
      filePath: '/tmp/book.txt',
      importedAt: DateTime(2026),
      chapterCount: 10,
      currentChapterIndex: 2,
    );

    final state = ReaderState(
      book: book,
      chapter: const BookChapter(
        id: 'chapter-3',
        bookId: 'book-1',
        chapterIndex: 2,
        title: '第三章',
        content: '正文',
      ),
      chapters: const [],
      readingProgress: ReadingProgress(
        bookId: 'book-1',
        chapterIndex: 2,
        progress: 0.25,
        scrollOffset: 680,
        chapterProgress: 0.42,
        updatedAt: DateTime(2026),
      ),
    );

    expect(state.savedScrollOffset, 680);
    expect(state.savedChapterProgress, 0.42);
    expect(state.progress, 0.25);
  });
}

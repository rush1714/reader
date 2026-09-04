import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/reader_repository.dart';

/// 阅读页状态。
class ReaderState {
  const ReaderState({
    required this.book,
    required this.chapter,
    required this.chapters,
  });

  /// 当前图书。
  final Book book;

  /// 当前章节。
  final BookChapter chapter;

  /// 当前图书章节目录。
  final List<ChapterSummary> chapters;

  /// 是否还有上一章。
  bool get canGoPrevious => chapter.chapterIndex > 0;

  /// 是否还有下一章。
  bool get canGoNext => chapter.chapterIndex < book.chapterCount - 1;

  /// 整本书进度展示值。
  double get progress {
    if (book.chapterCount <= 0) return 0;
    return (chapter.chapterIndex + 1) / book.chapterCount;
  }
}

/// 阅读页 ViewModel Provider。
final readerViewModelProvider = AsyncNotifierProvider.family<ReaderViewModel, ReaderState, String>(
  ReaderViewModel.new,
);

/// 阅读页 ViewModel。
///
/// 负责加载当前章节、切换章节和保存阅读进度。正文排版与滚动仍由页面层负责。
class ReaderViewModel extends AsyncNotifier<ReaderState> {
  ReaderViewModel(this.bookId);

  /// 当前阅读图书 ID。
  final String bookId;

  @override
  Future<ReaderState> build() async {
    final repository = ref.watch(readerRepositoryProvider);
    final book = await repository.getBook(bookId);
    if (book == null) {
      throw StateError('没有找到这本书，可能已被删除。');
    }

    final progress = await repository.getProgress(bookId);
    final chapterIndex = progress?.chapterIndex ?? book.currentChapterIndex;
    final loaded = await _loadChapter(chapterIndex);
    await _saveProgress(loaded);
    ref.invalidate(libraryViewModelProvider);
    return loaded;
  }

  /// 跳转上一章。
  Future<void> previousChapter() async {
    final current = state.value;
    if (current == null || !current.canGoPrevious) return;
    await _setChapter(current.chapter.chapterIndex - 1);
  }

  /// 跳转下一章。
  Future<void> nextChapter() async {
    final current = state.value;
    if (current == null || !current.canGoNext) return;
    await _setChapter(current.chapter.chapterIndex + 1);
  }

  /// 跳转到指定章节。
  Future<void> goToChapter(int chapterIndex) async {
    await _setChapter(chapterIndex);
  }

  Future<void> _setChapter(int chapterIndex) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final next = await _loadChapter(chapterIndex);
      await _saveProgress(next);
      ref.invalidate(libraryViewModelProvider);
      return next;
    });
  }

  Future<void> _saveProgress(ReaderState next) {
    return ref.read(readerRepositoryProvider).saveProgress(
          book: next.book,
          chapterIndex: next.chapter.chapterIndex,
        );
  }

  Future<ReaderState> _loadChapter(int chapterIndex) async {
    final repository = ref.read(readerRepositoryProvider);
    final book = await repository.getBook(bookId);
    if (book == null) {
      throw StateError('没有找到这本书，可能已被删除。');
    }

    final chapters = await repository.listChapters(book.id);
    if (chapters.isEmpty) {
      throw StateError('这本书没有可阅读章节。');
    }

    final safeChapterIndex = chapterIndex.clamp(0, book.chapterCount - 1);
    final chapter = await repository.getChapter(
      bookId: book.id,
      chapterIndex: safeChapterIndex,
    );
    if (chapter == null) {
      throw StateError('没有找到章节内容。');
    }

    return ReaderState(
      book: book,
      chapter: chapter,
      chapters: chapters,
    );
  }
}

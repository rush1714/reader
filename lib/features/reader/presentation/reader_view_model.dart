import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';
import 'package:reader_app/features/reader/data/reader_repository.dart';

/// 阅读页状态。
class ReaderState {
  const ReaderState({
    required this.book,
    required this.chapter,
    required this.chapters,
    this.readingProgress,
  });

  /// 当前图书。
  final Book book;

  /// 当前章节。
  final BookChapter chapter;

  /// 当前图书章节目录。
  final List<ChapterSummary> chapters;

  /// 打开阅读器时从本地加载的阅读位置。
  final ReadingProgress? readingProgress;

  /// 是否还有上一章。
  bool get canGoPrevious => chapter.chapterIndex > 0;

  /// 是否还有下一章。
  bool get canGoNext => chapter.chapterIndex < book.chapterCount - 1;

  /// 当前章节需要恢复的滚动像素位置。
  double get savedScrollOffset => readingProgress?.scrollOffset ?? 0;

  /// 当前章节内需要恢复的相对阅读进度。
  double get savedChapterProgress => readingProgress?.chapterProgress ?? 0;

  /// 整本书进度展示值。
  double get progress {
    final savedProgress = readingProgress;
    if (savedProgress != null) return savedProgress.progress;
    if (book.chapterCount <= 0) return 0;
    return (chapter.chapterIndex + 1) / book.chapterCount;
  }
}

/// 阅读页 ViewModel Provider。
final readerViewModelProvider =
    AsyncNotifierProvider.family<ReaderViewModel, ReaderState, String>(
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

    final readingProgress = await repository.getProgress(bookId);
    final chapterIndex =
        readingProgress?.chapterIndex ?? book.currentChapterIndex;
    return _loadChapter(chapterIndex, readingProgress: readingProgress);
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

  /// 保存当前章节的滚动位置。
  Future<void> saveReadingPosition({
    required double scrollOffset,
    required double chapterProgress,
  }) async {
    final current = state.value;
    if (current == null) return;

    await _saveProgress(
      current,
      scrollOffset: scrollOffset,
      chapterProgress: chapterProgress,
    );
  }

  Future<void> _setChapter(int chapterIndex) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final next = await _loadChapter(chapterIndex);
      await _saveProgress(next, scrollOffset: 0, chapterProgress: 0);
      ref.invalidate(libraryViewModelProvider);
      return next;
    });
  }

  Future<void> _saveProgress(
    ReaderState next, {
    required double scrollOffset,
    required double chapterProgress,
  }) {
    return ref
        .read(readerRepositoryProvider)
        .saveProgress(
          book: next.book,
          chapterIndex: next.chapter.chapterIndex,
          scrollOffset: scrollOffset,
          chapterProgress: chapterProgress,
        );
  }

  Future<ReaderState> _loadChapter(
    int chapterIndex, {
    ReadingProgress? readingProgress,
  }) async {
    final repository = ref.read(readerRepositoryProvider);
    final book = await repository.getBook(bookId);
    if (book == null) {
      throw StateError('没有找到这本书，可能已被删除。');
    }

    final chapters = await repository.listChapters(book.id);
    if (chapters.isEmpty) {
      throw StateError('这本书没有可阅读章节。');
    }

    final safeChapterIndex = chapterIndex
        .clamp(0, book.chapterCount - 1)
        .toInt();
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
      readingProgress: readingProgress?.chapterIndex == safeChapterIndex
          ? readingProgress
          : null,
    );
  }
}

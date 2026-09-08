import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';
import 'package:reader_app/features/reader/data/reader_repository.dart';

/// 阅读页状态。
///
/// 这是页面一次 build 所需要的所有阅读数据：当前书、当前章、目录、阅读进度，以及为了
/// 连续章节滑动提前加载的相邻章节。
class ReaderState {
  const ReaderState({
    required this.book,
    required this.chapter,
    required this.chapters,
    this.previousChapter,
    this.nextChapter,
    this.readingProgress,
  });

  /// 当前图书。
  final Book book;

  /// 当前章节。
  final BookChapter chapter;

  /// 当前图书章节目录。
  final List<ChapterSummary> chapters;

  /// 当前章节的上一章正文，用于连续滚动预加载。
  final BookChapter? previousChapter;

  /// 当前章节的下一章正文，用于连续滚动预加载。
  final BookChapter? nextChapter;

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

  /// 连续滚动进入下一章时，切换“当前章节”状态。
  ///
  /// 普通 [nextChapter] / [previousChapter] 是按钮或目录触发的明确跳转，会把进度重置到
  /// 章首；这个方法只用于页面已经自然滑进下一章的场景，所以不主动把 scrollOffset 写成
  /// 0，而是保留页面层刚刚计算出来的位置。
  Future<void> activateChapterFromScroll(int chapterIndex) async {
    final current = state.value;
    if (current == null || current.chapter.chapterIndex == chapterIndex) return;

    state = await AsyncValue.guard(() async {
      final next = await _loadChapter(chapterIndex);
      ref.invalidate(libraryViewModelProvider);
      return next;
    });
  }

  /// 按章节序号读取正文，但不改变阅读页的当前章节状态。
  ///
  /// 连续滚动页面用它按需加载前后章节。这个查询只访问 Repository，不会让
  /// [ReaderState.chapter] 改变，也不会触发阅读页进入 loading 状态。
  Future<BookChapter?> getChapterAt(int chapterIndex) {
    return ref
        .read(readerRepositoryProvider)
        .getChapter(bookId: bookId, chapterIndex: chapterIndex);
  }

  /// 保存阅读位置。
  ///
  /// [chapterIndex] 可选：
  ///
  /// - 不传时保存当前 ViewModel 里的章节，适用于普通单章节阅读。
  /// - 传入时保存指定章节，适用于连续滑动时用户已经看到了下一章，但 ViewModel 状态还
  ///   没完全切过去的瞬间。
  Future<void> saveReadingPosition({
    required double scrollOffset,
    required double chapterProgress,
    int? chapterIndex,
  }) async {
    final current = state.value;
    if (current == null) return;

    await _saveProgress(
      current,
      chapterIndex: chapterIndex ?? current.chapter.chapterIndex,
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
    int? chapterIndex,
    required double scrollOffset,
    required double chapterProgress,
  }) {
    return ref
        .read(readerRepositoryProvider)
        .saveProgress(
          book: next.book,
          chapterIndex: chapterIndex ?? next.chapter.chapterIndex,
          scrollOffset: scrollOffset,
          chapterProgress: chapterProgress,
        );
  }

  /// 加载一个章节及其阅读页需要的上下文。
  ///
  /// 除了当前章节本身，还会读取上一章和下一章：
  ///
  /// - `previousChapter` 为后续支持向下连续滑回上一章预留。
  /// - `nextChapter` 当前已经用于章末继续向上滑动时无缝接下一章。
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

    final previousChapter = safeChapterIndex <= 0
        ? null
        : await repository.getChapter(
            bookId: book.id,
            chapterIndex: safeChapterIndex - 1,
          );
    final nextChapter = safeChapterIndex >= book.chapterCount - 1
        ? null
        : await repository.getChapter(
            bookId: book.id,
            chapterIndex: safeChapterIndex + 1,
          );

    return ReaderState(
      book: book,
      chapter: chapter,
      chapters: chapters,
      previousChapter: previousChapter,
      nextChapter: nextChapter,
      readingProgress: readingProgress?.chapterIndex == safeChapterIndex
          ? readingProgress
          : null,
    );
  }
}

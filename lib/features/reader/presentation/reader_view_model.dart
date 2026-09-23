import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/data/models/reading_progress.dart';
import 'package:reader_app/features/reader/data/reader_repository.dart';

/// 阅读页状态。
///
/// 阅读器现在一次性把当前图书的所有章节正文读入内存，然后交给页面层用一个稳定的章节
/// 列表滚动。这样章节之间的上下滑动完全由 Flutter 列表处理，不再需要“当前章窗口”、
/// 前插/追加章节和滚动补偿这些容易产生竞态的逻辑。
class ReaderState {
  const ReaderState({
    required this.book,
    required this.chapter,
    required this.allChapters,
    required this.chapters,
    this.readingProgress,
  });

  /// 当前图书。
  final Book book;

  /// 当前阅读线所在章节。
  ///
  /// 页面根据可见章节更新这个值，顶部标题、底部进度、朗读上下文都以它为准。
  final BookChapter chapter;

  /// 当前图书的全部章节正文，按 `chapterIndex ASC` 排序。
  ///
  /// 一次性持有章节数据可以让 UI 使用稳定的章节索引滚动；真正的 Widget 构建仍由
  /// `ScrollablePositionedList.builder` 懒加载，所以不会一次性创建所有章节视图。
  final List<BookChapter> allChapters;

  /// 当前图书章节目录。
  ///
  /// 目录弹窗只关心标题和序号，因此这里保留轻量目录模型，避免 UI 层从正文模型里拆字段。
  final List<ChapterSummary> chapters;

  /// 打开阅读器时从本地加载的阅读位置。
  ///
  /// 这个值只用于首次恢复位置。自然滚动和手动跳章后，当前章节由 [chapter] 表示。
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
    if (savedProgress != null &&
        savedProgress.chapterIndex == chapter.chapterIndex) {
      return savedProgress.progress;
    }
    if (book.chapterCount <= 0) return 0;
    return (chapter.chapterIndex + 1) / book.chapterCount;
  }

  /// 创建一个只替换当前章节的状态副本。
  ///
  /// 章节列表本身保持同一个对象，可避免页面把“切换当前章节”误解成“重新加载全书”。
  ReaderState copyWithCurrentChapter(BookChapter chapter) {
    return ReaderState(
      book: book,
      chapter: chapter,
      allChapters: allChapters,
      chapters: chapters,
    );
  }
}

/// 阅读页 ViewModel Provider。
final readerViewModelProvider =
    AsyncNotifierProvider.family<ReaderViewModel, ReaderState, String>(
      ReaderViewModel.new,
    );

/// 阅读页 ViewModel。
///
/// 负责一次性加载全书章节、更新当前章节状态，并把阅读进度写回本地数据库。正文滚动、
/// 可见章节计算和章节内位置恢复仍放在页面层，因为这些都依赖 RenderObject 和视口尺寸。
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

    final allChapters = await repository.listFullChapters(book.id);
    if (allChapters.isEmpty) {
      throw StateError('这本书没有可阅读章节。');
    }

    final readingProgress = await repository.getProgress(bookId);
    final chapterIndex = _safeChapterIndex(
      readingProgress?.chapterIndex ?? book.currentChapterIndex,
      allChapters,
    );
    final chapter = allChapters[chapterIndex];

    return ReaderState(
      book: book,
      chapter: chapter,
      allChapters: allChapters,
      chapters: allChapters.map(_chapterSummaryFromChapter).toList(),
      readingProgress: readingProgress?.chapterIndex == chapter.chapterIndex
          ? readingProgress
          : null,
    );
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

  /// 连续滚动进入另一章时，同步顶部标题、目录选中项和朗读上下文。
  ///
  /// 这里不读取数据库、不进入 loading，也不保存 0 进度；页面已经在全书列表中自然滚到了
  /// 目标章节，我们只需要把状态里的当前章节改成对应列表项。
  void activateChapterFromScroll(int chapterIndex) {
    final current = state.value;
    if (current == null || current.chapter.chapterIndex == chapterIndex) return;
    final safeIndex = _safeChapterIndex(chapterIndex, current.allChapters);
    state = AsyncData(
      current.copyWithCurrentChapter(current.allChapters[safeIndex]),
    );
    ref.invalidate(libraryViewModelProvider);
  }

  /// 保存阅读位置。
  ///
  /// [chapterIndex] 来自页面可见章节计算；全章节列表里章节索引稳定，因此可以直接保存。
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

  /// 加载并发布用户明确选择的章节。
  ///
  /// 明确跳章会把章节内进度重置为 0；页面随后按章节 index 把列表滚动到目标章节顶部。
  Future<void> _setChapter(int chapterIndex) async {
    final current = state.value;
    if (current == null) return;

    final safeIndex = _safeChapterIndex(chapterIndex, current.allChapters);
    final next = current.copyWithCurrentChapter(current.allChapters[safeIndex]);
    await _saveProgress(next, scrollOffset: 0, chapterProgress: 0);
    state = AsyncData(next);
    ref.invalidate(libraryViewModelProvider);
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

  /// 把数据库章节模型转换为目录模型。
  ///
  /// 目录仍使用轻量结构，是为了让目录弹窗的语义保持清晰：它只负责导航，不直接消费正文。
  ChapterSummary _chapterSummaryFromChapter(BookChapter chapter) {
    return ChapterSummary(
      id: chapter.id,
      bookId: chapter.bookId,
      chapterIndex: chapter.chapterIndex,
      title: chapter.title,
    );
  }

  /// 把外部传入的章节序号限制在可读范围内。
  int _safeChapterIndex(int chapterIndex, List<BookChapter> chapters) {
    return chapterIndex.clamp(0, chapters.length - 1).toInt();
  }
}

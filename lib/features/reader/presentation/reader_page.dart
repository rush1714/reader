import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/app/theme/app_colors.dart';
import 'package:reader_app/app/theme/app_text_styles.dart';
import 'package:reader_app/core/widgets/app_error_view.dart';
import 'package:reader_app/core/widgets/app_loading.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/presentation/reader_view_model.dart';
import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/presentation/speech_view_model.dart';

/// 图书阅读页。
///
/// 阅读页现在使用“全书章节列表”的方式工作：ViewModel 一次性从 SQLite 读取当前书的全部
/// 章节正文，页面用 [ScrollablePositionedList] 按章节 index 懒构建。这样上下滑动完全交给
/// Flutter 自带的滚动系统，目录跳章也直接按 item index 定位，不再需要动态前插/追加章节、
/// 手写像素补偿和复杂的异步窗口状态。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({required this.bookId, super.key});

  /// 当前图书 ID。
  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  /// 按章节 index 跳转的滚动控制器。
  ///
  /// 普通 [ScrollController] 只能按像素跳转，而每章高度都不固定；使用 item 级控制器可以
  /// 直接跳到“第 N 章”这个列表项，避免再次回到手算高度的复杂实现。
  final ItemScrollController _itemScrollController = ItemScrollController();

  /// 监听当前哪些章节 item 出现在视口中。
  ///
  /// 顶部/底部显示的当前章节、阅读进度保存、朗读上下文都通过这个监听推导出来。
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// 当前章节每一个“可朗读句段”的 key。
  ///
  /// 只有当前章节需要这些 key，因为朗读高亮和自动滚动都只作用在当前章节的句段上。
  final List<GlobalKey> _sentenceKeys = [];

  /// 恢复阅读位置时最多等几个 frame。
  ///
  /// 首帧时列表控制器可能尚未 attach，多等几帧能避免启动后没有跳到保存章节。
  static const int _maxScrollRestoreAttempts = 8;

  /// 标记 [_sentenceKeys] 当前属于哪一章。
  String? _sentenceKeySeed;

  /// 阅读进度保存的防抖计时器。
  ///
  /// 滚动通知非常频繁，延迟写库能减少 SQLite 写入次数；滚动结束和离开页面时会立即 flush。
  Timer? _progressSaveDebounce;

  /// 自动朗读会话 ID。
  ///
  /// 开始、暂停、停止朗读都会递增它，旧的异步朗读循环看到 ID 变化后会自动退出。
  int _autoReadSession = 0;

  /// 滚动恢复/跳章的代数。
  ///
  /// 异步 post-frame 回调会检查这个值，避免旧回调在用户已经选择新章节后继续执行。
  int _scrollOperationGeneration = 0;

  /// 是否正在由程序主动跳转列表。
  ///
  /// 程序跳转期间会产生滚动通知，但这些通知不代表用户阅读位置变化，不能立即保存进度。
  bool _isProgrammaticScroll = false;

  /// 初次进入页面时，是否已经执行过阅读位置恢复。
  bool _hasRestoredInitialPosition = false;

  /// 顶部和底部控制栏是否可见。
  bool _chromeVisible = false;

  /// 记录手指按下的位置，用来区分“轻点显示控制栏”和“拖动滚动正文”。
  Offset? _tapDownPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemPositionsListener.itemPositions.addListener(
      _handleVisibleItemsChanged,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushReadingPosition());
    }
  }

  @override
  void dispose() {
    _autoReadSession += 1;
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(
      _handleVisibleItemsChanged,
    );
    _progressSaveDebounce?.cancel();
    unawaited(_persistCurrentReadingPosition(force: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerViewModelProvider(widget.bookId));
    final settings = ref.watch(readerSettingsProvider).value;
    final speechState = ref.watch(speechViewModelProvider).value;
    final fontSize = settings?.fontSize ?? 18;
    final speakingSentenceIndex = speechState?.currentSentenceIndex;
    final playbackState =
        speechState?.playbackState ?? SpeechPlaybackState.idle;
    final isSpeaking = playbackState == SpeechPlaybackState.speaking;
    final isActive = isSpeaking || playbackState == SpeechPlaybackState.paused;

    ref.listen(speechViewModelProvider, (previous, next) {
      if (next.hasError && next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error.toString())));
        return;
      }

      final nextIndex = next.value?.currentSentenceIndex;
      final previousIndex = previous?.value?.currentSentenceIndex;
      if (nextIndex != null && nextIndex != previousIndex) {
        _scrollToSentence(nextIndex);
      }
    });

    return Scaffold(
      body: readerState.when(
        loading: () => const AppLoading(),
        error: (error, stackTrace) => AppErrorView(error: error),
        data: (data) {
          final currentSentences = _sentencesFrom(data.chapter.content);
          _ensureSentenceKeys(data.chapter.id, currentSentences.length);
          _restoreInitialPositionIfNeeded(data, currentSentences.length);

          final isDark = Theme.of(context).brightness == Brightness.dark;
          final backgroundColor = isDark
              ? AppColors.readingPaperDark
              : AppColors.readingPaperLight;

          return ColoredBox(
            color: backgroundColor,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.down,
                  onTapDown: (details) =>
                      _tapDownPosition = details.globalPosition,
                  onTapUp: (details) =>
                      _handleReaderTap(details.globalPosition),
                  onTapCancel: () => _tapDownPosition = null,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ScrollablePositionedList.builder(
                      itemCount: data.allChapters.length,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top + 28,
                        24,
                        120 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemBuilder: (context, index) {
                        final chapter = data.allChapters[index];
                        final isCurrentChapter = chapter.id == data.chapter.id;
                        final sentences = isCurrentChapter
                            ? currentSentences
                            : _sentencesFrom(chapter.content);
                        return _ChapterBlockView(
                          key: ValueKey(chapter.id),
                          block: _ChapterRenderBlock(
                            chapter: chapter,
                            sentences: sentences,
                            sentenceKeys: isCurrentChapter
                                ? _sentenceKeys
                                : const [],
                            isCurrentChapter: isCurrentChapter,
                          ),
                          bookTitle: data.book.title,
                          chapterCount: data.book.chapterCount,
                          fontSize: fontSize,
                          speakingSentenceIndex: speakingSentenceIndex,
                        );
                      },
                    ),
                  ),
                ),
                _ReaderTopDrawer(
                  visible: _chromeVisible,
                  title: data.book.title,
                  subtitle: data.chapter.title,
                  onBack: () => _goLibrary(data),
                  onChapter: () => _showChapterSheet(data),
                  onDecreaseFont: settings == null
                      ? null
                      : () => ref
                            .read(readerSettingsProvider.notifier)
                            .updateFontSize(
                              (fontSize - 1).clamp(14, 30).toDouble(),
                            ),
                  onIncreaseFont: settings == null
                      ? null
                      : () => ref
                            .read(readerSettingsProvider.notifier)
                            .updateFontSize(
                              (fontSize + 1).clamp(14, 30).toDouble(),
                            ),
                ),
                _ReaderBottomDrawer(
                  visible: _chromeVisible,
                  progress: data.progress.clamp(0, 1).toDouble(),
                  chapterLabel:
                      '第 ${data.chapter.chapterIndex + 1} / ${data.book.chapterCount} 章',
                  isSpeaking: isSpeaking,
                  isActive: isActive,
                  canGoPrevious: data.canGoPrevious,
                  canGoNext: data.canGoNext,
                  sentenceIndex: speakingSentenceIndex,
                  sentenceCount: currentSentences.length,
                  currentSentence: speakingSentenceIndex == null
                      ? null
                      : currentSentences[speakingSentenceIndex.clamp(
                          0,
                          currentSentences.length - 1,
                        )],
                  onPrevious: _goPrevious,
                  onNext: _goNext,
                  onPlayPause: isSpeaking
                      ? _pauseSpeech
                      : () => _startAutoRead(data),
                  onStop: isActive ? _stopSpeech : null,
                  onSettings: () => unawaited(_goSettings(data)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 处理正文区域点击。
  ///
  /// 滑动时也可能触发 tap 相关回调，所以用按下和抬起距离过滤掉拖动手势。
  void _handleReaderTap(Offset position) {
    final start = _tapDownPosition;
    _tapDownPosition = null;
    if (start == null || (position - start).distance > 10) return;

    setState(() {
      _chromeVisible = !_chromeVisible;
    });
  }

  /// 处理横向右滑返回书库。
  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 520) {
      unawaited(_goLibrary());
    }
  }

  /// 返回书库前先保存当前可见章节位置。
  Future<void> _goLibrary([ReaderState? data]) async {
    await _flushReadingPosition();
    if (!mounted) return;
    context.go(RoutePaths.library);
  }

  /// 跳到设置页前保存当前位置，避免修改字号回来后丢失阅读点。
  Future<void> _goSettings(ReaderState data) async {
    await _flushReadingPosition();
    if (!mounted) return;
    context.go(RoutePaths.settings);
  }

  /// 处理列表滚动通知。
  ///
  /// 章节状态同步主要由 [ItemPositionsListener] 完成；这里负责滚动过程中的防抖保存，以及
  /// 滚动结束时立即保存一次最终位置。
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (_isProgrammaticScroll) return false;

    if (notification is ScrollUpdateNotification) {
      _schedulePersistReadingPosition();
    } else if (notification is ScrollEndNotification) {
      _schedulePersistReadingPosition(delay: Duration.zero);
    }
    return false;
  }

  /// 根据当前可见章节 item 更新阅读状态。
  ///
  /// 列表项位置由 `scrollable_positioned_list` 维护，我们只取阅读线所在的 item。状态更新是
  /// 同步的，不会触发正文列表重建到顶部。
  void _handleVisibleItemsChanged() {
    if (_isProgrammaticScroll) return;
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current == null) return;
    final visible = _visibleChapterPosition(current);
    if (visible == null) return;
    if (visible.chapterIndex == current.chapter.chapterIndex) return;

    ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .activateChapterFromScroll(visible.chapterIndex);
  }

  /// 从当前可见句段开始自动朗读。
  Future<void> _startAutoRead(ReaderState initialState) async {
    await _flushReadingPosition();
    if (!mounted) return;
    setState(() {
      _chromeVisible = true;
    });
    final sessionId = ++_autoReadSession;
    var currentState = initialState;
    var startIndex = _firstVisibleSentenceIndex();

    while (mounted && sessionId == _autoReadSession) {
      final sentences = _sentencesFrom(currentState.chapter.content);
      final completed = await ref
          .read(speechViewModelProvider.notifier)
          .speakSentences(sentences, startIndex: startIndex);
      if (!completed ||
          !mounted ||
          sessionId != _autoReadSession ||
          !currentState.canGoNext) {
        break;
      }

      await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .nextChapter();
      if (!mounted || sessionId != _autoReadSession) break;

      final nextState = ref.read(readerViewModelProvider(widget.bookId)).value;
      if (nextState == null) break;
      _jumpToChapter(nextState.chapter.chapterIndex);
      currentState = nextState;
      startIndex = 0;
    }
  }

  /// 底部控制栏“上一章”按钮。
  Future<void> _goPrevious() async {
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current == null || !current.canGoPrevious) return;

    await _flushReadingPosition();
    await _stopSpeech();
    await ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .previousChapter();
    _jumpToChapter(current.chapter.chapterIndex - 1);
  }

  /// 底部控制栏“下一章”按钮。
  Future<void> _goNext() async {
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current == null || !current.canGoNext) return;

    await _flushReadingPosition();
    await _stopSpeech();
    await ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .nextChapter();
    _jumpToChapter(current.chapter.chapterIndex + 1);
  }

  /// 暂停朗读。
  Future<void> _pauseSpeech() async {
    _autoReadSession += 1;
    await ref.read(speechViewModelProvider.notifier).pause();
  }

  /// 停止朗读并清空当前朗读句段。
  Future<void> _stopSpeech() async {
    _autoReadSession += 1;
    await ref.read(speechViewModelProvider.notifier).stop();
  }

  /// 打开章节目录底部弹窗。
  ///
  /// 目录选择只需要更新当前章节状态并跳到对应 item index。正文列表已经包含全书章节，
  /// 因此这里没有任何窗口重建或章节预加载逻辑。
  Future<void> _showChapterSheet(ReaderState data) async {
    await _flushReadingPosition();
    if (!mounted) return;

    const itemExtent = 64.0;
    final selectedIndex = data.chapter.chapterIndex
        .clamp(0, data.chapters.length - 1)
        .toInt();
    final initialOffset = (selectedIndex * itemExtent - 160)
        .clamp(0, double.infinity)
        .toDouble();
    final scrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) {
          return SafeArea(
            child: ListView.builder(
              controller: scrollController,
              itemExtent: itemExtent,
              itemCount: data.chapters.length,
              itemBuilder: (context, index) {
                final chapter = data.chapters[index];
                final selected =
                    chapter.chapterIndex == data.chapter.chapterIndex;
                return ListTile(
                  selected: selected,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  leading: Text('${chapter.chapterIndex + 1}'),
                  title: Text(
                    chapter.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: selected ? const Icon(Icons.check_rounded) : null,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _flushReadingPosition();
                    await _stopSpeech();
                    await ref
                        .read(readerViewModelProvider(widget.bookId).notifier)
                        .goToChapter(chapter.chapterIndex);
                    _jumpToChapter(chapter.chapterIndex);
                  },
                );
              },
            ),
          );
        },
      );
    } finally {
      scrollController.dispose();
    }
  }

  /// 初次进入阅读页时恢复保存章节。
  ///
  /// 全章节列表的章节 index 稳定，所以先按 index 跳到保存章节；如果保存了章节内进度，
  /// 再用句段 key 尽量恢复到该章节内部相近位置。
  void _restoreInitialPositionIfNeeded(ReaderState data, int sentenceCount) {
    if (_hasRestoredInitialPosition) return;
    _hasRestoredInitialPosition = true;
    final chapterIndex =
        data.readingProgress?.chapterIndex ?? data.chapter.chapterIndex;
    final chapterProgress = data.savedChapterProgress
        .clamp(0.0, 1.0)
        .toDouble();
    _jumpToChapter(
      chapterIndex,
      chapterProgress: chapterProgress,
      sentenceCount: sentenceCount,
    );
  }

  /// 按章节 index 跳转列表。
  ///
  /// [chapterProgress] 只在恢复阅读进度时使用。章节高度无法提前知道，所以恢复采用“先跳到
  /// 章节顶部，再滚到近似句段”的方式，换取实现稳定性和可预测性。
  void _jumpToChapter(
    int chapterIndex, {
    double chapterProgress = 0,
    int? sentenceCount,
  }) {
    final generation = ++_scrollOperationGeneration;
    _isProgrammaticScroll = true;

    void finish() {
      if (!mounted || generation != _scrollOperationGeneration) return;
      _isProgrammaticScroll = false;
      _handleVisibleItemsChanged();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _scrollOperationGeneration) return;
      if (!_itemScrollController.isAttached) {
        _retryJumpToChapter(
          chapterIndex,
          generation: generation,
          chapterProgress: chapterProgress,
          sentenceCount: sentenceCount,
          attempt: 0,
        );
        return;
      }

      _itemScrollController.jumpTo(index: chapterIndex, alignment: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (chapterProgress > 0 && sentenceCount != null && sentenceCount > 0) {
          final sentenceIndex = (chapterProgress * (sentenceCount - 1))
              .round()
              .clamp(0, sentenceCount - 1);
          _scrollToSentence(sentenceIndex, duration: Duration.zero);
        }
        finish();
      });
    });
  }

  /// 在列表控制器尚未 attach 时重试章节跳转。
  void _retryJumpToChapter(
    int chapterIndex, {
    required int generation,
    required double chapterProgress,
    required int? sentenceCount,
    required int attempt,
  }) {
    if (attempt >= _maxScrollRestoreAttempts) {
      if (generation == _scrollOperationGeneration) {
        _isProgrammaticScroll = false;
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _scrollOperationGeneration) return;
      if (!_itemScrollController.isAttached) {
        _retryJumpToChapter(
          chapterIndex,
          generation: generation,
          chapterProgress: chapterProgress,
          sentenceCount: sentenceCount,
          attempt: attempt + 1,
        );
        return;
      }

      _itemScrollController.jumpTo(index: chapterIndex, alignment: 0);
      _isProgrammaticScroll = false;
      _handleVisibleItemsChanged();
    });
  }

  /// 计算当前阅读线所在章节和章节内大致进度。
  _VisibleChapterPosition? _visibleChapterPosition(ReaderState data) {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return null;

    final readingLine = _readingLineFraction();
    final visiblePositions = positions
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList();
    if (visiblePositions.isEmpty) return null;

    ItemPosition selected = visiblePositions.first;
    for (final position in visiblePositions) {
      if (position.itemLeadingEdge <= readingLine &&
          position.itemTrailingEdge >= readingLine) {
        selected = position;
        break;
      }

      final selectedDistance = _distanceToReadingLine(selected, readingLine);
      final positionDistance = _distanceToReadingLine(position, readingLine);
      if (positionDistance < selectedDistance) {
        selected = position;
      }
    }

    if (selected.index < 0 || selected.index >= data.allChapters.length) {
      return null;
    }
    final chapter = data.allChapters[selected.index];
    final itemHeight = (selected.itemTrailingEdge - selected.itemLeadingEdge)
        .abs()
        .clamp(0.0001, double.infinity)
        .toDouble();
    final chapterProgress =
        ((readingLine - selected.itemLeadingEdge) / itemHeight)
            .clamp(0.0, 1.0)
            .toDouble();

    return _VisibleChapterPosition(
      chapterIndex: chapter.chapterIndex,
      chapterProgress: chapterProgress,
    );
  }

  /// 阅读线在视口中的相对位置。
  double _readingLineFraction() => 0.42;

  /// 计算某个可见章节块中心到阅读线的距离。
  double _distanceToReadingLine(ItemPosition position, double readingLine) {
    if (position.itemLeadingEdge <= readingLine &&
        position.itemTrailingEdge >= readingLine) {
      return 0;
    }
    final middle = (position.itemLeadingEdge + position.itemTrailingEdge) / 2;
    return (middle - readingLine).abs();
  }

  /// 安排一次阅读进度保存。
  void _schedulePersistReadingPosition({
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (_isProgrammaticScroll) return;
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(delay, () {
      unawaited(_persistCurrentReadingPosition());
    });
  }

  /// 立即保存阅读进度。
  Future<void> _flushReadingPosition() {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = null;
    return _persistCurrentReadingPosition(force: true);
  }

  /// 把当前阅读线所在章节写入数据库。
  ///
  /// 全章节列表下，阅读线落在哪个 item 就保存哪个章节；章节内进度用 item 的相对位置估算，
  /// 后续恢复时会映射到接近的句段。
  Future<void> _persistCurrentReadingPosition({bool force = false}) async {
    if (!mounted) return;
    if (!force && _isProgrammaticScroll) return;
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current == null) return;

    final visible = _visibleChapterPosition(current);
    final chapterIndex = visible?.chapterIndex ?? current.chapter.chapterIndex;
    final chapterProgress = visible?.chapterProgress ?? 0.0;
    await ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .saveReadingPosition(
          chapterIndex: chapterIndex,
          scrollOffset: 0,
          chapterProgress: chapterProgress,
        );
  }

  /// 确保当前章节的句段 key 数量和句段数量一致。
  void _ensureSentenceKeys(String chapterId, int length) {
    if (_sentenceKeySeed == chapterId && _sentenceKeys.length == length) return;
    _sentenceKeySeed = chapterId;
    _sentenceKeys
      ..clear()
      ..addAll(List.generate(length, (_) => GlobalKey()));
  }

  /// 找到当前屏幕里第一个可见句段。
  int _firstVisibleSentenceIndex() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topBoundary = MediaQuery.paddingOf(context).top + 24;
    final bottomBoundary =
        screenHeight - MediaQuery.paddingOf(context).bottom - 36;

    for (var index = 0; index < _sentenceKeys.length; index += 1) {
      final itemContext = _sentenceKeys[index].currentContext;
      if (itemContext == null) continue;
      final renderObject = itemContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final offset = renderObject.localToGlobal(Offset.zero);
      final bottom = offset.dy + renderObject.size.height;
      if (bottom > topBoundary && offset.dy < bottomBoundary) {
        return index;
      }
    }

    return ref.read(speechViewModelProvider).value?.currentSentenceIndex ?? 0;
  }

  /// 滚动到正在朗读的句段。
  void _scrollToSentence(
    int index, {
    Duration duration = const Duration(milliseconds: 350),
  }) {
    if (index < 0 || index >= _sentenceKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _sentenceKeys[index].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
    });
  }

  /// 把章节正文拆分成用于显示和朗读的句段。
  List<String> _sentencesFrom(String content) {
    final normalized = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) return const ['当前章节没有可显示的文字内容。'];

    final sentences = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i += 1) {
      final char = normalized[i];
      buffer.write(char);
      if (_isSentenceEnd(char)) {
        while (i + 1 < normalized.length &&
            _isClosingQuote(normalized[i + 1])) {
          i += 1;
          buffer.write(normalized[i]);
        }
        _addSentence(sentences, buffer.toString());
        buffer.clear();
      } else if (char == '\n') {
        final text = buffer.toString().trim();
        if (text.length > 80) {
          _addSentence(sentences, text);
          buffer.clear();
        }
      }
    }
    _addSentence(sentences, buffer.toString());

    if (sentences.isEmpty) return const ['当前章节没有可显示的文字内容。'];
    return sentences.expand(_splitLongSentence).toList();
  }

  /// 清理并加入一个句段。
  void _addSentence(List<String> target, String value) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || _isNoiseSentence(text)) return;
    target.add(text);
  }

  /// 判断一个句段是否只有空白、标点或符号。
  bool _isNoiseSentence(String text) {
    return RegExp(r'^[\s\p{P}\p{S}]+$', unicode: true).hasMatch(text);
  }

  /// 判断字符是否是句末标点。
  bool _isSentenceEnd(String char) {
    return '。！？!?；;.'.contains(char);
  }

  /// 判断字符是否是句末标点后面的闭合符号。
  bool _isClosingQuote(String char) {
    return '”’」』）)]》'.contains(char);
  }

  /// 把过长句段切小。
  Iterable<String> _splitLongSentence(String sentence) sync* {
    const maxLength = 180;
    if (sentence.length <= maxLength) {
      yield sentence;
      return;
    }

    for (var start = 0; start < sentence.length; start += maxLength) {
      final end = start + maxLength > sentence.length
          ? sentence.length
          : start + maxLength;
      yield sentence.substring(start, end);
    }
  }
}

class _ChapterRenderBlock {
  const _ChapterRenderBlock({
    required this.chapter,
    required this.sentences,
    required this.sentenceKeys,
    required this.isCurrentChapter,
  });

  final BookChapter chapter;
  final List<String> sentences;
  final List<GlobalKey> sentenceKeys;
  final bool isCurrentChapter;
}

class _VisibleChapterPosition {
  const _VisibleChapterPosition({
    required this.chapterIndex,
    required this.chapterProgress,
  });

  final int chapterIndex;
  final double chapterProgress;
}

class _ChapterBlockView extends StatelessWidget {
  const _ChapterBlockView({
    required this.block,
    required this.bookTitle,
    required this.chapterCount,
    required this.fontSize,
    required this.speakingSentenceIndex,
    super.key,
  });

  final _ChapterRenderBlock block;
  final String bookTitle;
  final int chapterCount;
  final double fontSize;
  final int? speakingSentenceIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: block.chapter.chapterIndex == 0 ? 0 : 26,
            bottom: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.chapter.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$bookTitle · 第 ${block.chapter.chapterIndex + 1} / $chapterCount 章',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < block.sentences.length; index += 1)
          _SentenceText(
            key: block.isCurrentChapter ? block.sentenceKeys[index] : null,
            text: block.sentences[index],
            fontSize: fontSize,
            isSpeaking:
                block.isCurrentChapter && speakingSentenceIndex == index,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 24),
          child: Text(
            '第 ${block.chapter.chapterIndex + 1} / $chapterCount 章',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReaderTopDrawer extends StatelessWidget {
  const _ReaderTopDrawer({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onChapter,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onChapter;
  final VoidCallback? onDecreaseFont;
  final VoidCallback? onIncreaseFont;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.08),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor
                  .withValues(alpha: 0.95),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.55),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回书库',
                      onPressed: onBack,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '减小字号',
                      onPressed: onDecreaseFont,
                      icon: const Icon(Icons.text_decrease_rounded),
                    ),
                    IconButton(
                      tooltip: '增大字号',
                      onPressed: onIncreaseFont,
                      icon: const Icon(Icons.text_increase_rounded),
                    ),
                    IconButton(
                      tooltip: '章节目录',
                      onPressed: onChapter,
                      icon: const Icon(Icons.format_list_bulleted_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomDrawer extends StatelessWidget {
  const _ReaderBottomDrawer({
    required this.visible,
    required this.progress,
    required this.chapterLabel,
    required this.isSpeaking,
    required this.isActive,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.sentenceIndex,
    required this.sentenceCount,
    required this.currentSentence,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
    required this.onStop,
    required this.onSettings,
  });

  final bool visible;
  final double progress;
  final String chapterLabel;
  final bool isSpeaking;
  final bool isActive;
  final bool canGoPrevious;
  final bool canGoNext;
  final int? sentenceIndex;
  final int sentenceCount;
  final String? currentSentence;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPlayPause;
  final VoidCallback? onStop;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.08),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor
                    .withValues(alpha: 0.97),
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.55),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 26,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isSpeaking
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isSpeaking ? 'TTS 语音朗读中' : '点击播放开始朗读',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: isSpeaking
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          ),
                          Text(
                            chapterLabel,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      if (currentSentence != null) ...[
                        const SizedBox(height: 11),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outline.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Text(
                            '“$currentSentence”',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: progress,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            sentenceIndex == null
                                ? '段落未开始'
                                : '段落 ${sentenceIndex! + 1} / $sentenceCount',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            tooltip: '上一章',
                            onPressed: canGoPrevious ? onPrevious : null,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '停止朗读',
                            onPressed: onStop,
                            icon: Icon(
                              isActive
                                  ? Icons.stop_circle_rounded
                                  : Icons.stop_circle_outlined,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox.square(
                            dimension: 56,
                            child: IconButton.filled(
                              tooltip: isSpeaking ? '暂停朗读' : '开始朗读',
                              onPressed: onPlayPause,
                              icon: Icon(
                                isSpeaking
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '语音设置',
                            onPressed: onSettings,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          const Spacer(),
                          IconButton.filledTonal(
                            tooltip: '下一章',
                            onPressed: canGoNext ? onNext : null,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SentenceText extends StatelessWidget {
  const _SentenceText({
    required this.text,
    required this.fontSize,
    required this.isSpeaking,
    super.key,
  });

  final String text;
  final double fontSize;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.symmetric(
        horizontal: isSpeaking ? 9 : 0,
        vertical: isSpeaking ? 7 : 0,
      ),
      decoration: BoxDecoration(
        color: isSpeaking
            ? colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSpeaking
            ? Border(bottom: BorderSide(color: colorScheme.primary, width: 2))
            : null,
      ),
      child: Text(
        text,
        textAlign: TextAlign.justify,
        style: AppTextStyles.readerBody.copyWith(
          fontSize: fontSize,
          height: 1.92,
          letterSpacing: 0.35,
          color: isSpeaking
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.91),
          fontWeight: isSpeaking ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

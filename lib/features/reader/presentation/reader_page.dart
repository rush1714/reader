import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/app/theme/app_colors.dart';
import 'package:reader_app/app/theme/app_text_styles.dart';
import 'package:reader_app/core/widgets/app_error_view.dart';
import 'package:reader_app/core/widgets/app_loading.dart';
import 'package:reader_app/features/reader/data/models/book_chapter.dart';
import 'package:reader_app/features/reader/presentation/reader_view_model.dart';
import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/presentation/speech_view_model.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';

/// 图书阅读页。
///
/// 这个页面是整个阅读体验的入口，负责把下面几类能力组合到同一个屏幕里：
///
/// 1. 正文展示：把数据库里保存的章节纯文本拆成适合阅读和朗读的句段。
/// 2. 连续章节滑动：当前章后面预渲染下一章，用户滑到章末时可以自然接上下一章。
/// 3. 阅读进度：根据屏幕中正在看的章节区域保存章节索引、章节内像素位置和相对进度。
/// 4. 朗读跟随：TTS 正在朗读哪个句段，就把对应句段高亮并滚动到视野中。
/// 5. 顶部/底部控制栏：点击正文显示或隐藏返回、目录、字号、朗读等操作。
///
/// 页面层只做“如何显示”和“如何响应手势”；章节加载、保存进度等数据操作都交给
/// [ReaderViewModel]，这样 UI 不需要直接碰 SQLite 或文件系统。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({required this.bookId, super.key});

  /// 当前图书 ID。
  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  /// 主正文列表的滚动控制器。
  ///
  /// 阅读页需要自己保存和恢复滚动位置，也需要在 TTS 朗读时滚动到当前句段，
  /// 所以不能只依赖 ListView 默认的内部控制器。
  final ScrollController _scrollController = ScrollController();

  /// 恢复阅读位置时最多等几个 frame。
  ///
  /// Flutter 第一次 build 完后，文字高度、设备安全区、字体大小等布局信息可能还没有
  /// 完全稳定；多试几帧可以避免“刚打开书时恢复到错误高度”。
  static const int _maxScrollRestoreAttempts = 8;

  /// 当前章节每一个“可朗读句段”的 key。
  ///
  /// TTS 朗读时只高亮当前章节里的句段，下一章虽然已经预渲染在下面，但还不是当前
  /// 朗读上下文，所以不会放到这个列表里。
  final List<GlobalKey> _sentenceKeys = [];

  /// 每个已渲染章节 block 对应的 key。
  ///
  /// 连续滑动时需要知道“当前屏幕中线落在哪一章”，只能通过 GlobalKey 找到对应
  /// RenderBox 后计算它在屏幕上的 top/bottom 位置。
  final Map<String, GlobalKey> _chapterKeys = {};

  /// 阅读页本地维护的连续章节窗口。
  ///
  /// 这是解决滚动跳动的核心：滚动过程中不再切换 ReaderViewModel 的当前章节，而是只
  /// 在这里增量前插/追加章节。窗口初始包含当前章前后各两章，形如：
  /// `1 + 2 + 当前 3 + 4 + 5`。
  final List<BookChapter> _loadedChapters = [];

  /// 当前本地章节窗口属于哪一本书。
  ///
  /// 路由切换到另一张书时必须清空旧窗口，避免短暂显示上一本书的正文。
  String? _loadedBookId;

  /// 当前本地窗口以哪个章节为初始化中心。
  ///
  /// 点击目录或上一章/下一章按钮时，这个值会改变，窗口随后重新以目标章节为中心加载。
  int? _loadedCenterChapterIndex;

  /// 是否已经发起章节窗口初始化。
  ///
  /// build 可能在异步加载完成前连续执行多次，标记可以避免重复查询同一批章节。
  bool _isInitializingChapterWindow = false;

  /// 是否正在向列表顶部前插更早章节。
  bool _isPrependingChapter = false;

  /// 是否正在向列表底部追加更晚章节。
  bool _isAppendingChapter = false;

  /// 标记 [_sentenceKeys] 当前属于哪一章。
  ///
  /// 如果章节没变且句段数量也没变，就复用原来的 key，避免朗读高亮时找不到原来的
  /// BuildContext。
  String? _sentenceKeySeed;

  /// 已经执行过滚动恢复的章节 ID。
  ///
  /// 防止同一章在每次 build 时反复 jumpTo，导致用户正在滑动时被拉回保存位置。
  String? _restoredChapterId;

  /// 阅读进度保存的防抖计时器。
  ///
  /// 滚动过程中会产生大量通知，如果每一像素都写 SQLite，会浪费性能；这里延迟保存，
  /// 滚动停止时再立即 flush。
  Timer? _progressSaveDebounce;

  /// 自动朗读会话 ID。
  ///
  /// 每次开始/暂停/停止朗读都递增，旧的异步朗读循环看到 ID 不一致就自动退出，避免
  /// 多个朗读循环同时控制同一个 TTS 引擎。
  int _autoReadSession = 0;

  /// 滚动恢复代数。
  ///
  /// 每次开始或取消恢复都递增。异步 post-frame 回调会检查代数，避免旧回调在新章节
  /// 已经出现后继续执行错误的 jumpTo。
  int _scrollRestoreGeneration = 0;

  /// 顶部和底部控制栏是否可见。
  ///
  /// false 时阅读器尽量沉浸，只显示正文；true 时显示返回、目录、字号、朗读按钮等。
  bool _chromeVisible = false;

  /// 当前是否正在切换章节。
  ///
  /// 手动点上一章/下一章、目录跳转、连续滑动激活下一章都会设置它，用来禁止重复保存
  /// 或重复激活章节。
  bool _isChangingChapter = false;

  /// 当前是否正在恢复滚动位置。
  ///
  /// 恢复过程中不应该把临时 jumpTo 产生的位置写回数据库，否则会覆盖真实阅读位置。
  bool _isRestoringScrollOffset = false;

  /// 记录手指按下的位置，用来区分“轻点显示控制栏”和“拖动滚动正文”。
  Offset? _tapDownPosition;

  @override
  void initState() {
    super.initState();

    // 监听 App 生命周期，用于在切后台、锁屏、退出前尽快保存阅读进度。
    WidgetsBinding.instance.addObserver(this);
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
    // 让正在运行的自动朗读循环失效；dispose 后不能再让异步循环 setState 或滚动。
    _autoReadSession += 1;

    // 成对移除 initState 里注册的生命周期监听。
    WidgetsBinding.instance.removeObserver(this);

    // 取消防抖任务，并主动保存最后一次可见阅读位置。
    _progressSaveDebounce?.cancel();
    unawaited(_persistCurrentReadingPosition(force: true));

    // 取消还没来得及执行的滚动恢复回调。
    _cancelScrollRestore();

    // ScrollController 是手动创建的资源，页面销毁时必须释放。
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 阅读器主状态：包含当前图书、当前章节、目录、阅读进度，以及为了连续滑动预加载的下一章。
    final readerState = ref.watch(readerViewModelProvider(widget.bookId));

    // 阅读设置：字号、主题、语音设置等。这里主要用字号控制正文大小。
    final settings = ref.watch(readerSettingsProvider).value;

    // 朗读状态：用来决定是否显示“朗读中”、当前高亮哪一句、按钮显示播放还是暂停。
    final speechState = ref.watch(speechViewModelProvider).value;

    // 设置还在加载时给一个稳定默认字号，避免页面空白或布局抖动。
    final fontSize = settings?.fontSize ?? 18;

    // 当前 TTS 正在朗读的句段索引，只对应“当前章节”的句段列表。
    final speakingSentenceIndex = speechState?.currentSentenceIndex;

    // 把可能为空的播放状态规整为 idle，后面 UI 判断就不用反复判空。
    final playbackState =
        speechState?.playbackState ?? SpeechPlaybackState.idle;

    // 是否正在发声；只在 speaking 时显示当前朗读高亮。
    final isSpeaking = playbackState == SpeechPlaybackState.speaking;

    // 是否处于朗读相关状态；paused 也算 active，因为可以停止或继续。
    final isActive = isSpeaking || playbackState == SpeechPlaybackState.paused;

    ref.listen(speechViewModelProvider, (previous, next) {
      // 朗读出错时直接在阅读页底部提示，避免用户只看到播放停止却不知道原因。
      if (next.hasError && next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error.toString())));
        return;
      }

      // 朗读推进到新句段时，让正文自动滚动，让高亮句子保持在屏幕偏上位置。
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
          // 把当前章节正文拆成较短句段：阅读显示、朗读高亮、自动滚动都复用这一份列表。
          final currentSentences = _sentencesFrom(data.chapter.content);

          // 为当前章节每个句段准备 GlobalKey，方便 TTS 朗读时调用 ensureVisible 定位。
          _ensureSentenceKeys(data.chapter.id, currentSentences.length);

          // 初始化本地五章滑动窗口。窗口准备好之前仍先显示当前章节，避免白屏。
          _ensureChapterWindow(data);
          final chapterBlocks = _chapterBlocks(data, currentSentences);

          // 页面首次打开某章时恢复上次位置；同一章后续 rebuild 不会重复恢复。
          _restoreScrollOffsetIfNeeded(data);

          // 阅读背景按亮暗主题选择纸张色，保证正文区域没有 Scaffold 默认色闪烁。
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final backgroundColor = isDark
              ? AppColors.readingPaperDark
              : AppColors.readingPaperLight;

          return ColoredBox(
            color: backgroundColor,
            child: Stack(
              children: [
                // 这个 GestureDetector 包住正文滚动区：
                // - 轻点正文：显示/隐藏上下控制栏。
                // - 右滑：返回书库。
                // - 竖向滚动：继续交给内部 ListView 自己处理。
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.down,
                  onTapDown: (details) =>
                      _tapDownPosition = details.globalPosition,
                  onTapUp: (details) =>
                      _handleReaderTap(details.globalPosition),
                  onTapCancel: () => _tapDownPosition = null,
                  onHorizontalDragEnd: (details) =>
                      _handleHorizontalDragEnd(details),
                  child: NotificationListener<ScrollNotification>(
                    // 监听 ListView 滚动，用于防抖保存进度，以及在用户自然滑入下一章时
                    // 激活下一章为当前章节。
                    onNotification: (notification) =>
                        _handleScrollNotification(notification, data),
                    child: ListView(
                      controller: _scrollController,
                      // 顶部避开刘海/状态栏，底部留出控制栏高度，避免正文被底部抽屉遮挡。
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top + 28,
                        24,
                        120 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        // 每个 block 是一整章。上一章、当前章、下一章放在同一条
                        // ListView 里，避免切章时重建到顶部造成跳动。
                        for (final block in chapterBlocks)
                          _ChapterBlockView(
                            key: _chapterKeyFor(block.chapter.id),
                            block: block,
                            bookTitle: data.book.title,
                            chapterCount: data.book.chapterCount,
                            fontSize: fontSize,
                            speakingSentenceIndex: speakingSentenceIndex,
                          ),
                      ],
                    ),
                  ),
                ),
                // 顶部抽屉控制栏：默认收起，点击正文后从顶部滑下。
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
                // 底部抽屉控制栏：显示阅读进度、朗读控制和上一章/下一章按钮。
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

  /// 处理正文区域的点击手势。
  ///
  /// Flutter 的 [GestureDetector] 在用户滑动时也可能收到 tap 相关事件，所以这里用
  /// `onTapDown` 记录起点、`onTapUp` 记录终点，如果两点距离超过 10 像素，就认为这是
  /// 滚动/拖动而不是点击，避免用户翻页时误触发控制栏。
  void _handleReaderTap(Offset position) {
    final start = _tapDownPosition;
    _tapDownPosition = null;
    if (start == null || (position - start).distance > 10) return;

    setState(() {
      _chromeVisible = !_chromeVisible;
    });
  }

  /// 处理横向滑动返回。
  ///
  /// iOS 用户习惯从左向右滑返回。这里读取横向主速度：正数表示向右，超过阈值时返回
  /// 书库。返回前 [_goLibrary] 会先保存当前阅读位置。
  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 520) {
      unawaited(_goLibrary());
    }
  }

  /// 返回书库。
  ///
  /// [data] 是调用时的当前阅读状态。传入它可以在保存进度时校验章节 ID，避免用户已经
  /// 切到下一章但旧异步回调又把上一章位置写回去。
  Future<void> _goLibrary([ReaderState? data]) async {
    await _flushReadingPosition(expectedChapterId: data?.chapter.id);
    if (!mounted) return;
    context.go(RoutePaths.library);
  }

  /// 跳到设置页。
  ///
  /// 设置页可能会调整字号或语音，跳走前先保存当前章节位置，回来后才能恢复到同一段。
  Future<void> _goSettings(ReaderState data) async {
    await _flushReadingPosition(expectedChapterId: data.chapter.id);
    if (!mounted) return;
    context.go(RoutePaths.settings);
  }

  /// 处理正文列表滚动通知。
  ///
  /// 做两件事：
  ///
  /// 1. 保存阅读进度：滚动中防抖保存，滚动结束立刻保存。
  /// 2. 连续章节激活：用户从当前章自然滑入下一章后，后台把下一章设为当前章节。
  ///
  /// 返回 false 表示不拦截通知，让 Flutter 原有滚动行为继续执行。
  bool _handleScrollNotification(
    ScrollNotification notification,
    ReaderState data,
  ) {
    if (notification.depth != 0) return false;

    if (notification is ScrollUpdateNotification) {
      _schedulePersistReadingPosition(data);
      _loadMoreChaptersIfNeeded(data, notification.metrics);
    } else if (notification is ScrollEndNotification) {
      _schedulePersistReadingPosition(data, delay: Duration.zero);
      _loadMoreChaptersIfNeeded(data, notification.metrics);
    }

    return false;
  }

  /// 从当前可见句段开始自动朗读。
  ///
  /// 朗读循环只读当前章节的句段；读完后如果还有下一章，会让 ViewModel 切到下一章，
  /// 然后从下一章第 0 段继续读。这里没有把“下一章正文”直接读掉，是因为朗读高亮和
  /// 章节状态仍然需要以当前章节为准。
  Future<void> _startAutoRead(ReaderState initialState) async {
    await _flushReadingPosition(expectedChapterId: initialState.chapter.id);
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

      await Future<void>.delayed(const Duration(milliseconds: 120));
      final nextState = ref.read(readerViewModelProvider(widget.bookId)).value;
      if (nextState == null) break;
      currentState = nextState;
      startIndex = 0;
    }
  }

  /// 底部控制栏“上一章”按钮。
  ///
  /// 这是明确的按钮跳转，所以仍然跳到上一章顶部；和手势连续滑动不同，按钮代表用户
  /// 主动选择章节。
  Future<void> _goPrevious() async {
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    _isChangingChapter = true;
    _cancelScrollRestore();
    try {
      await _flushReadingPosition(expectedChapterId: current?.chapter.id);
      await _stopSpeech();
      await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .previousChapter();
      if (!mounted) return;
      _jumpToTopAfterBuild();
    } catch (_) {
      _isChangingChapter = false;
      rethrow;
    }
  }

  /// 底部控制栏“下一章”按钮。
  ///
  /// 按钮行为和连续滑动行为分开：按钮会直接进入下一章并定位到章首；连续滑动则通过
  /// [_activateVisibleChapter] 在用户滑进下一章时无感切换状态。
  Future<void> _goNext() async {
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    _isChangingChapter = true;
    _cancelScrollRestore();
    try {
      await _flushReadingPosition(expectedChapterId: current?.chapter.id);
      await _stopSpeech();
      await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .nextChapter();
      if (!mounted) return;
      _jumpToTopAfterBuild();
    } catch (_) {
      _isChangingChapter = false;
      rethrow;
    }
  }

  /// 暂停朗读。
  ///
  /// 递增 [_autoReadSession] 的目的，是通知 [_startAutoRead] 里正在等待的旧循环停止。
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
  /// 目录只显示章节标题和序号，不加载正文；点击某章后让 ViewModel 读取对应章节，
  /// 页面随后跳到章首。
  Future<void> _showChapterSheet(ReaderState data) async {
    await _flushReadingPosition(expectedChapterId: data.chapter.id);
    if (!mounted) return;
    const itemExtent = 64.0;
    final selectedIndex = data.chapters.isEmpty
        ? 0
        : data.chapter.chapterIndex.clamp(0, data.chapters.length - 1).toInt();
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
                    _isChangingChapter = true;
                    _cancelScrollRestore();
                    try {
                      await _flushReadingPosition(
                        expectedChapterId: data.chapter.id,
                      );
                      await _stopSpeech();
                      await ref
                          .read(readerViewModelProvider(widget.bookId).notifier)
                          .goToChapter(chapter.chapterIndex);
                      if (!mounted) return;
                      _jumpToTopAfterBuild();
                    } catch (_) {
                      _isChangingChapter = false;
                      rethrow;
                    }
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

  /// 按保存的阅读位置恢复滚动。
  ///
  /// 这个函数只负责“安排恢复”。真正的 jumpTo 放在 post-frame 回调里执行，因为只有等
  /// 当前帧布局完成后，ListView 才知道 maxScrollExtent。
  void _restoreScrollOffsetIfNeeded(ReaderState data) {
    if (_restoredChapterId == data.chapter.id) return;
    final chapterId = data.chapter.id;
    _restoredChapterId = chapterId;
    final savedOffset = data.savedScrollOffset;
    final savedChapterProgress = data.savedChapterProgress
        .clamp(0.0, 1.0)
        .toDouble();
    final generation = ++_scrollRestoreGeneration;
    _isRestoringScrollOffset = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollOffset(
        chapterId: chapterId,
        savedOffset: savedOffset,
        savedChapterProgress: savedChapterProgress,
        generation: generation,
        attempt: 0,
      );
    });
  }

  /// 真正执行滚动恢复。
  ///
  /// 参数说明：
  ///
  /// - [chapterId]：恢复操作绑定的章节，防止异步等待期间章节已经切走。
  /// - [savedOffset]：数据库保存的像素偏移。
  /// - [savedChapterProgress]：数据库保存的章节内比例，字体变化后优先用它恢复。
  /// - [generation]：恢复任务代数，用于识别过期回调。
  /// - [attempt]：当前第几次尝试。
  /// - [previousMaxExtent]：上一帧最大滚动范围，用来判断布局是否稳定。
  void _restoreScrollOffset({
    required String chapterId,
    required double savedOffset,
    required double savedChapterProgress,
    required int generation,
    required int attempt,
    double? previousMaxExtent,
  }) {
    if (!mounted || generation != _scrollRestoreGeneration) {
      _finishScrollRestore(generation);
      return;
    }

    if (!_scrollController.hasClients) {
      _retryScrollRestore(
        chapterId: chapterId,
        savedOffset: savedOffset,
        savedChapterProgress: savedChapterProgress,
        generation: generation,
        attempt: attempt,
        previousMaxExtent: previousMaxExtent,
      );
      return;
    }

    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current?.chapter.id != chapterId) {
      _finishScrollRestore(generation);
      return;
    }

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final target =
        _chapterRestoreTargetOffset(
          chapterId: chapterId,
          savedOffset: savedOffset,
          savedChapterProgress: savedChapterProgress,
        ) ??
        _restoreTargetOffset(
          maxExtent: maxExtent,
          savedOffset: savedOffset,
          savedChapterProgress: savedChapterProgress,
        );
    if ((position.pixels - target).abs() > 0.5) {
      position.jumpTo(target);
    }

    final isExtentStable =
        previousMaxExtent != null &&
        (previousMaxExtent - maxExtent).abs() < 0.5;
    final noSavedPosition = savedOffset <= 0 && savedChapterProgress <= 0;
    if (noSavedPosition ||
        isExtentStable ||
        attempt >= _maxScrollRestoreAttempts - 1) {
      _finishScrollRestore(generation);
      return;
    }

    _retryScrollRestore(
      chapterId: chapterId,
      savedOffset: savedOffset,
      savedChapterProgress: savedChapterProgress,
      generation: generation,
      attempt: attempt,
      previousMaxExtent: maxExtent,
    );
  }

  /// 在下一帧继续尝试恢复滚动位置。
  ///
  /// 文字排版可能因为字体加载、系统字号、安全区等因素连续变化几帧，所以恢复位置不是
  /// 只做一次，而是等 maxScrollExtent 稳定后才结束。
  void _retryScrollRestore({
    required String chapterId,
    required double savedOffset,
    required double savedChapterProgress,
    required int generation,
    required int attempt,
    double? previousMaxExtent,
  }) {
    if (attempt >= _maxScrollRestoreAttempts - 1) {
      _finishScrollRestore(generation);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollOffset(
        chapterId: chapterId,
        savedOffset: savedOffset,
        savedChapterProgress: savedChapterProgress,
        generation: generation,
        attempt: attempt + 1,
        previousMaxExtent: previousMaxExtent,
      );
    });
  }

  /// 在连续章节列表中，计算某个章节自己的恢复位置。
  ///
  /// 因为现在 ListView 里可能先放了上一章，再放当前章，所以不能再把 savedOffset 当成
  /// 整条 ListView 的 offset。这里先找到当前章节 block 在 ListView 里的起点，再加上章节
  /// 内部 offset / progress，才能恢复到真正读到的位置。
  double? _chapterRestoreTargetOffset({
    required String chapterId,
    required double savedOffset,
    required double savedChapterProgress,
  }) {
    if (!_scrollController.hasClients) return null;
    final context = _chapterKeys[chapterId]?.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final top = renderObject.localToGlobal(Offset.zero).dy;
    final height = renderObject.size.height;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final chapterScrollableHeight = (height - viewportHeight)
        .clamp(1.0, double.infinity)
        .toDouble();
    final innerTarget = savedChapterProgress > 0
        ? chapterScrollableHeight * savedChapterProgress
        : savedOffset;
    return (_scrollController.offset + top + innerTarget)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
  }

  /// 计算需要恢复到的 ListView 像素位置。
  ///
  /// 有 [savedChapterProgress] 时优先用比例恢复，因为用户改字号后原来的像素值可能不准；
  /// 没有比例时再回退到旧版保存的像素值。
  double _restoreTargetOffset({
    required double maxExtent,
    required double savedOffset,
    required double savedChapterProgress,
  }) {
    final target = savedChapterProgress > 0
        ? maxExtent * savedChapterProgress
        : savedOffset;
    return target.clamp(0.0, maxExtent).toDouble();
  }

  /// 标记某一次滚动恢复结束。
  ///
  /// 只有 generation 仍然匹配时才清理状态，避免旧恢复任务把新恢复任务的状态关掉。
  void _finishScrollRestore(int generation) {
    if (generation == _scrollRestoreGeneration) {
      _isRestoringScrollOffset = false;
    }
  }

  /// 取消所有尚未执行的滚动恢复任务。
  void _cancelScrollRestore() {
    _scrollRestoreGeneration += 1;
    _isRestoringScrollOffset = false;
  }

  /// 获取某个章节 block 的 GlobalKey。
  ///
  /// 同一章的 key 要稳定复用，否则 build 后无法比较章节切换前后的屏幕位置。
  GlobalKey _chapterKeyFor(String chapterId) {
    return _chapterKeys.putIfAbsent(chapterId, GlobalKey.new);
  }

  /// 初始化以当前章节为中心的五章滑动窗口。
  ///
  /// 例如当前是第 3 章时，页面会查询并保留 `1、2、3、4、5`。后续用户滑到边缘时只
  /// 查询一个新章节并插入窗口，不替换整张阅读页，因此没有“刷新一下再跳”的感觉。
  void _ensureChapterWindow(ReaderState data) {
    final needsInitialization =
        _loadedBookId != data.book.id ||
        _loadedCenterChapterIndex != data.chapter.chapterIndex ||
        _loadedChapters.isEmpty;
    if (!needsInitialization || _isInitializingChapterWindow) return;

    _isInitializingChapterWindow = true;
    unawaited(() async {
      try {
        final notifier = ref.read(
          readerViewModelProvider(widget.bookId).notifier,
        );
        final chapters = <BookChapter>[];
        final start = (data.chapter.chapterIndex - 2)
            .clamp(0, data.book.chapterCount - 1)
            .toInt();
        final end = (data.chapter.chapterIndex + 2)
            .clamp(0, data.book.chapterCount - 1)
            .toInt();

        for (var index = start; index <= end; index += 1) {
          final chapter = index == data.chapter.chapterIndex
              ? data.chapter
              : await notifier.getChapterAt(index);
          if (chapter != null) chapters.add(chapter);
        }

        if (!mounted) return;
        setState(() {
          _loadedBookId = data.book.id;
          _loadedCenterChapterIndex = data.chapter.chapterIndex;
          _loadedChapters
            ..clear()
            ..addAll(chapters);
          _chapterKeys.clear();
        });
      } finally {
        _isInitializingChapterWindow = false;
      }
    }());
  }

  /// 组装要交给 ListView 渲染的章节块。
  ///
  /// 初始化完成后完全以 [_loadedChapters] 为准。这个数组只会在边缘处增量增删，不会因为
  /// 触及某章标题就重建为另一批章节；这正是连续滑动不跳顶的关键。
  List<_ChapterRenderBlock> _chapterBlocks(
    ReaderState data,
    List<String> currentSentences,
  ) {
    final chapters = _loadedChapters.isEmpty
        ? <BookChapter>[data.chapter]
        : _loadedChapters;
    final blocks = chapters
        .map(
          (chapter) => _ChapterRenderBlock(
            chapter: chapter,
            sentences: chapter.id == data.chapter.id
                ? currentSentences
                : _sentencesFrom(chapter.content),
            sentenceKeys: chapter.id == data.chapter.id
                ? _sentenceKeys
                : const [],
            isCurrentChapter: chapter.id == data.chapter.id,
          ),
        )
        .toList();

    _chapterKeys.removeWhere(
      (chapterId, _) => !blocks.any((block) => block.chapter.id == chapterId),
    );
    return blocks;
  }

  /// 在靠近连续列表顶部或底部时，按需加载一个新章节。
  ///
  /// 这里刻意不调用 `nextChapter`、`previousChapter` 或 `activateChapterFromScroll`：
  /// 它们都会替换 ReaderState 并让正文重建。正确做法是只查询一个章节，直接插入
  /// [_loadedChapters]，保持用户正在阅读的 Text widget 不动。
  void _loadMoreChaptersIfNeeded(ReaderState data, ScrollMetrics metrics) {
    if (_loadedChapters.isEmpty) return;

    // 距离底部约两个屏幕高度时提前查询下一章，快速滑动也不会看到等待空白。
    if (metrics.extentAfter < metrics.viewportDimension * 2) {
      unawaited(_appendNextChapter(data));
    }

    // 距离顶部约两个屏幕高度时提前查询上一章。
    if (metrics.extentBefore < metrics.viewportDimension * 2) {
      unawaited(_prependPreviousChapter(data));
    }
  }

  /// 查询并追加当前窗口之后的一章。
  Future<void> _appendNextChapter(ReaderState data) async {
    if (_isAppendingChapter || _loadedChapters.isEmpty) return;
    final last = _loadedChapters.last;
    if (last.chapterIndex >= data.book.chapterCount - 1) return;

    _isAppendingChapter = true;
    try {
      final chapter = await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .getChapterAt(last.chapterIndex + 1);
      if (!mounted || chapter == null) return;
      if (_loadedChapters.any((item) => item.id == chapter.id)) return;

      setState(() {
        // 只在列表末尾插入一个 child，现有 child 的位置不会变化。
        _loadedChapters.add(chapter);
      });
    } finally {
      _isAppendingChapter = false;
    }
  }

  /// 查询并前插当前窗口之前的一章，同时保持用户眼前文字位置不动。
  ///
  /// 前插和末尾追加不同：新章节会把所有已有 child 向下推。如果仅仅 `insert(0, chapter)`，
  /// 用户会看到正文瞬间向下跳一整章。因此必须以原窗口第一章为锚点：
  ///
  /// 1. 插入前记录锚点章节在屏幕中的 y 坐标。
  /// 2. 前插新章节并等待 Flutter 完成布局。
  /// 3. 计算锚点新增后的 y 偏移。
  /// 4. 用相同偏移修正 ScrollPosition，让锚点回到原 y 坐标。
  ///
  /// [_isPrependingChapter] 会一直保持 true 到第四步完成。不能在 setState 后立即解锁，
  /// 否则此时触发的下一条 ScrollNotification 会再次开始前插，造成多次补偿互相叠加。
  Future<void> _prependPreviousChapter(ReaderState data) async {
    if (_isPrependingChapter || _loadedChapters.isEmpty) return;
    final first = _loadedChapters.first;
    if (first.chapterIndex <= 0) return;

    _isPrependingChapter = true;
    try {
      final chapter = await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .getChapterAt(first.chapterIndex - 1);
      if (!mounted || chapter == null) return;
      if (_loadedChapters.any((item) => item.id == chapter.id)) return;

      // 把原窗口第一章作为锚点；它在前插后仍保留同一个 GlobalKey。
      final anchorContext = _chapterKeys[first.id]?.currentContext;
      final anchorRenderObject = anchorContext?.findRenderObject();
      final previousAnchorTop =
          anchorRenderObject is RenderBox && anchorRenderObject.hasSize
          ? anchorRenderObject.localToGlobal(Offset.zero).dy
          : null;

      setState(() {
        _loadedChapters.insert(0, chapter);
      });

      // 没有可用锚点时只能保留 Flutter 默认位置；这种情况通常只会发生在首次布局。
      if (previousAnchorTop == null) return;

      final frameCompleted = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          frameCompleted.complete();
          return;
        }

        final currentContext = _chapterKeys[first.id]?.currentContext;
        final currentRenderObject = currentContext?.findRenderObject();
        if (currentRenderObject is RenderBox && currentRenderObject.hasSize) {
          final currentAnchorTop = currentRenderObject
              .localToGlobal(Offset.zero)
              .dy;
          final target =
              (_scrollController.offset + currentAnchorTop - previousAnchorTop)
                  .clamp(0.0, _scrollController.position.maxScrollExtent)
                  .toDouble();

          // correctPixels 不会像 jumpTo 一样派发新的滚动通知，避免补偿本身再次触发加载。
          _scrollController.position.correctPixels(target);
        }
        frameCompleted.complete();
      });

      // 等补偿完成再允许下一个前插请求进入。
      await frameCompleted.future;
    } finally {
      _isPrependingChapter = false;
    }
  }

  /// 计算屏幕阅读线当前落在哪个章节里。
  ///
  /// 这里不用“滚动到底部”判断，而是取屏幕上方约 42% 的位置作为阅读线：
  ///
  /// - 阅读线落在当前章：保存当前章进度。
  /// - 阅读线落在上一章/下一章：保存对应章节进度。
  ///
  /// 返回值同时包含章节内位置，供进度保存使用。
  _VisibleChapterPosition? _visibleChapterPosition(ReaderState data) {
    if (!_scrollController.hasClients) return null;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final readingLine =
        MediaQuery.paddingOf(context).top + viewportHeight * 0.42;
    // 进度计算必须看完整本地窗口，而不是只看 ReaderState 的相邻两章；用户可能已经
    // 在同一条列表中滑到了追加进来的第 6、7 章。
    final candidates = _loadedChapters.isEmpty
        ? <BookChapter>[data.chapter]
        : _loadedChapters;

    for (final chapter in candidates) {
      final position = _chapterPosition(chapter, readingLine: readingLine);
      if (position != null) return position;
    }

    return null;
  }

  _VisibleChapterPosition? _chapterPosition(
    BookChapter chapter, {
    double? readingLine,
  }) {
    if (!_scrollController.hasClients) return null;
    final context = _chapterKeys[chapter.id]?.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final effectiveReadingLine =
        readingLine ??
        MediaQuery.paddingOf(context).top + viewportHeight * 0.42;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final height = renderObject.size.height;
    final bottom = top + height;
    if (effectiveReadingLine < top || effectiveReadingLine > bottom) {
      return null;
    }

    final rawOffset = effectiveReadingLine - top;
    final chapterScrollableHeight = (height - viewportHeight)
        .clamp(1.0, double.infinity)
        .toDouble();
    final chapterOffset = rawOffset
        .clamp(0.0, chapterScrollableHeight)
        .toDouble();
    final chapterProgress = (chapterOffset / chapterScrollableHeight)
        .clamp(0.0, 1.0)
        .toDouble();
    return _VisibleChapterPosition(
      chapterId: chapter.id,
      chapterIndex: chapter.chapterIndex,
      top: top,
      scrollOffset: chapterOffset,
      chapterProgress: chapterProgress,
    );
  }

  /// 在下一帧跳到章节顶部。
  ///
  /// 这个函数只用于明确的“按钮/目录跳章”。连续滑动不调用它，因为连续滑动需要保持
  /// 屏幕位置不动。
  void _jumpToTopAfterBuild() {
    final generation = _scrollRestoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _scrollRestoreGeneration) {
        _isChangingChapter = false;
        return;
      }
      if (!_scrollController.hasClients) {
        _isChangingChapter = false;
        return;
      }
      _scrollController.jumpTo(0);
      _isChangingChapter = false;
    });
  }

  /// 安排一次阅读进度保存。
  ///
  /// 默认延迟 450ms，是为了滚动过程中不要频繁写数据库；滚动结束时调用方会传入
  /// [Duration.zero] 立即保存。
  void _schedulePersistReadingPosition(
    ReaderState data, {
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (_isRestoringScrollOffset || _isChangingChapter) return;
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(delay, () {
      unawaited(
        _persistCurrentReadingPosition(expectedChapterId: data.chapter.id),
      );
    });
  }

  /// 立即保存阅读进度。
  ///
  /// 离开页面、进入设置、打开目录前都会调用它，确保用户最后看到的位置不会因为防抖
  /// 延迟还没到而丢失。
  Future<void> _flushReadingPosition({String? expectedChapterId}) {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = null;
    return _persistCurrentReadingPosition(
      expectedChapterId: expectedChapterId,
      force: true,
    );
  }

  /// 把当前屏幕对应的阅读位置写入数据库。
  ///
  /// 连续章节模式下，当前 ListView 可能同时包含“当前章 + 下一章”。因此保存时先用
  /// [_visibleChapterPosition] 判断阅读线落在哪一章，再保存那一章的进度；只有判断不到
  /// 具体章节时，才退回到旧的整条 ListView 比例算法。
  Future<void> _persistCurrentReadingPosition({
    String? expectedChapterId,
    bool force = false,
  }) async {
    if (!mounted || !_scrollController.hasClients) return;
    if (!force && (_isRestoringScrollOffset || _isChangingChapter)) return;
    final current = ref.read(readerViewModelProvider(widget.bookId)).value;
    if (current == null) return;
    if (expectedChapterId != null && current.chapter.id != expectedChapterId) {
      return;
    }

    final visible = _visibleChapterPosition(current);
    if (visible != null) {
      await ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .saveReadingPosition(
            chapterIndex: visible.chapterIndex,
            scrollOffset: visible.scrollOffset,
            chapterProgress: visible.chapterProgress,
          );
      return;
    }

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final offset = position.pixels.clamp(0.0, maxExtent).toDouble();
    final chapterProgress = maxExtent <= 0
        ? 0.0
        : (offset / maxExtent).clamp(0.0, 1.0).toDouble();

    await ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .saveReadingPosition(
          scrollOffset: offset,
          chapterProgress: chapterProgress,
        );
  }

  /// 确保当前章节的句段 key 数量和句段数量一致。
  ///
  /// 每个 key 对应一个 [_SentenceText]，TTS 自动滚动时需要通过 key 找到该句段在屏幕上
  /// 的位置。
  void _ensureSentenceKeys(String chapterId, int length) {
    if (_sentenceKeySeed == chapterId && _sentenceKeys.length == length) return;
    _sentenceKeySeed = chapterId;
    _sentenceKeys
      ..clear()
      ..addAll(List.generate(length, (_) => GlobalKey()));
  }

  /// 找到当前屏幕里第一个可见句段。
  ///
  /// 用户点击“开始朗读”时，不应该从章节第一句重新读，而是从当前屏幕正在看的句段附近
  /// 开始读，所以这里遍历所有当前章句段 key，找第一个和阅读区域相交的句段。
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
  ///
  /// 使用 [Scrollable.ensureVisible] 而不是手算 offset，是因为句段高度会受字体大小、屏幕
  /// 宽度、中英文混排等因素影响，Flutter 自己定位更稳。
  void _scrollToSentence(int index) {
    if (index < 0 || index >= _sentenceKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _sentenceKeys[index].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.28,
      );
    });
  }

  /// 把章节正文拆分成用于显示和朗读的句段。
  ///
  /// 规则说明：
  ///
  /// - 先统一换行符，去掉首尾空白。
  /// - 遇到常见中英文句末标点时切分。
  /// - 句末后紧跟的右引号/右括号会并入同一句，避免 `“你好。”` 被拆坏。
  /// - 很长的段落会按固定长度再切小，避免单个 Text 或 TTS 任务过长。
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
  ///
  /// 把连续空白折叠成一个空格，并过滤掉只有标点/符号的噪声段。
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
  ///
  /// 这样做有两个好处：
  ///
  /// 1. UI：单个 Text 不会过长，朗读高亮的位置更容易控制。
  /// 2. TTS：系统语音一次朗读的文本不会太长，降低失败或延迟风险。
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
    required this.chapterId,
    required this.chapterIndex,
    required this.top,
    required this.scrollOffset,
    required this.chapterProgress,
  });

  final String chapterId;
  final int chapterIndex;
  final double top;
  final double scrollOffset;
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
            top: block.isCurrentChapter ? 0 : 26,
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

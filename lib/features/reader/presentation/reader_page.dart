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
import 'package:reader_app/features/reader/presentation/reader_view_model.dart';
import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/presentation/speech_view_model.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';

/// 图书阅读页。
///
/// 阅读页负责正文展示、章节目录、章节切换和朗读跟随。章节数据和进度保存由 ViewModel 负责。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({required this.bookId, super.key});

  /// 当前图书 ID。
  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  static const double _nextChapterOverscrollTrigger = 72;
  static const int _maxScrollRestoreAttempts = 8;

  final List<GlobalKey> _sentenceKeys = [];
  String? _sentenceKeySeed;
  String? _restoredChapterId;
  Timer? _progressSaveDebounce;
  int _autoReadSession = 0;
  int _scrollRestoreGeneration = 0;
  double _bottomOverscroll = 0;
  bool _chromeVisible = false;
  bool _isChangingChapter = false;
  bool _isRestoringScrollOffset = false;
  Offset? _tapDownPosition;

  @override
  void initState() {
    super.initState();
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
    _autoReadSession += 1;
    WidgetsBinding.instance.removeObserver(this);
    _progressSaveDebounce?.cancel();
    unawaited(_persistCurrentReadingPosition(force: true));
    _cancelScrollRestore();
    _scrollController.dispose();
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
          final sentences = _sentencesFrom(data.chapter.content);
          _ensureSentenceKeys(data.chapter.id, sentences.length);
          _restoreScrollOffsetIfNeeded(data);

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
                  onHorizontalDragEnd: (details) =>
                      _handleHorizontalDragEnd(details),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) =>
                        _handleScrollNotification(notification, data),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top + 28,
                        24,
                        120 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: sentences.length + 2,
                      itemBuilder: (context, index) {
                        final contentIndex = index;
                        if (contentIndex == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.chapter.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.4,
                                        height: 1.18,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${data.book.title} · 第 ${data.chapter.chapterIndex + 1} / ${data.book.chapterCount} 章',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        letterSpacing: 0.2,
                                      ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (contentIndex == sentences.length + 1) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 22, bottom: 24),
                            child: Text(
                              '第 ${data.chapter.chapterIndex + 1} / ${data.book.chapterCount} 章',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          );
                        }

                        final sentenceIndex = contentIndex - 1;
                        final isCurrentSentence =
                            speakingSentenceIndex == sentenceIndex;
                        return _SentenceText(
                          key: _sentenceKeys[sentenceIndex],
                          text: sentences[sentenceIndex],
                          fontSize: fontSize,
                          isSpeaking: isCurrentSentence,
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
                  sentenceCount: sentences.length,
                  currentSentence: speakingSentenceIndex == null
                      ? null
                      : sentences[speakingSentenceIndex.clamp(
                          0,
                          sentences.length - 1,
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

  void _handleReaderTap(Offset position) {
    final start = _tapDownPosition;
    _tapDownPosition = null;
    if (start == null || (position - start).distance > 10) return;

    setState(() {
      _chromeVisible = !_chromeVisible;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 520) {
      unawaited(_goLibrary());
    }
  }

  Future<void> _goLibrary([ReaderState? data]) async {
    await _flushReadingPosition(expectedChapterId: data?.chapter.id);
    if (!mounted) return;
    context.go(RoutePaths.library);
  }

  Future<void> _goSettings(ReaderState data) async {
    await _flushReadingPosition(expectedChapterId: data.chapter.id);
    if (!mounted) return;
    context.go(RoutePaths.settings);
  }

  bool _handleScrollNotification(
    ScrollNotification notification,
    ReaderState data,
  ) {
    if (notification.depth != 0) return false;

    if (notification is ScrollUpdateNotification) {
      _schedulePersistReadingPosition(data);
      if (notification.dragDetails == null) {
        _bottomOverscroll = 0;
      }
    } else if (notification is ScrollEndNotification) {
      _bottomOverscroll = 0;
      _schedulePersistReadingPosition(data, delay: Duration.zero);
    }

    if (!data.canGoNext || _isChangingChapter || _isRestoringScrollOffset) {
      return false;
    }

    if (notification is! OverscrollNotification ||
        notification.dragDetails == null ||
        notification.overscroll <= 0) {
      return false;
    }

    final metrics = notification.metrics;
    final atBottom = metrics.pixels >= metrics.maxScrollExtent - 2;
    if (!atBottom) {
      _bottomOverscroll = 0;
      return false;
    }

    _bottomOverscroll += notification.overscroll;
    if (_bottomOverscroll >= _nextChapterOverscrollTrigger) {
      _bottomOverscroll = 0;
      unawaited(_autoNextChapter(data));
    }
    return false;
  }

  Future<void> _autoNextChapter(ReaderState currentState) async {
    if (_isChangingChapter) return;
    _isChangingChapter = true;
    _cancelScrollRestore();
    try {
      await _flushReadingPosition(expectedChapterId: currentState.chapter.id);
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

  Future<void> _pauseSpeech() async {
    _autoReadSession += 1;
    await ref.read(speechViewModelProvider.notifier).pause();
  }

  Future<void> _stopSpeech() async {
    _autoReadSession += 1;
    await ref.read(speechViewModelProvider.notifier).stop();
  }

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
    final target = _restoreTargetOffset(
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

  void _finishScrollRestore(int generation) {
    if (generation == _scrollRestoreGeneration) {
      _isRestoringScrollOffset = false;
    }
  }

  void _cancelScrollRestore() {
    _scrollRestoreGeneration += 1;
    _isRestoringScrollOffset = false;
  }

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

  Future<void> _flushReadingPosition({String? expectedChapterId}) {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = null;
    return _persistCurrentReadingPosition(
      expectedChapterId: expectedChapterId,
      force: true,
    );
  }

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

  void _ensureSentenceKeys(String chapterId, int length) {
    if (_sentenceKeySeed == chapterId && _sentenceKeys.length == length) return;
    _sentenceKeySeed = chapterId;
    _sentenceKeys
      ..clear()
      ..addAll(List.generate(length, (_) => GlobalKey()));
  }

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

  void _addSentence(List<String> target, String value) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || _isNoiseSentence(text)) return;
    target.add(text);
  }

  bool _isNoiseSentence(String text) {
    return RegExp(r'^[\s\p{P}\p{S}]+$', unicode: true).hasMatch(text);
  }

  bool _isSentenceEnd(String char) {
    return '。！？!?；;.'.contains(char);
  }

  bool _isClosingQuote(String char) {
    return '”’」』）)]》'.contains(char);
  }

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

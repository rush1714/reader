import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sentenceKeys = [];
  String? _sentenceKeySeed;
  int _autoReadSession = 0;

  @override
  void dispose() {
    _autoReadSession += 1;
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
    final playbackState = speechState?.playbackState ?? SpeechPlaybackState.idle;
    final isSpeaking = playbackState == SpeechPlaybackState.speaking;
    final isActive = isSpeaking || playbackState == SpeechPlaybackState.paused;

    ref.listen(speechViewModelProvider, (previous, next) {
      if (next.hasError && next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error.toString())),
        );
        return;
      }

      final nextIndex = next.value?.currentSentenceIndex;
      final previousIndex = previous?.value?.currentSentenceIndex;
      if (nextIndex != null && nextIndex != previousIndex) {
        _scrollToSentence(nextIndex);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: readerState.maybeWhen(
          data: (data) => Text(data.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          orElse: () => const Text('阅读'),
        ),
        actions: [
          readerState.maybeWhen(
            data: (data) => IconButton(
              tooltip: '章节目录',
              onPressed: () => _showChapterSheet(data),
              icon: const Icon(Icons.format_list_bulleted),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: '减小字号',
            onPressed: settings == null
                ? null
                : () => ref
                    .read(readerSettingsProvider.notifier)
                    .updateFontSize((fontSize - 1).clamp(14, 30).toDouble()),
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: '增大字号',
            onPressed: settings == null
                ? null
                : () => ref
                    .read(readerSettingsProvider.notifier)
                    .updateFontSize((fontSize + 1).clamp(14, 30).toDouble()),
            icon: const Icon(Icons.text_increase),
          ),
        ],
      ),
      body: readerState.when(
        loading: () => const AppLoading(),
        error: (error, stackTrace) => AppErrorView(error: error),
        data: (data) {
          final sentences = _sentencesFrom(data.chapter.content);
          _ensureSentenceKeys(data.chapter.id, sentences.length);

          final isDark = Theme.of(context).brightness == Brightness.dark;
          return ColoredBox(
            color: isDark ? AppColors.readingPaperDark : AppColors.readingPaperLight,
            child: Column(
              children: [
                LinearProgressIndicator(value: data.progress.clamp(0, 1)),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    itemCount: sentences.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            data.chapter.title,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        );
                      }

                      if (index == sentences.length + 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '第 ${data.chapter.chapterIndex + 1} / ${data.book.chapterCount} 章',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        );
                      }

                      final sentenceIndex = index - 1;
                      final isCurrentSentence = speakingSentenceIndex == sentenceIndex;
                      return _SentenceText(
                        key: _sentenceKeys[sentenceIndex],
                        text: sentences[sentenceIndex],
                        fontSize: fontSize,
                        isSpeaking: isCurrentSentence,
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: '上一章',
                          onPressed: data.canGoPrevious ? () => _goPrevious() : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isSpeaking ? _pauseSpeech : () => _startAutoRead(data),
                            icon: Icon(isSpeaking ? Icons.pause : Icons.play_arrow),
                            label: Text(
                              isSpeaking ? '暂停' : '开始朗读',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '停止朗读',
                          onPressed: isActive ? _stopSpeech : null,
                          icon: Icon(isActive ? Icons.stop_circle : Icons.stop_circle_outlined),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '下一章',
                          onPressed: data.canGoNext ? () => _goNext() : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _startAutoRead(ReaderState initialState) async {
    final sessionId = ++_autoReadSession;
    var currentState = initialState;
    var startIndex = _firstVisibleSentenceIndex();

    while (mounted && sessionId == _autoReadSession) {
      final sentences = _sentencesFrom(currentState.chapter.content);
      final completed = await ref.read(speechViewModelProvider.notifier).speakSentences(
            sentences,
            startIndex: startIndex,
          );
      if (!completed || !mounted || sessionId != _autoReadSession || !currentState.canGoNext) {
        break;
      }

      await ref.read(readerViewModelProvider(widget.bookId).notifier).nextChapter();
      if (!mounted || sessionId != _autoReadSession) break;

      await Future<void>.delayed(const Duration(milliseconds: 120));
      final nextState = ref.read(readerViewModelProvider(widget.bookId)).value;
      if (nextState == null) break;
      currentState = nextState;
      startIndex = 0;
    }
  }

  Future<void> _goPrevious() async {
    await _stopSpeech();
    await ref.read(readerViewModelProvider(widget.bookId).notifier).previousChapter();
  }

  Future<void> _goNext() async {
    await _stopSpeech();
    await ref.read(readerViewModelProvider(widget.bookId).notifier).nextChapter();
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: data.chapters.length,
            itemBuilder: (context, index) {
              final chapter = data.chapters[index];
              final selected = chapter.chapterIndex == data.chapter.chapterIndex;
              return ListTile(
                selected: selected,
                leading: Text('${chapter.chapterIndex + 1}'),
                title: Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _stopSpeech();
                  await ref
                      .read(readerViewModelProvider(widget.bookId).notifier)
                      .goToChapter(chapter.chapterIndex);
                },
              );
            },
          ),
        );
      },
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
    const topBoundary = kToolbarHeight + 24;
    final bottomBoundary = screenHeight - 120;

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
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const ['当前章节没有可显示的文字内容。'];

    final sentences = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i += 1) {
      final char = normalized[i];
      buffer.write(char);
      if (_isSentenceEnd(char)) {
        while (i + 1 < normalized.length && _isClosingQuote(normalized[i + 1])) {
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
    if (text.isNotEmpty) target.add(text);
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
      final end = start + maxLength > sentence.length ? sentence.length : start + maxLength;
      yield sentence.substring(start, end);
    }
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
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: isSpeaking ? 10 : 0,
        vertical: isSpeaking ? 8 : 0,
      ),
      decoration: BoxDecoration(
        color: isSpeaking ? colorScheme.primaryContainer.withValues(alpha: 0.78) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: AppTextStyles.readerBody.copyWith(
          fontSize: fontSize,
          color: isSpeaking ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
          fontWeight: isSpeaking ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

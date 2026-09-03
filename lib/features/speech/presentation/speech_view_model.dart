import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/data/services/speech_service.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';

/// 阅读页语音播放状态。
class SpeechViewState {
  const SpeechViewState({
    required this.playbackState,
    required this.currentSentenceIndex,
  });

  /// 当前播放状态。
  final SpeechPlaybackState playbackState;

  /// 当前朗读段落索引。
  final int? currentSentenceIndex;

  SpeechViewState copyWith({
    SpeechPlaybackState? playbackState,
    Object? currentSentenceIndex = _notProvided,
  }) {
    return SpeechViewState(
      playbackState: playbackState ?? this.playbackState,
      currentSentenceIndex: identical(currentSentenceIndex, _notProvided)
          ? this.currentSentenceIndex
          : currentSentenceIndex as int?,
    );
  }
}

const _notProvided = Object();

/// 阅读页语音播放状态 Provider。
final speechViewModelProvider = AsyncNotifierProvider<SpeechViewModel, SpeechViewState>(
  SpeechViewModel.new,
);

/// 语音播放控制器。
///
/// 负责按段落朗读和维护当前朗读段落。跨章节自动阅读由阅读页协调，因为下一章内容属于阅读器状态。
class SpeechViewModel extends AsyncNotifier<SpeechViewState> {
  int _sessionId = 0;

  @override
  Future<SpeechViewState> build() async {
    final settings = await ref.watch(readerSettingsProvider.future);
    return SpeechViewState(
      playbackState: ref.watch(speechServiceProvider).stateFor(settings.speechEngine),
      currentSentenceIndex: null,
    );
  }

  /// 按段落朗读当前章节。
  ///
  /// 返回 `true` 表示本章节段落全部读完；返回 `false` 表示被暂停、停止或发生错误。
  Future<bool> speakSentences(
    List<String> sentences, {
    required int startIndex,
  }) async {
    final sessionId = ++_sessionId;
    if (sentences.isEmpty) {
      state = const AsyncData(
        SpeechViewState(
          playbackState: SpeechPlaybackState.idle,
          currentSentenceIndex: null,
        ),
      );
      return true;
    }

    final safeStartIndex = startIndex.clamp(0, sentences.length - 1);
    for (var index = safeStartIndex; index < sentences.length; index += 1) {
      if (sessionId != _sessionId) return false;

      final settings = await ref.read(readerSettingsProvider.future);
      final service = ref.read(speechServiceProvider);
      state = AsyncData(
        SpeechViewState(
          playbackState: SpeechPlaybackState.speaking,
          currentSentenceIndex: index,
        ),
      );

      try {
        await service.speak(sentences[index], settings);
      } catch (error, stackTrace) {
        state = AsyncError(error, stackTrace);
        return false;
      }

      if (sessionId != _sessionId) return false;
    }

    if (sessionId == _sessionId) {
      state = const AsyncData(
        SpeechViewState(
          playbackState: SpeechPlaybackState.idle,
          currentSentenceIndex: null,
        ),
      );
    }
    return true;
  }

  /// 兼容旧的整段朗读调用。
  Future<void> speak(String text) async {
    await speakSentences([text], startIndex: 0);
  }

  /// 试听当前选择的声音。
  Future<void> previewCurrentVoice() async {
    _sessionId += 1;
    final settings = await ref.read(readerSettingsProvider.future);
    final service = ref.read(speechServiceProvider);
    state = const AsyncData(
      SpeechViewState(
        playbackState: SpeechPlaybackState.speaking,
        currentSentenceIndex: null,
      ),
    );

    try {
      await service.speak('这是一段试听语音。', settings);
      state = const AsyncData(
        SpeechViewState(
          playbackState: SpeechPlaybackState.idle,
          currentSentenceIndex: null,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 暂停朗读。
  Future<void> pause() async {
    _sessionId += 1;
    final settings = await ref.read(readerSettingsProvider.future);
    final service = ref.read(speechServiceProvider);
    await service.pause(settings);
    state = AsyncData(
      SpeechViewState(
        playbackState: service.stateFor(settings.speechEngine),
        currentSentenceIndex: state.value?.currentSentenceIndex,
      ),
    );
  }

  /// 停止朗读。
  Future<void> stop() async {
    _sessionId += 1;
    final settings = await ref.read(readerSettingsProvider.future);
    final service = ref.read(speechServiceProvider);
    await service.stop(settings);
    state = AsyncData(
      SpeechViewState(
        playbackState: service.stateFor(settings.speechEngine),
        currentSentenceIndex: null,
      ),
    );
  }
}

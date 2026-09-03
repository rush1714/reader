import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';

/// 语音引擎抽象。
///
/// 阅读页只依赖这个接口。后续接入端侧 AI TTS 模型时，只需要新增实现并在
/// `SpeechService` 中切换，不需要改阅读页。
abstract interface class SpeechEngineService {
  /// 引擎类型。
  SpeechEngineType get type;

  /// 引擎是否可用。
  bool get isAvailable;

  /// 当前播放状态。
  SpeechPlaybackState get playbackState;

  /// 查询可选声音。
  Future<List<SpeechVoice>> listVoices();

  /// 开始朗读文本。
  Future<void> speak(String text, ReaderSettings settings);

  /// 暂停朗读。
  Future<void> pause();

  /// 停止朗读。
  Future<void> stop();
}

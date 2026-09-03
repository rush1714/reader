import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/speech/data/services/speech_engine_service.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';

/// 端侧 AI TTS 预留引擎。
///
/// 第一版不打包大模型，也不调用云端大语言模型。该类明确表达未来接入点：可以接入
/// 小型端侧 TTS 模型或平台高质量神经语音，并保持阅读页调用方式不变。
class OnDeviceAiTtsService implements SpeechEngineService {
  SpeechPlaybackState _state = SpeechPlaybackState.unavailable;

  @override
  SpeechEngineType get type => SpeechEngineType.onDeviceAi;

  @override
  bool get isAvailable => false;

  @override
  SpeechPlaybackState get playbackState => _state;

  @override
  Future<List<SpeechVoice>> listVoices() async {
    return const [
      SpeechVoice(
        id: 'ai-anchor-reserved-zh',
        name: 'AI 主播女声（预留）',
        locale: 'zh-CN',
        quality: 'premium',
        gender: 'female',
        isPremiumLike: true,
      ),
      SpeechVoice(
        id: 'ai-anchor-reserved-en',
        name: 'AI Narrator（Reserved）',
        locale: 'en-US',
        quality: 'premium',
        gender: 'female',
        isPremiumLike: true,
      ),
    ];
  }

  @override
  Future<void> speak(String text, ReaderSettings settings) async {
    _state = SpeechPlaybackState.unavailable;
    throw StateError('本地 AI 语音引擎已预留，尚未集成模型文件。');
  }

  @override
  Future<void> pause() async {
    _state = SpeechPlaybackState.unavailable;
  }

  @override
  Future<void> stop() async {
    _state = SpeechPlaybackState.unavailable;
  }
}

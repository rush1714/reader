import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/speech/data/services/speech_engine_service.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';
import 'package:reader_app/features/speech/data/services/system_tts_service.dart';

/// 提供语音服务。
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService(SystemTtsService());
});

/// 语音服务门面。
///
/// 当前只使用 iOS / Android 系统 TTS。语音质量由设备已安装的系统语音决定。
class SpeechService {
  SpeechService(this._engine);

  final SpeechEngineService _engine;

  /// 当前播放状态。
  SpeechPlaybackState stateFor(SpeechEngineType type) => _engine.playbackState;

  /// 当前引擎是否可用。
  bool isAvailable(SpeechEngineType type) => _engine.isAvailable;

  /// 查询系统声音列表。
  Future<List<SpeechVoice>> listVoices(SpeechEngineType type) {
    return _engine.listVoices();
  }

  /// 使用系统 TTS 朗读文本。
  Future<void> speak(String text, ReaderSettings settings) {
    return _engine.speak(text, settings.copyWith(speechEngine: SpeechEngineType.system));
  }

  /// 暂停当前引擎。
  Future<void> pause(ReaderSettings settings) {
    return _engine.pause();
  }

  /// 停止当前引擎。
  Future<void> stop(ReaderSettings settings) {
    return _engine.stop();
  }
}

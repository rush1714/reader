import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/speech/data/services/on_device_ai_tts_service.dart';
import 'package:reader_app/features/speech/data/services/speech_engine_service.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';
import 'package:reader_app/features/speech/data/services/system_tts_service.dart';

/// 提供语音服务。
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService([
    OnDeviceAiTtsService(),
    SystemTtsService(),
  ]);
});

/// 语音服务门面。
///
/// 统一管理不同语音引擎，阅读页只和这个服务交互，不感知具体实现。
class SpeechService {
  SpeechService(this._engines);

  final List<SpeechEngineService> _engines;

  /// 当前播放状态。
  SpeechPlaybackState stateFor(SpeechEngineType type) => _engineFor(type).playbackState;

  /// 当前引擎是否可用。
  bool isAvailable(SpeechEngineType type) => _engineFor(type).isAvailable;

  /// 查询当前引擎声音列表。
  Future<List<SpeechVoice>> listVoices(SpeechEngineType type) {
    return _engineFor(type).listVoices();
  }

  /// 使用设置中选择的引擎朗读文本。
  Future<void> speak(String text, ReaderSettings settings) {
    return _engineFor(settings.speechEngine).speak(text, settings);
  }

  /// 暂停当前引擎。
  Future<void> pause(ReaderSettings settings) {
    return _engineFor(settings.speechEngine).pause();
  }

  /// 停止当前引擎。
  Future<void> stop(ReaderSettings settings) {
    return _engineFor(settings.speechEngine).stop();
  }

  SpeechEngineService _engineFor(SpeechEngineType type) {
    return _engines.firstWhere((engine) => engine.type == type);
  }
}

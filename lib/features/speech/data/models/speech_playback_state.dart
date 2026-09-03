/// 朗读播放状态。
enum SpeechPlaybackState {
  /// 空闲。
  idle,

  /// 正在播放。
  speaking,

  /// 暂停。
  paused,

  /// 当前语音引擎不可用。
  unavailable,
}

import 'package:flutter/material.dart';

/// 阅读器和语音相关设置。
///
/// 这些设置只保存在本机，不依赖账号或后端。后续如果增加同步，可以由 Repository
/// 负责迁移，页面不需要关心存储来源。
class ReaderSettings {
  const ReaderSettings({
    required this.fontSize,
    required this.themeMode,
    required this.speechEngine,
    required this.speechLocale,
    required this.voiceId,
    required this.speechRate,
    required this.pitch,
    required this.volume,
  });

  /// 默认设置。
  factory ReaderSettings.defaults() {
    return const ReaderSettings(
      fontSize: 18,
      themeMode: ThemeMode.system,
      speechEngine: SpeechEngineType.system,
      speechLocale: 'zh-CN',
      voiceId: null,
      speechRate: 0.48,
      pitch: 1,
      volume: 1,
    );
  }

  /// 阅读正文字号。
  final double fontSize;

  /// App 主题模式，默认跟随系统。
  final ThemeMode themeMode;

  /// 当前选择的语音引擎。
  final SpeechEngineType speechEngine;

  /// 当前选择的朗读语言区域，例如 zh-CN、en-US。
  final String? speechLocale;

  /// 当前选择的声音 ID。
  final String? voiceId;

  /// 朗读速度，取值范围 0.0 - 1.0。
  final double speechRate;

  /// 朗读音调，取值范围 0.5 - 2.0。
  final double pitch;

  /// 朗读音量，取值范围 0.0 - 1.0。
  final double volume;

  ReaderSettings copyWith({
    double? fontSize,
    ThemeMode? themeMode,
    SpeechEngineType? speechEngine,
    Object? speechLocale = _notProvided,
    Object? voiceId = _notProvided,
    double? speechRate,
    double? pitch,
    double? volume,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      themeMode: themeMode ?? this.themeMode,
      speechEngine: speechEngine ?? this.speechEngine,
      speechLocale: identical(speechLocale, _notProvided) ? this.speechLocale : speechLocale as String?,
      voiceId: identical(voiceId, _notProvided) ? this.voiceId : voiceId as String?,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'fontSize': fontSize,
      'themeMode': themeMode.name,
      'speechEngine': speechEngine.name,
      'speechLocale': speechLocale,
      'voiceId': voiceId,
      'speechRate': speechRate,
      'pitch': pitch,
      'volume': volume,
    };
  }

  factory ReaderSettings.fromMap(Map<String, Object?> map) {
    final defaults = ReaderSettings.defaults();

    return ReaderSettings(
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? defaults.fontSize,
      themeMode: _themeModeFromName(map['themeMode'] as String?) ?? defaults.themeMode,
      speechEngine: _speechEngineFromName(map['speechEngine'] as String?) ?? defaults.speechEngine,
      speechLocale: map['speechLocale'] as String? ?? defaults.speechLocale,
      voiceId: map['voiceId'] as String?,
      speechRate: (map['speechRate'] as num?)?.toDouble() ?? defaults.speechRate,
      pitch: (map['pitch'] as num?)?.toDouble() ?? defaults.pitch,
      volume: (map['volume'] as num?)?.toDouble() ?? defaults.volume,
    );
  }

  static ThemeMode? _themeModeFromName(String? name) {
    for (final value in ThemeMode.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static SpeechEngineType? _speechEngineFromName(String? name) {
    for (final value in SpeechEngineType.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

const _notProvided = Object();

/// 可选语音引擎类型。
enum SpeechEngineType {
  /// 端侧 AI TTS 预留引擎。
  onDeviceAi,

  /// 系统 TTS 兜底引擎。
  system,
}

/// 语音引擎类型展示文案。
extension SpeechEngineTypeLabel on SpeechEngineType {
  String get label {
    return switch (this) {
      SpeechEngineType.onDeviceAi => '本地 AI 语音（预留）',
      SpeechEngineType.system => '手机自带语音',
    };
  }
}

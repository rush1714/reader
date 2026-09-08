/// 可供朗读使用的系统声音。
///
/// 这个模型是设置页展示声音列表的统一格式。底层 `flutter_tts` 在 iOS / Android 上返回的
///字段不完全一样，所以服务层会先把原始 Map 转成这个对象，再交给 UI 展示。
class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.identifier,
    required this.name,
    required this.locale,
    required this.quality,
    required this.gender,
    required this.isSiriVoice,
    required this.isPremiumLike,
  });

  /// 声音唯一 ID。
  final String id;

  /// 系统返回的原始声音标识。
  final String identifier;

  /// 系统返回的声音名称。
  final String name;

  /// 语言区域，例如 zh-CN、en-US。
  final String locale;

  /// 系统声音质量：default / enhanced / premium。
  final String quality;

  /// 系统返回的性别：male / female / unspecified。
  final String gender;

  /// 是否为系统实际返回的 Siri 朗读声音。
  ///
  /// 注意：这里的 Siri 只认系统语音列表中的原始 name/identifier 是否包含 `siri`，不会把
  /// enhanced、premium、neural 等高质量声音误标成 Siri。
  final bool isSiriVoice;

  /// 是否偏向主播级/高品质声音。
  final bool isPremiumLike;

  /// 语言中文名称。
  String get languageLabel => _localeLabel(locale);

  /// 声音质量中文名称。
  String get qualityLabel {
    final lower = quality.toLowerCase();
    if (lower.contains('premium')) return '高级';
    if (lower.contains('enhanced')) return '增强';
    return '标准';
  }

  /// 性别中文名称。
  String get genderLabel {
    final lower = gender.toLowerCase();
    if (lower.contains('female')) return '女声';
    if (lower.contains('male')) return '男声';
    return '声音';
  }

  /// 类似 iOS 设置中声音列表的主标题。
  String get title {
    final voiceName = _voiceNameLabel(name);
    if (isSiriVoice || voiceName == 'Siri') return 'Siri 声音';
    if (genderLabel == '声音') return voiceName;
    return '$voiceName · $genderLabel';
  }

  /// 详细说明。
  String get description => '$languageLabel · $qualityLabel';

  /// 中文化后的展示名称。
  String get displayName => '$title · $description';

  String _localeLabel(String value) {
    final normalized = value.replaceAll('_', '-');
    if (normalized.startsWith('zh-Hans') || normalized.startsWith('zh-CN')) {
      return '中文（普通话，中国大陆）';
    }
    if (normalized.startsWith('zh-Hant') || normalized.startsWith('zh-TW')) {
      return '中文（台湾）';
    }
    if (normalized.startsWith('zh-HK') || normalized.startsWith('yue')) {
      return '中文（粤语，香港）';
    }
    if (normalized.startsWith('en-US')) return '英语（美国）';
    if (normalized.startsWith('en-GB')) return '英语（英国）';
    if (normalized.startsWith('en-AU')) return '英语（澳大利亚）';
    if (normalized.startsWith('en-IN')) return '英语（印度）';
    if (normalized.startsWith('en')) return '英语';
    if (normalized.startsWith('ja')) return '日语';
    if (normalized.startsWith('ko')) return '韩语';
    if (normalized.startsWith('fr')) return '法语';
    if (normalized.startsWith('de')) return '德语';
    if (normalized.startsWith('es')) return '西班牙语';
    if (normalized.isEmpty) return '未知语言';
    return normalized;
  }

  String _voiceNameLabel(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '默认声音';

    final candidate = raw.contains('.') ? raw.split('.').last : raw;
    final lower = candidate.toLowerCase();

    if (lower == 'system' || lower == 'default') return '默认声音';
    if (lower.contains('siri')) return 'Siri';
    if (lower.contains('tingting')) return '婷婷';
    if (lower.contains('meijia')) return '美佳';
    if (lower.contains('sinji')) return 'Sinji';
    if (lower.contains('samantha')) return 'Samantha';
    if (lower.contains('alex')) return 'Alex';
    if (lower.contains('ava')) return 'Ava';
    if (lower.contains('allison')) return 'Allison';
    if (lower.contains('karen')) return 'Karen';
    if (lower.contains('daniel')) return 'Daniel';
    if (lower.contains('google')) return 'Google';

    return candidate;
  }
}

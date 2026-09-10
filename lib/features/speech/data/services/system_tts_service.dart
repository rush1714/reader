import 'package:flutter_tts/flutter_tts.dart';

import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/speech/data/models/speech_playback_state.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';
import 'package:reader_app/features/speech/data/services/speech_engine_service.dart';

/// 系统 TTS 服务。
///
/// 通过 `flutter_tts` 调用 iOS / Android 本机语音模块。声音质量取决于用户设备已安装的
/// 系统语音包；后续端侧 AI 语音仍通过独立服务扩展，不影响这里的系统语音实现。
class SystemTtsService implements SpeechEngineService {
  SystemTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _configureHandlers();
  }

  final FlutterTts _tts;
  SpeechPlaybackState _state = SpeechPlaybackState.idle;
  int _sessionId = 0;

  /// 系统声音缓存。
  ///
  /// `AVSpeechSynthesisVoice.speechVoices()`/Android voice 查询通常不重，但每朗读一句都查一遍
  /// 仍然会带来不必要的平台通道开销。缓存后，设置页第一次加载声音列表或首次朗读会填充它；
  /// 如果用户刚在系统设置里下载了新声音，重启 App 或重新进入进程即可刷新。
  List<SpeechVoice>? _cachedVoices;

  @override
  SpeechEngineType get type => SpeechEngineType.system;

  @override
  bool get isAvailable => true;

  @override
  SpeechPlaybackState get playbackState => _state;

  @override
  Future<List<SpeechVoice>> listVoices() async {
    final cachedVoices = _cachedVoices;
    if (cachedVoices != null) return cachedVoices;

    try {
      final rawVoices = await _tts.getVoices;
      final voices = <SpeechVoice>[];

      if (rawVoices is List) {
        voices.addAll(
          rawVoices
              .whereType<Map<dynamic, dynamic>>()
              .map(_voiceFromMap)
              .where(
                (voice) => voice.locale.isNotEmpty || voice.name.isNotEmpty,
              ),
        );
      }

      final defaultVoice = await _readDefaultVoice();
      if (defaultVoice != null &&
          !voices.any((voice) => voice.id == defaultVoice.id)) {
        voices.insert(0, defaultVoice);
      }

      final uniqueVoices = <String, SpeechVoice>{};
      for (final voice in voices) {
        uniqueVoices[voice.id] = voice;
      }

      final sorted = uniqueVoices.values.toList()..sort(_compareVoices);
      final result = sorted.isEmpty ? _fallbackVoices : sorted;
      _cachedVoices = result;
      return result;
    } catch (_) {
      _cachedVoices = _fallbackVoices;
      return _fallbackVoices;
    }
  }

  @override
  Future<void> speak(String text, ReaderSettings settings) async {
    final content = text.trim();
    if (content.isEmpty) return;

    final sessionId = ++_sessionId;
    await _configureAudioSession();
    await _tts.awaitSpeakCompletion(true);
    await _applySpeechParameters(settings);
    await _applyVoiceOrLanguage(settings, content);

    _state = SpeechPlaybackState.speaking;
    for (final chunk in _splitForSpeech(content)) {
      if (sessionId != _sessionId || _state != SpeechPlaybackState.speaking) {
        break;
      }

      final result = await _tts.speak(chunk, focus: true);
      if (result != 1) {
        _state = SpeechPlaybackState.idle;
        break;
      }
    }

    if (sessionId == _sessionId && _state == SpeechPlaybackState.speaking) {
      _state = SpeechPlaybackState.idle;
    }
  }

  @override
  Future<void> pause() async {
    final result = await _tts.pause();
    if (result == 1) {
      _state = SpeechPlaybackState.paused;
    }
  }

  @override
  Future<void> stop() async {
    _sessionId += 1;
    await _tts.stop();
    _state = SpeechPlaybackState.idle;
  }

  void _configureHandlers() {
    _tts.setStartHandler(() {
      _state = SpeechPlaybackState.speaking;
    });
    _tts.setCompletionHandler(() {
      _state = SpeechPlaybackState.idle;
    });
    _tts.setCancelHandler(() {
      _state = SpeechPlaybackState.idle;
    });
    _tts.setPauseHandler(() {
      _state = SpeechPlaybackState.paused;
    });
    _tts.setContinueHandler(() {
      _state = SpeechPlaybackState.speaking;
    });
    _tts.setErrorHandler((message) {
      _state = SpeechPlaybackState.idle;
    });
  }

  Future<void> _configureAudioSession() async {
    try {
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.allowAirPlay,
      ], IosTextToSpeechAudioMode.spokenAudio);
      await _tts.autoStopSharedSession(false);
      await _tts.setSharedInstance(true);
    } catch (_) {
      // Android 或不支持该能力的平台会忽略 iOS 音频会话设置。
    }
  }

  /// 应用用户手动调整过的朗读参数。
  ///
  /// iOS 的屏幕朗读和 App 内 [FlutterTts] 走的是不同的系统入口，因此“不设置参数”也不
  /// 保证能得到屏幕朗读相同的声线。这里仍然只在用户显式调整后覆盖参数，默认保留系统
  /// 引擎参数，避免再次把 Siri voice 的原始节奏和音调改坏。
  Future<void> _applySpeechParameters(ReaderSettings settings) async {
    if (settings.usesSystemDefaultSpeechParameters) return;

    await _tts.setSpeechRate(settings.speechRate.clamp(0, 1).toDouble());
    await _tts.setPitch(settings.pitch.clamp(0.5, 2).toDouble());
    await _tts.setVolume(settings.volume.clamp(0, 1).toDouble());
  }

  Future<void> _applyVoiceOrLanguage(
    ReaderSettings settings,
    String text,
  ) async {
    final voice = _decodeVoiceId(settings.voiceId);
    if (voice != null) {
      final identifier = voice['identifier'];
      if (identifier != null && identifier.isNotEmpty) {
        // iOS / macOS 必须用 identifier 选定具体 AVSpeechSynthesisVoice；只传语言或名字
        // 可能回退到同语言的默认紧凑声音，听起来就和用户选中的 Siri 声音不同。
        final result = await _tts.setVoice({'identifier': identifier});
        if (result == 1) return;
      }

      final locale = voice['locale'];
      if (locale != null && locale.isNotEmpty) {
        await _tts.setLanguage(locale);
      }

      // 没有 identifier 的平台才使用 name + locale 组合。
      await _tts.setVoice(voice);
      return;
    }

    final locale = settings.speechLocale ?? _guessLanguage(text);

    // 未指定 voiceId 时不再简单调用 setLanguage。iOS 对 setLanguage 往往会回到紧凑/标准
    // 声音，听感会明显输给“朗读内容”里下载的增强、高级或 Siri 声音。这里主动扫描系统
    // 公开的 voice 列表，自动选同语言里质量最高的一条；用户仍可在设置页手动固定某个声音。
    final bestVoice = await _bestVoiceForLocale(locale);
    if (bestVoice?.identifier.isNotEmpty ?? false) {
      final result = await _tts.setVoice({'identifier': bestVoice!.identifier});
      if (result == 1) return;
    }
    if (bestVoice != null &&
        bestVoice.name.isNotEmpty &&
        !bestVoice.id.startsWith('||')) {
      // Android 的 voice 往往没有 iOS identifier，但可以用 name + locale 精确选择。
      // 在这种情况下也要调用 setVoice，否则自动优选会退化成普通 setLanguage。
      final result = await _tts.setVoice({
        'name': _rawVoiceName(bestVoice.name),
        'locale': bestVoice.locale,
      });
      if (result == 1) return;
    }

    await _tts.setLanguage(locale);
  }

  /// 为当前语言自动选择最自然的系统声音。
  ///
  /// 选择策略偏向“真实可用的高质量声音”而不是固定某个名字：不同 iOS/Android 版本、地区和
  /// 已下载语音包返回的 voice 名称并不一致，所以先按 locale 兼容性过滤，再复用
  /// [_compareVoices] 中的质量排序，把 Siri / Premium / Enhanced / Neural 之类声音排前面。
  Future<SpeechVoice?> _bestVoiceForLocale(String locale) async {
    final voices = await listVoices();
    final candidates =
        voices
            .where((voice) => _isLocaleCompatible(voice.locale, locale))
            .toList()
          ..sort((a, b) => _compareVoicesForRequestedLocale(a, b, locale));
    if (candidates.isEmpty) return null;

    // 优先返回能通过 identifier 精确选中的 voice。只按 name/locale 选择时，不同平台可能再次
    // 回落到普通质量；identifier 是 iOS 上最可靠的“我就要这条声音”的方式。
    return candidates.firstWhere(
      (voice) => voice.identifier.isNotEmpty,
      orElse: () => candidates.first,
    );
  }

  Future<SpeechVoice?> _readDefaultVoice() async {
    try {
      final raw = await _tts.getDefaultVoice;
      if (raw is Map<dynamic, dynamic>) {
        return _voiceFromMap(raw, isDefault: true);
      }
    } catch (_) {
      // iOS 可能没有 Android 的 default voice API，忽略即可。
    }
    return null;
  }

  SpeechVoice _voiceFromMap(
    Map<dynamic, dynamic> raw, {
    bool isDefault = false,
  }) {
    final stringMap = raw.map((key, value) => MapEntry('$key', '$value'));
    final identifier = stringMap['identifier'] ?? '';
    final name = stringMap['name'] ?? _nameFromIdentifier(identifier) ?? '默认声音';
    final locale =
        stringMap['locale'] ??
        stringMap['language'] ??
        _localeFromIdentifier(identifier) ??
        '';
    final quality = stringMap['quality'] ?? (isDefault ? 'default' : '');
    final gender = stringMap['gender'] ?? '';
    final id = _encodeVoiceId({
      'identifier': identifier,
      'name': name,
      'locale': locale,
    });

    final isSiriVoice = _isSiriVoice(name: name, identifier: identifier);

    return SpeechVoice(
      id: id,
      identifier: identifier,
      name: isDefault ? '$name（默认）' : name,
      locale: locale,
      quality: quality,
      gender: gender,
      isSiriVoice: isSiriVoice,
      isPremiumLike: _isPremiumLike(
        name: name,
        quality: quality,
        identifier: identifier,
      ),
    );
  }

  bool _isSiriVoice({required String name, required String identifier}) {
    final value = '$name $identifier'.toLowerCase();
    return value.contains('siri');
  }

  bool _isPremiumLike({
    required String name,
    required String quality,
    required String identifier,
  }) {
    final value = '$name $quality $identifier'.toLowerCase();
    return value.contains('enhanced') ||
        value.contains('premium') ||
        value.contains('siri') ||
        value.contains('neural');
  }

  int _compareVoices(SpeechVoice a, SpeechVoice b) {
    final languageCompare = _languagePriority(a.locale)
        .compareTo(_languagePriority(b.locale));
    if (languageCompare != 0) return languageCompare;

    final qualityCompare = _voicePriority(a).compareTo(_voicePriority(b));
    if (qualityCompare != 0) return qualityCompare;

    return a.title.compareTo(b.title);
  }

  /// 针对某次朗读语言排序候选声音。
  ///
  /// 全局声音列表会把中文、英文等按固定顺序排好；但真正朗读时必须先尊重用户当前选择的
  /// locale。例如用户选了 `en-GB`，就应该优先英国英语，而不是被全局排序里的 `en-US`
  /// 抢到前面。locale 精确度相同后，再比较声音质量。
  int _compareVoicesForRequestedLocale(
    SpeechVoice a,
    SpeechVoice b,
    String requestedLocale,
  ) {
    final localeCompare = _requestedLocalePriority(
      a.locale,
      requestedLocale,
    ).compareTo(_requestedLocalePriority(b.locale, requestedLocale));
    if (localeCompare != 0) return localeCompare;

    final qualityCompare = _voicePriority(a).compareTo(_voicePriority(b));
    if (qualityCompare != 0) return qualityCompare;

    return a.title.compareTo(b.title);
  }

  int _languagePriority(String locale) {
    final normalized = locale.replaceAll('_', '-').toLowerCase();
    if (normalized.startsWith('zh-cn') || normalized.startsWith('zh-hans')) {
      return 0;
    }
    if (normalized.startsWith('zh-hk') || normalized.startsWith('yue')) {
      return 1;
    }
    if (normalized.startsWith('zh-tw') || normalized.startsWith('zh-hant')) {
      return 2;
    }
    if (normalized.startsWith('en-us')) return 3;
    if (normalized.startsWith('en-gb')) return 4;
    if (normalized.startsWith('en')) return 5;
    return 20;
  }

  /// 判断系统 voice 的语言是否能服务用户当前选择的语言。
  ///
  /// 语言代码在不同平台上可能出现 `zh-CN`、`zh-Hans-CN`、`cmn-Hans-CN` 等变体。
  /// 如果只做字符串相等，可能错过同一个普通话语音；这里把常见中文/英文变体归一化成
  /// “普通话简体、普通话繁体、粤语、英语”等族群，再做匹配。
  bool _isLocaleCompatible(String voiceLocale, String requestedLocale) {
    if (voiceLocale.isEmpty || requestedLocale.isEmpty) return false;

    final voiceFamily = _localeFamily(voiceLocale);
    final requestedFamily = _localeFamily(requestedLocale);
    if (voiceFamily == requestedFamily) return true;

    final normalizedVoice = voiceLocale.replaceAll('_', '-').toLowerCase();
    final normalizedRequested = requestedLocale
        .replaceAll('_', '-')
        .toLowerCase();
    return normalizedVoice.startsWith(normalizedRequested) ||
        normalizedRequested.startsWith(normalizedVoice);
  }

  /// 计算 voice locale 和用户请求 locale 的贴合程度，数值越小越适合。
  int _requestedLocalePriority(String voiceLocale, String requestedLocale) {
    final normalizedVoice = voiceLocale.replaceAll('_', '-').toLowerCase();
    final normalizedRequested = requestedLocale
        .replaceAll('_', '-')
        .toLowerCase();
    if (normalizedVoice == normalizedRequested) return 0;
    if (normalizedVoice.startsWith(normalizedRequested) ||
        normalizedRequested.startsWith(normalizedVoice)) {
      return 1;
    }
    if (_localeFamily(voiceLocale) == _localeFamily(requestedLocale)) return 2;
    return 10;
  }

  /// 把平台语言代码归并成用于自动选声的粗粒度族群。
  String _localeFamily(String locale) {
    final normalized = locale.replaceAll('_', '-').toLowerCase();
    if (normalized.startsWith('yue') || normalized.contains('zh-hk')) {
      return 'zh-yue';
    }
    if (normalized.contains('hant') ||
        normalized.contains('zh-tw') ||
        normalized.contains('zh-mo')) {
      return 'zh-hant';
    }
    if (normalized.startsWith('zh') || normalized.startsWith('cmn')) {
      return 'zh-hans';
    }
    if (normalized.startsWith('en')) return 'en';
    return normalized.split('-').first;
  }

  int _voicePriority(SpeechVoice voice) {
    final value = '${voice.name} ${voice.quality} ${voice.identifier}'
        .toLowerCase();
    if (voice.isSiriVoice) return 0;
    if (value.contains('premium')) return 1;
    if (value.contains('enhanced')) return 2;
    if (value.contains('neural')) return 3;
    return 4;
  }

  String _encodeVoiceId(Map<String, String> voice) {
    final identifier = voice['identifier'] ?? '';
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? voice['language'] ?? '';
    return [identifier, name, locale].map(Uri.encodeComponent).join('|');
  }

  Map<String, String>? _decodeVoiceId(String? voiceId) {
    if (voiceId == null || !voiceId.contains('|')) return null;
    final parts = voiceId.split('|').map(Uri.decodeComponent).toList();
    if (parts.length != 3) return null;

    final identifier = parts[0];
    final name = parts[1];
    final locale = parts[2];
    final result = <String, String>{};
    if (identifier.isNotEmpty) result['identifier'] = identifier;
    if (name.isNotEmpty) result['name'] = name;
    if (locale.isNotEmpty) result['locale'] = locale;
    return result.isEmpty ? null : result;
  }

  String? _nameFromIdentifier(String identifier) {
    if (identifier.isEmpty || !identifier.contains('.')) return null;
    return identifier.split('.').last;
  }

  /// 去掉 UI 为“默认 voice”添加的中文提示后缀，还原平台 setVoice 需要的原始 name。
  String _rawVoiceName(String name) {
    return name.replaceFirst('（默认）', '');
  }

  String? _localeFromIdentifier(String identifier) {
    final match = RegExp(r'([a-z]{2}(?:[-_][A-Z]{2})?)').firstMatch(identifier);
    return match?.group(1);
  }

  List<String> _splitForSpeech(String text) {
    const maxChunkLength = 3500;
    if (text.length <= maxChunkLength) return [text];

    final chunks = <String>[];
    final sentences = text.split(RegExp(r'\n{2,}'));
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length > maxChunkLength) {
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        for (var start = 0; start < trimmed.length; start += maxChunkLength) {
          final end = start + maxChunkLength > trimmed.length
              ? trimmed.length
              : start + maxChunkLength;
          chunks.add(trimmed.substring(start, end));
        }
        continue;
      }

      if (buffer.length + trimmed.length + 2 > maxChunkLength) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(trimmed);
      buffer.writeln();
    }

    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }
    return chunks;
  }

  String _guessLanguage(String text) {
    return RegExp(r'[一-鿿]').hasMatch(text) ? 'zh-CN' : 'en-US';
  }

  List<SpeechVoice> get _fallbackVoices {
    return const [
      SpeechVoice(
        id: '||zh-CN',
        identifier: '',
        name: '默认声音',
        locale: 'zh-CN',
        quality: 'default',
        gender: 'unspecified',
        isSiriVoice: false,
        isPremiumLike: false,
      ),
      SpeechVoice(
        id: '||en-US',
        identifier: '',
        name: 'Default',
        locale: 'en-US',
        quality: 'default',
        gender: 'unspecified',
        isSiriVoice: false,
        isPremiumLike: false,
      ),
    ];
  }
}

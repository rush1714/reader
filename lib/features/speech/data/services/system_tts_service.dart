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

  @override
  SpeechEngineType get type => SpeechEngineType.system;

  @override
  bool get isAvailable => true;

  @override
  SpeechPlaybackState get playbackState => _state;

  @override
  Future<List<SpeechVoice>> listVoices() async {
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
      return sorted.isEmpty ? _fallbackVoices : sorted;
    } catch (_) {
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
      final locale = voice['locale'];
      if (locale != null && locale.isNotEmpty) {
        await _tts.setLanguage(locale);
      }

      final identifier = voice['identifier'];
      if (identifier != null && identifier.isNotEmpty) {
        await _tts.setVoice({'identifier': identifier});
        return;
      }

      await _tts.setVoice(voice);
      return;
    }

    await _tts.setLanguage(settings.speechLocale ?? _guessLanguage(text));
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

  int _languagePriority(String locale) {
    final normalized = locale.replaceAll('_', '-');
    if (normalized.startsWith('zh-CN') || normalized.startsWith('zh-Hans')) {
      return 0;
    }
    if (normalized.startsWith('zh-HK') || normalized.startsWith('yue')) {
      return 1;
    }
    if (normalized.startsWith('zh-TW') || normalized.startsWith('zh-Hant')) {
      return 2;
    }
    if (normalized.startsWith('en-US')) return 3;
    if (normalized.startsWith('en-GB')) return 4;
    if (normalized.startsWith('en')) return 5;
    return 20;
  }

  int _voicePriority(SpeechVoice voice) {
    final value = '${voice.name} ${voice.quality}'.toLowerCase();
    if (voice.isSiriVoice) return 0;
    if (value.contains('premium')) return 1;
    if (value.contains('enhanced')) return 2;
    return 3;
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

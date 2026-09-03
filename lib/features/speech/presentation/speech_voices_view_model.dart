import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/data/services/speech_service.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';

/// 当前语音引擎可选声音列表。
final speechVoicesViewModelProvider = FutureProvider<List<SpeechVoice>>((ref) async {
  final settings = await ref.watch(readerSettingsProvider.future);
  return ref.watch(speechServiceProvider).listVoices(settings.speechEngine);
});

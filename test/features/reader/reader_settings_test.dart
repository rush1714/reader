import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/features/settings/data/models/reader_settings.dart';

void main() {
  test('ReaderSettings can round-trip through map', () {
    final settings = ReaderSettings.defaults().copyWith(
      fontSize: 22,
      themeMode: ThemeMode.dark,
      speechEngine: SpeechEngineType.system,
      voiceId: 'system-zh',
    );

    final restored = ReaderSettings.fromMap(settings.toMap());

    expect(restored.fontSize, 22);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.speechEngine, SpeechEngineType.system);
    expect(restored.voiceId, 'system-zh');
  });
}

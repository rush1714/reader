import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/core/widgets/app_error_view.dart';
import 'package:reader_app/core/widgets/app_loading.dart';
import 'package:reader_app/features/settings/data/models/reader_settings.dart';
import 'package:reader_app/features/settings/data/settings_repository.dart';
import 'package:reader_app/features/speech/data/models/speech_voice.dart';
import 'package:reader_app/features/speech/presentation/speech_view_model.dart';
import 'package:reader_app/features/speech/presentation/speech_voices_view_model.dart';

/// 设置页面。
///
/// 第一版聚合阅读器、主题和语音设置。所有设置都保存在本机 SQLite。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(readerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settingsState.when(
        loading: () => const AppLoading(),
        error: (error, stackTrace) => AppErrorView(error: error),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              title: '阅读器',
              children: [
                ListTile(
                  title: const Text('正文字号'),
                  subtitle: Slider(
                    value: settings.fontSize,
                    min: 14,
                    max: 30,
                    divisions: 16,
                    label: settings.fontSize.round().toString(),
                    onChanged: (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .updateFontSize(value),
                  ),
                  trailing: Text(settings.fontSize.round().toString()),
                ),
              ],
            ),
            _SectionCard(
              title: '主题',
              children: [
                RadioGroup<ThemeMode>(
                  groupValue: settings.themeMode,
                  onChanged: (value) => _updateTheme(ref, value),
                  child: const Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: Text('跟随系统'),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: Text('明亮模式'),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: Text('深色模式'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _SectionCard(
              title: '语音',
              children: [
                DropdownButtonFormField<SpeechEngineType>(
                  initialValue: settings.speechEngine,
                  decoration: const InputDecoration(
                    labelText: '语音引擎',
                    border: OutlineInputBorder(),
                  ),
                  items: SpeechEngineType.values.map((engine) {
                    return DropdownMenuItem(
                      value: engine,
                      child: Text(engine.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(readerSettingsProvider.notifier).updateSpeechEngine(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _VoiceSelector(settings: settings),
                const SizedBox(height: 12),
                _SliderTile(
                  title: '语速',
                  value: settings.speechRate,
                  min: 0.2,
                  max: 1,
                  divisions: 8,
                  onChanged: (value) => ref
                      .read(readerSettingsProvider.notifier)
                      .updateSpeechRate(value),
                ),
                _SliderTile(
                  title: '音调',
                  value: settings.pitch,
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  onChanged: (value) => ref
                      .read(readerSettingsProvider.notifier)
                      .updatePitch(value),
                ),
                _SliderTile(
                  title: '音量',
                  value: settings.volume,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: (value) => ref
                      .read(readerSettingsProvider.notifier)
                      .updateVolume(value),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('语音说明'),
                  subtitle: Text(
                    '当前默认调用 iOS / Android 本机系统语音模块；声音质量取决于设备已安装的系统语音。本地 AI TTS 架构仍保留，不上传书籍内容，也不调用大型语言模型。',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateTheme(WidgetRef ref, ThemeMode? value) {
    if (value != null) {
      ref.read(readerSettingsProvider.notifier).updateThemeMode(value);
    }
  }
}

class _VoiceSelector extends ConsumerWidget {
  const _VoiceSelector({required this.settings});

  final ReaderSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voices = ref.watch(speechVoicesViewModelProvider);

    return voices.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stackTrace) => Text(error.toString()),
      data: (voices) {
        final languages = _languagesFrom(voices);
        final selectedLocale = languages.contains(settings.speechLocale)
            ? settings.speechLocale
            : (languages.isEmpty ? null : languages.first);
        final filteredVoices = voices.where((voice) => voice.locale == selectedLocale).toList();
        final selectedVoice = filteredVoices.any((voice) => voice.id == settings.voiceId)
            ? settings.voiceId
            : (filteredVoices.isEmpty ? null : filteredVoices.first.id);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedLocale,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '语言',
                border: OutlineInputBorder(),
              ),
              items: languages.map((locale) {
                final voice = voices.firstWhere((item) => item.locale == locale);
                return DropdownMenuItem(
                  value: locale,
                  child: Text(voice.languageLabel, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                ref.read(readerSettingsProvider.notifier).updateSpeechLocale(value);
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedVoice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '声音',
                      border: OutlineInputBorder(),
                    ),
                    selectedItemBuilder: (context) {
                      return filteredVoices.map((voice) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            voice.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                    items: filteredVoices.map((voice) {
                      return DropdownMenuItem(
                        value: voice.id,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(voice.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(voice.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      ref.read(readerSettingsProvider.notifier).updateVoiceId(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '试听声音',
                  onPressed: selectedVoice == null
                      ? null
                      : () async {
                          await ref.read(readerSettingsProvider.notifier).updateVoiceId(selectedVoice);
                          await ref.read(speechViewModelProvider.notifier).previewCurrentVoice();
                        },
                  icon: const Icon(Icons.volume_up_outlined),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<String> _languagesFrom(List<SpeechVoice> voices) {
    final locales = <String>[];
    for (final voice in voices) {
      if (voice.locale.isEmpty || locales.contains(voice.locale)) continue;
      locales.add(voice.locale);
    }
    return locales;
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: value.toStringAsFixed(2),
        onChanged: onChanged,
      ),
      trailing: Text(value.toStringAsFixed(2)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

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
/// 聚合阅读器、主题和语音设置。所有设置都保存在本机 SQLite。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(readerSettingsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: settingsState.when(
          loading: () => const AppLoading(),
          error: (error, stackTrace) => AppErrorView(error: error),
          data: (settings) => ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 104),
            children: [
              const _SettingsHeader(),
              const SizedBox(height: 16),
              _SettingsCard(
                icon: Icons.menu_book_rounded,
                title: '阅读器',
                subtitle: '正文版式与排版微调',
                trailing: const _SoftBadge(label: '排版已优化'),
                children: [
                  _ControlSlider(
                    title: '正文字号',
                    valueText: '${settings.fontSize.round()} pt',
                    value: settings.fontSize,
                    min: 14,
                    max: 30,
                    divisions: 16,
                    startLabel: 'A- 14pt',
                    middleLabel: '标准 22pt',
                    endLabel: 'A+ 30pt',
                    onChanged: (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .updateFontSize(value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: Icons.palette_rounded,
                title: '主题模式',
                subtitle: '护眼色彩与显示配色',
                children: [
                  _ThemeOption(
                    selected: settings.themeMode == ThemeMode.system,
                    title: '跟随系统',
                    subtitle: '自动切换羊皮暖黄与雅致深蓝',
                    icon: Icons.hdr_auto_rounded,
                    onTap: () => ref
                        .read(readerSettingsProvider.notifier)
                        .updateThemeMode(ThemeMode.system),
                  ),
                  _ThemeOption(
                    selected: settings.themeMode == ThemeMode.light,
                    title: '羊皮暖黄 (Parchment)',
                    subtitle: '温润经典纸书质感',
                    icon: Icons.auto_stories_rounded,
                    onTap: () => ref
                        .read(readerSettingsProvider.notifier)
                        .updateThemeMode(ThemeMode.light),
                  ),
                  _ThemeOption(
                    selected: settings.themeMode == ThemeMode.dark,
                    title: '雅致深蓝 (Navy Slate)',
                    subtitle: '深邃沉浸夜读风格',
                    icon: Icons.nights_stay_rounded,
                    onTap: () => ref
                        .read(readerSettingsProvider.notifier)
                        .updateThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                icon: Icons.volume_up_rounded,
                title: '语音与朗读',
                subtitle: '调用手机系统语音，支持已安装的高质量声音',
                trailing: const _SoftBadge(label: '系统语音', active: true),
                children: [
                  DropdownButtonFormField<SpeechEngineType>(
                    initialValue: settings.speechEngine,
                    decoration: const InputDecoration(labelText: '语音引擎'),
                    items: SpeechEngineType.values.map((engine) {
                      return DropdownMenuItem(
                        value: engine,
                        child: Text(engine.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(readerSettingsProvider.notifier)
                            .updateSpeechEngine(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _VoiceSelector(settings: settings),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      // 用户觉得声音“很机械”时，最常见原因是之前固定了某条标准音色，
                      // 或者把语速/音调调离了系统默认值。这个按钮只恢复语音相关设置，
                      // 不影响阅读字号、主题等个人偏好。
                      onPressed: () => ref
                          .read(readerSettingsProvider.notifier)
                          .resetSpeechToNaturalDefaults(),
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('恢复推荐语音'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ControlSlider(
                    title: '语速',
                    valueText: '${_speechRateLabel(settings.speechRate)}x',
                    value: settings.speechRate,
                    min: 0.2,
                    max: 1,
                    divisions: 8,
                    startLabel: '慢速',
                    middleLabel: '自然',
                    endLabel: '快速',
                    onChanged: (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .updateSpeechRate(value),
                  ),
                  const SizedBox(height: 12),
                  _ControlSlider(
                    title: '音调',
                    valueText: settings.pitch.toStringAsFixed(2),
                    value: settings.pitch,
                    min: 0.5,
                    max: 2,
                    divisions: 15,
                    startLabel: '低沉',
                    middleLabel: '适中',
                    endLabel: '高昂',
                    onChanged: (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .updatePitch(value),
                  ),
                  const SizedBox(height: 12),
                  _ControlSlider(
                    title: '音量',
                    valueText: '${(settings.volume * 100).round()}%',
                    value: settings.volume,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    startLabel: '静音',
                    middleLabel: '50%',
                    endLabel: '100%',
                    onChanged: (value) => ref
                        .read(readerSettingsProvider.notifier)
                        .updateVolume(value),
                  ),
                  const SizedBox(height: 10),
                  _InfoPanel(
                    icon: Icons.info_outline_rounded,
                    title: '为什么没有 Siri？',
                    message: 'iOS 不会把“嘿 Siri/个人助理声音”完整开放给第三方 App。系统 TTS 只能列出 AVSpeechSynthesizer 允许使用的朗读声音；如果想要更多高质量中文声音，请在系统“设置 → 辅助功能 → 朗读内容 → 声音 → 中文”里下载增强/高级声音，然后回到这里选择。',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _SettingsCard(
                icon: Icons.storage_rounded,
                title: '离线书籍缓存',
                subtitle: '导入的书籍与模型均保存在本机',
                children: [
                  _InfoPanel(
                    icon: Icons.verified_user_outlined,
                    title: '本地优先',
                    message: '书籍、阅读进度、主题和语音设置都存储在设备本地。',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '深阅 · Deep Reader',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _speechRateLabel(double value) {
    final speed = 0.75 + (value.clamp(0.2, 1).toDouble() - 0.2) / 0.8 * 0.7;
    return speed.toStringAsFixed(2);
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '设置',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Settings',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '更多',
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.62,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 17),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.48)
                  : colorScheme.outline.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colorScheme.primary : colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 21, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 系统语音选择器。
///
/// 这个组件负责三件事：
///
/// 1. 从系统 TTS 服务加载当前设备实际可用的声音列表。
/// 2. 先按语言筛选，再让用户选择具体声音。
/// 3. 单独把系统返回的 Siri voice 列出来，避免把“增强/高级”等其他声音误认为 Siri。
class _VoiceSelector extends ConsumerWidget {
  const _VoiceSelector({required this.settings});

  /// 下拉菜单中“自动选择最佳声音（推荐）”的特殊值。
  ///
  /// 它不会写入真实 voice identifier；选择该值时会把 ReaderSettings.voiceId 清空，让
  /// 服务层根据语言和 voice 质量自动挑选当前设备最自然的系统朗读声音。
  static const _systemDefaultVoiceId = '__system_default_voice__';

  /// 当前持久化的阅读/语音设置，用于决定下拉框初始选中项。
  final ReaderSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voices = ref.watch(speechVoicesViewModelProvider);

    return voices.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stackTrace) => _InfoPanel(
        icon: Icons.error_outline_rounded,
        title: '声音列表加载失败',
        message: error.toString(),
      ),
      data: (voices) {
        // 系统可能返回很多语言的声音，先整理出不重复的语言列表，用第一个下拉框筛选。
        final languages = _languagesFrom(voices);

        // 如果用户上次选择的语言仍然存在，就继续选中；否则回退到系统返回的第一个语言。
        final selectedLocale = languages.contains(settings.speechLocale)
            ? settings.speechLocale
            : (languages.isEmpty ? null : languages.first);

        // 第二个下拉框只显示当前语言的声音，避免所有国家/地区声音混在一起难找。
        final filteredVoices = voices
            .where((voice) => voice.locale == selectedLocale)
            .toList();

        // voiceId 为 null 时代表“自动优选”，而不是“没有选择”。服务层会按当前语言从
        // 系统公开 voice 列表中挑出 Siri / 高级 / 增强等更自然的声音，避免落回紧凑声线。
        final selectedVoice = settings.voiceId == null
            ? _systemDefaultVoiceId
            : filteredVoices.any((voice) => voice.id == settings.voiceId)
            ? settings.voiceId
            : _systemDefaultVoiceId;

        // 只收集系统返回的真正 Siri 语音：判断逻辑在 SpeechVoice/SystemTtsService 中完成。
        final siriVoices = voices.where((voice) => voice.isSiriVoice).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedLocale,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '语言'),
              items: languages.map((locale) {
                final voice = voices.firstWhere(
                  (item) => item.locale == locale,
                );
                return DropdownMenuItem(
                  value: locale,
                  child: Text(
                    voice.languageLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                ref
                    .read(readerSettingsProvider.notifier)
                    .updateSpeechLocale(value);
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
                    decoration: const InputDecoration(labelText: '声音'),
                    selectedItemBuilder: (context) {
                      return [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '自动选择最佳声音（推荐）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...filteredVoices.map((voice) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              voice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ];
                    },
                    items: [
                      const DropdownMenuItem(
                        value: _systemDefaultVoiceId,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('自动选择最佳声音（推荐）'),
                          subtitle: Text('优先使用当前语言的 Siri / 高级 / 增强声音'),
                        ),
                      ),
                      ...filteredVoices.map((voice) {
                        return DropdownMenuItem(
                          value: voice.id,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              voice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              voice.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      // 特殊菜单值不保存为 voiceId；保存 null 才会触发 SystemTtsService 的
                      // “按语言自动优选高质量声音”逻辑。
                      final voiceId = value == _systemDefaultVoiceId
                          ? null
                          : value;
                      ref
                          .read(readerSettingsProvider.notifier)
                          .updateVoiceId(voiceId);
                    },
                  ),
                ),
                const SizedBox(width: 9),
                SizedBox.square(
                  dimension: 48,
                  child: IconButton.filledTonal(
                    tooltip: '试听声音',
                    // 自动优选也可以试听：清空 voiceId 后让服务层按当前语言挑最好的公开声音。
                    onPressed: () async {
                      final voiceId = selectedVoice == _systemDefaultVoiceId
                          ? null
                          : selectedVoice;
                      await ref
                          .read(readerSettingsProvider.notifier)
                          .updateVoiceId(voiceId);
                      await ref
                          .read(speechViewModelProvider.notifier)
                          .previewCurrentVoice();
                    },
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _InfoPanel(
              icon: Icons.auto_awesome_rounded,
              title: '自动选择最佳声音（推荐）',
              message: '不固定某条普通 Voice，而是按当前语言优先挑选系统公开的 Siri / 高级 / 增强声音。若声音仍不自然，请先到系统“朗读内容”里下载更高质量中文声音，再回到这里试听。',
            ),
            const SizedBox(height: 12),
            _SiriVoicesPanel(voices: siriVoices),
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

/// Siri 语音说明面板。
///
/// 重点：这里不是猜测哪个声音“像 Siri”，而是只展示系统 voice 列表中明确带 Siri 标识的
/// 条目。如果列表为空，说明当前 iOS 没有把 Siri voice 暴露给这个 App。
class _SiriVoicesPanel extends StatelessWidget {
  const _SiriVoicesPanel({required this.voices});

  /// 系统返回且被识别为 Siri 的声音列表。
  final List<SpeechVoice> voices;

  @override
  Widget build(BuildContext context) {
    // 空列表时给出明确原因，防止用户误以为 App 把 Siri 隐藏了。
    if (voices.isEmpty) {
      return const _InfoPanel(
        icon: Icons.record_voice_over_rounded,
        title: '当前没有发现 Siri 语音',
        message: '本 App 只把 iOS 系统实际返回、名称或标识包含 Siri 的朗读声音列为 Siri。当前设备没有向 App 返回 Siri 语音；可以到“设置 → 辅助功能 → 朗读内容 → 声音”下载后再回来查看。',
      );
    }

    // 有 Siri 时把 identifier 也显示出来，方便确认“这一个就是 Siri”，而不是普通增强声音。
    return _InfoPanel(
      icon: Icons.record_voice_over_rounded,
      title: '已发现 Siri 语音',
      message: voices
          .map((voice) {
            final identifier = voice.identifier.isEmpty
                ? '无 identifier'
                : voice.identifier;
            return '${voice.title} · ${voice.languageLabel}\n$identifier';
          })
          .join('\n\n'),
    );
  }
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.startLabel,
    required this.middleLabel,
    required this.endLabel,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String startLabel;
  final String middleLabel;
  final String endLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.62,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                valueText,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(startLabel, style: _sliderLabelStyle(context)),
              Text(middleLabel, style: _sliderLabelStyle(context)),
              Text(endLabel, style: _sliderLabelStyle(context)),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle? _sliderLabelStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant
          .withValues(alpha: 0.76),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

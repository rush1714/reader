# Mobile System TTS 与平台收敛计划

> 日期：2026-09-02  
> 项目：Reader App  
> 目标：接入 iOS / Android 本机语音模块，保留 AI 语音扩展，删除非 iOS / Android 平台目录

## Goal

把当前预留的系统 TTS 改为真实调用手机本机语音模块；保留端侧 AI TTS 入口；项目只保留 iOS 和 Android 平台。

## Scope

- 增加 `flutter_tts` 依赖，用系统语音模块朗读。
- 默认语音引擎调整为“系统语音”，AI 语音继续作为可选预留项。
- 设置页继续支持语音引擎、声音、语速、音调、音量。
- 阅读页播放按钮调用真实系统 TTS。
- 增加暂停按钮或在控制器中支持暂停。
- 删除 iOS / Android 之外的平台目录：`web/`、`macos/`、`windows/`、`linux/`。
- 更新 README，说明当前支持平台为 iOS / Android。

## Decisions

1. 使用 `flutter_tts` 调用系统 TTS。
   - iOS 调用系统 `AVSpeechSynthesizer`。
   - Android 调用系统 TextToSpeech。
   - 声音质量取决于用户手机系统已安装语音。

2. 保留 AI 语音架构。
   - `OnDeviceAiTtsEngine` 继续保留，但不打包模型、不调用云端。
   - 后续可接端侧 TTS 模型。

3. 默认使用系统语音。
   - 这样第一版打开即可朗读。
   - 设置页仍可切到“本地 AI 语音（预留）”。

4. 项目仅保留移动端。
   - 删除非目标平台目录和相关图标资源。
   - `pubspec.yaml` 的依赖只要兼容 iOS / Android 即可。

## Steps

1. 修改 `pubspec.yaml`，加入 `flutter_tts` 精确版本。
2. 运行 `flutter pub get`。
3. 重写 `SystemTtsEngine`：
   - 初始化 `FlutterTts`。
   - `listVoices()` 读取系统声音。
   - `speak()` 设置 voice / language / rate / pitch / volume 并朗读。
   - `pause()` 调用插件暂停能力。
   - `stop()` 停止朗读。
4. 更新 `SpeechController` 支持 pause。
5. 更新阅读页控制按钮：朗读 / 暂停 / 停止。
6. 更新默认设置为系统语音。
7. 删除 `web/`、`macos/`、`windows/`、`linux/`。
8. 更新 README。
9. 验证：
   - `flutter analyze`
   - `flutter test`

## Risks or open questions

- 系统 TTS 的“主播级”效果依赖 iOS / Android 系统语音包，不一定所有设备都有高质量声音。
- `flutter_tts` 的 voice 数据在 iOS 和 Android 字段结构可能不同，需要做兼容解析。
- 暂停能力在不同 Android TTS 引擎上可能表现不完全一致，停止通常更稳定。

## Verification checklist

- [ ] 系统语音引擎不再抛“未接入”错误。
- [ ] 设置页能列出系统声音或显示默认声音。
- [ ] 阅读页能调用系统朗读。
- [ ] AI 语音选项仍保留并明确为预留。
- [ ] 只保留 Android / iOS 平台目录。
- [ ] `flutter analyze` 通过。
- [ ] `flutter test` 通过。

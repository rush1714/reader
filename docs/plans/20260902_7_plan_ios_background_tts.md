# iOS 后台与锁屏朗读计划

> 日期：2026-09-02  
> 项目：Reader App

## Goal

让 iOS 上系统 TTS 朗读在 App 进入后台、锁屏后仍能继续播放，并尽量保持当前“按段落自动朗读、读完章节自动进入下一章”的体验。

## Current findings

- 当前语音实现使用 `flutter_tts`，iOS 底层是 `AVSpeechSynthesizer`。
- `SystemTtsService` 已经把 iOS audio category 设置为 `playback` + `spokenAudio`，这一步是必要的。
- `ios/Runner/Info.plist` 目前没有 `UIBackgroundModes` / `audio`。没有这个能力声明时，iOS 锁屏或切后台后会暂停/挂起 App，导致 TTS 不能持续朗读，也不能继续排队下一段/下一章。
- 当前 `_configureAudioSession()` 先 `setSharedInstance(true)` 再 `setIosAudioCategory(...)`，更稳妥的顺序是先设置 category/mode/options，再激活 shared audio session。

## Scope

1. 在 `ios/Runner/Info.plist` 增加：
   - `UIBackgroundModes`
   - `audio`

2. 调整 `SystemTtsService._configureAudioSession()`：
   - 先设置 iOS audio category 为 `playback`。
   - 使用 `spokenAudio` mode。
   - 增加常用外放路由选项：`allowBluetooth`、`allowBluetoothA2DP`、`allowAirPlay`。
   - 再 `setSharedInstance(true)` 激活音频会话。
   - 调用 `autoStopSharedSession(false)`，避免每段朗读结束后 iOS audio session 被自动停掉，从而减少段落间、章节间后台中断概率。

3. 保持现有 Dart 自动朗读逻辑不大改：
   - `ReaderPage._startAutoRead()` 继续按段落顺序朗读。
   - 当前章节完成后继续进入下一章。
   - 不引入 `audio_service` / `just_audio`，避免把本次修复扩大成完整媒体后台服务重构。

## Non-goals

- 本次不做锁屏控制中心的播放/暂停按钮和 Now Playing 信息。
- 本次不做后台下载、后台任务或推送唤醒。
- 本次不把 TTS 预合成为音频文件播放。

## Notes / limitations

- iOS 只允许“正在播放音频”的 App 在后台持续运行；用户手动停止朗读、音频会话被系统中断、或 App 被用户从多任务界面上划掉后，不能保证继续自动播放。
- Simulator 对锁屏/后台音频表现可能和真机不同，需要优先用真机验证。
- 如果后续需要锁屏控制中心按钮、耳机按键控制、封面/章节标题等媒体信息，需要进一步接入 `audio_service`/原生 `MPRemoteCommandCenter`，这会是单独一轮实现。

## Implementation steps

1. 编辑 `ios/Runner/Info.plist`，添加 `UIBackgroundModes` audio。
2. 编辑 `lib/features/speech/data/services/system_tts_service.dart`，调整 iOS audio session 配置顺序和选项。
3. 运行 `flutter analyze`。
4. 运行 `flutter test`。
5. 如环境允许，运行 iOS debug build：`flutter build ios --debug --no-codesign`。
6. 真机验证：开始朗读后按电源键锁屏、切到后台，观察是否继续按段落播放并自动进入下一章。

## Verification checklist

- [ ] iOS 锁屏后当前朗读不停止。
- [ ] iOS 切到后台后朗读继续。
- [ ] 段落间不中断。
- [ ] 当前章节读完后仍可进入下一章继续朗读。
- [ ] `flutter analyze` 通过。
- [ ] `flutter test` 通过。

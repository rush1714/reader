# 语言优先的语音选择器计划

> 日期：2026-09-02

## Goal

把当前单个声音下拉框改为更接近 iOS 设置体验的两级选择：先选语言，再选该语言下的声音。声音展示要清楚中文化，优先展示 iOS Siri / 高品质声音；选择后试听和正式朗读都必须使用同一个已选 voice。

## Research

Apple `AVSpeechSynthesisVoice` 可用于声音列表，关键字段包括：

- `name`：可读声音名称，例如 Samantha。
- `language`：BCP-47 语言代码，例如 `en-US`。
- `identifier`：稳定声音 ID，保存选择时应该使用它。
- `quality`：质量，含 default / enhanced / premium。
- `gender`：性别，可能是 male / female / unspecified。

实现中应优先保存和使用 `identifier`，而不是只用 `name + locale`。

## Scope

- `SpeechVoice` 模型增加：
  - `identifier`
  - `quality`
  - `gender`
  - `languageLabel`
  - `qualityLabel`
  - `genderLabel`
  - 更清楚的 `displayName` / `description`
- 设置模型 `ReaderSettings` 增加 `speechLocale`。
- 设置页语音选择改为：
  1. 语言下拉框。
  2. 声音下拉框。
  3. 手动试听按钮。
- 移除“选择声音后自动试听”。
- `SystemTtsService`：
  - 读取 iOS/Android voice 字段。
  - 优先使用 `identifier` 设置 iOS voice。
  - 获取 default voice 并合并进列表，避免系统默认声音遗漏。
  - 列表排序：中文优先、Siri/高品质优先、名称排序。
- 正式朗读和试听都读取同一个 `ReaderSettings.voiceId`。

## Steps

1. 更新 `SpeechVoice` 模型。
2. 更新 `ReaderSettings` 增加 `speechLocale` 和更新方法。
3. 更新 `SystemTtsService` voice 解析、编码、解码、排序、默认 voice 合并。
4. 更新 `SettingsPage` voice selector 为语言 + 声音两级选择。
5. 手动试听时如当前 voice 未保存，先保存再试听。
6. 更新测试。
7. 验证 analyze / test / debug build。

## Verification

- [ ] 语言先选，声音后选。
- [ ] iOS Siri / Samantha / Tingting 等声音显示友好中文描述。
- [ ] 不再切换声音后自动反复试听。
- [ ] 试听用当前选中 voice。
- [ ] 正式朗读用当前选中 voice。
- [ ] analyze/test/build 通过。

## Sources

- Apple `AVSpeechSynthesisVoice` 文档：`name`、`language`、`identifier`、`quality`、`gender` 可用于构建声音选择器。

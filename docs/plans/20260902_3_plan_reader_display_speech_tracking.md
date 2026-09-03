# 阅读显示、系统声音中文化与朗读跟随计划

> 日期：2026-09-02  
> 项目：Reader App

## Goal

修复 iPhone 调试时设置页声音下拉框溢出；把 iOS / Android 系统声音以更易懂的中文展示；导入图书后在阅读器中展示章节；朗读时高亮当前朗读段落并自动滚动，当前章节朗读完后自动翻到下一章继续朗读。

## Scope

- 修复 `SettingsPage` 中 `DropdownButtonFormField<String>` 横向溢出。
- 系统 TTS 声音列表中文化展示：根据 locale、系统 voice 名称、quality 生成中文标签，同时保留原始名称方便识别。
- 扩展章节查询能力：阅读页可以打开章节目录并跳转指定章节。
- 阅读正文由“一整段 Text”改为“段落列表”。
- 朗读时按段落朗读：
  - 高亮当前朗读段落。
  - 自动滚动到当前段落。
  - 当前章节读完后自动进入下一章并继续朗读。
- 保留 AI 语音入口；若选择 AI 预留引擎，仍提示未集成模型。

## Decisions

1. 不做复杂分页排版，先做段落级阅读器。
   - 更适合当前“自动朗读跟随”需求。
   - 手动阅读时仍可滚动阅读。

2. 章节目录用阅读页 AppBar 的目录按钮打开 bottom sheet。
   - 简单、移动端友好。
   - 不改变现有路由结构。

3. 朗读跟随放在 `ReaderPage` 的 Stateful/ConsumerStateful 层。
   - 朗读进度、高亮段落、滚动控制属于页面交互状态。
   - 章节加载和持久化仍留在 ViewModel/Repository。

4. `SystemTtsEngine` 增加段落朗读回调。
   - 在 `SpeechService` 暴露 `speakParagraphs`。
   - 控制器负责顺序朗读段落并通知 UI 当前 index。

## Steps

1. 新增/调整语音显示工具，把 voice 名称和 locale 转成中文展示。
2. 修复设置页 voice dropdown：`isExpanded: true`、文本 `overflow: ellipsis`。
3. 在 `ReaderRepository` 增加章节列表查询。
4. 在 `ReaderViewModel` 增加章节目录状态与 `goToChapter(index)`。
5. 重构 `ReaderPage` 为 `ConsumerStatefulWidget`：
   - 段落拆分。
   - `ScrollController`。
   - 当前朗读段落 index。
   - 自动滚动。
6. 更新 `SpeechController`：
   - 增加段落朗读方法。
   - 增加朗读完成回调支持。
   - 支持暂停/停止清理状态。
7. 更新 README 说明阅读器支持章节目录和朗读跟随。
8. 验证：`flutter analyze`、`flutter test`、必要时 Android debug build。

## Risks

- iOS / Android 系统 TTS 的 voice 字段不完全一致，中文化需做兜底显示。
- Android 系统 TTS pause 在不同引擎上表现可能不一致，stop 更稳定。
- 自动“翻页”第一版按章节切换，不做真实分页动画。

## Verification checklist

- [ ] 设置页声音下拉框不再溢出。
- [ ] 声音选项展示为中文可读文案。
- [ ] 阅读页可以打开章节目录。
- [ ] 阅读页正文按段落展示。
- [ ] 朗读时当前段落高亮并自动滚动。
- [ ] 当前章节读完后可自动进入下一章继续朗读。
- [ ] `flutter analyze` 通过。
- [ ] `flutter test` 通过。

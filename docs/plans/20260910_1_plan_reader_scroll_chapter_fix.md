# 修复阅读页下滑与手动选章跳转问题计划

## 问题理解

用户反馈：

- 向下滑动章节时会出问题，屏幕像刷新一样回到章节顶部。
- 手动从目录选择章节后，屏幕上显示的不是选择的章节。
- 选择章节后再下滑也异常；不选择章节直接下滑也会异常。

## 初步定位

主要问题集中在 `lib/features/reader/presentation/reader_page.dart` 的连续章节窗口和滚动恢复逻辑：

1. `_ensureChapterWindow` 会以当前章节为中心加载“前 2 章 + 当前章 + 后 2 章”，但窗口初始化完成前 `_chapterBlocks` 仍可能继续使用旧的 `_loadedChapters`。
   - 这会导致目录选择新章节后，页面短时间甚至持续显示旧章节窗口。

2. 手动选章、上一章、下一章目前调用 `_jumpToTopAfterBuild()`，它只是 `jumpTo(0)`。
   - 在连续窗口中，`0` 是窗口第一章的顶部，不一定是当前选中的章节顶部。
   - 如果选中第 10 章，窗口可能是第 8-12 章，`jumpTo(0)` 实际会显示第 8 章。

3. `_restoreScrollOffsetIfNeeded` 可能在目标章节还没进入本地窗口时就把 `_restoredChapterId` 标记为已恢复。
   - 后续窗口真正加载出来后不会再次恢复，导致当前位置被前插章节推偏。

4. `_chapterRestoreTargetOffset` 用章节 `RenderBox.localToGlobal(...).dy` 计算目标偏移时没有减去阅读区顶部/阅读线基准。
   - 这会让恢复位置偏大；在窗口替换或章节前插后，更容易出现“跳一下/回顶部”的感觉。

## 修改方案

1. **让章节窗口和当前 ReaderState 强绑定**
   - 新增一个判断方法，确认 `_loadedChapters` 是否属于当前书、当前中心章节，并且包含当前章节。
   - 如果窗口不匹配，`_chapterBlocks` 先只渲染 `data.chapter`，绝不复用旧窗口，避免“手动选章后显示的不是我选的”。

2. **把“跳到列表顶部”改成“跳到当前章节顶部”**
   - 将 `_jumpToTopAfterBuild()` 改为类似 `_jumpToChapterTopAfterBuild(chapterId)` 的方法。
   - 目标偏移按章节 block 的屏幕位置计算：`当前滚动 offset + 章节顶部 y - 正文顶部 y`。
   - 这样即使窗口包含前两章，也会显示用户选择的那一章。

3. **修正滚动恢复的目标计算**
   - `_chapterRestoreTargetOffset` 不再直接 `offset + top + innerTarget`。
   - 如果恢复的是章首，按正文顶部对齐。
   - 如果恢复的是章节内位置，按保存时使用的“阅读线”对齐：`offset + chapterTop - readingLine + innerOffset`。
   - 保留进度比例恢复，字号变化后仍优先用 `chapterProgress`。

4. **窗口重新初始化后主动重新定位当前章节**
   - `_ensureChapterWindow` 完成异步加载并 setState 后，下一帧再次把当前章节定位到应在的位置。
   - 对手动选章/上一章/下一章：定位到当前章节顶部。
   - 对首次打开/恢复阅读：定位到保存的章节内进度。
   - 定位期间继续使用 `_isChangingChapter` / `_isRestoringScrollOffset` 阻止临时 jump 写入数据库。

5. **避免滚动保存导致意外重建或覆盖**
   - 保持滚动保存只写数据库，不触发整页 loading。
   - 保存时如果当前可见章节与 ReaderState 当前章节不同，只保存该可见章节进度；不在滚动过程中强行把窗口重置成另一组章节。

## 验证方式

1. 运行静态分析：

   ```bash
   fvm flutter analyze
   ```

2. 运行现有测试：

   ```bash
   fvm flutter test
   ```

3. 手动验证阅读页：
   - 打开已有书籍，向下滑过章节边界，确认不会刷新到章首。
   - 从目录选择中间章节，确认正文立即显示该章节而不是前两章或旧章节。
   - 选择章节后继续下滑，确认连续章节仍能正常追加并保持阅读位置。
   - 退出再进入，确认保存的章节和章节内位置能恢复。

## 不触碰范围

- 不修改大模型/语音资产目录；当前 git 状态里已有大量 `assets/models/...` 变更，本次只处理阅读页滚动问题。
- 不改数据库 schema。
- 不重构 ReaderRepository / LibraryRepository 的整体架构。

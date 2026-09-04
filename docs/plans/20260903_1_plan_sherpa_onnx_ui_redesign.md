# Sherpa-ONNX AI 语音与界面重设计计划

## 目标

1. 接入 Sherpa-ONNX 本地 AI 语音框架，并保留系统 TTS 兜底。
2. 按 `docs/desi/` 的参考界面重设计书库、阅读页、设置页和全局主题。
3. 阅读页改成沉浸式交互：默认隐藏头部和底部控制区，点击屏幕后头部向下抽屉出现、底部朗读控制区从底部抽屉上来；朗读控制不再悬浮。
4. 底部导航取消选中背景，只通过图标和文字颜色表达选中状态。
5. 主题主色调整为深蓝、羊皮暖黄等阅读友好色。
6. 将 `assets/branding/app_icon.svg` 改为简洁的翻开图书 Logo。

## 已确认的语音方案

- 使用 `sherpa_onnx` Flutter/Dart 包接入离线 TTS。文档显示当前包支持本地离线 TTS，版本为 `sherpa_onnx: ^1.13.7`，核心 API 包括 `OfflineTts`、`OfflineTtsConfig`、`OfflineTtsModelConfig`、`OfflineTtsVitsModelConfig`、`GeneratedAudio.samples` 和 `GeneratedAudio.sampleRate`。
- 选择公开小体积中文模型 `vits-icefall-zh-aishell3` 作为默认打包模型：Sherpa-ONNX 文档标注它是中文多说话人 VITS 模型，`model.onnx` 约 29 MB，所需文件包括 `model.onnx`、`lexicon.txt`、`tokens.txt`、`phone.fst`、`date.fst`、`number.fst`。
- 如果 Sherpa-ONNX 初始化失败、模型文件缺失、平台运行失败，自动回退到当前 `flutter_tts` 系统语音。

参考来源：
- https://pub.dev/packages/sherpa_onnx
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTts-class.html
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTtsConfig-class.html
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTtsModelConfig-class.html
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OfflineTtsVitsModelConfig-class.html
- https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/GeneratedAudio-class.html
- https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html

## 实施步骤

### 1. 依赖与模型资产

- 在 `pubspec.yaml` 增加：
  - `sherpa_onnx: ^1.13.7`
  - `audioplayers: ^6.8.1`（用于播放 Sherpa-ONNX 生成的临时 WAV 文件）
- 增加模型资产目录：
  - `assets/models/sherpa_onnx_tts/vits-icefall-zh-aishell3/`
- 下载并解压模型：
  - `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-icefall-zh-aishell3.tar.bz2`
- 在 `pubspec.yaml` assets 中登记模型目录。

### 2. Sherpa-ONNX TTS 服务

- 将当前 `OnDeviceAiTtsService` 从“预留不可用”改为真实 Sherpa-ONNX 实现。
- 新增或内聚以下能力：
  - 首次使用时把 Flutter asset 中的模型文件复制到应用文档/缓存目录，因为 Sherpa-ONNX 配置需要文件路径。
  - 使用 `OfflineTtsConfig` + `OfflineTtsVitsModelConfig` 初始化 TTS：
    - `model`: `model.onnx`
    - `lexicon`: `lexicon.txt`
    - `tokens`: `tokens.txt`
    - `ruleFsts`: `phone.fst,date.fst,number.fst`
  - 调用 `OfflineTts.generate(...)` 得到 `Float32List samples` 和 `sampleRate`。
  - 将 float PCM 样本写成临时 WAV 文件。
  - 用 `audioplayers` 播放本地 WAV，播放完成后返回，以保持现有“逐句朗读”的控制逻辑。
- 为 AI 引擎返回本地声音列表，例如：
  - `Sherpa Aishell3 · 中文女声 0`
  - `Sherpa Aishell3 · 中文男声 10`
  - `Sherpa Aishell3 · 中文旁白 21`
- voiceId 解析为 Sherpa speaker id（sid），没有选择则用 sid 0。
- `pause()`/`stop()` 对 `audioplayers` 生效，并更新播放状态。

### 3. 系统 TTS 兜底

- 保留现有 `SystemTtsService` 不破坏。
- 修改 `SpeechService.speak/listVoices/isAvailable`：
  - 用户选 `onDeviceAi` 时优先 Sherpa-ONNX。
  - 如果 Sherpa 初始化/朗读失败，捕获错误并调用系统 TTS 朗读同一文本。
  - 设置页文案说明“本地 AI 语音优先，异常时系统语音兜底”。

### 4. 主题系统

- 扩展 `AppColors` 与 `AppTheme`：
  - 羊皮暖黄：背景 `#F5EFE3` / 卡片 `#FAF7F0` / 文字 `#2C2825` / 暖棕 `#6C4A2D`
  - 深蓝：背景 `#0F172A` 或阅读深蓝 `#1E3A5F` / 卡片 `#1E293B` / 高亮 `#38BDF8`
  - 统一卡片圆角、柔和阴影、按钮/输入框圆角、Slider 配色。
- 当前数据模型只有 `ThemeMode`，本次先把 Light 设计成羊皮暖黄、Dark 设计成深蓝；设置页展示“羊皮暖黄 / 雅致深蓝 / 跟随系统”的体验文案，但仍复用现有 `ThemeMode` 持久化，避免数据库迁移。

### 5. 底部导航

- 重写 `ReaderShell` 的底部导航样式：
  - 不使用 `NavigationBar` 的选中胶囊背景。
  - 使用自定义 `Container + InkResponse/InkWell` 或配置 `NavigationBarTheme`，只改变 icon/text 颜色和字体粗细。
  - 颜色：选中用主题主色/暖棕，未选中用柔和灰褐。

### 6. 书库页参考界面

- 按 `docs/desi/书库首页.html` 改为羊皮纸风格：
  - 顶部大标题“我的书库” + 副标识。
  - 暖黄背景、卡片化视觉。
  - 有书时增加“正在阅读”Hero 卡片（取最近/第一本书），下方显示书架网格。
  - 书籍封面改为更像纸质书/书脊的卡片，进度条用暖棕色。
  - 导入入口保留：空书库显示大按钮，有书时保留右上导入与书架中的导入卡。
- 删除/保留图书的功能不变。

### 7. 阅读页沉浸交互

- 将 `ReaderPage` 改为 `Stack` 沉浸式布局：
  - 阅读正文全屏显示。
  - 默认 `_chromeVisible = false`，不显示头部和底部控制区。
  - 点击正文空白/屏幕：切换 `_chromeVisible`。
  - 头部：`AnimatedSlide` 从 `Offset(0, -1)` 到 `Offset.zero`，像向下抽屉出来；含返回、标题、目录、字号。
  - 底部：`AnimatedSlide` 从 `Offset(0, 1)` 到 `Offset.zero`，像从下方抽屉上来；含上一章/播放暂停/停止/下一章、段落/进度信息。
  - 朗读控制区不再是悬浮小卡，而是贴底安全区的抽屉面板。
  - 只在点击屏幕后唤醒头部与底部，滚动阅读不强行显示。
- 保留功能：章节目录、字号调整、上一章/下一章、逐句朗读高亮、自动滚动到当前句。
- 调整 `_firstVisibleSentenceIndex()` 的上下边界，适配隐藏/显示抽屉状态。

### 8. 设置页参考界面

- 按 `docs/desi/设置页面.html` 重构视觉：
  - 卡片式分组：阅读器、主题模式、语音与朗读、存储/关于。
  - 使用更细腻的 Slider 区块和圆角选择项。
  - 语音设置文案体现 Sherpa-ONNX 本地 AI + 系统 TTS 兜底。
  - 保留现有设置项：字号、跟随系统/明亮/深色、语音引擎、语言、声音、语速、音调、音量、试听。

### 9. Logo

- 重写 `assets/branding/app_icon.svg`：
  - 简洁翻开的图书。
  - 背景用深蓝圆角方形。
  - 书页用羊皮暖黄/米白。
  - 移除当前声波元素，让图标聚焦“阅读”。

### 10. 验证

- 运行：
  - `fvm flutter pub get`
  - `fvm flutter analyze`
  - `fvm flutter test`
- 如果模型下载或平台原生依赖导致本机验证耗时/失败，会如实报告错误，并确保系统 TTS 兜底路径仍可用。

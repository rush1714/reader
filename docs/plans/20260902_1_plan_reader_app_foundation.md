# Reader App Foundation 计划

> 日期：2026-09-02  
> 项目：Reader / 自动阅读器  
> Flutter：3.47.0，通过 FVM 管理  
> 架构参考：`/Users/guobiao/PRO/me/growfolio-kids`

## Goal

设计并落地一个无后端的 Flutter 自动阅读 App 第一版骨架，支持本机导入 EPUB 和基础文档，支持中英文阅读、阅读进度、设置页、跟随系统明暗主题，并为端侧 AI 有声阅读预留可替换架构。

## Scope

第一阶段实现范围：

- 使用 `fvm` 锁定 Flutter `3.47.0`。
- 创建 Flutter iOS / Android App 项目基础结构。
- 参考 `growfolio-kids` 的 Feature-first + MVVM + Repository + Service 架构。
- 首页展示本地导入的图书列表。
- 支持从本机选择并导入：
  - EPUB（用户已确认 `.edup` 实际指 EPUB / `.epub`）。
  - TXT / Markdown 这类纯文本文件作为基础“文档”支持。
- EPUB 离线解析目录、章节标题和章节正文。
- 阅读页支持：
  - 章节阅读。
  - 中英文文本展示。
  - 字号调整。
  - 阅读进度保存。
  - 自动阅读控制入口（播放 / 暂停 / 停止）。
- 设置页支持：
  - 阅读器字号。
  - 语音引擎选择入口。
  - 声音选择入口。
  - 语速 / 音调 / 音量设置入口。
  - 主题模式：跟随系统 / 明亮 / 深色。
- App 默认跟随系统明暗主题。
- 设计简单“图书”Logo，并放入 `assets/branding/app_icon.svg`；如果环境允许，再生成平台图标资源。
- 不做后端，不接大型语言模型服务，不上传用户书籍内容。

不在第一阶段实现：

- 云同步、账号系统、后端 API。
- DRM 加密 EPUB。
- PDF / DOCX 的完整文字抽取与重排阅读。
- 真正主播级神经 TTS 模型文件打包。第一阶段只完成端侧 AI TTS 可插拔边界和 UI 入口。

## Decisions

### 1. 架构

沿用 `growfolio-kids` 的方向：

```text
Feature-first + MVVM + Repository + Service
```

推荐依赖方向：

```text
Page / Widget
  -> ViewModel / Controller
  -> Repository
  -> Local Service / Parser / TTS Engine
  -> SQLite / File System / Native TTS or Future On-device AI TTS
```

目录结构：

```text
lib/
  main.dart
  app/
    app.dart
    router/
    theme/
    localization/
    presentation/reader_shell.dart
  core/
    storage/
    files/
    widgets/
    utils/
  features/
    library/
      data/
      presentation/
    reader/
      data/
      presentation/
    settings/
      data/
      presentation/
    speech/
      data/
      presentation/
```

### 2. 本地存储

因为 App 不准备做后端，第一阶段采用本地持久化：

- 书籍原文件：复制到 App 文档目录。
- 图书元数据、章节索引、阅读进度、设置：SQLite。
- 少量轻偏好也可通过 SharedPreferences，但核心书库数据统一放 SQLite，便于后续查询和扩展。

### 3. 文件导入和解析

- 使用文件选择器导入本机文件。
- EPUB 解析通过纯 Dart ZIP / XML / HTML 解析链路完成，避免依赖在线服务。
- TXT / Markdown 作为纯文本导入，按段落或固定长度拆分成章节。
- EPUB 和文本解析统一输出内部模型：`Book`、`BookChapter`、`ReadingProgress`。

### 4. 有声阅读 / 本地 AI 预留

用户已选择“本地 AI 预留”。第一阶段采用可替换接口设计：

```text
SpeechService
  -> SpeechEngine
      -> SystemTtsEngine（可作为调试/兜底）
      -> OnDeviceAiTtsEngine（预留，不打包大模型）
```

设计原则：

- 不调用大型语言模型。
- 不上传书籍文本。
- 阅读页和设置页只依赖 `SpeechService`，不直接依赖具体 TTS 插件。
- 先提供本地 AI 引擎占位状态、能力说明和配置模型，后续可接端侧模型（例如 Piper / Kokoro / Sherpa-ONNX 这类小型端侧 TTS 方案）或平台神经语音。
- 如需第一版可听，建议保留系统 TTS 作为可选兜底；真正“主播级”声音需要后续评估模型体积、授权、iOS/Android 性能和发布包大小。

### 5. UI

底部导航保持简单：

```text
书库 / 设置
```

页面：

- 书库首页：书籍列表、空状态、导入按钮。
- 阅读页：章节正文、进度、上一章/下一章、播放控制、字号控制。
- 设置页：阅读器设置、语音设置、主题设置。

### 6. 主题

- `MaterialApp.router` 配置 `theme`、`darkTheme` 和 `themeMode`。
- 默认 `ThemeMode.system`，支持设置页切换。

### 7. Logo

- 创建简洁图书图标：圆角底色 + 打开的书 + 声波元素。
- SVG 作为源文件保留在 `assets/branding/app_icon.svg`。
- 平台图标可用 Flutter/脚本生成 PNG 后替换 Android / iOS 默认 icon。

## Steps

1. 初始化项目
   - 使用 Flutter 3.47.0 创建项目。
   - 写入 `.fvmrc` 和 `.fvm/fvm_config.json`。
   - 调整 `pubspec.yaml`：项目名、描述、依赖、assets。

2. 搭建基础架构
   - 创建 `app/`、`core/`、`features/` 目录。
   - 配置 Riverpod、go_router、Material 3 主题。
   - 创建底部导航 Shell：书库 / 设置。

3. 实现本地数据层
   - 定义 `Book`、`BookChapter`、`ReadingProgress`、`ReaderSettings`、`SpeechSettings`。
   - 实现本地数据库服务。
   - 实现书籍文件复制和删除的基础服务。

4. 实现导入与解析
   - 文件选择器选择 EPUB / TXT / MD。
   - EPUB 解析 metadata、spine、章节内容。
   - 文本文档解析为章节。
   - 保存书籍、章节和导入时间。

5. 实现书库首页
   - 展示导入图书列表。
   - 空状态提示导入。
   - 导入成功后刷新列表。
   - 点击书籍进入阅读页。

6. 实现阅读页
   - 加载章节正文。
   - 显示标题、正文、进度。
   - 支持上一章 / 下一章。
   - 支持字号设置。
   - 保存当前章节和滚动/阅读进度。
   - 提供自动朗读控制按钮。

7. 实现语音架构
   - 定义 `SpeechEngine` 抽象。
   - 定义 `SpeechVoice`、`SpeechPlaybackState`。
   - 实现 `OnDeviceAiTtsEngine` 占位，明确返回“端侧 AI 语音引擎待集成”。
   - 可选实现 `SystemTtsEngine` 作为兜底和验证链路。

8. 实现设置页
   - 阅读器字号。
   - 主题模式：系统 / 明亮 / 深色。
   - 语音设置：引擎、声音、语速、音调、音量。
   - 保存到本地。

9. 设计资源
   - 添加简单图书 Logo SVG。
   - 注册 assets。

10. 验证
    - `fvm flutter pub get`
    - `fvm flutter analyze`
    - `fvm flutter test`
    - 如本地工具链允许，运行 Android debug build。

## Risks or open questions

- 当前全局 `flutter` / `fvm flutter` 曾尝试使用损坏的 3.27.4 缓存；实施时应在项目内先锁定 3.47.0，必要时直接调用 `/Users/guobiao/fvm/versions/3.47.0/bin/flutter` 验证。
- EPUB 包结构存在差异，第一版支持标准无 DRM EPUB；复杂 EPUB 需要后续增强解析兼容性。
- 主播级端侧 AI TTS 通常需要模型文件，可能带来较大包体、授权和性能问题；第一阶段先完成架构和占位，后续再选择具体端侧模型。
- iOS / Android 对本机文件权限、TTS 声音列表和后台播放能力不同，第一版先聚焦前台阅读和朗读。
- “文档”第一阶段按 TXT / Markdown 处理；PDF / DOCX 后续作为单独能力扩展。

## Verification checklist

- [ ] 项目可通过 FVM 使用 Flutter 3.47.0。
- [ ] App 能启动到书库页。
- [ ] 可导入 EPUB 文件并出现在书库列表。
- [ ] 可导入 TXT / Markdown 文件并出现在书库列表。
- [ ] 点击书籍可进入阅读页并显示正文。
- [ ] 阅读进度能本地保存并恢复。
- [ ] 设置页能修改字号、主题模式和语音设置。
- [ ] 默认主题跟随系统明暗。
- [ ] 语音层不调用后端或大型语言模型。
- [ ] Logo 源文件存在并在 `pubspec.yaml` 中注册。
- [ ] `fvm flutter analyze` 通过。
- [ ] `fvm flutter test` 通过。

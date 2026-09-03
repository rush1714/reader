# Reader App

Reader App 是一个 Flutter 离线阅读器，目标是支持本机导入 EPUB 和基础文档，并为端侧 AI 有声阅读预留架构。

## 技术栈

- Flutter 3.47.0
- FVM 管理 Flutter 版本
- Riverpod 状态管理和依赖注入
- go_router 路由
- SQLite 本地存储
- flutter_tts 调用 iOS / Android 本机语音模块
- Feature-first + MVVM + Repository + Service

## 当前功能

- 书库首页：展示已导入图书。
- 本机导入：支持 `.epub`、`.txt`、`.md`、`.markdown`。
- EPUB 解析：解析标准无 DRM EPUB 的元数据和章节正文。
- 阅读页：章节阅读、上一章/下一章、字号调整、进度保存。
- 设置页：阅读字号、主题模式、语音引擎、声音、语速、音调、音量。
- 主题：默认跟随系统明暗。
- 语音：调用 iOS / Android 本机系统 TTS，可选择系统声音；保留本地 AI TTS 预留入口，当前不上传文本，不调用大型语言模型。
- 平台：仅保留 iOS 与 Android。
- Logo：`assets/branding/app_icon.svg`。

## 开发命令

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run
```

如本地全局 Flutter 缓存异常，可直接使用：

```bash
/Users/guobiao/fvm/versions/3.47.0/bin/flutter --version
```

## 架构说明

```text
Page / Widget
  -> ViewModel / Controller
  -> Repository
  -> Local Service / Parser / TTS Engine
  -> SQLite / File System / Future On-device AI TTS
```

主要目录：

```text
lib/
  app/                 App、路由、主题、Shell
  core/                本地数据库、文件服务、通用 Widget
  features/library/    书库、导入、EPUB/文档解析
  features/reader/     阅读页、章节和进度
  features/settings/   本地设置
  features/speech/     语音接口和端侧 AI TTS 预留
```

## 有声阅读说明

当前默认使用 `flutter_tts` 调用 iOS / Android 本机系统语音模块：

- 不做后端。
- 不上传书籍内容。
- 不调用大型语言模型。
- 可在设置页选择系统语音、语速、音调和音量。
- 通过 `SpeechEngine` 抽象继续保留端侧 AI TTS 接入点。

系统语音的效果取决于设备已安装的语音包。后续若要达到更稳定的“主播级”声音，需要选择并集成具体端侧 TTS 模型或平台高质量语音，并评估模型体积、授权、iOS/Android 性能和发布包大小。

# Feature 目录结构与命名规范化计划

> 日期：2026-09-02  
> 项目：Reader App

## Goal

把当前 feature 目录整理成更规范的 Flutter Feature-first 结构：模型放入 `data/models/`，服务放入 `data/services/`，页面与 ViewModel 放在 `presentation/`，文件命名统一使用 `_page`、`_view_model`、`_repository`、`_service`。

## Scope

本次只做结构和命名调整，不改变业务行为。

调整范围：

- `features/library/`
  - `Book`、`ImportedBook` 移到 `data/models/`。
  - `BookParser` 改为 `BookParserService`，文件改为 `book_parser_service.dart`，放到 `data/services/`。
  - `library_repository.dart` 保持在 `data/`。
  - `library_page.dart`、`library_view_model.dart` 保持在 `presentation/`。

- `features/reader/`
  - `BookChapter`、`ChapterSummary`、`ReadingProgress` 移到 `data/models/`。
  - `reader_repository.dart` 保持在 `data/`。
  - `reader_page.dart`、`reader_view_model.dart` 保持在 `presentation/`。

- `features/settings/`
  - `ReaderSettings` 移到 `data/models/reader_settings.dart`。
  - `settings_repository.dart` 保持在 `data/`。
  - `settings_page.dart` 保持在 `presentation/`。

- `features/speech/`
  - 新结构：

```text
features/speech/
  data/
    models/
      speech_playback_state.dart
      speech_view_state.dart
      speech_voice.dart
    services/
      speech_engine_service.dart
      speech_service.dart
      system_tts_service.dart
      on_device_ai_tts_service.dart
  presentation/
    speech_view_model.dart
    speech_voices_view_model.dart
```

命名调整：

- `SpeechEngine` -> `SpeechEngineService`
- `SystemTtsEngine` -> `SystemTtsService`
- `OnDeviceAiTtsEngine` -> `OnDeviceAiTtsService`
- `SpeechController` -> `SpeechViewModel`
- `SpeechControllerState` -> `SpeechViewState`
- `speechControllerProvider` -> `speechViewModelProvider`
- `speech_voices_provider.dart` -> `speech_voices_view_model.dart`

## Steps

1. 创建规范化目录。
2. 移动文件到 `models/`、`services/`、`presentation/`。
3. 修改类名、provider 名和 import 路径。
4. 更新测试 import。
5. 运行 `flutter analyze` 和 `flutter test`。
6. 如 analyze 发现遗漏引用，继续修正。

## Verification checklist

- [ ] `features/speech/data` 不再直接堆所有文件。
- [ ] 模型均在 `data/models/`。
- [ ] 服务均在 `data/services/` 且文件名以 `_service.dart` 结尾。
- [ ] 页面文件以 `_page.dart` 结尾。
- [ ] ViewModel 文件以 `_view_model.dart` 结尾。
- [ ] Repository 文件以 `_repository.dart` 结尾。
- [ ] `flutter analyze` 通过。
- [ ] `flutter test` 通过。

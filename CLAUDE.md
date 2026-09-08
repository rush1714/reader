# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Reader App is a Flutter offline reader for locally imported EPUB and text documents. The app is intentionally local-first: imported books are copied into the app documents directory, metadata/progress/settings are stored in SQLite, and speech uses device-local engines rather than a backend.

Use FVM for Flutter commands. The pinned SDK is Flutter 3.47.0 (`.fvm/fvm_config.json`), with Dart constrained to `>=3.13.0 <3.14.0`.

## Common commands

```bash
# Install dependencies
fvm flutter pub get

# Static analysis / linting
fvm flutter analyze

# Run all tests
fvm flutter test

# Run a single test file
fvm flutter test test/features/reader/reader_settings_test.dart

# Run tests matching a name
fvm flutter test --name "ReaderSettings can round-trip through map"

# Run the app
fvm flutter run

# List devices before choosing a target
fvm flutter devices
fvm flutter run -d <device-id>

# Build supported mobile targets
fvm flutter build apk
fvm flutter build ios --no-codesign

# Format Dart sources
fvm dart format lib test
```

If the local global Flutter cache is problematic, the README notes the pinned binary can be checked directly:

```bash
/Users/guobiao/fvm/versions/3.47.0/bin/flutter --version
```

## Code comments

The user reads the source code to learn from it. All future code changes should include detailed Chinese comments, especially in `lib/` Dart code.

- Public classes, public methods, providers, models, and service/repository methods must have Dart doc comments (`///`) explaining their role and why they exist.
- Complex private helpers should also have `///` comments, not only public APIs.
- For UI pages and widgets, explain what each widget/component represents, how state flows through it, and why callbacks are wired that way.
- For non-obvious statements, state changes, async callbacks, timers, scroll math, persistence decisions, parsing rules, and platform-specific behavior, add inline `//` comments near the relevant lines.
- Prefer “learning comments” that explain intent and trade-offs, not comments that merely repeat syntax.
- When adding new code, match the existing code style but err on the side of more explanation.

## Architecture

The app follows a feature-first MVVM + Repository + Service structure:

```text
Page / Widget
  -> ViewModel / Controller
  -> Repository
  -> Local Service / Parser / TTS Engine
  -> SQLite / File System / On-device TTS assets
```

Top-level layout:

- `lib/main.dart` creates a `ProviderScope` and launches `ReaderApp`.
- `lib/app/` contains app-level composition: `MaterialApp.router`, `go_router` routes, shell navigation, and theme definitions.
- `lib/core/` contains cross-feature local infrastructure: SQLite database setup, app-private file copying/deletion, and shared loading/error/empty widgets.
- `lib/features/library/` owns book import, parsing, listing, and deletion.
- `lib/features/reader/` owns chapter loading, chapter navigation, and reading progress persistence.
- `lib/features/settings/` owns reader and speech settings persisted as a JSON value in SQLite.
- `lib/features/speech/` owns speech playback abstractions and engine implementations.

Riverpod is used for both dependency injection and UI state. Providers generally live beside the implementation they expose (for example `libraryRepositoryProvider`, `readerViewModelProvider`, and `readerSettingsProvider`). Pages should call ViewModels/Controllers; they should not access SQLite or file APIs directly.

## Data and persistence

`AppDatabase` opens `reader_app.db` in the application documents directory and creates four tables at schema version 1:

- `books`: imported book metadata and current chapter index.
- `chapters`: parsed plain-text chapter content keyed by book and chapter index.
- `reading_progress`: current chapter and whole-book progress.
- `settings`: key/value storage; `ReaderSettings` is stored under `reader_settings` as JSON.

`LibraryRepository` coordinates imports: `BookParserService` parses the source file, `AppFileService` copies the original into the app-private `books/` directory, then the repository writes book/chapter/progress rows in one SQLite transaction. Deleting a book removes the database row and then deletes the copied file.

`ReaderRepository` delegates book metadata lookups to `LibraryRepository`, reads chapter data directly from SQLite, and saves progress through `LibraryRepository.updateCurrentChapter`. `ReaderViewModel` invalidates `libraryViewModelProvider` after progress changes so the library list reflects recent reading state.

## Book parsing

`BookParserService` is the single import parser entry point. It supports:

- `.epub`: standard non-DRM EPUB ZIPs. It reads `META-INF/container.xml`, resolves the OPF manifest/spine, extracts HTML body text, and uses metadata title/creator when available.
- `.txt`, `.md`, `.markdown`: plain text. It normalizes whitespace, detects simple Chinese/English chapter headings when possible, and otherwise chunks long text into ~7000-character chapters.

The parser returns `ImportedBook` / `ImportedChapter` drafts; only repositories assign IDs and persist them.

## Speech system

Speech is behind `SpeechEngineService`, with `SpeechService` acting as the facade. `ReaderSettings.speechEngine` selects the engine:

- `SystemTtsService` wraps `flutter_tts` for iOS/Android system voices, applies selected voice/language/rate/pitch/volume, and chunks long text before speaking.
- `OnDeviceAiTtsService` wraps `sherpa_onnx` and `audioplayers`. It packages the Sherpa ONNX Aishell3 model from `assets/models/sherpa_onnx_tts/vits-icefall-zh-aishell3/`, copies required model files into the app documents directory on first use, generates a temporary WAV file, plays it, then deletes it.
- If the on-device AI engine fails, `SpeechService` falls back to system TTS.

`SpeechViewModel` speaks a chapter by paragraph/sentence list and tracks the current spoken segment. Cross-chapter autoplay is coordinated by the reader page because next-chapter content belongs to reader state.

## Routing and supported platforms

Routes are defined centrally in `lib/app/router/app_router.dart` with a `ShellRoute` wrapping:

- `/library`
- `/reader/:bookId`
- `/settings`

The README states the app only targets iOS and Android. `analysis_options.yaml` also excludes generated/build and unsupported platform folders (`web`, `windows`, `macos`, `linux`) from analysis.

## Assets and large files

`pubspec.yaml` registers:

- `assets/branding/app_icon.svg`
- `assets/models/sherpa_onnx_tts/vits-icefall-zh-aishell3/`

The Sherpa ONNX model files are large app assets. Avoid moving or renaming them unless you also update `OnDeviceAiTtsService._assetRoot`, `_requiredFiles`, and `pubspec.yaml` together.

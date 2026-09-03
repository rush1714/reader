import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:reader_app/core/storage/app_database.dart';
import 'package:reader_app/features/settings/data/models/reader_settings.dart';

/// 提供阅读器设置仓库。
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SettingsRepository(database);
});

/// 本地设置仓库。
///
/// 设置存储在 SQLite 的 key-value 表中，方便与书库数据一起迁移和备份。
class SettingsRepository {
  const SettingsRepository(this._database);

  static const _settingsKey = 'reader_settings';

  final AppDatabase _database;

  /// 读取阅读器设置。未保存过时返回默认值。
  Future<ReaderSettings> loadSettings() async {
    final db = await _database.database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [_settingsKey],
      limit: 1,
    );

    if (rows.isEmpty) return ReaderSettings.defaults();

    final value = rows.first['value']! as String;
    return ReaderSettings.fromMap(jsonDecode(value) as Map<String, Object?>);
  }

  /// 保存阅读器设置。
  Future<void> saveSettings(ReaderSettings settings) async {
    final db = await _database.database;
    await db.insert(
      'settings',
      {
        'key': _settingsKey,
        'value': jsonEncode(settings.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// 设置页和 App 根组件共享的设置状态。
final readerSettingsProvider = AsyncNotifierProvider<ReaderSettingsController, ReaderSettings>(
  ReaderSettingsController.new,
);

/// 阅读器设置控制器。
///
/// 负责把用户操作转换为持久化设置，UI 不直接写数据库。
class ReaderSettingsController extends AsyncNotifier<ReaderSettings> {
  @override
  Future<ReaderSettings> build() {
    return ref.watch(settingsRepositoryProvider).loadSettings();
  }

  /// 更新正文字号。
  Future<void> updateFontSize(double value) {
    return _update((settings) => settings.copyWith(fontSize: value));
  }

  /// 更新主题模式。
  Future<void> updateThemeMode(ThemeMode mode) {
    return _update((settings) => settings.copyWith(themeMode: mode));
  }

  /// 更新语音引擎。
  Future<void> updateSpeechEngine(SpeechEngineType engine) {
    return _update((settings) => settings.copyWith(speechEngine: engine));
  }

  /// 更新朗读语言，并清空当前声音，避免语言和声音不匹配。
  Future<void> updateSpeechLocale(String? locale) {
    return _update((settings) => settings.copyWith(speechLocale: locale, voiceId: null));
  }

  /// 更新声音 ID。
  Future<void> updateVoiceId(String? voiceId) {
    return _update((settings) => settings.copyWith(voiceId: voiceId));
  }

  /// 更新语速。
  Future<void> updateSpeechRate(double value) {
    return _update((settings) => settings.copyWith(speechRate: value));
  }

  /// 更新音调。
  Future<void> updatePitch(double value) {
    return _update((settings) => settings.copyWith(pitch: value));
  }

  /// 更新音量。
  Future<void> updateVolume(double value) {
    return _update((settings) => settings.copyWith(volume: value));
  }

  Future<void> _update(ReaderSettings Function(ReaderSettings settings) transform) async {
    final previous = state.value ?? ReaderSettings.defaults();
    final next = transform(previous);

    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).saveSettings(next);
  }
}

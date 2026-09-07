import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 提供 App SQLite 数据库。
///
/// 数据库只保存本机书库、章节、阅读进度和设置，不承载任何后端同步职责。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// 本地 SQLite 数据库封装。
///
/// 这里维护建表和底层 database 单例。业务代码应通过各自 Repository 调用，避免页面直接写 SQL。
class AppDatabase {
  Database? _database;

  /// 获取数据库实例。
  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'reader_app.db');

    final database = await openDatabase(
      path,
      version: 2,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    _database = database;
    return database;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  format TEXT NOT NULL,
  filePath TEXT NOT NULL,
  importedAt TEXT NOT NULL,
  chapterCount INTEGER NOT NULL,
  currentChapterIndex INTEGER NOT NULL DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE chapters (
  id TEXT PRIMARY KEY,
  bookId TEXT NOT NULL,
  chapterIndex INTEGER NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE UNIQUE INDEX chapters_book_index
ON chapters(bookId, chapterIndex)
''');

    await db.execute('''
CREATE TABLE reading_progress (
  bookId TEXT PRIMARY KEY,
  chapterIndex INTEGER NOT NULL,
  progress REAL NOT NULL,
  scrollOffset REAL NOT NULL DEFAULT 0,
  chapterProgress REAL NOT NULL DEFAULT 0,
  updatedAt TEXT NOT NULL,
  FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE reading_progress ADD COLUMN scrollOffset REAL NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE reading_progress ADD COLUMN chapterProgress REAL NOT NULL DEFAULT 0',
      );
    }
  }
}

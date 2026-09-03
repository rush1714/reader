import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/data/library_repository.dart';

/// 书库页面状态。
class LibraryState {
  const LibraryState({
    required this.books,
    required this.isImporting,
  });

  /// 当前本地书库列表。
  final List<Book> books;

  /// 是否正在导入图书。
  final bool isImporting;

  LibraryState copyWith({
    List<Book>? books,
    bool? isImporting,
  }) {
    return LibraryState(
      books: books ?? this.books,
      isImporting: isImporting ?? this.isImporting,
    );
  }
}

/// 书库 ViewModel Provider。
final libraryViewModelProvider = AsyncNotifierProvider<LibraryViewModel, LibraryState>(
  LibraryViewModel.new,
);

/// 书库 ViewModel。
///
/// 负责响应导入、刷新、删除等 UI 行为，并通过 Repository 访问本地数据。
class LibraryViewModel extends AsyncNotifier<LibraryState> {
  @override
  Future<LibraryState> build() async {
    final books = await ref.watch(libraryRepositoryProvider).listBooks();
    return LibraryState(books: books, isImporting: false);
  }

  /// 刷新书库列表。
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final books = await ref.read(libraryRepositoryProvider).listBooks();
      return LibraryState(books: books, isImporting: false);
    });
  }

  /// 选择并导入本机文件。
  Future<void> importFromFilePicker() async {
    final previous = state.value ?? const LibraryState(books: [], isImporting: false);
    state = AsyncData(previous.copyWith(isImporting: true));

    state = await AsyncValue.guard(() async {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['epub', 'txt', 'md', 'markdown'],
      );

      final path = result?.path;
      if (path == null) {
        return previous.copyWith(isImporting: false);
      }

      await ref.read(libraryRepositoryProvider).importBook(path);
      final books = await ref.read(libraryRepositoryProvider).listBooks();
      return LibraryState(books: books, isImporting: false);
    });
  }

  /// 删除指定图书。
  Future<void> deleteBook(Book book) async {
    final previous = state.value ?? const LibraryState(books: [], isImporting: false);
    state = AsyncData(previous.copyWith(
      books: previous.books.where((item) => item.id != book.id).toList(),
    ));

    await ref.read(libraryRepositoryProvider).deleteBook(book);
    await refresh();
  }
}

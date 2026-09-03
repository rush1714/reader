import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/core/widgets/app_empty_view.dart';
import 'package:reader_app/core/widgets/app_error_view.dart';
import 'package:reader_app/core/widgets/app_loading.dart';
import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/presentation/library_view_model.dart';

/// 书库首页。
///
/// 首页只展示本机已导入的图书列表，并提供导入入口。导入和持久化逻辑由 ViewModel 处理。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryViewModelProvider);

    ref.listen(libraryViewModelProvider, (previous, next) {
      if (!next.hasError || next.error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next.error.toString())),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书库'),
        actions: [
          IconButton(
            tooltip: '导入图书',
            onPressed: state.value?.isImporting == true
                ? null
                : () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: state.when(
        loading: () => const AppLoading(),
        error: (error, stackTrace) => AppErrorView(
          error: error,
          onRetry: () => ref.read(libraryViewModelProvider.notifier).refresh(),
        ),
        data: (data) {
          if (data.books.isEmpty) {
            return AppEmptyView(
              icon: Icons.menu_book_outlined,
              message: '还没有图书。\n支持导入 EPUB、TXT 和 Markdown，本地离线保存。',
              action: FilledButton.icon(
                onPressed: data.isImporting
                    ? null
                    : () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
                icon: data.isImporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(data.isImporting ? '正在导入...' : '导入本机图书'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(libraryViewModelProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: data.books.length + (data.isImporting ? 1 : 0),
              itemBuilder: (context, index) {
                if (data.isImporting && index == 0) {
                  return const Card(
                    child: ListTile(
                      leading: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      title: Text('正在导入图书'),
                      subtitle: Text('解析 EPUB 或文档内容并保存到本机。'),
                    ),
                  );
                }

                final book = data.books[index - (data.isImporting ? 1 : 0)];
                return _BookTile(book: book);
              },
            ),
          );
        },
      ),
      floatingActionButton: state.value?.books.isEmpty == false
          ? FloatingActionButton.extended(
              onPressed: state.value?.isImporting == true
                  ? null
                  : () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
              icon: const Icon(Icons.add),
              label: const Text('导入'),
            )
          : null,
    );
  }
}

class _BookTile extends ConsumerWidget {
  const _BookTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = book.chapterCount == 0 ? 0.0 : (book.currentChapterIndex + 1) / book.chapterCount;

    return Card(
      child: InkWell(
        onTap: () => context.go(RoutePaths.readerForBook(book.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookCover(book: book),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'delete') {
                              _confirmDelete(context, ref, book);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${book.author} · ${book.chapterCount} 章',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress.clamp(0, 1)),
                    const SizedBox(height: 6),
                    Text(
                      '已读到第 ${book.currentChapterIndex + 1} 章',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除图书？'),
        content: Text('将从本机书库删除《${book.title}》和阅读进度，原始外部文件不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(libraryViewModelProvider.notifier).deleteBook(book);
    }
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = _coverColors(book.title);

    return Container(
      width: 72,
      height: 104,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 8,
            bottom: 8,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_stories, color: colorScheme.onPrimary, size: 20),
                const Spacer(),
                Text(
                  book.title.characters.take(6).toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _coverColors(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (value, unit) => value + unit);
    final palettes = [
      [const Color(0xFF2957D8), const Color(0xFF19B8A8)],
      [const Color(0xFF7C3AED), const Color(0xFFEC4899)],
      [const Color(0xFFEA580C), const Color(0xFFFACC15)],
      [const Color(0xFF059669), const Color(0xFF38BDF8)],
      [const Color(0xFF334155), const Color(0xFF64748B)],
    ];
    return palettes[hash % palettes.length];
  }
}

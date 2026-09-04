import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:reader_app/app/router/route_names.dart';
import 'package:reader_app/app/theme/app_colors.dart';
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
      body: SafeArea(
        bottom: false,
        child: state.when(
          loading: () => const AppLoading(),
          error: (error, stackTrace) => AppErrorView(
            error: error,
            onRetry: () => ref.read(libraryViewModelProvider.notifier).refresh(),
          ),
          data: (data) {
            final spotlightBook = data.books.isEmpty
                ? null
                : data.books.firstWhere(
                    _hasStarted,
                    orElse: () => data.books.first,
                  );

            return RefreshIndicator(
              onRefresh: () => ref.read(libraryViewModelProvider.notifier).refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _LibraryHeader(
                      isImporting: data.isImporting,
                      onImport: () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
                    ),
                  ),
                  if (data.books.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyLibrary(
                        isImporting: data.isImporting,
                        onImport: () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
                      ),
                    )
                  else ...[
                    if (spotlightBook != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _NowReadingCard(book: spotlightBook),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: _ShelfToolbar(
                          total: data.books.length,
                          reading: data.books.where(_hasStarted).length,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 104),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.48,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index == data.books.length) {
                              return _ImportBookTile(
                                isImporting: data.isImporting,
                                onImport: () => ref.read(libraryViewModelProvider.notifier).importFromFilePicker(),
                              );
                            }

                            return _BookShelfTile(book: data.books[index]);
                          },
                          childCount: data.books.length + 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.isImporting,
    required this.onImport,
  });

  final bool isImporting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '我的书库',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        'WARM PARCHMENT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '本地离线阅读 · EPUB / TXT / Markdown',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: '导入图书',
            onPressed: isImporting ? null : onImport,
            icon: isImporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _NowReadingCard extends StatelessWidget {
  const _NowReadingCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = book.readingProgress.clamp(0, 1).toDouble();
    final hasStarted = progress > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'NOW READING · 正在阅读',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.go(RoutePaths.readerForBook(book.id)),
            child: Stack(
              children: [
                Positioned(
                  right: -42,
                  bottom: -42,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _BookCover(book: book, width: 92, height: 132),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '作者：${book.author} · ${book.format.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  hasStarted ? '已读至 第 ${book.currentChapterIndex + 1} 章' : '尚未开始阅读',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                Text(
                                  '${(progress * 100).round()}%',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: progress,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () => context.go(RoutePaths.readerForBook(book.id)),
                              icon: const Icon(Icons.play_arrow_rounded, size: 18),
                              label: const Text('继续阅读'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfToolbar extends StatelessWidget {
  const _ShelfToolbar({required this.total, required this.reading});

  final int total;
  final int reading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            _FilterChip(label: '全部 ($total)', selected: true),
            const SizedBox(width: 8),
            _FilterChip(label: '在读 ($reading)', selected: false),
            const SizedBox(width: 8),
            const _FilterChip(label: '收藏', selected: false),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 5),
            Text(
              '按最近阅读时间排序',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Text(
              '$reading 本进行中 · ${total - reading} 本未开始',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? colorScheme.surface : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: selected ? 0.7 : 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
      ),
    );
  }
}

class _BookShelfTile extends ConsumerWidget {
  const _BookShelfTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = book.readingProgress.clamp(0, 1).toDouble();
    final hasStarted = _hasStarted(book);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go(RoutePaths.readerForBook(book.id)),
      onLongPress: () => _confirmDelete(context, ref, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _BookCover(
              book: book,
              width: double.infinity,
              height: double.infinity,
              progress: progress,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  hasStarted ? '第 ${book.currentChapterIndex + 1} 章' : '未开始',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Text(
                hasStarted ? '${(progress * 100).round()}%' : '待读',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: progress == 0
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
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

class _ImportBookTile extends StatelessWidget {
  const _ImportBookTile({
    required this.isImporting,
    required this.onImport,
  });

  final bool isImporting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: isImporting ? null : onImport,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.72),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: isImporting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.add_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isImporting ? '导入中' : '导入书籍',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'EPUB / TXT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 29),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.isImporting,
    required this.onImport,
  });

  final bool isImporting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.auto_stories_outlined, size: 54, color: colorScheme.primary),
          ),
          const SizedBox(height: 22),
          Text(
            '还没有图书',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '支持导入 EPUB、TXT 和 Markdown，本地离线保存，随时沉浸阅读。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isImporting ? null : onImport,
            icon: isImporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(isImporting ? '正在导入...' : '导入本机图书'),
          ),
        ],
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.book,
    required this.width,
    required this.height,
    this.progress,
  });

  final Book book;
  final double width;
  final double height;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = _coverColors(book.title);
    final textColor = colors.first.computeLuminance() > 0.55 ? AppColors.parchmentText : Colors.white;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.22),
                    Colors.black.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 18, color: textColor.withValues(alpha: 0.9)),
                    const Spacer(),
                    Text(
                      book.format.label,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.72),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  book.title.characters.take(8).toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                minHeight: 4,
                value: progress!.clamp(0, 1),
                color: AppColors.parchmentGold,
                backgroundColor: Colors.black.withValues(alpha: 0.18),
              ),
            ),
        ],
      ),
    );
  }

  List<Color> _coverColors(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (value, unit) => value + unit);
    final palettes = [
      [const Color(0xFF4A321E), const Color(0xFF25170B)],
      [const Color(0xFFECE5D8), const Color(0xFFD8CBB8)],
      [const Color(0xFF153443), const Color(0xFF2D4B5A)],
      [const Color(0xFF6C4A2D), const Color(0xFFCBB279)],
      [const Color(0xFF1E3A5F), const Color(0xFF0F172A)],
    ];
    return palettes[hash % palettes.length];
  }
}

bool _hasStarted(Book book) {
  return book.readingProgress > 0 || book.lastReadAt != null || book.currentChapterIndex > 0;
}

// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/pages/comic_cover.dart';

/// 漫画搜索页：搜索框 + 结果网格 + 空/错误/重试。
///
/// 只认 [ComicDataSource]；fixture 与 A′ 源引擎实现可无缝替换。
/// 空关键词返回推荐列表（fixture 语义），搜索无结果时显示空态。
class ComicSearchPage extends StatefulWidget {
  const ComicSearchPage({
    super.key,
    required this.dataSource,
    this.showAppBar = true,
    this.onOpenDetail,
  });

  final ComicDataSource dataSource;

  /// 壳已提供顶部导航时设为 false，本页不再画自己的 AppBar。
  final bool showAppBar;

  /// 点结果卡片时回调；由模块层决定如何钻进详情页。
  final ValueChanged<ComicSummary>? onOpenDetail;

  @override
  State<ComicSearchPage> createState() => _ComicSearchPageState();
}

class _ComicSearchPageState extends State<ComicSearchPage> {
  final TextEditingController _controller = TextEditingController();
  late Future<List<ComicSummary>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.dataSource.search(_query);
  }

  @override
  void didUpdateWidget(ComicSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据源被替换（fixture 切换 / A′ 引擎注入）时按当前关键词重查。
    if (oldWidget.dataSource != widget.dataSource) {
      _future = widget.dataSource.search(_query);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch(String value) {
    final query = value.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = query;
      _future = widget.dataSource.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('搜索漫画')) : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SearchBar(
                controller: _controller,
                hintText: '搜索漫画名称',
                leading: const Icon(Icons.search),
                trailing: <Widget>[
                  IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => _runSearch(_controller.text),
                  ),
                ],
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildResults(context, cs)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, ColorScheme cs) {
    return FutureBuilder<List<ComicSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _SearchErrorState(onRetry: () => _runSearch(_query));
        }
        final results = snapshot.data ?? const <ComicSummary>[];
        if (results.isEmpty) return _SearchEmptyState(query: _query);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                '共 ${results.length} 部',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.apply(color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 296,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final item = results[index];
                  return ComicPosterCard(
                    key: ValueKey<String>('search-result-${item.id}'),
                    item: item,
                    onTap: widget.onOpenDetail == null
                        ? null
                        : () => widget.onOpenDetail!(item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 搜索结果卡片：封面 + 标题 + 状态行。
class ComicPosterCard extends StatelessWidget {
  const ComicPosterCard({super.key, required this.item, this.onTap});

  final ComicSummary item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ComicCover(url: item.coverUrl, title: item.title),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  if (item.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.apply(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty ? '暂时没有可搜索的漫画' : '没有找到「$query」',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '换个关键词试试',
              style: textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
          const SizedBox(height: 12),
          const Text('搜索失败，请稍后重试'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

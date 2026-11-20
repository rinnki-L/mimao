// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/pages/anime_cover.dart';
import 'package:mimao/anime/pages/anime_error_state.dart';
import 'package:mimao/anime/pages/anime_image_mirror.dart';

/// 番剧搜索页：搜索框 + 结果网格。
///
/// 只认 [AnimeDataSource]；fixture 与 A 线引擎实现可无缝替换。
/// 空关键词返回推荐列表（fixture 语义），搜索无结果时显示空态。
class AnimeSearchPage extends StatefulWidget {
  const AnimeSearchPage({
    super.key,
    required this.dataSource,
    this.showAppBar = true,
    this.onOpenDetail,
    this.mirror,
  });

  final AnimeDataSource dataSource;

  /// 壳已提供顶部导航时设为 false，本页不再画自己的 AppBar。
  final bool showAppBar;

  /// 点结果卡片时回调；由模块层决定如何钻进详情页。
  final ValueChanged<AnimeSummary>? onOpenDetail;

  /// 封面镜像开关控制器；null 时封面不走代理（保持既有行为）。
  final AnimeImageMirrorController? mirror;

  @override
  State<AnimeSearchPage> createState() => _AnimeSearchPageState();
}

class _AnimeSearchPageState extends State<AnimeSearchPage> {
  final TextEditingController _controller = TextEditingController();
  late Future<List<AnimeSummary>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.dataSource.search(_query);
  }

  @override
  void didUpdateWidget(AnimeSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据源被替换（如 fixture 切换 / A 线引擎注入）时按当前关键词重查。
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
      appBar: widget.showAppBar ? AppBar(title: const Text('搜索')) : null,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SearchBar(
                controller: _controller,
                hintText: '搜索番剧名称',
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
    return FutureBuilder<List<AnimeSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AnimeRetryErrorState(
            message: '搜索失败，请稍后重试',
            onRetry: () => _runSearch(_query),
          );
        }
        final results = snapshot.data ?? const <AnimeSummary>[];
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
                  return _AnimePosterCard(
                    key: ValueKey<String>('search-result-${item.id}'),
                    item: item,
                    mirror: widget.mirror,
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
class _AnimePosterCard extends StatelessWidget {
  const _AnimePosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.mirror,
  });

  final AnimeSummary item;
  final VoidCallback? onTap;
  final AnimeImageMirrorController? mirror;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 形态（无阴影 / surfaceContainerLow / r20）走 cardTheme，页面不再覆写。
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: AnimeCover(
                url: item.coverUrl,
                title: item.title,
                mirror: mirror,
              ),
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
              query.isEmpty ? '暂时没有可搜索的番剧' : '没有找到「$query」',
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

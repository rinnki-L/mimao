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

  /// 诊断是"取走即清"，builder 内不能 setState。按 [_future] 身份缓存一次读取
  /// 结果：同一 future 的多次 build 复用缓存，换 future（新一轮搜索）才重新取。
  /// 这样既满足 builder 无副作用，也避免 rebuild 时诊断被清空后错误态闪烁回空态。
  Future<List<ComicSummary>>? _diagnosticsForFuture;
  List<String> _searchDiagnostics = const <String>[];

  List<String> _diagnosticsFor(Future<List<ComicSummary>> future) {
    if (!identical(_diagnosticsForFuture, future)) {
      _diagnosticsForFuture = future;
      _searchDiagnostics = widget.dataSource.takeSearchDiagnostics();
    }
    return _searchDiagnostics;
  }

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
        if (results.isEmpty) {
          // 失败被吞成空结果时，用搜索期诊断还原真实原因（最多 10 条）。
          final diagnostics = _diagnosticsFor(_future);
          if (diagnostics.isNotEmpty) {
            return _SearchDiagnosticsState(
              diagnostics: diagnostics,
              onRetry: () => _runSearch(_query),
            );
          }
          return _SearchEmptyState(query: _query);
        }
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

/// 搜索无结果但有诊断时的错误态：逐条列出各源失败原因，而不是笼统的"没找到"。
/// 最多展示 10 条，超出用"还有 N 条"收口；提供重试。
class _SearchDiagnosticsState extends StatelessWidget {
  const _SearchDiagnosticsState({
    required this.diagnostics,
    required this.onRetry,
  });

  /// 单页最多列出的原因条数（超出显示"还有 N 条"）。
  static const int _maxVisible = 10;

  final List<String> diagnostics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visible = diagnostics.take(_maxVisible).toList(growable: false);
    final remaining = diagnostics.length - visible.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('搜索未成功', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '以下来源未能返回结果：',
              style: theme.textTheme.bodyMedium?.apply(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final reason in visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '• $reason',
                          key: Key('search-diagnostic-$reason'),
                          style: theme.textTheme.bodySmall?.apply(
                            color: cs.error,
                          ),
                        ),
                      ),
                    if (remaining > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '还有 $remaining 条',
                          key: const Key('search-diagnostics-remaining'),
                          style: theme.textTheme.bodySmall?.apply(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

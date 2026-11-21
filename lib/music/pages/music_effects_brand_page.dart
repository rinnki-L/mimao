// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 耳机品牌型号音效页（L1）：某品牌下的耳机型号音效分页列表。
///
/// 从音效页的品牌行 push 进来；标题用品牌名，数据走
/// [MusicEffectsApi.effectsBrandDetail]（brand_id 必填）。列表项复用音效页
/// 同构的卡片形态（本文件自带一份私有实现，保持页面文件自包含）：不可用
/// 型号置灰并显示原因（耳机音效多为「未解锁」），不接播放链路。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/effects_api.dart';
import 'package:mimao/music/api/effects_brand_detail.dart';
import 'package:mimao/music/models/effects_models.dart';

/// 耳机品牌型号音效页。
class MusicEffectsBrandPage extends StatefulWidget {
  const MusicEffectsBrandPage({
    super.key,
    required this.effects,
    required this.brand,
  });

  /// 音效/品牌端点组（型号音效走 effectsBrandDetail）。
  final MusicEffectsApi effects;

  /// 品牌（id 进查询参数，name 进标题）。
  final MusicEarphoneBrand brand;

  @override
  State<MusicEffectsBrandPage> createState() => _MusicEffectsBrandPageState();
}

class _MusicEffectsBrandPageState extends State<MusicEffectsBrandPage> {
  /// 型号列表页大小（audio_effect.rs paging 上限 50）。
  static const int _pageSize = 50;

  bool _loading = true;
  Object? _error;
  List<MusicEffect> _items = List<MusicEffect>.empty();
  bool _loadingMore = false;
  Object? _moreError;
  bool _hasMore = false;
  int _nextPage = 1;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() {
    _items = List<MusicEffect>.empty();
    _nextPage = 1;
    _hasMore = false;
    _moreError = null;
    _loadingMore = false;
    return _loadPage();
  }

  Future<void> _loadPage() async {
    final page = _nextPage;
    final firstPage = page == 1;
    setState(() {
      if (firstPage) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
        _moreError = null;
      }
    });
    try {
      final result = await widget.effects.effectsBrandDetail(
        EffectsBrandDetailQuery(
          page: page,
          pageSize: _pageSize,
          brandId: widget.brand.id,
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _moreError = null;
        _items = <MusicEffect>[..._items, ...result.items];
        _nextPage = page + 1;
        // total 优先收口；没给 total 就按「整页满」推测还有下一页。
        final total = result.total;
        _hasMore = total != null
            ? _items.length < total
            : result.items.length == (result.pageSize ?? 0);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (firstPage) {
          _loading = false;
          _error = error;
          _hasMore = false;
        } else {
          _loadingMore = false;
          _moreError = error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const _ListPlaceholder();
    } else if (_error != null) {
      body = _StateView(
        key: const Key('effects-brand-detail-error'),
        message: '耳机音效加载失败：$_error',
        onRetry: _refresh,
      );
    } else if (_items.isEmpty) {
      body = const _StateView(message: '该品牌暂无耳机音效');
    } else {
      body = ListView.builder(
        key: const Key('effects-brand-detail-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) return _buildMoreFooter();
          return _EffectCard(effect: _items[index]);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand.name)),
      body: body,
    );
  }

  /// 分页页脚：加载更多 / 加载中 / 失败重试（失败不清列表）。
  Widget _buildMoreFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: Text('正在加载更多…')),
      );
    }
    if (_moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextButton.icon(
          key: const Key('effects-brand-detail-more-retry'),
          onPressed: _loadPage,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('加载更多失败，点此重试'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        key: const Key('effects-brand-detail-more'),
        onPressed: _loadPage,
        child: const Text('加载更多'),
      ),
    );
  }
}

/// section 级提示/空态/错误视图；带 onRetry 时显示重试按钮。
class _StateView extends StatelessWidget {
  const _StateView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              onRetry == null ? Icons.inbox_outlined : Icons.error_outline,
              size: 36,
              color: onRetry == null ? cs.onSurfaceVariant : cs.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 首屏加载占位：静态灰块（避免 indeterminate 进度条令 pumpAndSettle 不收敛）。
class _ListPlaceholder extends StatelessWidget {
  const _ListPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        for (final _ in List<int>.generate(3, (index) => index))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: MimaoShapes.md,
              ),
            ),
          ),
      ],
    );
  }
}

/// 音效卡（与音效页同构）：不可用时主体置灰、原因行单独显示；不可点。
class _EffectCard extends StatelessWidget {
  const _EffectCard({required this.effect});

  final MusicEffect effect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unavailableReason = effect.unavailableReason;
    final main = Row(
      children: <Widget>[
        _EffectIcon(url: effect.iconUrl, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                effect.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              if (effect.author.isNotEmpty)
                Text(
                  effect.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (effect.userCount != null)
          Text(
            '${effect.userCount}人在用',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Opacity(
                opacity: unavailableReason == null ? 1 : 0.45,
                child: main,
              ),
              if (unavailableReason != null) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.block_outlined, size: 14, color: cs.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        unavailableReason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 音效图标：无 URL / 加载失败回退均衡器占位。
class _EffectIcon extends StatelessWidget {
  const _EffectIcon({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.md,
      ),
      child: Icon(Icons.graphic_eq, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.md,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

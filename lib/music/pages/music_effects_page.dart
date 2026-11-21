// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音效页（L1）：音效商城目录 / 耳机品牌 / 设备匹配三个 tab + 听歌识曲入口。
///
/// 页面只依赖注入的 [MusicEffectsApi] / [MusicPlaybackExtApi]，不 import
/// Kugou 实现与传输层。三个 tab 各自独立 loading/错误重试/空态，失败互不
/// 阻塞；`playbackExt` 为空时「音效商城」tab 与「听歌识曲」入口整体隐藏
/// （音效商城目录 getModel 与识曲都在播放补全端点组上）。
///
/// 音效不是歌曲：卡片只做展示（含不可用置灰与原因），不接播放链路。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/effects_api.dart';
import 'package:mimao/music/api/effects_brand.dart';
import 'package:mimao/music/api/get_model.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_audio_match_page.dart';
import 'package:mimao/music/pages/music_effects_brand_page.dart';

/// 音效页：音效商城 / 耳机品牌 / 设备匹配。
class MusicEffectsPage extends StatefulWidget {
  const MusicEffectsPage({super.key, required this.effects, this.playbackExt});

  /// 音效/品牌端点组（品牌列表 / 品牌型号 / 设备匹配）。
  final MusicEffectsApi effects;

  /// 播放补全端点组：音效商城目录（getModel）与听歌识曲入口都走它；
  /// null 时对应 tab 与入口隐藏。
  final MusicPlaybackExtApi? playbackExt;

  @override
  State<MusicEffectsPage> createState() => _MusicEffectsPageState();
}

class _MusicEffectsPageState extends State<MusicEffectsPage>
    with SingleTickerProviderStateMixin {
  /// 音效列表页大小（audio_effect.rs paging 上限 50，目录页取常用值）。
  static const int _effectPageSize = 30;

  /// 品牌列表页大小（品牌条目少，直接取协议上限）。
  static const int _brandPageSize = 50;

  /// 音效商城排序码：上游白名单 2/3/4，语义由服务端定义，UI 固定取 2。
  static const int _marketSort = 2;

  late final TabController _tabController = TabController(
    length: widget.playbackExt == null ? 2 : 3,
    vsync: this,
  );

  // —— 三个 section（互不阻塞，独立三态） ——
  final _PagedSection<MusicEffect> _market = _PagedSection<MusicEffect>();
  final _PagedSection<MusicEarphoneBrand> _brands =
      _PagedSection<MusicEarphoneBrand>();
  bool _matchLoading = false;
  Object? _matchError;
  bool _matchLoaded = false;
  MusicEffect? _matched;

  @override
  void initState() {
    super.initState();
    if (widget.playbackExt != null) _refreshMarket();
    _refreshBrands();
    _loadMatch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── 音效商城（getModel 分页） ─────────────────────────────────────────

  Future<void> _refreshMarket() {
    _market
      ..items = List<MusicEffect>.empty()
      ..nextPage = 1
      ..hasMore = false
      ..moreError = null
      ..loadingMore = false;
    return _loadMarketPage();
  }

  Future<void> _loadMarketPage() async {
    final playbackExt = widget.playbackExt;
    if (playbackExt == null) return;
    await _loadPage(
      section: _market,
      first: () => playbackExt.getModel(
        GetModelQuery(page: 1, pageSize: _effectPageSize, sort: _marketSort),
      ),
      more: (page) => playbackExt.getModel(
        GetModelQuery(page: page, pageSize: _effectPageSize, sort: _marketSort),
      ),
    );
  }

  // ── 耳机品牌（effectsBrand 分页） ─────────────────────────────────────

  Future<void> _refreshBrands() {
    _brands
      ..items = List<MusicEarphoneBrand>.empty()
      ..nextPage = 1
      ..hasMore = false
      ..moreError = null
      ..loadingMore = false;
    return _loadBrandsPage();
  }

  Future<void> _loadBrandsPage() async {
    await _loadPage(
      section: _brands,
      first: () => widget.effects.effectsBrand(
        const EffectsBrandQuery(page: 1, pageSize: _brandPageSize),
      ),
      more: (page) => widget.effects.effectsBrand(
        EffectsBrandQuery(page: page, pageSize: _brandPageSize),
      ),
    );
  }

  // ── 设备匹配（effectsMatch 单次） ─────────────────────────────────────

  Future<void> _loadMatch() async {
    setState(() {
      _matchLoading = true;
      _matchError = null;
    });
    try {
      final match = await widget.effects.effectsMatch();
      if (!mounted) return;
      setState(() {
        _matched = match;
        _matchLoaded = true;
        _matchLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _matchError = error;
        _matchLoading = false;
      });
    }
  }

  // ── 分页装载（market / brands 共用） ──────────────────────────────────

  /// 追加一页：首页失败进错误态（可整页重试）；加载更多失败只进页脚
  /// （不清列表，保留已加载内容）。
  Future<void> _loadPage<T>({
    required _PagedSection<T> section,
    required Future<MusicPage<T>> Function() first,
    required Future<MusicPage<T>> Function(int page) more,
  }) async {
    final page = section.nextPage;
    final firstPage = page == 1;
    setState(() {
      if (firstPage) {
        section
          ..loading = true
          ..error = null;
      } else {
        section
          ..loadingMore = true
          ..moreError = null;
      }
    });
    try {
      final result = await (firstPage ? first() : more(page));
      if (!mounted) return;
      setState(() {
        section
          ..loading = false
          ..loadingMore = false
          ..moreError = null
          ..items = <T>[...section.items, ...result.items]
          ..nextPage = page + 1;
        // total 优先：目录给了总数就按总数收口；没给就按「整页满」推测
        // 还有下一页（下一页为空时自然收口）。
        final total = result.total;
        section.hasMore = total != null
            ? section.items.length < total
            : result.items.length == (result.pageSize ?? 0);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (firstPage) {
          section
            ..loading = false
            ..error = error
            ..hasMore = false;
        } else {
          section
            ..loadingMore = false
            ..moreError = error;
        }
      });
    }
  }

  // ── 骨架 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasMarket = widget.playbackExt != null;
    final tabs = <Widget>[
      if (hasMarket) const Tab(text: '音效商城'),
      const Tab(text: '耳机品牌'),
      const Tab(text: '设备匹配'),
    ];
    final views = <Widget>[
      if (hasMarket) _buildMarketTab(),
      _buildBrandsTab(),
      _buildMatchTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('音效商城'),
        actions: <Widget>[
          if (widget.playbackExt != null)
            IconButton(
              key: const Key('effects-match-entry'),
              tooltip: '听歌识曲',
              icon: const Icon(Icons.mic_outlined),
              onPressed: _openAudioMatch,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(controller: _tabController, children: views),
          ),
        ],
      ),
    );
  }

  void _openAudioMatch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/audio-match'),
        builder: (context) =>
            MusicAudioMatchPage(playbackExt: widget.playbackExt!),
      ),
    );
  }

  void _openBrand(MusicEarphoneBrand brand) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/effects-brand'),
        builder: (context) =>
            MusicEffectsBrandPage(effects: widget.effects, brand: brand),
      ),
    );
  }

  /// 音效商城 tab：分页卡片列表（加载更多页脚）。
  Widget _buildMarketTab() {
    return _buildEffectListTab(
      section: _market,
      listKey: 'effects-market-list',
      moreKey: 'effects-market-more',
      emptyText: '暂无音效',
      errorPrefix: '音效商城加载失败',
      onLoadMore: _loadMarketPage,
      onRetry: () => _refreshMarket(),
    );
  }

  /// 耳机品牌 tab：品牌行，点击进入型号音效列表。
  Widget _buildBrandsTab() {
    final section = _brands;
    Widget body;
    if (section.loading) {
      body = const _ListPlaceholder();
    } else if (section.error != null) {
      body = _StateView(
        key: const Key('effects-brand-error'),
        message: '耳机品牌加载失败：${section.error}',
        onRetry: _refreshBrands,
      );
    } else if (section.items.isEmpty) {
      body = const _StateView(message: '暂无耳机品牌');
    } else {
      body = ListView.builder(
        key: const Key('effects-brand-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: section.items.length + (section.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == section.items.length) {
            return _buildMoreFooter(
              key: const Key('effects-brand-more'),
              section: section,
              onLoadMore: _loadBrandsPage,
            );
          }
          final brand = section.items[index];
          return ListTile(
            leading: _EffectIcon(url: brand.iconUrl, size: 44),
            title: Text(
              brand.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: brand.modelCount == null
                ? null
                : Text('${brand.modelCount} 个型号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBrand(brand),
          );
        },
      );
    }
    return body;
  }

  /// 设备匹配 tab：命中一张音效卡；未命中空态 + 重新匹配。
  Widget _buildMatchTab() {
    Widget body;
    if (_matchLoading) {
      body = const _StateView(message: '正在匹配设备…');
    } else if (_matchError != null) {
      body = _StateView(
        key: const Key('effects-match-error'),
        message: '设备匹配失败：$_matchError',
        onRetry: _loadMatch,
      );
    } else if (!_matchLoaded) {
      body = const SizedBox.shrink();
    } else if (_matched == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.headphones,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('当前设备未匹配到耳机音效'),
            const SizedBox(height: 4),
            Text(
              '连接耳机后可重新匹配',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('effects-match-retry'),
              onPressed: _loadMatch,
              child: const Text('重新匹配'),
            ),
          ],
        ),
      );
    } else {
      body = ListView(
        key: const Key('effects-match-card'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[_EffectCard(effect: _matched!)],
      );
    }
    return body;
  }

  /// 分页音效列表 tab 的通用骨架（音效商城；品牌详情页同构另有一份）。
  Widget _buildEffectListTab({
    required _PagedSection<MusicEffect> section,
    required String listKey,
    required String moreKey,
    required String emptyText,
    required String errorPrefix,
    required VoidCallback onLoadMore,
    required VoidCallback onRetry,
  }) {
    Widget body;
    if (section.loading) {
      body = const _ListPlaceholder();
    } else if (section.error != null) {
      body = _StateView(
        message: '$errorPrefix：${section.error}',
        onRetry: onRetry,
      );
    } else if (section.items.isEmpty) {
      body = _StateView(message: emptyText);
    } else {
      body = ListView.builder(
        key: Key(listKey),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: section.items.length + (section.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == section.items.length) {
            return _buildMoreFooter(
              key: Key(moreKey),
              section: section,
              onLoadMore: onLoadMore,
            );
          }
          return _EffectCard(effect: section.items[index]);
        },
      );
    }
    return body;
  }

  /// 分页页脚：加载更多 / 加载中 / 失败重试（失败不清列表）。
  Widget _buildMoreFooter({
    required Key key,
    required _PagedSection<dynamic> section,
    required VoidCallback onLoadMore,
  }) {
    if (section.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: Text('正在加载更多…')),
      );
    }
    if (section.moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('加载更多失败，点此重试'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        key: key,
        onPressed: onLoadMore,
        child: const Text('加载更多'),
      ),
    );
  }
}

/// 一个分页 section 的状态：首屏三态 + 追加页页脚状态。
class _PagedSection<T> {
  bool loading = false;
  Object? error;
  List<T> items = List<T>.empty();
  bool loadingMore = false;
  Object? moreError;
  bool hasMore = false;
  int nextPage = 1;
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

/// 首屏加载占位：静态灰块（不用 indeterminate 进度条，避免 pumpAndSettle
/// 不收敛；与发现页同款取舍）。
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

/// 音效卡：icon + 名称 + 作者 + 标签 chips + 使用人数；
/// `unavailableReason` 非空时主体置灰、原因行单独显示（保持可读）。
/// 卡片不可点——音效不是歌曲，不接播放链路。
class _EffectCard extends StatelessWidget {
  const _EffectCard({required this.effect});

  final MusicEffect effect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unavailableReason = effect.unavailableReason;
    final main = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
              // 不可用音效整块压暗；原因行放灰块外保持可读。
              Opacity(
                opacity: unavailableReason == null ? 1 : 0.45,
                child: main,
              ),
              if (effect.labels.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final label in effect.labels) _LabelChip(label: label),
                  ],
                ),
              ],
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

/// 标签 chip（小号，避免挤爆窄屏卡片）。
class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 音效/品牌图标：无 URL / 加载失败回退均衡器占位（与发现页封面同款
/// errorBuilder + loadingBuilder 模式）。
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

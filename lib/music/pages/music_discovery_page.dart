// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐发现页（U1）：AppBar + SearchBar + 入口网格 + 每日推荐长条。
///
/// 搜索分类 Tab 已取消：发现页 SearchBar 只负责输入 / 建议 chips / 提交，
/// 提交（以及建议词、热搜页点词）统一 push [MusicDiscoverySearchPage]，歌曲
/// 搜索结果、历史、收藏都在搜索页完成。
///
/// 页面只依赖注入的接口（[MusicSearchExtApi]/[MusicDiscoveryApi]/
/// [MusicPlayerUi]/[MusicCollectApi]/[MusicSearchHistoryApi]），不 import
/// 播放器与库服务的实现——与 P/C 线保持编译隔离。
///
/// 入口网格（3 列圆角小方块：首页发现 / 风格推荐 / AI 免费畅听 / 私人 FM /
/// 热门搜索 / 排行榜）的 4 个内容入口在 initState 并行预取一次封面（取列表
/// 第一首的 coverUrl），封面铺满 + 底部渐变遮罩 + 标签；预取失败静默，回退
/// 现有 icon 卡。同一份预览数据作为长条列表页的 initialSongs——保证卡片封面
/// 与列表第一首一致。每日推荐仍留在本页：独立 loading/error/retry，空数据
/// 隐藏，下拉刷新重取。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/api/home_discover.dart';
import 'package:mimao/music/api/personal_fm.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';
import 'package:mimao/music/pages/music_discovery_mappers.dart';
import 'package:mimao/music/pages/music_discovery_search_page.dart';
import 'package:mimao/music/pages/music_hot_search_page.dart';
import 'package:mimao/music/pages/music_style_discovery_page.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 音乐发现页：入口网格 + 每日推荐；搜索统一交给搜索结果页。回调按集成者
/// 契约接线，null 时对应功能降级（入口不显示 / 行可点但不跳转）。
class MusicDiscoveryPage extends StatefulWidget {
  const MusicDiscoveryPage({
    super.key,
    required this.searchExt,
    required this.discovery,
    required this.store,
    required this.player,
    this.collect,
    this.searchHistory,
    this.onOpenRank,
    this.authEpoch,
  });

  /// 搜索扩展端点组（默认词/热词/建议；搜索页只用建议）。
  final MusicSearchExtApi searchExt;

  /// 发现/推荐端点组（首页发现/每日推荐/AI 畅听/私人 FM/风格推荐）。
  final MusicDiscoveryApi discovery;

  /// 歌曲搜索状态（MobX）；原样传给搜索页，跨页保持。
  final MusicStore store;

  /// 播放 UI：点歌后 playSong 并 push 播放页。
  final MusicPlayerUi player;

  /// 收藏门面；原样传给搜索页（null 时搜索行不显示收藏按钮）。
  final MusicCollectApi? collect;

  /// 搜索历史；原样传给搜索页（null 时不记录、不展示历史词）。
  final MusicSearchHistoryApi? searchHistory;

  /// 打开榜单页（入口网格「排行榜」入口；null 时不显示入口）。
  final VoidCallback? onOpenRank;

  /// 登录态变化信号：转发给私人 FM 长条页，并重取 FM 入口卡封面预览。
  final ValueListenable<int>? authEpoch;

  @override
  State<MusicDiscoveryPage> createState() => _MusicDiscoveryPageState();
}

class _MusicDiscoveryPageState extends State<MusicDiscoveryPage> {
  /// 建议防抖间隔；输入停顿后请求 searchSuggest，取消旧请求靠 stale 检查。
  static const Duration _suggestDebounce = Duration(milliseconds: 400);

  late final TextEditingController _controller = TextEditingController();
  Timer? _suggestTimer;

  /// 当前展开的建议词（输入变化防抖后刷新；提交/清空时收回）。
  List<String> _suggestions = const <String>[];

  /// 最近一次提交的关键词（建议 stale 判断沿用原逻辑）。
  String _submittedKeyword = '';

  // —— 发现 tab 内联的唯一推荐 section，独立 loading/error ——
  final _AsyncList<MusicDiscoverySong> _dailySongs =
      _AsyncList<MusicDiscoverySong>();

  // —— 4 个内容入口的封面预览（同一份数据作为对应长条页的 initialSongs） ——
  _EntryPreview _homePreview = const _EntryPreview();
  _EntryPreview _stylePreview = const _EntryPreview();
  _EntryPreview _aiPreview = const _EntryPreview();
  _EntryPreview _fmPreview = const _EntryPreview();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadDailySongs();
    // 并行预取 4 个入口封面；失败静默，入口仍可点（回退 icon 卡）。
    _prefetchHome();
    _prefetchStyle();
    _prefetchAi();
    _prefetchFm();
    // 登录态变化时只重取 FM 预览（FM 是唯一要账号的入口）。
    widget.authEpoch?.addListener(_onAuthEpochChanged);
  }

  @override
  void dispose() {
    widget.authEpoch?.removeListener(_onAuthEpochChanged);
    _suggestTimer?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onAuthEpochChanged() => _prefetchFm();

  // ── 数据装载 ──────────────────────────────────────────────────────────

  /// 每日推荐的首次装载、下拉刷新与重试共用；失败只影响自己。
  Future<void> _loadDailySongs() => _load(
    _dailySongs,
    () async => (await widget.discovery.everydayRecommend()).songs,
  );

  /// 预览请求的统一包装：失败静默（FM 未登录会失败 → 无封面，不报错、不挡页）。
  Future<void> _preview(
    Future<List<MusicSong>> Function() task,
    void Function(List<MusicSong>) assign,
  ) async {
    try {
      final songs = await task();
      if (!mounted) return;
      setState(() => assign(songs));
    } on Object {
      // 预览失败不影响入口可点；对应卡片保持 icon 回退。
    }
  }

  Future<void> _prefetchHome() => _preview(
    () async => <MusicSong>[
      for (final item in (await widget.discovery.homeDiscover(
        const HomeDiscoverQuery(pageSize: 20),
      )).items)
        discoverySongToMusicSong(item.song.song),
    ],
    (songs) => _homePreview = _EntryPreview(songs: songs),
  );

  Future<void> _prefetchStyle() => _preview(
    () async => <MusicSong>[
      for (final item in (await widget.discovery.everydayStyleRecommend(
        const EverydayStyleRecommendQuery(),
      )).songs)
        discoverySongToMusicSong(item.song),
    ],
    (songs) => _stylePreview = _EntryPreview(songs: songs),
  );

  Future<void> _prefetchAi() => _preview(
    () async => <MusicSong>[
      for (final item in (await widget.discovery.aiRecommendSongs()).songs)
        discoverySongToMusicSong(item.song),
    ],
    (songs) => _aiPreview = _EntryPreview(songs: songs),
  );

  Future<void> _prefetchFm() => _preview(
    () async => <MusicSong>[
      for (final item in (await widget.discovery.personalFm(
        const MusicPersonalFmQuery(),
      )).songs)
        discoverySongToMusicSong(item.song.song),
    ],
    (songs) => _fmPreview = _EntryPreview(songs: songs),
  );

  /// 跑一个 section 的加载：独立 loading/错误态，失败只影响自己。
  Future<void> _load<T>(
    _AsyncList<T> section,
    Future<List<T>> Function() task,
  ) async {
    section
      ..loading = true
      ..error = null;
    if (mounted) setState(() {});
    try {
      final items = await task();
      section
        ..items = items
        ..loading = false;
    } on Object catch (error) {
      section
        ..items = List<T>.empty()
        ..error = error
        ..loading = false;
    }
    if (mounted) setState(() {});
  }

  // ── 入口网格 / 子页导航 ────────────────────────────────────────────────

  /// 入口网格的条目；排行榜只在回调接线时出现，点击直接回调不建页面。
  /// 4 个内容入口带预览封面（第一首歌），热搜/排行榜保持 icon 卡。
  List<_DiscoveryEntry> get _entries => <_DiscoveryEntry>[
    _DiscoveryEntry(
      keyName: 'discover-entry-home',
      shortName: 'home',
      icon: Icons.explore_outlined,
      label: '首页发现',
      coverUrl: _homePreview.coverUrl,
      onTap: _openHomeDiscover,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-style',
      shortName: 'style',
      icon: Icons.palette_outlined,
      label: '风格推荐',
      coverUrl: _stylePreview.coverUrl,
      onTap: _openStylePage,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-ai',
      shortName: 'ai',
      icon: Icons.smart_toy_outlined,
      label: 'AI 免费畅听',
      coverUrl: _aiPreview.coverUrl,
      onTap: _openAiSongs,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-fm',
      shortName: 'fm',
      icon: Icons.podcasts_outlined,
      label: '私人 FM',
      coverUrl: _fmPreview.coverUrl,
      onTap: _openPersonalFm,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-hot',
      icon: Icons.local_fire_department_outlined,
      label: '热门搜索',
      onTap: _openHotSearch,
    ),
    if (widget.onOpenRank != null)
      _DiscoveryEntry(
        keyName: 'discover-entry-rank',
        icon: Icons.leaderboard_outlined,
        label: '排行榜',
        onTap: () => widget.onOpenRank!.call(),
      ),
  ];

  /// 首页发现：预览批次立即显示，后台分批拉到 ≥24 首（每批 8，最多 6 批）。
  void _openHomeDiscover() => _pushListPage(
    title: '首页发现',
    initialSongs: _homePreview.songs,
    targetCount: 24,
    maxBatches: 6,
    loadMore: () async => <MusicSong>[
      for (final item in (await widget.discovery.homeDiscover(
        const HomeDiscoverQuery(pageSize: 20),
      )).items)
        discoverySongToMusicSong(item.song.song),
    ],
  );

  /// AI 免费畅听：预览批次（30 首）直接作为初始数据，目标 30，不再追加。
  /// 仍给一次性 loadMore 兜底：预览失败（空列表）时点进去仍能拉到数据。
  void _openAiSongs() => _pushListPage(
    title: 'AI 免费畅听',
    initialSongs: _aiPreview.songs,
    targetCount: 30,
    maxBatches: 1,
    loadMore: () async => <MusicSong>[
      for (final item in (await widget.discovery.aiRecommendSongs()).songs)
        discoverySongToMusicSong(item.song),
    ],
  );

  /// 私人 FM：预览批次作为初始数据，后台拉到 ≥20 首（每批 5，最多 8 批）；
  /// 「换一批」清空后重新拉满；监听 authEpoch 登录/切号后自动重拉。
  void _openPersonalFm() => _pushListPage(
    title: '私人 FM',
    refreshLabel: '换一批',
    authEpoch: widget.authEpoch,
    initialSongs: _fmPreview.songs,
    targetCount: 20,
    maxBatches: 8,
    loadMore: () async => <MusicSong>[
      for (final item in (await widget.discovery.personalFm(
        const MusicPersonalFmQuery(),
      )).songs)
        discoverySongToMusicSong(item.song.song),
    ],
  );

  /// push 一个通用长条列表页（首页发现 / AI 畅听 / 私人 FM 共用）。
  void _pushListPage({
    required String title,
    required Future<List<MusicSong>> Function() loadMore,
    required List<MusicSong> initialSongs,
    required int targetCount,
    required int maxBatches,
    String? refreshLabel,
    ValueListenable<int>? authEpoch,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicDiscoveryListPage(
          title: title,
          player: widget.player,
          initialSongs: initialSongs,
          loadMore: loadMore,
          targetCount: targetCount,
          maxBatches: maxBatches,
          refreshLabel: refreshLabel,
          authEpoch: authEpoch,
        ),
      ),
    );
  }

  /// 风格推荐：标签 chips + 歌曲长条（逻辑在风格推荐页内；预览只用于封面）。
  void _openStylePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicStyleDiscoveryPage(
          discovery: widget.discovery,
          player: widget.player,
        ),
      ),
    );
  }

  /// 热门搜索：默认词 + 热搜榜（chips 点词 → [_openSearch] → push 搜索页并
  /// 自动提交该词；热搜页自身负责 pop 返回本页）。
  void _openHotSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicHotSearchPage(
          searchExt: widget.searchExt,
          onSearch: _openSearch,
        ),
      ),
    );
  }

  // ── 搜索流程 ──────────────────────────────────────────────────────────

  /// push 搜索结果页并预填关键词（搜索页 initState 自动提交）。
  void _openSearch(String keyword) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicDiscoverySearchPage(
          searchExt: widget.searchExt,
          store: widget.store,
          player: widget.player,
          collect: widget.collect,
          searchHistory: widget.searchHistory,
          initialKeyword: keyword,
        ),
      ),
    );
  }

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    _suggestTimer?.cancel();
    if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = const <String>[]);
    }
    _submittedKeyword = keyword;
    _openSearch(keyword);
  }

  /// 建议词的统一入口：填入搜索框并提交（搜索历史词在搜索页内处理）。
  void _applyKeyword(String keyword) {
    _controller
      ..text = keyword
      ..selection = TextSelection.collapsed(offset: keyword.length);
    _submit();
  }

  /// 输入变化：防抖拉建议；提交词/空串时收回建议。
  void _onQueryChanged() {
    _suggestTimer?.cancel();
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || keyword == _submittedKeyword) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const <String>[]);
      }
      return;
    }
    _suggestTimer = Timer(_suggestDebounce, () => _loadSuggestions(keyword));
  }

  Future<void> _loadSuggestions(String keyword) async {
    try {
      final result = await widget.searchExt.searchSuggest(
        MusicSearchSuggestQuery(keyword: keyword),
      );
      // stale：响应回来时输入已经变了（或已提交）就丢弃。
      if (!mounted || _controller.text.trim() != keyword) return;
      final words = <String>[];
      for (final group in result.groups) {
        for (final item in group.items) {
          final text = displayTitle(item.text).trim();
          if (text.isNotEmpty && !words.contains(text)) {
            words.add(text);
          }
          if (words.length >= 10) break;
        }
        if (words.length >= 10) break;
      }
      setState(() => _suggestions = words);
    } on Object {
      // 建议失败不影响主流程：静默收回旧建议。
      if (mounted) setState(() => _suggestions = const <String>[]);
    }
  }

  // ── 播放 ──────────────────────────────────────────────────────────────

  /// 点歌：先起播（地址异步解析）再打开播放页——与模块页 M4-P 行为一致。
  void _openSong(MusicSong song) {
    widget.player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  // ── 骨架 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发现音乐')),
      body: Column(
        // stretch 与模块搜索页同构；SearchBar 默认 maxWidth 800 在桌面宽窗
        // 会卡在居中位置，补 stretch 消除左右留白。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _controller,
              hintText: '搜索歌曲',
              leading: const Icon(Icons.search),
              trailing: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: '搜索',
                  onPressed: _submit,
                ),
              ],
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
            ),
          ),
          _buildSuggestionBar(),
          Expanded(child: _buildDiscoverTab()),
        ],
      ),
    );
  }

  /// 建议词条：SearchBar 下方的横向 chips；空时不占位。
  Widget _buildSuggestionBar() {
    final suggestions = _suggestions;
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          for (final word in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: Text(word),
                visualDensity: VisualDensity.compact,
                onPressed: () => _applyKeyword(word),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab() {
    return RefreshIndicator(
      onRefresh: _loadDailySongs,
      child: ListView(
        key: const Key('discover-scroll'),
        // 内容不足一屏时也要能下拉刷新（入口+每日推荐在宽屏很容易填不满）。
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[_buildEntryGrid(), _buildDailySection()],
      ),
    );
  }

  /// 入口网格：宽屏 6 列（一行放下全部入口）、中屏 4 列、窄屏 3 列；
  /// shrinkWrap + 不滚动，随发现页整体滚动。封面卡用正方形，避免桌面宽窗
  /// 下单卡被拉成巨幅壁纸。
  Widget _buildEntryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 6
            : width >= 720
            ? 4
            : 3;
        return GridView.count(
          key: const Key('discover-entry-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            for (final entry in _entries) _buildEntryCard(entry),
          ],
        );
      },
    );
  }

  Widget _buildEntryCard(_DiscoveryEntry entry) {
    return Card(
      key: Key(entry.keyName),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
      child: InkWell(
        onTap: entry.onTap,
        child: entry.coverUrl.isEmpty
            ? _buildIconEntry(entry)
            : _buildCoverEntry(entry),
      ),
    );
  }

  /// 无封面（含预取失败）回退现有 icon 卡。
  Widget _buildIconEntry(_DiscoveryEntry entry) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(entry.icon, size: 28),
          const SizedBox(height: 6),
          Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// 有封面：铺满 + 底部渐变遮罩 + 标签。Image.network 同时给 errorBuilder /
  /// loadingBuilder（widget 测试无网络时回退 icon 布局，不闪空块、不报错）。
  Widget _buildCoverEntry(_DiscoveryEntry entry) {
    final theme = Theme.of(context);
    final fallback = _buildIconEntry(entry);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: Image.network(
            entry.coverUrl,
            key: Key('discover-entry-cover-${entry.shortName}'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : fallback,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 更实的底部遮罩：浅色封面（人像/白底专辑）上的白字也能读清。
                colors: <Color>[Colors.transparent, Color(0xF2000000)],
                stops: <double>[0.45, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 每日推荐：独立 loading/error/retry，空数据隐藏；下拉刷新走 tab 的
  /// RefreshIndicator。
  Widget _buildDailySection() {
    final section = _dailySongs;
    if (!_sectionVisible(section)) return const SizedBox.shrink();
    return _SectionBlock(
      key: const Key('discover-daily'),
      title: '每日推荐',
      child: _sectionBody(
        section: section,
        loading: const _ListPlaceholder(),
        empty: const SizedBox.shrink(),
        content: () => Column(
          children: <Widget>[
            for (final item in section.items) _dailyTile(item),
          ],
        ),
        onRetry: _loadDailySongs,
      ),
    );
  }

  DiscoverySongTile _dailyTile(MusicDiscoverySong item) {
    final song = discoverySongToMusicSong(item.song);
    return DiscoverySongTile(song: song, onTap: () => _openSong(song));
  }

  /// section 是否值得渲染：loading/有错误/有数据三种都要占位；
  /// 全空（未加载到内容且无错误）时整块隐藏，不留下光秃秃的标题。
  bool _sectionVisible<T>(_AsyncList<T> section) =>
      section.loading || section.error != null || section.items.isNotEmpty;

  /// section 内部三态的小号骨架：loading 占位 / 错误行 / 空态替换 / 正常内容。
  Widget _sectionBody<T>({
    required _AsyncList<T> section,
    required Widget loading,
    required Widget empty,
    required Widget Function() content,
    required VoidCallback onRetry,
  }) {
    if (section.loading) return loading;
    final error = section.error;
    if (error != null) {
      return DiscoverySectionError(error: error, onRetry: onRetry);
    }
    if (section.items.isEmpty) return empty;
    return content();
  }
}

// ── 小组件 ────────────────────────────────────────────────────────────────

/// 一份 section 的独立三态（loading/error/items）；不接 MobX——发现页的
/// sections 生命周期跟页面走，plain State + setState 足够。
class _AsyncList<T> {
  bool loading = false;
  Object? error;
  List<T> items = List<T>.empty();
}

/// 一份入口预览（歌曲列表）；coverUrl 取第一首，空列表回退 icon 卡。
class _EntryPreview {
  const _EntryPreview({this.songs = const <MusicSong>[]});

  final List<MusicSong> songs;

  String get coverUrl => songs.isEmpty ? '' : songs.first.coverUrl;
}

/// 入口网格的条目。
class _DiscoveryEntry {
  const _DiscoveryEntry({
    required this.keyName,
    required this.label,
    required this.onTap,
    this.shortName = '',
    this.icon = Icons.widgets_outlined,
    this.coverUrl = '',
  });

  /// 测试定位用 key（`discover-entry-*`）。
  final String keyName;

  /// 封面 key 的短名（`discover-entry-cover-<shortName>`）；icon 卡可留空。
  final String shortName;

  final IconData icon;
  final String label;
  final String coverUrl;
  final VoidCallback onTap;
}

/// section 标题行（每日推荐用）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

/// 带标题的 section 块（每日推荐用；key 供测试定位）。
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(title: title),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// 纵向长条区的加载占位：静态灰块（不用 indeterminate 进度条，
/// 避免 pumpAndSettle 不收敛、也让占位与真实行高接近不跳版）。
class _ListPlaceholder extends StatelessWidget {
  const _ListPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (final _ in List<int>.generate(3, (index) => index))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 72,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: MimaoShapes.sm,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

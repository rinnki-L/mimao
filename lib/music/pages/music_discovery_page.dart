// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐发现页（U1）：发现入口网格 + 每日推荐长条 + 搜索扩展
/// （歌曲/专辑/歌手/歌单/歌词）。
///
/// 页面只依赖注入的接口（[MusicSearchExtApi]/[MusicDiscoveryApi]/
/// [MusicPlayerUi]/[MusicLyricApi]/[MusicCollectApi]/[MusicSearchHistoryApi]），
/// 不 import 播放器与库服务的实现——与 P/C 线保持编译隔离。
///
/// 结构：顶部 SearchBar + 六个 tab（发现 / 歌曲 / 专辑 / 歌手 / 歌单 / 歌词）。
/// 「发现」tab 不再横向铺开推荐卡片：顶部保留音效商城入口卡，其下是 3 列
/// 圆角小方块入口网格（首页发现 / 风格推荐 / AI 免费畅听 / 私人 FM /
/// 热门搜索 / 排行榜），推荐内容收进各自入口页——通用长条列表页
/// （`music_discovery_list_page.dart`）、风格推荐页
/// （`music_style_discovery_page.dart`）、热门搜索页
/// （`music_hot_search_page.dart`）。每日推荐仍留在本 tab，但改为与收藏同款
/// 的纵向长条列表：独立 loading/error/retry，空数据隐藏，下拉刷新重取。
/// 搜索提交后按关键词填充五个搜索 tab；热搜页点词同样经
/// [_applyKeyword] 触发搜索并返回发现页。与模块页（搜索页）的区别：本页
/// 聚焦发现与扩展搜索，歌曲搜索结果复用 [MusicStore]。
///
/// 模型 → [MusicSong] 的映射走 `music_discovery_mappers.dart`
/// （[discoverySongToMusicSong]），不改共享模型。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/home_discover.dart';
import 'package:mimao/music/api/lyric.dart';
import 'package:mimao/music/api/lyric_api.dart';
import 'package:mimao/music/api/personal_fm.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/lyric_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';
import 'package:mimao/music/pages/music_discovery_mappers.dart';
import 'package:mimao/music/pages/music_hot_search_page.dart';
import 'package:mimao/music/pages/music_style_discovery_page.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 音乐发现页：发现入口网格 + 每日推荐 + 搜索扩展。回调按集成者契约接线，
/// null 时对应功能降级（入口不显示 / 行可点但不跳转 / 按钮不显示）。
class MusicDiscoveryPage extends StatefulWidget {
  const MusicDiscoveryPage({
    super.key,
    required this.searchExt,
    required this.discovery,
    required this.store,
    required this.player,
    this.lyric,
    this.collect,
    this.searchHistory,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onOpenPlaylist,
    this.onOpenRank,
    this.onOpenEffects,
    this.authEpoch,
  });

  /// 搜索扩展端点组（默认词/热词/建议/专辑/歌手/歌单/歌词候选）。
  final MusicSearchExtApi searchExt;

  /// 发现/推荐端点组（首页发现/每日推荐/AI 畅听/私人 FM）。
  final MusicDiscoveryApi discovery;

  /// 歌曲搜索状态（MobX）；搜索 tab 的结果/加载/错误态都来自这里。
  final MusicStore store;

  /// 播放 UI：点歌后 playSong 并 push 播放页。
  final MusicPlayerUi player;

  /// 歌词下载；null 时歌词候选点击提示「未接线」。
  final MusicLyricApi? lyric;

  /// 收藏门面；null 时歌曲行不显示收藏按钮。
  final MusicCollectApi? collect;

  /// 搜索历史；null 时不记录、不展示历史词。
  final MusicSearchHistoryApi? searchHistory;

  /// 打开专辑详情页（酷狗专辑 id；搜索专辑行点击）。
  final ValueChanged<int>? onOpenAlbum;

  /// 打开歌手详情页（酷狗歌手 id；搜索歌手行点击）。
  final ValueChanged<int>? onOpenArtist;

  /// 打开公开歌单页（SearchPlaylists 只产出摘要，这里传
  /// `global_collection_id`；契约原为 `MusicPlaylistDetail`，见交付报告）。
  final ValueChanged<String>? onOpenPlaylist;

  /// 打开榜单页（入口网格「排行榜」入口；null 时不显示入口）。
  final VoidCallback? onOpenRank;

  /// 打开音效商城（L1 音效页，含耳机品牌/设备匹配）；null 时入口卡整体隐藏。
  final VoidCallback? onOpenEffects;

  /// 登录态变化信号：转发给私人 FM 长条页，登录/切号后自动重拉
  /// （FM 是唯一要账号的入口）；null 时保持旧行为（只在进入入口页时取）。
  final ValueListenable<int>? authEpoch;

  @override
  State<MusicDiscoveryPage> createState() => _MusicDiscoveryPageState();
}

class _MusicDiscoveryPageState extends State<MusicDiscoveryPage>
    with SingleTickerProviderStateMixin {
  static const int _discoverTabIndex = 0;
  static const int _songsTabIndex = 1;

  /// 响应式断点：歌曲结果 ≥720 双列。
  static const double _songTwoColumnBreakpoint = 720;

  /// 建议防抖间隔；输入停顿后请求 searchSuggest，取消旧请求靠 cancel + stale 检查。
  static const Duration _suggestDebounce = Duration(milliseconds: 400);

  late final TabController _tabController = TabController(
    length: 6,
    vsync: this,
  );
  late final TextEditingController _controller = TextEditingController();
  Timer? _suggestTimer;

  /// 当前展开的建议词（输入变化防抖后刷新；提交/清空时收回）。
  List<String> _suggestions = const <String>[];

  /// 最近一次提交的关键词（ext section 重试、建议 stale 判断都用它）。
  String _submittedKeyword = '';

  /// 搜索历史词（searchHistory 非空时加载）。
  List<String> _historyWords = const <String>[];

  /// 收藏态缓存（列表批量判断，避免逐行异步查询导致抖动）。
  final Set<String> _collectedIds = <String>{};

  // —— 每日推荐（发现 tab 内联的唯一推荐 section，独立 loading/error） ——
  final _AsyncList<MusicDiscoverySong> _dailySongs =
      _AsyncList<MusicDiscoverySong>();

  // —— 搜索扩展 sections（提交时随 store.search 一起刷新） ——
  final _AsyncList<MusicAlbumSummary> _albums = _AsyncList<MusicAlbumSummary>();
  final _AsyncList<MusicArtistSummary> _artists =
      _AsyncList<MusicArtistSummary>();
  final _AsyncList<MusicPlaylistSummary> _playlists =
      _AsyncList<MusicPlaylistSummary>();
  final _AsyncList<MusicLyricHit> _lyricHits = _AsyncList<MusicLyricHit>();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadDailySongs();
    _loadHistory();
    _loadCollected();
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── 数据装载 ──────────────────────────────────────────────────────────

  /// 每日推荐的首次装载、下拉刷新与重试共用；失败只影响自己。
  Future<void> _loadDailySongs() => _load(
    _dailySongs,
    () async => (await widget.discovery.everydayRecommend()).songs,
  );

  Future<void> _loadHistory() async {
    final history = widget.searchHistory;
    if (history == null) return;
    try {
      final words = await history.recent();
      if (!mounted) return;
      setState(() => _historyWords = words);
    } on Object {
      // 历史读不到不挡搜索。
    }
  }

  Future<void> _clearHistory() async {
    final history = widget.searchHistory;
    if (history == null) return;
    try {
      await history.clear();
    } on Object {
      // 清空失败不弹错——历史只是辅助入口。
    }
    if (!mounted) return;
    setState(() => _historyWords = const <String>[]);
  }

  Future<void> _loadCollected() async {
    final collect = widget.collect;
    if (collect == null) return;
    try {
      final ids = await collect.collectedIds();
      if (!mounted) return;
      setState(() {
        _collectedIds
          ..clear()
          ..addAll(ids);
      });
    } on Object {
      // 收藏态加载失败不挡搜索；图标维持未收藏。
    }
  }

  // ── 入口网格 / 子页导航 ────────────────────────────────────────────────

  /// 入口网格的条目；排行榜只在回调接线时出现，点击直接回调不建页面。
  List<_DiscoveryEntry> get _entries => <_DiscoveryEntry>[
    _DiscoveryEntry(
      keyName: 'discover-entry-home',
      icon: Icons.explore_outlined,
      label: '首页发现',
      onTap: _openHomeDiscover,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-style',
      icon: Icons.palette_outlined,
      label: '风格推荐',
      onTap: _openStylePage,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-ai',
      icon: Icons.smart_toy_outlined,
      label: 'AI 免费畅听',
      onTap: _openAiSongs,
    ),
    _DiscoveryEntry(
      keyName: 'discover-entry-fm',
      icon: Icons.podcasts_outlined,
      label: '私人 FM',
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

  /// 首页发现：入口页展示歌曲长条列表。
  void _openHomeDiscover() => _pushListPage(
    title: '首页发现',
    loader: () async => <MusicSong>[
      for (final item in (await widget.discovery.homeDiscover(
        const HomeDiscoverQuery(),
      )).items)
        discoverySongToMusicSong(item.song.song),
    ],
  );

  /// AI 免费畅听：入口页展示歌曲长条列表。
  void _openAiSongs() => _pushListPage(
    title: 'AI 免费畅听',
    loader: () async => <MusicSong>[
      for (final item in (await widget.discovery.aiRecommendSongs()).songs)
        discoverySongToMusicSong(item.song),
    ],
  );

  /// 私人 FM：长条列表 + 「换一批」刷新；FM 是唯一要账号的入口，长条页
  /// 监听 authEpoch，登录/切号后自动重拉。
  void _openPersonalFm() => _pushListPage(
    title: '私人 FM',
    refreshLabel: '换一批',
    authEpoch: widget.authEpoch,
    loader: () async => <MusicSong>[
      for (final item in (await widget.discovery.personalFm(
        const MusicPersonalFmQuery(),
      )).songs)
        discoverySongToMusicSong(item.song.song),
    ],
  );

  /// push 一个通用长条列表页（首页发现 / AI 畅听 / 私人 FM 共用）。
  void _pushListPage({
    required String title,
    required Future<List<MusicSong>> Function() loader,
    String? refreshLabel,
    ValueListenable<int>? authEpoch,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicDiscoveryListPage(
          title: title,
          player: widget.player,
          loader: loader,
          refreshLabel: refreshLabel,
          authEpoch: authEpoch,
        ),
      ),
    );
  }

  /// 风格推荐：标签 chips + 歌曲长条（逻辑在风格推荐页内）。
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

  /// 热门搜索：默认词 + 热搜榜（chips 点词 → [_applyKeyword] → 返回发现页）。
  void _openHotSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MusicHotSearchPage(
          searchExt: widget.searchExt,
          onSearch: _applyKeyword,
        ),
      ),
    );
  }

  // ── 搜索流程 ──────────────────────────────────────────────────────────

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    _suggestTimer?.cancel();
    if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = const <String>[]);
    }
    _submittedKeyword = keyword;
    widget.store.search(keyword);
    _load(
      _albums,
      () async => (await widget.searchExt.searchAlbums(
        SearchSongsQuery(keyword: keyword),
      )).items,
    );
    _load(
      _artists,
      () async => (await widget.searchExt.searchArtists(
        SearchSongsQuery(keyword: keyword),
      )).items,
    );
    _load(
      _playlists,
      () async => (await widget.searchExt.searchPlaylists(
        SearchSongsQuery(keyword: keyword),
      )).items,
    );
    _load(
      _lyricHits,
      () async => (await widget.searchExt.searchLyrics(
        SearchSongsQuery(keyword: keyword),
      )).items,
    );
    final history = widget.searchHistory;
    if (history != null) {
      history.record(keyword).catchError((Object _) {});
    }
    // 从「发现」tab 提交搜索时自动切到「歌曲」；已在某个搜索 tab 则留在原地。
    if (_tabController.index == _discoverTabIndex) {
      _tabController.animateTo(_songsTabIndex);
    }
  }

  /// 默认词/热词/建议/历史词的统一入口：填入搜索框并提交。
  void _applyKeyword(String keyword) {
    _controller
      ..text = keyword
      ..selection = TextSelection.collapsed(offset: keyword.length);
    _submit();
  }

  /// 输入变化：防抖拉建议（功能 3 可选项）；提交词/空串时收回建议。
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

  // ── 播放 / 收藏 / 跳转 ────────────────────────────────────────────────

  String _songId(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;

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

  Future<void> _toggleCollect(MusicSong song) async {
    final collect = widget.collect;
    if (collect == null) return;
    final id = _songId(song);
    if (id.isEmpty) return;
    final wasCollected = _collectedIds.contains(id);
    setState(() {
      if (wasCollected) {
        _collectedIds.remove(id);
      } else {
        _collectedIds.add(id);
      }
    });
    try {
      if (wasCollected) {
        await collect.remove(id);
      } else {
        await collect.collect(song);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasCollected) {
          _collectedIds.add(id);
        } else {
          _collectedIds.remove(id);
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(wasCollected ? '取消收藏失败：$error' : '收藏失败：$error')),
      );
    }
  }

  /// 歌词命中行点击：拉候选 → 候选 sheet（sheet 内再走 downloadLyric）。
  Future<void> _openLyricCandidates(MusicLyricHit hit) async {
    final lyric = widget.lyric;
    if (lyric == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('歌词下载未接线')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _LyricCandidateSheet(
        searchExt: widget.searchExt,
        lyric: lyric,
        song: hit.song,
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
              hintText: '搜索歌曲 / 专辑 / 歌手 / 歌单 / 歌词',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const <Widget>[
                Tab(text: '发现'),
                Tab(text: '歌曲'),
                Tab(text: '专辑'),
                Tab(text: '歌手'),
                Tab(text: '歌单'),
                Tab(text: '歌词'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildDiscoverTab(),
                LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildSongsTab(constraints.maxWidth),
                ),
                _buildAlbumsTab(),
                _buildArtistsTab(),
                _buildPlaylistsTab(),
                _buildLyricsTab(),
              ],
            ),
          ),
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

  // ── 发现 tab ──────────────────────────────────────────────────────────

  Widget _buildDiscoverTab() {
    return RefreshIndicator(
      onRefresh: _loadDailySongs,
      child: ListView(
        key: const Key('discover-scroll'),
        // 内容不足一屏时也要能下拉刷新（入口+每日推荐在宽屏很容易填不满）。
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          _buildEffectsEntry(),
          _buildEntryGrid(),
          _buildDailySection(),
        ],
      ),
    );
  }

  /// 音效商城入口卡：`onOpenEffects` 接线后出现在发现 tab 顶部（耳机品牌 /
  /// 设备匹配两个子功能的入口在音效页内）；未接线时整体隐藏。
  Widget _buildEffectsEntry() {
    final onOpen = widget.onOpenEffects;
    if (onOpen == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('discover-effects-entry'),
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.graphic_eq),
          title: const Text('音效商城'),
          subtitle: const Text('耳机品牌 / 设备匹配'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
      ),
    );
  }

  /// 入口网格：3 列圆角小方块（shrinkWrap + 不滚动，随发现 tab 整体滚动）。
  /// 推荐内容收进各自入口页，发现 tab 只留「入口 + 每日推荐」。
  Widget _buildEntryGrid() {
    return GridView.count(
      key: const Key('discover-entry-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      padding: const EdgeInsets.only(bottom: 16),
      children: <Widget>[for (final entry in _entries) _buildEntryCard(entry)],
    );
  }

  Widget _buildEntryCard(_DiscoveryEntry entry) {
    final theme = Theme.of(context);
    return Card(
      key: Key(entry.keyName),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
      child: InkWell(
        onTap: entry.onTap,
        child: Padding(
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
        ),
      ),
    );
  }

  /// 每日推荐：留在发现 tab 的唯一推荐 section，改为与收藏同款的纵向长条；
  /// 独立 loading/error/retry，空数据隐藏；下拉刷新走 tab 的 RefreshIndicator。
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

  // ── 歌曲 tab（MusicStore 的搜索结果，Observer 驱动） ───────────────────

  Widget _buildSongsTab(double width) {
    return Observer(
      builder: (context) {
        final store = widget.store;
        if (store.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = store.error;
        if (error != null) {
          return _ErrorState(message: error, onRetry: _submit);
        }
        if (!store.searched) {
          return _buildSearchLanding();
        }
        final results = store.results;
        if (results.isEmpty) {
          return const _EmptyState(message: '没有找到相关歌曲');
        }
        // 宽屏双列：按序号对半拆成两条 ListView（行高一致，拼接后仍是有序列表）。
        if (width >= _songTwoColumnBreakpoint && results.length > 1) {
          final half = (results.length + 1) ~/ 2;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _buildSongList(results.sublist(0, half))),
              Expanded(child: _buildSongList(results.sublist(half))),
            ],
          );
        }
        return _buildSongList(results);
      },
    );
  }

  Widget _buildSongList(List<MusicSong> songs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return _SongTile(
          song: song,
          isCollected: _collectedIds.contains(_songId(song)),
          onToggleCollect: widget.collect == null
              ? null
              : () => _toggleCollect(song),
          onTap: () => _openSong(song),
        );
      },
    );
  }

  /// 未搜索时的落位：搜索历史 chips + 引导文案。
  Widget _buildSearchLanding() {
    final words = _historyWords;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        if (words.isNotEmpty) ...<Widget>[
          _SectionHeader(
            title: '搜索历史',
            trailing: IconButton(
              tooltip: '清空历史',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _clearHistory,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final word in words)
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(word),
                  onPressed: () => _applyKeyword(word),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            '输入关键词开始搜索',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ── 专辑 / 歌手 / 歌单 / 歌词 tab ─────────────────────────────────────

  Widget _buildAlbumsTab() {
    return _buildSearchSectionPage<MusicAlbumSummary>(
      section: _albums,
      emptyText: '没有找到相关专辑',
      retryTask: (keyword) async => (await widget.searchExt.searchAlbums(
        SearchSongsQuery(keyword: keyword),
      )).items,
      itemBuilder: (context, album) => ListTile(
        leading: DiscoverySquareCover(url: album.coverUrl, size: 56),
        title: Text(
          displayTitle(album.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${album.artistText}${album.publishedAt.isEmpty ? '' : ' · ${album.publishedAt}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: album.songCount == null
            ? null
            : Text(
                '${album.songCount}首',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        onTap: () {
          final id = album.id;
          if (id == null) return;
          widget.onOpenAlbum?.call(id);
        },
      ),
    );
  }

  Widget _buildArtistsTab() {
    return _buildSearchSectionPage<MusicArtistSummary>(
      section: _artists,
      emptyText: '没有找到相关歌手',
      retryTask: (keyword) async => (await widget.searchExt.searchArtists(
        SearchSongsQuery(keyword: keyword),
      )).items,
      itemBuilder: (context, artist) {
        final facts = <String>[
          if (artist.albumCount != null) '专辑 ${artist.albumCount}',
          if (artist.songCount != null) '歌曲 ${artist.songCount}',
          if (artist.fans != null) '粉丝 ${artist.fans}',
        ];
        return ListTile(
          leading: _RoundAvatar(url: artist.avatarUrl, size: 48),
          title: Text(
            displayTitle(artist.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: facts.isEmpty
              ? null
              : Text(
                  facts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () {
            final id = artist.id;
            if (id == null) return;
            widget.onOpenArtist?.call(id);
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    return _buildSearchSectionPage<MusicPlaylistSummary>(
      section: _playlists,
      emptyText: '没有找到相关歌单',
      retryTask: (keyword) async => (await widget.searchExt.searchPlaylists(
        SearchSongsQuery(keyword: keyword),
      )).items,
      itemBuilder: (context, playlist) => ListTile(
        leading: DiscoverySquareCover(url: playlist.coverUrl, size: 56),
        title: Text(
          displayTitle(playlist.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${playlist.creatorName}${playlist.songCount == null ? '' : ' · ${playlist.songCount}首'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          final globalId = playlist.globalId;
          if (globalId.isEmpty) return;
          widget.onOpenPlaylist?.call(globalId);
        },
      ),
    );
  }

  Widget _buildLyricsTab() {
    return _buildSearchSectionPage<MusicLyricHit>(
      section: _lyricHits,
      emptyText: '没有找到相关歌词',
      retryTask: (keyword) async => (await widget.searchExt.searchLyrics(
        SearchSongsQuery(keyword: keyword),
      )).items,
      itemBuilder: (context, hit) => ListTile(
        leading: const Icon(Icons.lyrics_outlined),
        title: Text(
          '${displayTitle(hit.song.title)} - ${displayTitle(hit.song.artistText)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          displayTitle(hit.excerpt),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          formatDuration(hit.song.durationMs),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => _openLyricCandidates(hit),
      ),
    );
  }

  /// 搜索扩展 tab 的通用骨架：loading / 错误+重试 / 空态 / 结果列表。
  /// itemBuilder 用组内带类型的签名（IndexedWidgetBuilder 会把条目推断成 int）。
  Widget _buildSearchSectionPage<T>({
    required _AsyncList<T> section,
    required String emptyText,
    required Future<List<T>> Function(String keyword) retryTask,
    required Widget Function(BuildContext context, T item) itemBuilder,
  }) {
    if (section.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = section.error;
    if (error != null) {
      return _ErrorState(
        message: '搜索失败：$error',
        onRetry: () => _retrySearchSection(section, retryTask),
      );
    }
    if (section.items.isEmpty) {
      return _EmptyState(
        message: _submittedKeyword.isEmpty ? '输入关键词开始搜索' : emptyText,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: section.items.length,
      itemBuilder: (context, index) =>
          itemBuilder(context, section.items[index]),
    );
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

  /// 搜索扩展 section 的重试：按最近提交的关键词重跑。
  void _retrySearchSection<T>(
    _AsyncList<T> section,
    Future<List<T>> Function(String keyword) task,
  ) {
    final keyword = _submittedKeyword;
    if (keyword.isEmpty) return;
    _load(section, () => task(keyword));
  }

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
}

// ── 小组件 ────────────────────────────────────────────────────────────────

/// 一份 section 的独立三态（loading/error/items）；不接 MobX——发现页的
/// sections 生命周期跟页面走，plain State + setState 足够。
class _AsyncList<T> {
  bool loading = false;
  Object? error;
  List<T> items = List<T>.empty();
}

/// 入口网格的条目。
class _DiscoveryEntry {
  const _DiscoveryEntry({
    required this.keyName,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// 测试定位用 key（`discover-entry-*`）。
  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// section 标题行（可选 trailing：清空历史等动作）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 带标题的 section 块（发现 tab 每日推荐用；key 供测试定位）。
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

/// 页面级错误态（整 tab 失败时）——与模块搜索页同款。
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态文案。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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

/// 结果行——模块搜索页 `_SongTile` 的重建版（该文件是共享线文件，不 import）。
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.isCollected,
    required this.onTap,
    this.onToggleCollect,
  });

  final MusicSong song;
  final bool isCollected;
  final VoidCallback onTap;

  /// null 表示收藏功能未接线（不显示按钮）。
  final VoidCallback? onToggleCollect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      leading: DiscoverySquareCover(url: song.coverUrl, size: 44),
      title: Text(
        displayTitle(song.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${song.artistText}${song.albumTitle.isEmpty ? '' : ' · ${song.albumTitle}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // 收藏按钮用 filledTonal 的选中态：未收藏描边心形，已收藏 tonal 实底
      // 红心——与模块页同一形态。
      trailing: onToggleCollect != null
          ? IconButton.filledTonal(
              tooltip: isCollected ? '取消收藏' : '收藏',
              isSelected: isCollected,
              selectedIcon: const Icon(Icons.favorite),
              icon: const Icon(Icons.favorite_border),
              onPressed: onToggleCollect,
            )
          : Text(
              formatDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}

/// 圆形头像（歌手）：无头像/加载失败回退人形占位。
class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({required this.url, required this.size});

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
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, color: cs.primary, size: size / 2),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
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

/// 歌词候选底部 sheet：按命中歌曲拉候选（searchLyric），点候选
/// downloadLyric → base64 解码为 UTF-8 文本弹对话框展示。
class _LyricCandidateSheet extends StatefulWidget {
  const _LyricCandidateSheet({
    required this.searchExt,
    required this.lyric,
    required this.song,
  });

  final MusicSearchExtApi searchExt;
  final MusicLyricApi lyric;
  final MusicSong song;

  @override
  State<_LyricCandidateSheet> createState() => _LyricCandidateSheetState();
}

class _LyricCandidateSheetState extends State<_LyricCandidateSheet> {
  bool _loading = true;
  Object? _error;
  bool _downloading = false;
  List<MusicLyricCandidate> _candidates = const <MusicLyricCandidate>[];

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  /// 优先 hash 精确匹配（songId 解析失败按 0 传——上游按原样转发）；
  /// hash 缺失回退关键词模糊匹配。
  MusicSearchLyricQuery get _query {
    final song = widget.song;
    if (song.hash.isNotEmpty) {
      return MusicSearchLyricQuery.hash(
        hash: song.hash,
        songId: int.tryParse(song.id) ?? 0,
        durationMs: song.durationMs ?? 0,
        allCandidates: true,
      );
    }
    return MusicSearchLyricQuery.keywords(
      keywords: song.title,
      durationMs: song.durationMs ?? 0,
      allCandidates: true,
    );
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidates = await widget.searchExt.searchLyric(_query);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _download(MusicLyricCandidate candidate) async {
    setState(() => _downloading = true);
    String? text;
    try {
      final download = await widget.lyric.downloadLyric(
        MusicLyricDownloadQuery(
          id: candidate.sourceId,
          accesskey: candidate.accessKey,
        ),
      );
      text = _decodeLyricText(download);
    } on Object {
      text = null;
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('歌词 · ${displayTitle(candidate.title)}'),
        content: SizedBox(
          width: 480,
          child: text == null
              // base64/UTF-8 解码失败统一按「格式不支持」呈现（krc/lrc/text
              // 成功解码时都按纯文本展示）。
              ? const Text('歌词格式不支持')
              : SingleChildScrollView(child: Text(text)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '歌词候选 · ${displayTitle(widget.song.title)}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(message: '搜索歌词候选失败：$error', onRetry: _loadCandidates);
    }
    if (_candidates.isEmpty) {
      return const _EmptyState(message: '没有找到歌词候选');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _candidates.length,
      itemBuilder: (context, index) {
        final candidate = _candidates[index];
        final tags = <String>[
          if (candidate.sourceLabel.isNotEmpty) candidate.sourceLabel,
          if (candidate.language.isNotEmpty) candidate.language,
          if (candidate.wordTimed == true) '逐字',
        ];
        return ListTile(
          leading: const Icon(Icons.lyrics_outlined),
          title: Text(
            '${displayTitle(candidate.title)} - ${displayTitle(candidate.artist)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: tags.isEmpty
              ? null
              : Text(
                  tags.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: _downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _downloading ? null : () => _download(candidate),
        );
      },
    );
  }
}

// ── 私有工具 ──────────────────────────────────────────────────────────────

/// 歌词文档 base64 → UTF-8 文本；krc/lrc/text 都按纯文本展示。
/// 解码失败（非 base64、非法 UTF-8）返回 null，调用方显示「歌词格式不支持」。
String? _decodeLyricText(MusicLyricDownload download) {
  try {
    final bytes = base64.decode(
      download.content.replaceAll(RegExp(r'\s+'), ''),
    );
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

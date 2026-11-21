// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐发现页（U1）：发现推荐 + 搜索扩展（歌曲/专辑/歌手/歌单/歌词）。
///
/// 页面只依赖注入的接口（[MusicSearchExtApi]/[MusicDiscoveryApi]/
/// [MusicPlayerUi]/[MusicLyricApi]/[MusicCollectApi]/[MusicSearchHistoryApi]），
/// 不 import 播放器与库服务的实现——与 P/C 线保持编译隔离。
///
/// 结构：顶部 SearchBar + 六个 tab（发现 / 歌曲 / 专辑 / 歌手 / 歌单 / 歌词）。
/// 「发现」tab 拉取 homeDiscover / everydayRecommend / everydayStyleRecommend
/// （风格推荐：标签 chips 多选，选中即带 tagIds 重取）/ aiRecommendSongs /
/// personalFm / searchDefault / searchHot，每个 section 独立 loading/失败重试，
/// 支持下拉刷新；搜索提交后按关键词填充五个搜索 tab。与模块页（搜索页）的
/// 区别：本页聚焦发现与扩展搜索，歌曲搜索结果复用 [MusicStore]。
///
/// 模型 → [MusicSong] 的映射全部走本文件私有函数 [_discoverySongToMusicSong]，
/// 不改共享模型。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
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
import 'package:mimao/music/player/player_ui.dart';

/// 音乐发现页：发现推荐 + 搜索扩展。回调按集成者契约接线，null 时对应
/// 功能降级（行可点但不跳转 / 按钮不显示）。
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

  /// 打开榜单页（AppBar 排行榜入口）。
  final VoidCallback? onOpenRank;

  /// 打开音效商城（L1 音效页，含耳机品牌/设备匹配）；null 时入口卡整体隐藏。
  final VoidCallback? onOpenEffects;

  @override
  State<MusicDiscoveryPage> createState() => _MusicDiscoveryPageState();
}

class _MusicDiscoveryPageState extends State<MusicDiscoveryPage>
    with SingleTickerProviderStateMixin {
  static const int _discoverTabIndex = 0;
  static const int _songsTabIndex = 1;

  /// 响应式断点：歌曲结果 ≥720 双列；发现 sections ≥960 双列（横向列表）。
  static const double _songTwoColumnBreakpoint = 720;
  static const double _discoverTwoColumnBreakpoint = 960;

  /// 发现歌曲卡尺寸（横向列表行高随之固定，保证嵌套滚动有界）。
  static const double _cardWidth = 128;
  static const double _cardHeight = 184;

  /// 建议防抖间隔；输入停顿后请求 searchSuggest，取消旧请求靠 cancel + stale 检查。
  static const Duration _suggestDebounce = Duration(milliseconds: 400);

  /// 风格标签 id 的接口约束：仅 ASCII 字母数字（≤32 字节、总数 ≤128，由
  /// [EverydayStyleRecommendQuery.validate] 兜底）；页面用同一规则做防御性
  /// 过滤，脏 id 不渲染、不参与重取。
  static final RegExp _styleTagIdPattern = RegExp(r'^[0-9a-zA-Z]+$');

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

  // —— 发现 sections（互不阻塞，独立 loading/error） ——
  final _AsyncList<MusicSearchPromotion> _defaultWords =
      _AsyncList<MusicSearchPromotion>();
  final _AsyncList<MusicHotSearchGroup> _hotGroups =
      _AsyncList<MusicHotSearchGroup>();
  final _AsyncList<MusicDiscoverItem> _homeItems =
      _AsyncList<MusicDiscoverItem>();
  final _AsyncList<MusicDiscoverySong> _dailySongs =
      _AsyncList<MusicDiscoverySong>();
  final _AsyncList<MusicDiscoverySong> _aiSongs =
      _AsyncList<MusicDiscoverySong>();
  final _AsyncList<MusicPersonalFmSong> _fmSongs =
      _AsyncList<MusicPersonalFmSong>();

  // —— 风格推荐 section（不走 _AsyncList：单响应同时带标签目录与歌曲） ——
  bool _styleLoading = false;
  Object? _styleError;

  /// 最近一次成功响应（标签目录 + 命中歌曲）；标签重取期间保留旧值，
  /// chips 才不会在重取中整块消失。
  MusicStyleRecommendations? _styleData;

  /// 最近一次请求下发的 tagIds（重试沿用）；首载为空列表。
  List<String> _styleTagIds = const <String>[];

  /// 本地选中集（chips 选中态与重取 tagIds 的唯一来源）；null 表示还没从
  /// 服务端预选（selected == 1）初始化过——只同步首次成功响应，之后重取的
  /// 回显不覆盖用户操作。
  Set<String>? _styleSelected;

  /// 请求序号：标签连点时丢弃乱序旧响应。
  int _styleRequestSeq = 0;

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
    _loadDiscoverySections();
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

  /// 发现 sections 的首次装载与下拉刷新共用；Future.wait 之外每个 section
  /// 自带 try/catch，任何一个失败不清空整页（规格功能 6）。
  Future<void> _loadDiscoverySections() => Future.wait<void>(<Future<void>>[
    _load(
      _defaultWords,
      () async => (await widget.searchExt.searchDefault()).promotions,
    ),
    _load(_hotGroups, widget.searchExt.searchHot),
    _load(
      _homeItems,
      () async => (await widget.discovery.homeDiscover(
        const HomeDiscoverQuery(),
      )).items,
    ),
    _load(
      _dailySongs,
      () async => (await widget.discovery.everydayRecommend()).songs,
    ),
    _load(
      _aiSongs,
      () async => (await widget.discovery.aiRecommendSongs()).songs,
    ),
    _load(_fmSongs, _fetchFmSongs),
    _loadStyle(_styleTagIds),
  ]);

  /// 私人 FM 批次；「换一批」复用同一默认 query（action=play，参数按模型定义）。
  Future<List<MusicPersonalFmSong>> _fetchFmSongs() async =>
      (await widget.discovery.personalFm(const MusicPersonalFmQuery())).songs;

  // ── 风格推荐 ──────────────────────────────────────────────────────────

  /// 风格推荐装载（首载 / 选标签重取 / 下拉刷新 / 重试共用）。
  /// 与其它 section 一样失败只影响自己；seq 丢弃标签连点时的乱序旧响应。
  Future<void> _loadStyle(List<String> tagIds) async {
    final seq = ++_styleRequestSeq;
    setState(() {
      _styleLoading = true;
      _styleError = null;
      _styleTagIds = tagIds;
    });
    try {
      final result = await widget.discovery.everydayStyleRecommend(
        EverydayStyleRecommendQuery(tagIds: _filterStyleTagIds(tagIds)),
      );
      if (!mounted || seq != _styleRequestSeq) return;
      setState(() {
        _styleData = result;
        _styleLoading = false;
        // 预选只按首次成功响应同步（selected == 1 是服务端默认勾选态）；
        // 之后以本地选择为准，重取回显不再覆盖。
        _styleSelected ??= <String>{
          for (final group in result.groups)
            for (final tag in group.child)
              if (tag.selected == 1) tag.id,
        };
      });
    } on Object catch (error) {
      if (!mounted || seq != _styleRequestSeq) return;
      setState(() {
        _styleError = error;
        _styleLoading = false;
      });
    }
  }

  /// 重取前过滤 tagIds：接口只收 ASCII 字母数字且总数 ≤128（validate 会抛
  /// input 错），服务端下发的 id 理应合法，这里兜底过滤避免脏数据把整个
  /// section 打成错误态。
  List<String> _filterStyleTagIds(List<String> tagIds) {
    final valid = tagIds
        .where((id) => id.isNotEmpty && _styleTagIdPattern.hasMatch(id))
        .toList();
    return valid.length > 128 ? valid.sublist(0, 128) : valid;
  }

  /// 点 / 取消标签：本地集合先行更新（chips 即时反馈），再带最新 tagIds 重取。
  void _toggleStyleTag(String tagId) {
    final next = Set<String>.of(_styleSelected ?? const <String>{});
    if (!next.remove(tagId)) {
      next.add(tagId);
    }
    setState(() => _styleSelected = next);
    _loadStyle(next.toList());
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

  /// 搜索扩展 section 的重试：按最近提交的关键词重跑。
  void _retrySearchSection<T>(
    _AsyncList<T> section,
    Future<List<T>> Function(String keyword) task,
  ) {
    final keyword = _submittedKeyword;
    if (keyword.isEmpty) return;
    _load(section, () => task(keyword));
  }

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
          final text = _displayTitle(item.text).trim();
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
      appBar: AppBar(
        title: const Text('发现音乐'),
        actions: <Widget>[
          IconButton(
            tooltip: '排行榜',
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: widget.onOpenRank,
          ),
        ],
      ),
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
                LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildDiscoverTab(constraints.maxWidth),
                ),
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

  Widget _buildDiscoverTab(double width) {
    final sections = <Widget>[
      _buildDefaultWordsSection(),
      _buildSongCardsSection<MusicDiscoverItem>(
        key: const Key('discover-home'),
        title: '首页发现',
        section: _homeItems,
        songOf: (item) => _discoverySongToMusicSong(item.song.song),
        onRetry: () => _load(
          _homeItems,
          () async => (await widget.discovery.homeDiscover(
            const HomeDiscoverQuery(),
          )).items,
        ),
      ),
      _buildStyleSection(),
      _buildSongCardsSection<MusicDiscoverySong>(
        key: const Key('discover-daily'),
        title: '每日推荐',
        section: _dailySongs,
        songOf: (song) => _discoverySongToMusicSong(song.song),
        onRetry: () => _load(
          _dailySongs,
          () async => (await widget.discovery.everydayRecommend()).songs,
        ),
      ),
      _buildSongCardsSection<MusicDiscoverySong>(
        key: const Key('discover-ai'),
        title: 'AI 免费畅听',
        section: _aiSongs,
        songOf: (song) => _discoverySongToMusicSong(song.song),
        onRetry: () => _load(
          _aiSongs,
          () async => (await widget.discovery.aiRecommendSongs()).songs,
        ),
      ),
      _buildSongCardsSection<MusicPersonalFmSong>(
        key: const Key('discover-fm'),
        title: '私人 FM',
        section: _fmSongs,
        songOf: (item) => _discoverySongToMusicSong(item.song.song),
        onRetry: () => _load(_fmSongs, _fetchFmSongs),
        trailing: TextButton.icon(
          onPressed: () => _load(_fmSongs, _fetchFmSongs),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('换一批'),
        ),
      ),
      _buildHotGroupsSection(),
    ];
    // 宽屏 sections 拆两列提高一屏信息密度；窄屏单列纵向滚动。
    // 音效商城入口不参与拆列，始终横贯顶部（「发现音乐」区域首屏）。
    if (width >= _discoverTwoColumnBreakpoint) {
      return RefreshIndicator(
        onRefresh: _loadDiscoverySections,
        child: ListView(
          key: const Key('discover-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: <Widget>[
            _buildEffectsEntry(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: Column(children: sections.sublist(0, 3))),
                Expanded(child: Column(children: sections.sublist(3))),
              ],
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDiscoverySections,
      child: ListView(
        key: const Key('discover-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[_buildEffectsEntry(), ...sections],
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

  /// 风格推荐：标签 chips（多选，选中即带 tagIds 重取）+ 命中歌曲横向卡。
  /// 整段独立 loading/error/retry，失败不影响其它 section；
  /// 首载与重取都拿不到任何标签/歌曲时整段隐藏。
  Widget _buildStyleSection() {
    final data = _styleData;
    final hasContent =
        data != null && (data.groups.isNotEmpty || data.songs.isNotEmpty);
    if (!_styleLoading && _styleError == null && !hasContent) {
      return const SizedBox.shrink();
    }
    return _SectionBlock(
      key: const Key('discover-style'),
      title: '风格推荐',
      child: _buildStyleBody(),
    );
  }

  Widget _buildStyleBody() {
    final error = _styleError;
    if (error != null) {
      // 重试沿用最近一次请求的 tagIds（首载失败则是空标签）。
      return _SectionError(
        error: error,
        onRetry: () => _loadStyle(_styleTagIds),
      );
    }
    final data = _styleData;
    if (_styleLoading) {
      // 标签重取中：保留旧 chips（选中态由本地集合驱动），歌曲区给占位；
      // 首载则整块占位。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (data != null)
            _buildStyleChips(data)
          else
            const _ChipPlaceholder(),
          const SizedBox(height: 8),
          const _CardsPlaceholder(),
        ],
      );
    }
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (data.groups.isNotEmpty) _buildStyleChips(data),
        if (data.songs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _buildStyleSongs(data.songs),
        ],
      ],
    );
  }

  /// 标签目录 chips：按组渲染；组名缺失只省略标题行；id 不合法（接口校验
  /// 仅 ASCII 字母数字）的标签不渲染，避免「可点但永不生效」的死 chip。
  Widget _buildStyleChips(MusicStyleRecommendations data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in data.groups)
          if (group.child.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (group.name.isNotEmpty) ...<Widget>[
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final tag in group.child)
                        if (tag.id.isNotEmpty &&
                            _styleTagIdPattern.hasMatch(tag.id))
                          FilterChip(
                            label: Text(tag.name),
                            selected: _styleSelected?.contains(tag.id) ?? false,
                            // 不用勾选图标：勾选占宽 20px 会把 label 中心推进
                            // 框架为「删除按钮」预留的命中区（FilterChip 无
                            // onDeleted 时该区不可命中），点选中 chip 的文字
                            // 会落空；选中态由填充底色表达。
                            showCheckmark: false,
                            onSelected: (_) => _toggleStyleTag(tag.id),
                            visualDensity: VisualDensity.compact,
                          ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 命中歌曲横向卡：与其它发现 section 同款形态，点卡走统一播放链路。
  Widget _buildStyleSongs(List<MusicDiscoverySong> songs) {
    final cards = <MusicSong>[
      for (final item in songs) _discoverySongToMusicSong(item.song),
    ];
    return SizedBox(
      height: _cardHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (final song in cards)
            _SongCard(
              width: _cardWidth,
              song: song,
              onTap: () => _openSong(song),
            ),
        ],
      ),
    );
  }

  /// 默认搜索词 chips（searchDefault promotions；title 即搜索词）。
  Widget _buildDefaultWordsSection() {
    final section = _defaultWords;
    if (!_sectionVisible(section)) return const SizedBox.shrink();
    return _SectionBlock(
      key: const Key('discover-default-words'),
      title: '默认搜索词',
      child: _sectionBody(
        section: section,
        loading: const _ChipPlaceholder(),
        empty: const SizedBox.shrink(),
        content: () => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final promotion in section.items)
              if (promotion.title.isNotEmpty || promotion.mainTitle.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.campaign_outlined, size: 16),
                  label: Text(
                    promotion.title.isNotEmpty
                        ? promotion.title
                        : promotion.mainTitle,
                  ),
                  onPressed: () => _applyKeyword(
                    promotion.title.isNotEmpty
                        ? promotion.title
                        : promotion.mainTitle,
                  ),
                ),
          ],
        ),
        onRetry: () => _load(
          _defaultWords,
          () async => (await widget.searchExt.searchDefault()).promotions,
        ),
      ),
    );
  }

  /// 热搜分组（searchHot）：每组一张卡 + 关键词 chips。
  Widget _buildHotGroupsSection() {
    final section = _hotGroups;
    if (!_sectionVisible(section)) return const SizedBox.shrink();
    return _SectionBlock(
      key: const Key('discover-hot'),
      title: '热搜榜',
      child: _sectionBody(
        section: section,
        loading: const _ChipPlaceholder(),
        empty: const SizedBox.shrink(),
        content: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final group in section.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          group.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final keyword in group.keywords)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.local_fire_department_outlined,
                                  size: 16,
                                ),
                                label: Text(keyword.keyword),
                                tooltip: keyword.reason,
                                onPressed: () => _applyKeyword(keyword.keyword),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        onRetry: () => _load(_hotGroups, widget.searchExt.searchHot),
      ),
    );
  }

  /// 横向歌曲卡 section（首页发现/每日推荐/AI 畅听/私人 FM 共用）。
  /// 数据为空时整个 section 隐藏，不占版面。
  Widget _buildSongCardsSection<T>({
    Key? key,
    required String title,
    required _AsyncList<T> section,
    required MusicSong Function(T item) songOf,
    required VoidCallback onRetry,
    Widget? trailing,
  }) {
    if (!_sectionVisible(section)) return const SizedBox.shrink();
    return _SectionBlock(
      key: key,
      title: title,
      trailing: trailing,
      child: _sectionBody(
        section: section,
        loading: const _CardsPlaceholder(),
        empty: const SizedBox.shrink(),
        content: () => SizedBox(
          height: _cardHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: <Widget>[
              for (final item in section.items)
                _SongCard(
                  width: _cardWidth,
                  song: songOf(item),
                  onTap: () => _openSong(songOf(item)),
                ),
            ],
          ),
        ),
        onRetry: onRetry,
      ),
    );
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
        leading: _SquareCover(url: album.coverUrl, size: 56),
        title: Text(
          _displayTitle(album.title),
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
            _displayTitle(artist.name),
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
        leading: _SquareCover(url: playlist.coverUrl, size: 56),
        title: Text(
          _displayTitle(playlist.title),
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
          '${_displayTitle(hit.song.title)} - ${_displayTitle(hit.song.artistText)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _displayTitle(hit.excerpt),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatDuration(hit.song.durationMs),
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
      return _SectionError(error: error, onRetry: onRetry);
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

/// section 标题行（可选 trailing：换一批 / 清空历史等动作）。
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

/// 带标题的 section 块（发现 tab 用；key 供测试定位单个 section）。
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(title: title, trailing: trailing),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// section 级错误行：失败只占自己那一块，重试不牵连其它 section。
class _SectionError extends StatelessWidget {
  const _SectionError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.error_outline, size: 18, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '加载失败：$error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重试'),
        ),
      ],
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

/// 发现歌曲卡（横向列表项）：方形封面 + 标题 + 歌手。
class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.width,
    required this.song,
    required this.onTap,
  });

  final double width;
  final MusicSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: MimaoShapes.md,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SquareCover(
                url: song.coverUrl,
                size: width,
                radius: MimaoShapes.md,
              ),
              const SizedBox(height: 6),
              Text(
                _displayTitle(song.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                song.artistText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
      leading: _SquareCover(url: song.coverUrl, size: 44),
      title: Text(
        _displayTitle(song.title),
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
              _formatDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}

/// 方形封面（封面/专辑/歌单）：无 URL / 加载失败回退音符占位。
/// Image.network 必须同时给 errorBuilder 与 loadingBuilder（规格功能 7）。
class _SquareCover extends StatelessWidget {
  const _SquareCover({required this.url, required this.size, this.radius});

  final String url;
  final double size;

  /// 缺省 sm（10）——行级封面；卡片封面传 md。
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = radius ?? MimaoShapes.sm;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: shape,
      ),
      child: Icon(Icons.music_note, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: shape,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        // 加载中维持占位（与迷你条/播放页的 loading 模式对齐，不闪空块）。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
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

/// 横向歌曲卡区的加载占位：静态灰块（不用 indeterminate 进度条，
/// 避免 pumpAndSettle 不收敛、也让占位与真实卡片同高不跳版）。
class _CardsPlaceholder extends StatelessWidget {
  const _CardsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 184,
      child: Row(
        children: <Widget>[
          for (final _ in List<int>.generate(4, (index) => index))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 128,
                height: 176,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: MimaoShapes.md,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// chips 区的加载占位（默认词/热词）。
class _ChipPlaceholder extends StatelessWidget {
  const _ChipPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        for (final width in const <double>[72, 96, 64, 88])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: width,
              height: 32,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: MimaoShapes.pill,
              ),
            ),
          ),
      ],
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
        title: Text('歌词 · ${_displayTitle(candidate.title)}'),
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
              '歌词候选 · ${_displayTitle(widget.song.title)}',
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
            '${_displayTitle(candidate.title)} - ${_displayTitle(candidate.artist)}',
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

/// 发现组曲目摘要 → 播放链路的 [MusicSong]。发现组保留「专辑名缺失(null)
/// vs 空串」的 wire 区分，播放链路的骨架模型用空串表达缺失。
MusicSong _discoverySongToMusicSong(MusicDiscoverySongSummary summary) =>
    MusicSong(
      id: summary.id,
      hash: summary.hash,
      title: summary.title,
      artists: summary.artists,
      albumId: summary.albumId,
      albumTitle: summary.albumTitle ?? '',
      durationMs: summary.durationMs,
      coverUrl: summary.coverUrl,
      privilege: summary.privilege,
    );

/// wire 的 SongName 可能带 `<em>` 高亮标签，展示层统一剥掉；模型层保持
/// 上游 api 的原样语义（与模块页同款）。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

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

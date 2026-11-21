// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐发现页搜索结果页：取消发现页搜索分类 Tab 后，所有搜索（发现页
/// SearchBar 提交 / 建议词 / 历史词 / 热搜页点词）统一 push 到本页。
///
/// 只保留歌曲长条结果（封面 / 歌名 / 歌手 / 收藏按钮 / 时长），不区分专辑/
/// 歌手/歌单/歌词。未搜索时展示搜索历史 chips + 引导文案；输入防抖 400ms 拉
/// 建议，stale 响应丢弃。页面级单一 State，复用注入的 [MusicStore] / 收藏 /
/// 历史门面，不引入新依赖、不新增全局状态。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';
import 'package:mimao/music/pages/music_discovery_mappers.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 发现页搜索结果页。
class MusicDiscoverySearchPage extends StatefulWidget {
  const MusicDiscoverySearchPage({
    super.key,
    required this.searchExt,
    required this.store,
    required this.player,
    this.collect,
    this.searchHistory,
    this.initialKeyword = '',
  });

  /// 搜索扩展端点组（本页只用 searchSuggest；歌曲搜索走 [store]）。
  final MusicSearchExtApi searchExt;

  /// 歌曲搜索状态（MobX）；结果与加载/错误态都来自这里。
  final MusicStore store;

  /// 播放 UI：点歌后 playSong 并 push 播放页。
  final MusicPlayerUi player;

  /// 收藏门面；null 时歌曲行不显示收藏按钮。
  final MusicCollectApi? collect;

  /// 搜索历史；null 时不记录、不展示历史词。
  final MusicSearchHistoryApi? searchHistory;

  /// 预填关键词（非空时自动提交，供搜索页 push 时带词进入）。
  final String initialKeyword;

  @override
  State<MusicDiscoverySearchPage> createState() =>
      _MusicDiscoverySearchPageState();
}

class _MusicDiscoverySearchPageState extends State<MusicDiscoverySearchPage> {
  /// 建议防抖间隔：与旧发现页一致（输入停顿 400ms 后请求 searchSuggest）。
  static const Duration _suggestDebounce = Duration(milliseconds: 400);

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialKeyword,
  );
  Timer? _suggestTimer;

  /// 当前展开的建议词（提交/清空时收回）。
  List<String> _suggestions = const <String>[];

  /// 最近一次提交的关键词（建议 stale 判断、错误重试都用它）。
  String _submittedKeyword = '';

  /// 本页是否提交过搜索（store.searched 是跨页共享的，不能拿来判「未搜索」）。
  bool _searched = false;

  /// 搜索历史词（searchHistory 非空时加载）。
  List<String> _historyWords = const <String>[];

  /// 收藏态缓存（列表批量判断，避免逐行异步查询导致抖动）。
  final Set<String> _collectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadHistory();
    _loadCollected();
    if (widget.initialKeyword.trim().isNotEmpty) {
      // 带词进入（热搜页点词 / 建议词 / 历史词）：自动提交一次。
      _submit();
    }
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  // ── 数据装载 ──────────────────────────────────────────────────────────

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
    _submittedKeyword = keyword;
    if (mounted) {
      // 从落位切到结果视图必须重建：即使建议条本来就是空的，也要靠这次
      // setState 让 _searched 生效（initState 带词进入时 mounted 为 true，
      // 这里的 setState 只是提前标脏，首帧仍会构建结果视图）。
      setState(() {
        _searched = true;
        _suggestions = const <String>[];
      });
    } else {
      _searched = true;
    }
    widget.store.search(keyword);
    final history = widget.searchHistory;
    if (history != null) {
      history.record(keyword).catchError((Object _) {});
    }
  }

  /// 历史词/建议词的统一入口：填入搜索框并提交。
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

  // ── 播放 / 收藏 ───────────────────────────────────────────────────────

  String _songId(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;

  /// 点歌：先起播（地址异步解析）再打开播放页。
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

  // ── 骨架 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // pushed 路由自带返回箭头；SearchBar 作为 title 保持可编辑。
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SearchBar(
            key: const Key('discovery-search-bar'),
            controller: _controller,
            hintText: '搜索歌曲',
            autoFocus: true,
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSuggestionBar(),
          Expanded(child: _searched ? _buildResults() : _buildLanding()),
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
        key: const Key('discovery-search-suggestions'),
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

  /// 未搜索落位：搜索历史 chips + 引导文案。
  Widget _buildLanding() {
    final words = _historyWords;
    return ListView(
      key: const Key('discovery-search-landing'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        if (words.isNotEmpty) ...<Widget>[
          _SectionHeader(
            title: '搜索历史',
            trailing: IconButton(
              key: const Key('discovery-search-history-clear'),
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

  /// 搜索结果：歌曲长条列表（store MobX 驱动）。
  Widget _buildResults() {
    return Observer(
      builder: (context) {
        final store = widget.store;
        if (store.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = store.error;
        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final results = store.results;
        if (results.isEmpty) {
          return const DiscoveryEmptyState(message: '没有找到相关歌曲');
        }
        return ListView.builder(
          key: const Key('discovery-search-results'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final song = results[index];
            return MusicSongCard(
              child: _SongTile(
                song: song,
                isCollected: _collectedIds.contains(_songId(song)),
                onToggleCollect: widget.collect == null
                    ? null
                    : () => _toggleCollect(song),
                onTap: () => _openSong(song),
              ),
            );
          },
        );
      },
    );
  }
}

/// section 标题行（搜索历史用，trailing 为清空按钮）。
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

/// 搜索结果行：封面 / 歌名 / 歌手 / 时长 / 收藏按钮。
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
    final duration = formatDuration(song.durationMs);
    return ListTile(
      key: Key('discovery-search-result-${_id(song)}'),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (duration.isNotEmpty)
            Text(
              duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (onToggleCollect != null) ...<Widget>[
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: isCollected ? '取消收藏' : '收藏',
              isSelected: isCollected,
              selectedIcon: const Icon(Icons.favorite),
              icon: const Icon(Icons.favorite_border),
              onPressed: onToggleCollect,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  String _id(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;
}

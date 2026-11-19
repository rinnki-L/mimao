// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块主页（M4）：搜索 + 结果列表；可选「我的」页与迷你播放条。
///
/// 契约提交后本页只认接口（[MusicPlayerUi]/[MusicCollectApi]/
/// [MusicSearchHistoryApi]），不 import `player/` 实现，也不认识 C 线的
/// 服务类——三条线可各自独立编译。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 搜索框 + 结果列表。embedded=true 时由壳提供顶部「返回 + 标题」。
class MusicModulePage extends StatefulWidget {
  const MusicModulePage({
    super.key,
    required this.store,
    this.embedded = false,
    this.playerUi,
    this.collect,
    this.searchHistory,
    this.libraryTab,
  });

  final MusicStore store;

  /// true 时由壳提供顶部栏，本页不画 AppBar。
  final bool embedded;

  /// P 线播放 UI；null 时点歌显示占位提示、不渲染迷你播放条。
  final MusicPlayerUi? playerUi;

  /// C 线收藏服务；null 时不显示收藏按钮。
  final MusicCollectApi? collect;

  /// C 线搜索历史；null 时搜索不做记录。
  final MusicSearchHistoryApi? searchHistory;

  /// C 线「我的」页；null 时只有搜索页（不出底部导航）。
  final Widget? libraryTab;

  @override
  State<MusicModulePage> createState() => _MusicModulePageState();
}

class _MusicModulePageState extends State<MusicModulePage> {
  late final TextEditingController _controller = TextEditingController();

  int _index = 0;

  /// 收藏态缓存（列表批量判断，避免逐行异步查询导致抖动）。
  final Set<String> _collectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCollected();
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    widget.store.search(keyword);
    final searchHistory = widget.searchHistory;
    if (searchHistory != null) {
      searchHistory.record(keyword).catchError((Object _) {});
    }
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

  String _songId(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;

  void _openSong(MusicSong song) {
    final player = widget.playerUi;
    if (player == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('播放功能随播放器切片接入')));
      return;
    }
    // ── M4-P 播放 ──
    // 先起播（地址异步解析）再打开播放页：页面立刻呈现 loading/错误态，
    // 失败也有「重试」入口，不必回列表再点一次。
    player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => player.buildPlayerPage(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchBody = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手 / 专辑',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: '搜索',
                onPressed: _submit,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: Observer(builder: (_) => _buildBody(context))),
      ],
    );

    final libraryTab = widget.libraryTab;
    final content = libraryTab == null
        ? searchBody
        : IndexedStack(
            index: _index,
            children: <Widget>[searchBody, libraryTab],
          );
    // 迷你播放条住两页共用区：切「我的」时播放控制不消失（集成收口修正）。
    // Observer 包住调用：buildMiniPlayer 返回 null 时不渲染，队列变化
    // （点歌入队）由 MobX 驱动重建，不需要页面自己 setState。
    final body = Column(
      children: <Widget>[
        Expanded(child: content),
        if (widget.playerUi != null)
          Observer(
            builder: (context) =>
                widget.playerUi!.buildMiniPlayer(context) ??
                const SizedBox.shrink(),
          ),
      ],
    );

    final scaffold = Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('音乐')),
      body: body,
      bottomNavigationBar: libraryTab == null
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: '搜索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: '我的',
                ),
              ],
            ),
    );
    return scaffold;
  }

  Widget _buildBody(BuildContext context) {
    final store = widget.store;
    if (store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = store.error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: _submit);
    }
    if (store.results.isEmpty) {
      return _EmptyState(hasSearched: store.searched);
    }
    return ListView.builder(
      itemCount: store.results.length,
      itemBuilder: (context, index) {
        final song = store.results[index];
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
}

/// 结果行。封面占位图标——真实封面留待播放页。
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
    return ListTile(
      leading: Icon(Icons.music_note, color: theme.colorScheme.primary),
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
      trailing: onToggleCollect != null
          ? IconButton(
              tooltip: isCollected ? '取消收藏' : '收藏',
              icon: Icon(isCollected ? Icons.favorite : Icons.favorite_border),
              onPressed: onToggleCollect,
            )
          : Text(
              _formatDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}

/// wire 的 SongName 可能带 `<em>` 高亮标签（复杂搜索的命中高亮），
/// 展示层统一剥掉；模型层保持上游 api 的原样语义。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearched});

  final bool hasSearched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        hasSearched ? '没有找到相关歌曲' : '输入关键词开始搜索',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

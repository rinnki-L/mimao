// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 通用「长条歌曲列表」页 + 发现切片共用的小组件。
///
/// [MusicDiscoveryListPage] 是发现页入口网格的通用落位（首页发现 / AI 免费
/// 畅听 / 私人 FM）：只依赖注入的 [MusicPlayerUi] 与歌曲装载回调，不感知具体
/// 端点——调用方在 push 前把端点结果映射成骨架 [MusicSong]（见
/// `music_discovery_mappers.dart`）。发现 tab 的每日推荐与风格推荐页也复用本
/// 文件导出的 [DiscoverySongTile]，形态与收藏页的歌曲行一致（44 封面 + 歌名
/// + 歌手 + 时长 + 播放图标）。
///
/// 两种装载模式：
/// - 分批模式（传入 [initialSongs]）：预览批次先立即显示（与入口卡封面同源），
///   后台反复调用 [loadMore] 按 id/hash 去重追加，直到达到 [targetCount] 或
///   用完 [maxBatches] 批；追加期间列表底部显示小 spinner。失败静默，不挡已
///   有的数据。「换一批」/登录态变化会清空后重新拉满。
/// - 整页模式（未传 [initialSongs]）：保持原来的 `loader` 整页 loading/error/
///   retry 行为，适合一次性返回全部数据的端点。
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_discovery_mappers.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 长条歌曲列表页：AppBar 标题 +（refreshLabel 非空时）刷新按钮 + 歌曲长条。
class MusicDiscoveryListPage extends StatefulWidget {
  const MusicDiscoveryListPage({
    super.key,
    required this.title,
    required this.player,
    this.loader,
    this.loadMore,
    this.initialSongs,
    this.targetCount,
    this.maxBatches = 8,
    this.refreshLabel,
    this.authEpoch,
  });

  /// AppBar 标题（入口名，如「首页发现」）。
  final String title;

  /// 播放 UI：点歌后 playSong 并 push 播放页。
  final MusicPlayerUi player;

  /// 整页装载器（整页模式使用）：一次返回整页数据。首载 / 重试 / 刷新按钮 /
  /// 登录重拉共用；每次调用都要重新请求端点。
  final Future<List<MusicSong>> Function()? loader;

  /// 分批装载器（分批模式使用）：每次返回一批，由页面内部去重、追加、计数。
  final Future<List<MusicSong>> Function()? loadMore;

  /// 预览批次（可选）：非空时进入分批模式，立即显示这批歌曲，并在后台继续
  /// 拉满到 [targetCount]；传空列表表示「预览失败但仍按分批模式加载」。
  final List<MusicSong>? initialSongs;

  /// 分批模式的目标数量；达到即停（ AI 预览已 30 首时传 30 → 不再追加）。
  final int? targetCount;

  /// 分批模式最多请求多少批（防御服务端重复返回导致死循环）。
  final int maxBatches;

  /// 非空时 AppBar 显示刷新按钮（tooltip 同文案；私人 FM 用「换一批」）。
  final String? refreshLabel;

  /// 登录态变化信号：非空时登录/切号自动重拉（私人 FM 需要账号）。
  final ValueListenable<int>? authEpoch;

  @override
  State<MusicDiscoveryListPage> createState() => _MusicDiscoveryListPageState();
}

class _MusicDiscoveryListPageState extends State<MusicDiscoveryListPage> {
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<MusicSong> _songs = const <MusicSong>[];

  /// 去重键：id / hash 分别维护，任一命中即视为重复（id 优先、hash 兜底）。
  final Set<String> _seenIds = <String>{};
  final Set<String> _seenHashes = <String>{};

  /// 装载代次：换一批 / 登录重拉时递增，丢弃旧循环的迟到响应。
  int _generation = 0;

  /// 是否分批模式（以预览批次是否传入为准）。
  bool get _batched => widget.initialSongs != null;

  @override
  void initState() {
    super.initState();
    widget.authEpoch?.addListener(_refresh);
    if (_batched) {
      // 预览批次直接作为初始数据：不发整页 loading，第一首与入口卡封面同源。
      _loading = false;
      _resetWith(widget.initialSongs!);
      _appendUntilTarget();
    } else {
      _reload();
    }
  }

  @override
  void dispose() {
    widget.authEpoch?.removeListener(_refresh);
    super.dispose();
  }

  // ── 数据装载 ──────────────────────────────────────────────────────────

  /// 清空既有数据后装入一批，内部按 id/hash 去重。
  void _resetWith(Iterable<MusicSong> songs) {
    _songs = <MusicSong>[];
    _seenIds.clear();
    _seenHashes.clear();
    _addSongs(songs);
  }

  /// 追加一批；返回真正新增的条数。
  int _addSongs(Iterable<MusicSong> songs) {
    var added = 0;
    for (final song in songs) {
      final id = song.id.trim();
      final hash = song.hash.trim();
      if (id.isNotEmpty && _seenIds.contains(id)) continue;
      if (hash.isNotEmpty && _seenHashes.contains(hash)) continue;
      if (id.isNotEmpty) _seenIds.add(id);
      if (hash.isNotEmpty) _seenHashes.add(hash);
      _songs.add(song);
      added++;
    }
    return added;
  }

  /// 整页模式：独立 loading/error；失败清空列表（长条页只有这一份数据）。
  Future<void> _reload() async {
    final gen = ++_generation;
    final fetch = widget.loader ?? widget.loadMore;
    if (fetch == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final songs = await fetch();
      if (!mounted || gen != _generation) return;
      setState(() {
        _resetWith(songs);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _songs = const <MusicSong>[];
        _error = error;
        _loading = false;
      });
    }
  }

  /// 分批模式：后台拉到目标数量或批数上限；每批之间留一帧给 spinner 呈现，
  /// 失败静默（保留已有歌曲），不把整页打成错误态。
  Future<void> _appendUntilTarget() async {
    final gen = ++_generation;
    final fetch = widget.loadMore;
    if (fetch == null) return;
    if (mounted) setState(() => _loadingMore = true);
    final target = widget.targetCount ?? 0;
    var batches = 0;
    while (gen == _generation &&
        mounted &&
        batches < widget.maxBatches &&
        (target <= 0 || _songs.length < target)) {
      batches++;
      try {
        final batch = await fetch();
        if (!mounted || gen != _generation) return;
        if (batch.isEmpty) break;
        _addSongs(batch);
        if (mounted) setState(() {});
      } on Object {
        // 追加失败静默：已有列表照常展示，只停止继续追加。
        break;
      }
    }
    if (gen == _generation && mounted) {
      setState(() => _loadingMore = false);
    }
  }

  /// 换一批 / 登录态变化：清空后重新拉满（整页模式退回 _reload）。
  void _refresh() {
    if (!_batched) {
      _reload();
      return;
    }
    _generation++;
    setState(() {
      _error = null;
      _resetWith(const <MusicSong>[]);
    });
    _appendUntilTarget();
  }

  /// 点歌：先起播（地址异步解析）再打开播放页——与发现页同一链路。
  void _openSong(MusicSong song) {
    widget.player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (widget.refreshLabel != null)
            IconButton(
              tooltip: widget.refreshLabel!,
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return DiscoveryErrorState(message: '加载失败：$error', onRetry: _reload);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_songs.isEmpty && !_loadingMore) {
      return const DiscoveryEmptyState(message: '暂无歌曲');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _songs.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _songs.length) {
          // 追加中的底部小 spinner；稳定 key 供测试定位。
          return const Padding(
            key: Key('discover-list-loading-more'),
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final song = _songs[index];
        return MusicSongCard(
          child: DiscoverySongTile(song: song, onTap: () => _openSong(song)),
        );
      },
    );
  }
}

// ── 发现切片共用的小组件 ──────────────────────────────────────────────────

/// 长条歌曲行：44 封面 + 歌名 + 歌手 + 时长 + 播放图标；发现 tab 每日推荐、
/// 长条列表页与风格推荐页共用，点行走统一播放链路。
class DiscoverySongTile extends StatelessWidget {
  const DiscoverySongTile({super.key, required this.song, required this.onTap});

  final MusicSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = formatDuration(song.durationMs);
    return ListTile(
      leading: DiscoverySquareCover(url: song.coverUrl, size: 44),
      title: Text(
        displayTitle(song.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.artistText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (duration.isNotEmpty) ...<Widget>[
            Text(
              duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.play_circle_outline),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 方形封面（行级）：无 URL / 加载失败回退音符占位。Image.network 同时给
/// errorBuilder 与 loadingBuilder（与模块页同款，不闪空块）。
class DiscoverySquareCover extends StatelessWidget {
  const DiscoverySquareCover({
    super.key,
    required this.url,
    required this.size,
    this.radius,
  });

  final String url;
  final double size;

  /// 缺省 sm（10）——行级封面；大图场景可传 md/lg。
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
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 页面级错误态（整页失败时）：图标 + 信息 + 重试。
class DiscoveryErrorState extends StatelessWidget {
  const DiscoveryErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

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

/// section 级错误行：失败只占自己那一块，重试不牵连其它 section
/// （发现 tab 每日推荐 / 热门搜索页的两个 section）。
class DiscoverySectionError extends StatelessWidget {
  const DiscoverySectionError({
    super.key,
    required this.error,
    required this.onRetry,
  });

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

/// 空态文案（长条列表页 / 风格推荐页 / 热门搜索页）。
class DiscoveryEmptyState extends StatelessWidget {
  const DiscoveryEmptyState({super.key, required this.message});

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

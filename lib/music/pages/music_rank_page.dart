// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 榜单总页（U2）：榜单 / 新歌 / 专辑 / 歌单 / IP 五个 tab。
///
/// 页面只认 [MusicRankApi]（G3 组门面）与 [MusicPlayerUi]（P 线契约），
/// 不 import 共享 API 实现与 player/ 实现——与模块页同款编译隔离。
/// 五个 tab 各自持有加载/错误/空态，切走不丢状态（AutomaticKeepAlive）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/top_playlist.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/rank_models.dart';
import 'package:mimao/music/pages/music_rank_detail_page.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 榜单总页。
class MusicRankPage extends StatefulWidget {
  const MusicRankPage({super.key, required this.api, required this.player});

  final MusicRankApi api;
  final MusicPlayerUi player;

  @override
  State<MusicRankPage> createState() => _MusicRankPageState();
}

class _MusicRankPageState extends State<MusicRankPage> {
  /// 点歌：与 music_module_page 同款次序——先起播（地址异步解析）再 push
  /// 播放页，页面立刻呈现 loading/错误态，失败也有重试入口。
  void _openSong(MusicSong song) {
    widget.player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  /// 双击新歌行：整个新歌榜替换播放队列，并从 [startIndex] 起播。
  void _openSongList(List<MusicSong> songs, int startIndex) {
    widget.player.playList(songs, startIndex: startIndex);
  }

  void _openRank(MusicRank rank) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/rank-detail'),
        builder: (context) => MusicRankDetailPage(
          api: widget.api,
          rank: rank,
          player: widget.player,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('排行榜'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '榜单'),
              Tab(text: '新歌'),
              Tab(text: '专辑'),
              Tab(text: '歌单'),
              Tab(text: 'IP'),
            ],
          ),
        ),
        // 每个 tab 自建自管加载态；初次只 build 当前页，其余进 tab 才加载。
        body: TabBarView(
          children: <Widget>[
            _RankCatalogTab(api: widget.api, onOpenRank: _openRank),
            _NewSongsTab(
              api: widget.api,
              onOpenSong: _openSong,
              onOpenSongList: _openSongList,
            ),
            _TopAlbumsTab(api: widget.api),
            _TopPlaylistsTab(api: widget.api),
            _TopIpsTab(api: widget.api),
          ],
        ),
      ),
    );
  }
}

/// 五个 tab 的基座：进入后加载一次并保持存活（切 tab 不重挂、不重载）。
abstract class _RankTabBase<T extends StatefulWidget> extends State<T>
    with AutomaticKeepAliveClientMixin {
  /// 各 tab 自己的加载流水号：重试/换分类时递增，过期响应不落 setState。
  int _loadSeq = 0;

  bool _loading = true;

  Object? _error;

  bool get loading => _loading;

  Object? get error => _error;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return buildBody(context);
  }

  /// 子类渲染业务内容（loading/error 已由基座处理）。
  Widget buildContent(BuildContext context);

  /// 子类发起（重）加载；抛错由 [guard] 统一落到错误态。
  Future<void> load();

  /// 包一层加载流水线：loading → 数据 → 错误，全部带 mounted/流水号防御。
  Future<void> guard(Future<void> Function() fetch) async {
    final seq = ++_loadSeq;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await fetch();
    } on Object catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      return;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() => _loading = false);
  }

  Widget buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final e = _error;
    if (e != null) {
      return _ErrorState(message: '$e', onRetry: load);
    }
    return buildContent(context);
  }
}

// ── tab 1：榜单目录（rankTop + rankList 合并去重）──────────────────────────

class _RankCatalogTab extends StatefulWidget {
  const _RankCatalogTab({required this.api, required this.onOpenRank});

  final MusicRankApi api;
  final ValueChanged<MusicRank> onOpenRank;

  @override
  State<_RankCatalogTab> createState() => _RankCatalogTabState();
}

class _RankCatalogTabState extends _RankTabBase<_RankCatalogTab> {
  List<MusicRank> _ranks = const <MusicRank>[];

  @override
  Future<void> load() => guard(() async {
    // rankTop（推荐）排前、rankList（全目录）补齐；并行拉取。
    final results = await Future.wait(<Future<List<MusicRank>>>[
      widget.api.rankTop(),
      widget.api.rankList(),
    ]);
    _ranks = _mergeRanks(results[0], results[1]);
  });

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_ranks.isEmpty) {
      return const _EmptyState(text: '暂无榜单数据');
    }
    // 宽屏自动多列（每列最宽 420）、窄屏单列；行高固定不随列宽抖。
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      itemCount: _ranks.length,
      itemBuilder: (context, index) {
        final rank = _ranks[index];
        return _RankCard(rank: rank, onOpen: () => widget.onOpenRank(rank));
      },
    );
  }
}

/// rankTop + rankList 合并去重（按 id；缺 id 的条目按标题兜底，避免多条
/// 无 id 榜单被挤成一个 key）。推荐榜（rankTop）在前，重复时保留首个。
List<MusicRank> _mergeRanks(List<MusicRank> top, List<MusicRank> list) {
  final merged = <MusicRank>[];
  final seen = <String>{};
  for (final rank in <MusicRank>[...top, ...list]) {
    final key = rank.id != null ? 'id:${rank.id}' : 'title:${rank.title}';
    if (!seen.add(key)) continue;
    merged.add(rank);
  }
  return merged;
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank, required this.onOpen});

  final MusicRank rank;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      // 卡片主题自带 r20/surfaceContainerLow；行级水波纹交给主题。
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              _CoverImage(url: rank.coverUrl, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      rank.title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      rank.updateFrequency,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cs.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rank.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── tab 2：新歌首发（topSongs，固定新歌榜）────────────────────────────────

class _NewSongsTab extends StatefulWidget {
  const _NewSongsTab({
    required this.api,
    required this.onOpenSong,
    required this.onOpenSongList,
  });

  final MusicRankApi api;
  final ValueChanged<MusicSong> onOpenSong;

  /// 双击某行：整张新歌列表 + 起始下标（总页接到 player.playList）。
  final void Function(List<MusicSong> songs, int startIndex) onOpenSongList;

  @override
  State<_NewSongsTab> createState() => _NewSongsTabState();
}

class _NewSongsTabState extends _RankTabBase<_NewSongsTab> {
  List<MusicRankNewSong> _songs = const <MusicRankNewSong>[];

  @override
  Future<void> load() => guard(() async {
    final result = await widget.api.topSongs();
    _songs = result.songs;
  });

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_songs.isEmpty) {
      return const _EmptyState(text: '暂无新歌数据');
    }
    final songs = <MusicSong>[for (final entry in _songs) entry.song];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final entry = _songs[index];
        // 新歌模型本身就是共享 MusicSong（song 字段），无需再映射。
        return MusicSongCard(
          child: _RankSongRow(
            song: entry.song,
            // 榜内位置优先取 chart；缺省退回列表序号。
            position: entry.metadata.chart.position ?? index + 1,
            onTap: () => widget.onOpenSong(entry.song),
            onDoubleTap: () => widget.onOpenSongList(songs, index),
          ),
        );
      },
    );
  }
}

// ── tab 3：新碟榜单（topAlbums，chn/eur/jpn/kor 分组）─────────────────────

class _TopAlbumsTab extends StatefulWidget {
  const _TopAlbumsTab({required this.api});

  final MusicRankApi api;

  @override
  State<_TopAlbumsTab> createState() => _TopAlbumsTabState();
}

class _TopAlbumsTabState extends _RankTabBase<_TopAlbumsTab> {
  Map<String, List<MusicTopAlbumCard>> _regions =
      const <String, List<MusicTopAlbumCard>>{};

  @override
  Future<void> load() => guard(() async {
    final result = await widget.api.topAlbums();
    _regions = result.regions;
  });

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget buildContent(BuildContext context) {
    // wire 恒回 4 个分组；空分组直接不渲染标题。
    final sections = <String, List<MusicTopAlbumCard>>{
      for (final entry in _regions.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    if (sections.isEmpty) {
      return const _EmptyState(text: '暂无新碟数据');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        for (final entry in sections.entries) ...<Widget>[
          _SectionHeader(text: _regionName(entry.key)),
          _CardGrid(
            // 分区嵌在 ListView 里：网格自身不滚动，交给外层滚动。
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entry.value.length,
            itemBuilder: (context, index) {
              final album = entry.value[index];
              return _AlbumCard(album: album);
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// regions 键 → 展示名（top_album.rs：BTreeMap 字典序 chn/eur/jpn/kor）。
  String _regionName(String key) => switch (key) {
    'chn' => '华语',
    'eur' => '欧洲',
    'jpn' => '日本',
    'kor' => '韩国',
    _ => key,
  };
}

// ── tab 4：分类推荐歌单（topPlaylists，默认分类 0）────────────────────────

class _TopPlaylistsTab extends StatefulWidget {
  const _TopPlaylistsTab({required this.api});

  final MusicRankApi api;

  @override
  State<_TopPlaylistsTab> createState() => _TopPlaylistsTabState();
}

class _TopPlaylistsTabState extends _RankTabBase<_TopPlaylistsTab> {
  final TextEditingController _categoryController = TextEditingController(
    text: '0',
  );

  List<MusicRankPlaylistCard> _playlists = const <MusicRankPlaylistCard>[];

  /// 分类输入的本地校验提示；非空时显示在输入行下（input 错误不整页替换，
  /// 输入框保持可见可改）。
  String? _categoryHint;

  @override
  void initState() {
    super.initState();
    _loadCategory(_categoryController.text);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Future<void> load() => _loadCategory(_categoryController.text);

  /// 先用查询类自己的 validate 做 input 校验（行内提示，不走整页错误态），
  /// 再进加载流水线。
  Future<void> _loadCategory(String categoryId) async {
    try {
      MusicTopPlaylistQuery(categoryId: categoryId).validate();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _categoryHint = '$e');
      return;
    }
    if (!mounted) return;
    setState(() => _categoryHint = null);
    await guard(() async {
      _playlists = await widget.api.topPlaylists(
        MusicTopPlaylistQuery(categoryId: categoryId),
      );
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    final hint = _categoryHint;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: '分类 ID'),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _loadCategory(_categoryController.text),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '按分类刷新',
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadCategory(_categoryController.text),
              ),
            ],
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: _playlists.isEmpty
              ? const _EmptyState(text: '暂无歌单数据')
              : _CardGrid(
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) =>
                      _PlaylistCard(playlist: _playlists[index]),
                ),
        ),
      ],
    );
  }
}

// ── tab 5：IP 榜单（topIps）───────────────────────────────────────────────

class _TopIpsTab extends StatefulWidget {
  const _TopIpsTab({required this.api});

  final MusicRankApi api;

  @override
  State<_TopIpsTab> createState() => _TopIpsTabState();
}

class _TopIpsTabState extends _RankTabBase<_TopIpsTab> {
  List<MusicRankPlaylistCard> _ips = const <MusicRankPlaylistCard>[];

  @override
  Future<void> load() => guard(() async {
    _ips = await widget.api.topIps();
  });

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_ips.isEmpty) {
      return const _EmptyState(text: '暂无 IP 数据');
    }
    return _CardGrid(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _ips.length,
      itemBuilder: (context, index) => _PlaylistCard(playlist: _ips[index]),
    );
  }
}

// ── 共享小件 ──────────────────────────────────────────────────────────────

/// 自适应两列网格（列表分区用）：宽屏多列、窄屏单列，行高固定。
class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.physics,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// 分区标题（专辑/歌单卡片区共用）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 新歌行：序号 + 封面 + 标题/歌手 + 时长。
class _RankSongRow extends StatelessWidget {
  const _RankSongRow({
    required this.song,
    required this.position,
    required this.onTap,
    this.onDoubleTap,
  });

  final MusicSong song;
  final int position;
  final VoidCallback onTap;

  /// 双击 → 整张新歌列表替换播放队列；与 [onTap] 同一个 InkWell。
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subtitle = song.albumTitle.isEmpty
        ? song.artistText
        : '${song.artistText} · ${song.albumTitle}';
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: MimaoShapes.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '$position',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: cs.primary),
              ),
            ),
            const SizedBox(width: 8),
            _CoverImage(url: song.coverUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    song.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              _formatRankDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新碟卡片：封面 + 标题 + 歌手 + 发行时间（本切片不进专辑详情，纯展示）。
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final MusicTopAlbumCard album;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = <String>[
      if (album.publishedAt.isNotEmpty) album.publishedAt,
      if (album.songCount != null) '${album.songCount} 首',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            _CoverImage(url: album.coverUrl, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    album.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    album.creator,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 榜单歌单/IP 卡片（top_playlist 与 top_ip 复用同一模型，形态相同）。
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final MusicRankPlaylistCard playlist;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playCount = playlist.metadata.playCount;
    final meta = <String>[
      if (playlist.creator.isNotEmpty) playlist.creator,
      if (playCount != null) '播放 ${_formatRankCount(playCount)}',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            _CoverImage(url: playlist.coverUrl, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    playlist.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    meta,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面（errorBuilder/loadingBuilder 兜底音符占位；与模块页 _SongCover
/// 同款模式，尺寸参数化——网格 64、歌曲行 44）。
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.size});

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
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
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
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 毫秒 → m:ss（无时长/非法值返回空串，与模块页同款）。
String _formatRankDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// 播放数缩写（1.2 万 / 3.4 亿；小数位去尾零）。
String _formatRankCount(int count) {
  if (count >= 100000000) {
    return '${_trimZero((count / 100000000).toStringAsFixed(1))} 亿';
  }
  if (count >= 10000) {
    return '${_trimZero((count / 10000).toStringAsFixed(1))} 万';
  }
  return '$count';
}

String _trimZero(String text) =>
    text.endsWith('.0') ? text.substring(0, text.length - 2) : text;

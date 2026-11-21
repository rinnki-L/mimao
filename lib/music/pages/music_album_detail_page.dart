// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 专辑详情页（U3）：`albumDetail` 头部信息 + `albumSongs` 分页曲目列表。
///
/// 只认 [MusicAlbumApi] / [MusicPlayerUi] 接口，不 import 播放实现；
/// 动态封面（dycover）与收藏计数（favoriteCount）是可选增强——失败静默
/// 回退，不挡页面主体。宽屏两栏（左信息 / 右曲目），窄屏单列。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/album_api.dart';
import 'package:mimao/music/api/album_dycover.dart';
import 'package:mimao/music/api/album_songs.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/models/album_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_song_info_sheet.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 专辑详情页。`onOpenArtist` 为空时歌手名不可点；`playbackExt` 为空时
/// 曲目行不支持长按看资料。
class MusicAlbumDetailPage extends StatefulWidget {
  const MusicAlbumDetailPage({
    super.key,
    required this.album,
    required this.albumId,
    required this.player,
    this.onOpenArtist,
    this.playbackExt,
  });

  final MusicAlbumApi album;
  final int albumId;
  final MusicPlayerUi player;

  /// 点击头部歌手名 → 打开歌手详情（外层壳负责导航）。
  final ValueChanged<int>? onOpenArtist;

  /// 播放补全接口：非空时曲目行长按 → 打开歌曲资料面板（权益/资料/
  /// 歌手图片）。可选项，保持既有调用兼容。
  final MusicPlaybackExtApi? playbackExt;

  @override
  State<MusicAlbumDetailPage> createState() => _MusicAlbumDetailPageState();
}

class _MusicAlbumDetailPageState extends State<MusicAlbumDetailPage> {
  static const int _pageSize = 30;

  MusicAlbumDetail? _detail;
  Object? _detailError;
  bool _loading = true;

  final List<MusicAlbumTrack> _tracks = <MusicAlbumTrack>[];
  int? _tracksTotal;

  /// 下一页页码（只在成功后前进；失败重试拉同一页）。
  int _tracksNextPage = 1;
  bool _tracksLoading = false;
  bool _loadingMore = false;
  Object? _tracksError;

  /// 可选增强：动态封面 / 收藏数（失败不挡页面）。
  String? _dycoverUrl;
  String? _favoriteText;

  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _detailError = null;
      _descExpanded = false;
      _dycoverUrl = null;
      _favoriteText = null;
    });
    try {
      final detail = await widget.album.albumDetail(widget.albumId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _detailError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (_detail != null) {
      _loadTracks(reset: true);
      _loadDycover();
      _loadFavoriteCount();
    }
  }

  /// 曲目分页：`reset=true` 拉第 1 页（重置列表）；否则按 [MusicPage] 的
  /// page/total 追加下一页。请求中防重复（首页与加载更多各自有闸）。
  Future<void> _loadTracks({required bool reset}) async {
    if (reset) {
      setState(() {
        _tracks.clear();
        _tracksTotal = null;
        _tracksNextPage = 1;
        _tracksError = null;
        _tracksLoading = true;
      });
    } else {
      if (_loadingMore || _tracksLoading) return;
      setState(() => _loadingMore = true);
    }
    final page = reset ? 1 : _tracksNextPage;
    try {
      final result = await widget.album.albumSongs(
        AlbumSongsQuery(id: widget.albumId, page: page, pageSize: _pageSize),
      );
      if (!mounted) return;
      setState(() {
        _tracksNextPage = page + 1;
        _tracksTotal = result.page.total ?? _tracksTotal;
        _tracks.addAll(result.page.items);
        _sortTracksStable();
        _tracksError = null;
        _tracksLoading = false;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _tracksError = error;
        _tracksLoading = false;
        _loadingMore = false;
      });
    }
  }

  /// 按 disc/position 稳定排序：Dart 的 sort 不保证稳定，缺序字段时回退
  /// 追加顺序（原始下标），保证同键曲目不被打乱。
  void _sortTracksStable() {
    final indexed = <(int, MusicAlbumTrack)>[
      for (final (index, track) in _tracks.indexed) (index, track),
    ];
    indexed.sort((a, b) {
      final byDisc = (a.$2.disc ?? 0).compareTo(b.$2.disc ?? 0);
      if (byDisc != 0) return byDisc;
      final byPosition = (a.$2.position ?? a.$1).compareTo(
        b.$2.position ?? b.$1,
      );
      if (byPosition != 0) return byPosition;
      return a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < indexed.length; i++) {
      _tracks[i] = indexed[i].$2;
    }
  }

  /// 动态封面：成功替换头部封面图；失败/无可用 URL 静默回退静态封面。
  Future<void> _loadDycover() async {
    try {
      final cover = await widget.album.albumDycover(
        AlbumDycoverQuery(albumAudioId: 0, albumId: widget.albumId),
      );
      final url = (cover == null || cover.urls.isEmpty)
          ? null
          : cover.urls.first;
      if (!mounted || url == null) return;
      setState(() => _dycoverUrl = url);
    } on Object {
      // 可选增强：失败不挡页面。
    }
  }

  /// 收藏计数：按传入 id 命中的条目展示服务端格式化文本；失败忽略。
  Future<void> _loadFavoriteCount() async {
    try {
      final counts = await widget.album.favoriteCount(<int>[widget.albumId]);
      MusicAlbumFavoriteCount? match;
      for (final count in counts) {
        if (count.mixsongId == widget.albumId) match = count;
      }
      final text = match == null
          ? null
          : (match.countText.isNotEmpty
                ? match.countText
                : _countText(match.count));
      if (!mounted || text == null) return;
      setState(() => _favoriteText = text);
    } on Object {
      // 可选增强：失败忽略。
    }
  }

  void _playTrack(MusicSong song) {
    // 与模块主页同款：先起播（地址异步解析）再打开播放页。
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
      appBar: AppBar(title: Text(_appBarTitle)),
      body: _buildBody(context),
    );
  }

  String get _appBarTitle {
    final detail = _detail;
    if (detail != null && detail.title.isNotEmpty) return detail.title;
    return '专辑详情';
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _detailError;
    if (error != null) {
      return _ErrorState(message: '$error', onRetry: _reload);
    }
    final detail = _detail;
    if (detail == null) {
      return const _NotFoundState();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final header = _AlbumHeader(
          detail: detail,
          dycoverUrl: _dycoverUrl,
          favoriteText: _favoriteText,
          descExpanded: _descExpanded,
          onToggleDesc: () => setState(() => _descExpanded = !_descExpanded),
          onOpenArtist: widget.onOpenArtist,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: header,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: _trackChildren(context),
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            header,
            const SizedBox(height: 12),
            ..._trackChildren(context),
          ],
        );
      },
    );
  }

  /// 曲目区（不含头部）：标题行 + 列表/加载/错误/空态 + 加载更多。
  List<Widget> _trackChildren(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = <Widget>[
      Row(
        children: <Widget>[
          Text(
            _tracksTotal == null ? '曲目' : '曲目（$_tracksTotal）',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
      const SizedBox(height: 4),
    ];
    if (_tracksLoading && _tracks.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return children;
    }
    if (_tracks.isEmpty && _tracksError != null) {
      children.add(
        _ErrorState(
          message: '$_tracksError',
          onRetry: () => _loadTracks(reset: true),
        ),
      );
      return children;
    }
    if (_tracks.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              '专辑暂无曲目',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
      return children;
    }
    for (final (index, track) in _tracks.indexed) {
      children.add(
        MusicSongCard(
          child: _TrackTile(
            index: index + 1,
            track: track,
            onTap: () => _playTrack(track.song),
            // 播放补全接口未接线时长按不响应（资料面板需要它）。
            onLongPress: widget.playbackExt == null
                ? null
                : () => showMusicSongInfoSheet(
                    context,
                    song: track.song,
                    ext: widget.playbackExt,
                  ),
          ),
        ),
      );
    }
    if (_tracksError != null) {
      // 追加页失败：保留已加载内容，行内给出重试。
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '$_tracksError',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _loadTracks(reset: false),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (_hasMoreTracks) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _loadingMore ? null : () => _loadTracks(reset: false),
            icon: _loadingMore
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: const Text('加载更多'),
          ),
        ),
      );
    }
    return children;
  }

  bool get _hasMoreTracks {
    final total = _tracksTotal;
    if (total == null) return false;
    return _tracks.length < total;
  }
}

/// 头部：封面 / 标题 / 歌手（可点）/ 发行 / 语言 / 类型 / 热度 / 简介等。
class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.detail,
    required this.dycoverUrl,
    required this.favoriteText,
    required this.descExpanded,
    required this.onToggleDesc,
    required this.onOpenArtist,
  });

  final MusicAlbumDetail detail;
  final String? dycoverUrl;
  final String? favoriteText;
  final bool descExpanded;
  final VoidCallback onToggleDesc;
  final ValueChanged<int>? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badges = <Widget>[
      if (detail.exclusive == true) const _Badge(label: '独家', emphasized: true),
      if (detail.published == false) const _Badge(label: '未发布'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _DetailCover(url: dycoverUrl ?? detail.coverUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    detail.title.isEmpty ? '未知专辑' : detail.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _ArtistChips(
                    artists: detail.artists,
                    onOpenArtist: onOpenArtist,
                  ),
                  if (badges.isNotEmpty || favoriteText != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        ...badges,
                        if (favoriteText != null)
                          _Badge(
                            label: '收藏 $favoriteText',
                            icon: Icons.favorite_border,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (detail.publishedAt.isNotEmpty)
          _MetaRow(label: '发行', value: detail.publishedAt),
        if (detail.publisher.isNotEmpty)
          _MetaRow(label: '厂牌', value: detail.publisher),
        if (detail.language.isNotEmpty)
          _MetaRow(label: '语言', value: detail.language),
        if (detail.category.isNotEmpty)
          _MetaRow(label: '类型', value: detail.category),
        if (detail.heat != null) _MetaRow(label: '热度', value: '${detail.heat}'),
        const SizedBox(height: 12),
        if (detail.description.isNotEmpty) ...<Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('简介', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Text(
            detail.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: descExpanded ? null : 4,
            overflow: descExpanded ? null : TextOverflow.ellipsis,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggleDesc,
              child: Text(descExpanded ? '收起' : '展开'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 歌手名 chips：有 id 且外层接线了 onOpenArtist 才可点。
class _ArtistChips extends StatelessWidget {
  const _ArtistChips({required this.artists, required this.onOpenArtist});

  final List<MusicArtistRef> artists;
  final ValueChanged<int>? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final callback = onOpenArtist;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final (index, artist) in artists.indexed) ...<Widget>[
          if (index > 0) Text('/', style: theme.textTheme.bodyMedium),
          if (callback != null && artist.id != null)
            InkWell(
              borderRadius: MimaoShapes.sm,
              onTap: () => callback(artist.id!),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  artist.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            )
          else
            Text(artist.name, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// 曲目行：序号 / 封面 / 标题 / 歌手 / 时长；长按打开歌曲资料面板（可选）。
class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.index,
    required this.track,
    required this.onTap,
    this.onLongPress,
  });

  final int index;
  final MusicAlbumTrack track;
  final VoidCallback onTap;

  /// 长按曲目 → 歌曲资料面板；未接线播放补全接口时为 null。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = track.song;
    final subtitle = song.artistText;
    return ListTile(
      leading: _SongCover(url: song.coverUrl),
      title: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMusicDuration(song.durationMs),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 秒 → m:ss；未知时长返回空串。
String formatMusicDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// 收藏数兜底：服务端没给格式化文本时用原始数字。
String _countText(int? count) => count == null ? '' : '$count';

/// 小徽标（独家 / 收藏数）。
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.emphasized = false, this.icon});

  final String label;
  final bool emphasized;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: MimaoShapes.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: 12,
              color: emphasized
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: emphasized
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 头部封面（112×112，r20）；无 URL / 失败回退音符占位。
class _DetailCover extends StatelessWidget {
  const _DetailCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 112,
      height: 112,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.lg,
      ),
      child: Icon(Icons.album, size: 40, color: scheme.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.lg,
      child: Image.network(
        url,
        width: 112,
        height: 112,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        // 加载中维持占位（与模块主页封面同款，不闪空块）。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 曲目封面缩略图（44×44，r10）。
class _SongCover extends StatelessWidget {
  const _SongCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: scheme.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 元信息行（发行 / 厂牌 / 语言 / 类型 / 热度）。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 错误态（带重试）——与模块主页同构。
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

/// 专辑详情接口成功但无此专辑（上游 null 语义）：不算错误，给空态。
class _NotFoundState extends StatelessWidget {
  const _NotFoundState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '没有找到这张专辑',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

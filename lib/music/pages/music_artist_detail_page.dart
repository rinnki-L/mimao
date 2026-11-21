// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 歌手详情页（U3）：`artistDetail` 头部 + `artistAlbums` 专辑网格 +
/// `artistAudiosNew` 歌曲列表 + `artistLists` 可选目录分区 +
/// 「歌手写真」可选分区（images_audio，需接线 playbackExt）。
///
/// 只认 [MusicArtistApi] / [MusicPlayerUi] 接口；目录（artistLists）与写真
/// 都是可选增强——目录失败给行内提示；写真失败/空数据整段隐藏。均不挡
/// 头部/专辑/歌曲主体。宽屏两栏（左信息 / 右列表），窄屏单列。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/artist_albums.dart';
import 'package:mimao/music/api/artist_api.dart';
import 'package:mimao/music/api/artist_audios_new.dart';
import 'package:mimao/music/api/artist_lists.dart';
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_album_detail_page.dart'
    show formatMusicDuration;
import 'package:mimao/music/pages/music_song_info_sheet.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 歌手详情页。`onOpenAlbum` 为空时专辑卡不可点；`playbackExt` 为空时
/// 不展示「歌手写真」分区。
class MusicArtistDetailPage extends StatefulWidget {
  const MusicArtistDetailPage({
    super.key,
    required this.artist,
    required this.artistId,
    required this.player,
    this.onOpenAlbum,
    this.playbackExt,
  });

  final MusicArtistApi artist;
  final int artistId;
  final MusicPlayerUi player;

  /// 点击专辑卡 → 打开专辑详情（外层壳负责导航）。
  final ValueChanged<int>? onOpenAlbum;

  /// 播放补全接口：非空时用歌曲 hash 拉一次歌手写真（images_audio）。
  /// 可选项，保持既有调用兼容。
  final MusicPlaybackExtApi? playbackExt;

  @override
  State<MusicArtistDetailPage> createState() => _MusicArtistDetailPageState();
}

class _MusicArtistDetailPageState extends State<MusicArtistDetailPage> {
  static const int _pageSize = 30;

  /// 歌手写真查询的资源上限（规格：歌曲 hash 去重、最多 20）。
  static const int _portraitMaxResources = 20;

  MusicArtistDetail? _detail;
  Object? _detailError;
  bool _loading = true;

  final List<MusicAlbumSummary> _albums = <MusicAlbumSummary>[];
  int? _albumsTotal;
  int _albumsNextPage = 1;
  bool _albumsLoading = false;
  bool _albumsLoadingMore = false;
  Object? _albumsError;

  final List<MusicArtistSong> _songs = <MusicArtistSong>[];
  int? _songsTotal;
  int _songsNextPage = 1;
  bool _songsLoading = false;
  bool _songsLoadingMore = false;
  Object? _songsError;

  // ── 可选目录（artistLists）：失败给行内提示，不挡主体 ──
  MusicArtistDirectory? _directory;
  Object? _directoryError;
  bool _directoryLoading = false;
  int _sexFilter = 0;
  int _categoryFilter = 0;
  int _musicianFilter = 0;

  // ── 可选歌手写真（images_audio）：失败/空数据整段隐藏（装饰性分区）──
  List<MusicPortrait> _portraits = const <MusicPortrait>[];

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
    });
    try {
      final detail = await widget.artist.artistDetail(widget.artistId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _detailError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (_detail != null) {
      _loadAlbums(reset: true);
      _loadSongs(reset: true);
      _loadDirectory();
    }
  }

  /// 专辑分页（reset=true 拉第 1 页；否则追加下一页，请求中防重复）。
  Future<void> _loadAlbums({required bool reset}) async {
    if (reset) {
      setState(() {
        _albums.clear();
        _albumsTotal = null;
        _albumsNextPage = 1;
        _albumsError = null;
        _albumsLoading = true;
      });
    } else {
      if (_albumsLoadingMore || _albumsLoading) return;
      setState(() => _albumsLoadingMore = true);
    }
    final page = reset ? 1 : _albumsNextPage;
    try {
      final result = await widget.artist.artistAlbums(
        MusicArtistAlbumsQuery(
          id: widget.artistId,
          page: page,
          pageSize: _pageSize,
        ),
      );
      if (!mounted) return;
      setState(() {
        _albumsNextPage = page + 1;
        _albumsTotal = result.total ?? _albumsTotal;
        _albums.addAll(result.items);
        _albumsError = null;
        _albumsLoading = false;
        _albumsLoadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _albumsError = error;
        _albumsLoading = false;
        _albumsLoadingMore = false;
      });
    }
  }

  /// 歌曲分页：平铺的 [MusicArtistSong] 在点击/展示时映射为 [MusicSong]。
  Future<void> _loadSongs({required bool reset}) async {
    if (reset) {
      setState(() {
        _songs.clear();
        _songsTotal = null;
        _songsNextPage = 1;
        _songsError = null;
        _songsLoading = true;
      });
    } else {
      if (_songsLoadingMore || _songsLoading) return;
      setState(() => _songsLoadingMore = true);
    }
    final page = reset ? 1 : _songsNextPage;
    try {
      final result = await widget.artist.artistAudiosNew(
        MusicArtistAudiosQuery(
          id: widget.artistId,
          page: page,
          pageSize: _pageSize,
        ),
      );
      if (!mounted) return;
      setState(() {
        _songsNextPage = page + 1;
        _songsTotal = result.total ?? _songsTotal;
        _songs.addAll(result.items);
        _songsError = null;
        _songsLoading = false;
        _songsLoadingMore = false;
      });
      if (reset) _loadPortraits(); // 歌曲首页成功后刷新写真（可选增强）
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _songsError = error;
        _songsLoading = false;
        _songsLoadingMore = false;
      });
    }
  }

  /// 歌手写真（可选增强）：用已加载歌曲的 hash 去重（最多 20）查询一次。
  /// 失败/空数据整段隐藏——装饰性分区，不给重试入口，不打扰主体。
  Future<void> _loadPortraits() async {
    final ext = widget.playbackExt;
    if (ext == null) return;
    final resources = <ImagesAudioResource>[];
    final seen = <String>{};
    for (final song in _songs) {
      if (resources.length >= _portraitMaxResources) break;
      final hash = song.hash;
      if (!isValidResourceHash(hash) || !seen.add(hash)) continue;
      resources.add(ImagesAudioResource(hash: hash, filename: song.title));
    }
    if (resources.isEmpty) return;
    try {
      final groups = await ext.imagesAudio(
        ImagesAudioQuery(resources: resources),
      );
      if (!mounted) return;
      setState(() => _portraits = flattenAuthorImages(groups));
    } on Object {
      if (!mounted) return;
      setState(() => _portraits = const <MusicPortrait>[]);
    }
  }

  /// 歌手目录（可选分区）：sex/category 筛选变化时重新拉取。
  Future<void> _loadDirectory() async {
    setState(() {
      _directoryLoading = true;
      _directoryError = null;
    });
    try {
      final directory = await widget.artist.artistLists(
        MusicArtistListsQuery(
          sex: _sexFilter,
          category: _categoryFilter,
          musician: _musicianFilter,
        ),
      );
      if (!mounted) return;
      setState(() => _directory = directory);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _directory = null;
        _directoryError = error;
      });
    } finally {
      if (mounted) setState(() => _directoryLoading = false);
    }
  }

  void _playSong(MusicArtistSong item) {
    // 与模块主页同款：先起播（地址异步解析）再打开播放页。
    widget.player.playSong(artistSongToMusicSong(item));
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
    if (detail != null && detail.name.isNotEmpty) return detail.name;
    return '歌手详情';
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
        final header = _ArtistHeader(
          detail: detail,
          descExpanded: _descExpanded,
          onToggleDesc: () => setState(() => _descExpanded = !_descExpanded),
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
                  children: <Widget>[
                    ..._albumChildren(context),
                    const SizedBox(height: 12),
                    ..._songChildren(context),
                    _portraitSection(context),
                    const SizedBox(height: 12),
                    _directorySection(context),
                  ],
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
            ..._albumChildren(context),
            const SizedBox(height: 12),
            ..._songChildren(context),
            _portraitSection(context),
            const SizedBox(height: 12),
            _directorySection(context),
          ],
        );
      },
    );
  }

  /// 专辑区：标题 + 网格 / 加载 / 错误 / 空态 + 加载更多。
  List<Widget> _albumChildren(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = <Widget>[
      Text(
        _sectionTitle('专辑', _albumsTotal),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
    ];
    if (_albumsLoading && _albums.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return children;
    }
    if (_albums.isEmpty && _albumsError != null) {
      children.add(
        _ErrorState(
          message: '$_albumsError',
          onRetry: () => _loadAlbums(reset: true),
        ),
      );
      return children;
    }
    if (_albums.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '暂无专辑',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      return children;
    }
    children.add(
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.72,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: _albums.length,
        itemBuilder: (context, index) =>
            _AlbumCard(album: _albums[index], onOpenAlbum: widget.onOpenAlbum),
      ),
    );
    if (_albumsError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  '$_albumsError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => _loadAlbums(reset: false),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (_hasMore(_albums.length, _albumsTotal)) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _albumsLoadingMore
                ? null
                : () => _loadAlbums(reset: false),
            icon: _albumsLoadingMore
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

  /// 歌曲区：标题 + 列表 / 加载 / 错误 / 空态 + 加载更多。
  List<Widget> _songChildren(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = <Widget>[
      Text(
        _sectionTitle('歌曲', _songsTotal),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
    ];
    if (_songsLoading && _songs.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return children;
    }
    if (_songs.isEmpty && _songsError != null) {
      children.add(
        _ErrorState(
          message: '$_songsError',
          onRetry: () => _loadSongs(reset: true),
        ),
      );
      return children;
    }
    if (_songs.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '暂无歌曲',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      return children;
    }
    for (final (index, item) in _songs.indexed) {
      children.add(
        _ArtistSongTile(
          index: index + 1,
          song: item,
          onTap: () => _playSong(item),
        ),
      );
    }
    if (_songsError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  '$_songsError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => _loadSongs(reset: false),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (_hasMore(_songs.length, _songsTotal)) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _songsLoadingMore
                ? null
                : () => _loadSongs(reset: false),
            icon: _songsLoadingMore
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

  /// 歌手写真分区（可选）：仅在接线 playbackExt 且拿到写真时出现；
  /// 加载中/失败/空数据都整段隐藏（返回零尺寸，不留空档）。
  Widget _portraitSection(BuildContext context) {
    final portraits = _portraits;
    if (widget.playbackExt == null || portraits.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('歌手写真', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          MusicPortraitStrip(portraits: portraits),
        ],
      ),
    );
  }

  /// 可选目录分区（artistLists）：分组卡片 + 性别/类型筛选 chips。
  /// 失败只给行内提示与重试，不影响主体。
  Widget _directorySection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final directory = _directory;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('歌手目录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final (index, filter) in _sexFiltersIndexed)
                  ChoiceChip(
                    label: Text(
                      filter.label.isEmpty ? '性别${index + 1}' : filter.label,
                    ),
                    selected: _sexFilter == filter.category,
                    onSelected: (_) {
                      setState(() => _sexFilter = filter.category);
                      _loadDirectory();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final (index, filter) in _typeFiltersIndexed)
                  ChoiceChip(
                    label: Text(
                      filter.label.isEmpty ? '类型${index + 1}' : filter.label,
                    ),
                    selected:
                        _categoryFilter == filter.category &&
                        _musicianFilter == (filter.musician ?? 0),
                    onSelected: (_) {
                      setState(() {
                        _categoryFilter = filter.category;
                        _musicianFilter = filter.musician ?? 0;
                      });
                      _loadDirectory();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_directoryLoading)
              const Center(child: CircularProgressIndicator())
            else if (directory != null)
              _DirectoryGroups(directory: directory)
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${_directoryError ?? '歌手目录暂不可用'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _directoryLoading ? null : _loadDirectory,
                    child: const Text('重试目录'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<MusicArtistFilter> get _sexFilters =>
      _directory?.sexFilters ?? const <MusicArtistFilter>[];

  List<MusicArtistFilter> get _typeFilters =>
      _directory?.typeFilters ?? const <MusicArtistFilter>[];

  Iterable<(int, MusicArtistFilter)> get _sexFiltersIndexed =>
      _sexFilters.indexed;

  Iterable<(int, MusicArtistFilter)> get _typeFiltersIndexed =>
      _typeFilters.indexed;

  bool _hasMore(int loaded, int? total) => total != null && loaded < total;

  String _sectionTitle(String label, int? total) =>
      total == null ? label : '$label（$total）';
}

/// MusicArtistSong（平铺结构）→ 播放链路的 MusicSong；资源表从目录事实
/// 原样带上，便于播放器选择更高音质。
MusicSong artistSongToMusicSong(MusicArtistSong song) => MusicSong(
  id: song.id,
  hash: song.hash,
  title: song.title,
  artists: song.artists,
  albumId: song.albumId,
  albumTitle: song.albumTitle ?? '',
  durationMs: song.durationMs,
  coverUrl: song.coverUrl,
  privilege: song.privilege,
  resources: song.metadata.resources,
);

/// 头部：头像 / 名字 / 粉丝等统计 / 简介。
class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.detail,
    required this.descExpanded,
    required this.onToggleDesc,
  });

  final MusicArtistDetail detail;
  final bool descExpanded;
  final VoidCallback onToggleDesc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _ArtistAvatar(url: detail.avatarUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    detail.name.isEmpty ? '未知歌手' : detail.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: <Widget>[
                      if (detail.fans != null)
                        _Stat(label: '粉丝', value: detail.fans!),
                      if (detail.albumCount != null)
                        _Stat(label: '专辑', value: detail.albumCount!),
                      if (detail.mvCount != null)
                        _Stat(label: 'MV', value: detail.mvCount!),
                      if (detail.published == false) const _PendingBadge(),
                    ],
                  ),
                  if (detail.birthday.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '生日：${detail.birthday}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (detail.description.isNotEmpty) ...<Widget>[
          Text('简介', style: theme.textTheme.titleMedium),
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

/// 统计项（粉丝 / 专辑 / MV）。
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: <TextSpan>[
          TextSpan(text: '$value ', style: theme.textTheme.titleMedium),
          TextSpan(
            text: label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 未发布徽标。
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(
        '未发布',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// 歌手头像（96×96 圆形）；无 URL / 失败回退人形占位。
class _ArtistAvatar extends StatelessWidget {
  const _ArtistAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: 40, color: scheme.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 专辑卡：封面（1:1）/ 标题 / 歌手 / 发行时间。id 缺省或未接线时不可点。
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onOpenAlbum});

  final MusicAlbumSummary album;
  final ValueChanged<int>? onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final callback = onOpenAlbum;
    final id = album.id;
    final subtitle = album.artistText;
    return InkWell(
      borderRadius: MimaoShapes.md,
      onTap: callback != null && id != null ? () => callback(id) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(aspectRatio: 1, child: _GridCover(url: album.coverUrl)),
          const SizedBox(height: 6),
          Text(
            album.title.isEmpty ? '未知专辑' : album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (album.publishedAt.isNotEmpty)
            Text(
              album.publishedAt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// 网格封面（自适应方形，r14）。
class _GridCover extends StatelessWidget {
  const _GridCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.md,
      ),
      child: Icon(Icons.album, color: scheme.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.md,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 歌手歌曲行：序号 / 封面 / 标题 / 歌手·专辑 / 时长。
class _ArtistSongTile extends StatelessWidget {
  const _ArtistSongTile({
    required this.index,
    required this.song,
    required this.onTap,
  });

  final int index;
  final MusicArtistSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artist = song.artistText;
    final album = song.albumTitle;
    final parts = <String>[
      if (artist.isNotEmpty) artist,
      if (album != null && album.isNotEmpty) album,
    ];
    return ListTile(
      leading: _ThumbCover(url: song.coverUrl),
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
      subtitle: parts.isEmpty
          ? null
          : Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Text(
        formatMusicDuration(song.durationMs),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// 列表封面缩略图（44×44，r10）。
class _ThumbCover extends StatelessWidget {
  const _ThumbCover({required this.url});

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

/// 目录分组：组标签 + 该组歌手卡（显示层；详情页无「打开其它歌手」回调）。
class _DirectoryGroups extends StatelessWidget {
  const _DirectoryGroups({required this.directory});

  final MusicArtistDirectory directory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (directory.groups.isEmpty) {
      return Text(
        '该分类下暂无歌手',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final group in directory.groups) ...<Widget>[
          Text(group.label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final card in group.artists) _DirectoryCardChip(card: card),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 目录歌手卡 chip：头像 + 名字；description 存在时长按看提示。
/// （详情页没有「打开其它歌手」的回调，目录卡仅展示。）
class _DirectoryCardChip extends StatelessWidget {
  const _DirectoryCardChip({required this.card});

  final MusicArtistCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = card.metadata.description;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: MimaoShapes.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _DirectoryAvatar(url: card.coverUrl),
          const SizedBox(width: 6),
          Text(
            card.title.isEmpty ? '未知歌手' : card.title,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
    if (description == null || description.isEmpty) return chip;
    return Tooltip(message: description, child: chip);
  }
}

/// 目录卡小头像（24×24 圆形；失败静默隐藏）。
class _DirectoryAvatar extends StatelessWidget {
  const _DirectoryAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Icon(
        Icons.person,
        size: 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(width: 24, height: 24),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const SizedBox(width: 24, height: 24),
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

/// 歌手详情接口成功但无数据（上游 null 语义）：不算错误，给空态。
class _NotFoundState extends StatelessWidget {
  const _NotFoundState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '没有找到这位歌手',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

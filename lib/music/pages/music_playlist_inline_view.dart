// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 侧栏歌单的内嵌视图（2026-11-22 侧栏主从化）。
///
/// 点侧栏歌单行不再 push 详情页：模块内容区直接切到本视图（IndexedStack
/// 保活，切走再切回不重拉）。只读：歌曲行沿用「我喜欢」页的全宽卡片条
/// （MusicSongCard，无详情页的居中收窄），行点按起播、双击已加载列表
/// 整体替换队列；写操作（删歌/排序/编辑信息）仍在 push 的歌单详情页与
/// 歌单管理页。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_track_all.dart'
    show MusicPlaylistTrackAllQuery;
import 'package:mimao/music/api/playlist_track_all_new.dart'
    show MusicPlaylistTrackAllNewQuery;
import 'package:mimao/music/models/music_models.dart' show MusicPage, MusicSong;
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 歌单内嵌视图：头部（封面/标题/创建者/简介 + 分隔线）+ 全宽曲目卡列表。
class MusicPlaylistInlineView extends StatefulWidget {
  const MusicPlaylistInlineView({
    super.key,
    required this.read,
    required this.player,
    required this.playlist,
  });

  /// 歌单读端点组（曲目分页）。
  final MusicPlaylistReadApi read;

  /// 播放 UI：行点按起播（迷你条接管控制）。
  final MusicPlayerUi player;

  /// 侧栏选中的歌单行事实（title/cover/creator + id 选边已完成）。
  final MusicUserPlaylist playlist;

  @override
  State<MusicPlaylistInlineView> createState() =>
      _MusicPlaylistInlineViewState();
}

class _MusicPlaylistInlineViewState extends State<MusicPlaylistInlineView> {
  /// 曲目分页大小（与歌单详情页同款）。
  static const int _pageSize = 50;

  _Phase _phase = _Phase.loading;
  List<MusicPlaylistTrack> _tracks = const <MusicPlaylistTrack>[];
  bool _hasMore = false;
  bool _loadingMore = false;
  int _nextPage = 2;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // ── 数据装配 ────────────────────────────────────────────────────────────

  /// 自建行（有真 listid）走云端端点；收藏行走公开端点（globalId 已由
  /// [MusicUserPlaylist.publicGlobalId] 选为创作者真 id）。
  Future<MusicPage<MusicPlaylistTrack>> _fetch(int page) async {
    final playlist = widget.playlist;
    final useCloud =
        playlist.cloudListId != null &&
        playlist.kind != MusicCloudPlaylistKind.collected;
    if (useCloud) {
      final result = await widget.read.playlistTrackAllNew(
        MusicPlaylistTrackAllNewQuery(
          cloudListId: playlist.cloudListId!,
          page: page,
          pageSize: _pageSize,
        ),
      );
      return result.page;
    }
    return widget.read.playlistTrackAll(
      MusicPlaylistTrackAllQuery(
        globalId: playlist.publicGlobalId,
        page: page,
        pageSize: _pageSize,
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _tracks = const <MusicPlaylistTrack>[];
    });
    try {
      final tracks = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _tracks = tracks.items;
        _applyPage(tracks);
        _phase = _Phase.ready;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final tracks = await _fetch(_nextPage);
      if (!mounted) return;
      setState(() {
        _tracks = <MusicPlaylistTrack>[..._tracks, ...tracks.items];
        _applyPage(tracks);
        _loadingMore = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('加载更多失败，请重试')));
    }
  }

  /// total 缺省时按「末页不满一页」推断是否还有更多（详情页同款规则）。
  void _applyPage(MusicPage<MusicPlaylistTrack> page) {
    final total = page.total;
    _hasMore = total != null
        ? _tracks.length < total
        : page.items.length >= _pageSize;
    _nextPage = (page.page ?? 1) + 1;
  }

  // ── 播放 ────────────────────────────────────────────────────────────────

  /// 行点按起播（不跳播放页，迷你条接管控制；「我喜欢」页同款）。
  void _playAt(int index) {
    widget.player.playSong(_tracks[index].song);
  }

  /// 双击：已加载列表整体替换队列并从该行起播。
  void _playListFrom(int index) {
    widget.player.playList(<MusicSong>[
      for (final track in _tracks) track.song,
    ], startIndex: index);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 400 &&
        _hasMore &&
        !_loadingMore &&
        _phase == _Phase.ready) {
      unawaited(_loadMore());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final playlist = widget.playlist;
    final count = playlist.songCount;
    final meta = <String>[
      if (playlist.creatorName.isNotEmpty) '创建者：${playlist.creatorName}',
      if (count != null && count > 0) '共 $count 首',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Cover(url: playlist.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: MimaoFonts.bold,
                      ),
                    ),
                    if (meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (playlist.descriptionPresent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              playlist.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 1, color: cs.outlineVariant),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_phase) {
      _Phase.loading => const Center(child: CircularProgressIndicator()),
      _Phase.error => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('歌单加载失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      ),
      _Phase.ready when _tracks.isEmpty => Center(
        child: Text(
          '歌单里还没有歌曲',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      _Phase.ready => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _tracks.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _tracks.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              );
            }
            final track = _tracks[index];
            final song = track.song;
            return MusicSongCard(
              child: InkWell(
                onTap: () => _playAt(index),
                onDoubleTap: () => _playListFrom(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 8),
                      _Cover(url: song.coverUrl, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song.artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DurationText(durationMs: song.durationMs),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    };
  }
}

enum _Phase { loading, ready, error }

/// 歌单封面（64×64，r-md）；无 URL/加载失败回退音符占位。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, this.size = 64});

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
      child: Icon(Icons.queue_music, size: size / 2, color: cs.primary),
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

/// 行尾时长（mm:ss；缺省不占位）。
class _DurationText extends StatelessWidget {
  const _DurationText({required this.durationMs});

  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    final ms = durationMs ?? 0;
    if (ms <= 0) return const SizedBox.shrink();
    final seconds = ms ~/ 1000;
    return Text(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

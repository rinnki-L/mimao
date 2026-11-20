// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 榜单详情页（U2）：单个榜单的 rankAudio 歌曲列表。
///
/// 只认 [MusicRankApi] 与 [MusicPlayerUi]；AppBar 自带返回按钮，不依赖
/// 外层壳（可独立 push，也可在嵌入层打开）。rank.id 缺失时不发请求，
/// 直接落错误态。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/rank_api.dart';
import 'package:mimao/music/api/rank_audio.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/rank_models.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 榜单详情页。
class MusicRankDetailPage extends StatefulWidget {
  const MusicRankDetailPage({
    super.key,
    required this.api,
    required this.rank,
    required this.player,
  });

  final MusicRankApi api;
  final MusicRank rank;
  final MusicPlayerUi player;

  @override
  State<MusicRankDetailPage> createState() => _MusicRankDetailPageState();
}

class _MusicRankDetailPageState extends State<MusicRankDetailPage> {
  int _loadSeq = 0;
  bool _loading = true;
  Object? _error;
  List<MusicRankSong> _songs = const <MusicRankSong>[];

  @override
  void initState() {
    super.initState();
    load();
  }

  /// （重）加载榜单歌曲；rank.id 缺失时不打网络、直接报「榜单无效」。
  Future<void> load() async {
    final rankId = widget.rank.id;
    if (rankId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = const _RankIdMissing();
      });
      return;
    }
    final seq = ++_loadSeq;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.rankAudio(
        MusicRankAudioQuery(rankId: rankId),
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _songs = result.songs;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openSong(MusicRankSong entry) {
    // 与总页/模块页同款次序：先起播再 push 播放页。
    widget.player.playSong(entry.song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rank = widget.rank;
    return Scaffold(
      appBar: AppBar(title: Text(rank.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (rank.updateFrequency.isNotEmpty ||
              rank.description.isNotEmpty ||
              (rank.publishedAt?.isNotEmpty ?? false))
            _RankHeader(rank: rank),
          Expanded(child: _buildSongs(context)),
        ],
      ),
    );
  }

  Widget _buildSongs(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final e = _error;
    if (e != null) {
      return _DetailErrorState(message: '$e', onRetry: load);
    }
    if (_songs.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Text(
          '暂无歌曲',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final entry = _songs[index];
        // rankAudio 的歌曲摘要本身就是共享 MusicSong（song 字段）。
        return _DetailSongRow(
          song: entry.song,
          // 榜内位置优先取 ranking.position；缺省退回列表序号。
          position: entry.metadata.ranking?.position ?? index + 1,
          remark: _remarkOf(entry),
          onTap: () => _openSong(entry),
        );
      },
    );
  }

  /// 版本备注（remarks，如「Live」/「Remix」）拼到副标题；无则返回空串。
  String _remarkOf(MusicRankSong entry) {
    final remarks = entry.metadata.relatedVersions;
    if (remarks.isEmpty) return '';
    return remarks.map((r) => r.remark).where((t) => t.isNotEmpty).join(' / ');
  }
}

/// 头部：更新频率 + 发布期 + 简介（全部缺省时整块不渲染，由 build 控制）。
class _RankHeader extends StatelessWidget {
  const _RankHeader({required this.rank});

  final MusicRank rank;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final facts = <String>[
      if (rank.updateFrequency.isNotEmpty) rank.updateFrequency,
      if (rank.publishedAt?.isNotEmpty ?? false) rank.publishedAt!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (facts.isNotEmpty)
            Text(
              facts,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.primary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (rank.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                rank.description,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌曲行：序号 + 封面 + 标题/歌手（可带版本备注）+ 时长。
class _DetailSongRow extends StatelessWidget {
  const _DetailSongRow({
    required this.song,
    required this.position,
    required this.remark,
    required this.onTap,
  });

  final MusicSong song;
  final int position;
  final String remark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final artist = song.artistText;
    final album = song.albumTitle;
    final subtitleParts = <String>[
      if (remark.isNotEmpty) remark,
      if (artist.isNotEmpty) artist,
      if (album.isNotEmpty) album,
    ];
    return InkWell(
      onTap: onTap,
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
            _DetailCover(url: song.coverUrl),
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
                    subtitleParts.join(' · '),
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
              _formatDetailDuration(song.durationMs),
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

/// 封面（44×44，errorBuilder/loadingBuilder 回退音符占位；与总页同款模式）。
class _DetailCover extends StatelessWidget {
  const _DetailCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 44,
      height: 44,
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

/// rank.id 缺失（wire rankid 不可解析）时取代网络请求的本地错误。
class _RankIdMissing implements Exception {
  const _RankIdMissing();

  @override
  String toString() => '榜单缺少有效 ID，无法加载歌曲';
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.message, required this.onRetry});

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

/// 毫秒 → m:ss（无时长/非法值返回空串）。
String _formatDetailDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

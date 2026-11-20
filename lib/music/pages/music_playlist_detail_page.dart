// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 歌单详情页（U4）：头部信息 + 曲目分页 + 播放。
///
/// - 云歌单（[MusicPlaylistDetailPage.cloudListId] 非空）走
///   `playlistTrackAllNew`，头部用构造传入的 title/coverUrl；
/// - 公开歌单走 `playlistDetail`（头部）+ `playlistTrackAll`（曲目），
///   头部缺失/失败时用传入占位，不挡曲目。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/api/playlist_detail.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_track_all.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 歌单详情。`globalId` 是公开歌单标识（云歌单可传空串）；`cloudListId`
/// 非空时优先走云歌单曲目端点。`editable` 由列表页传入（U4 契约外的可选
/// 参数）：true 且 write 非空时 AppBar 提供「删除歌单」。
class MusicPlaylistDetailPage extends StatefulWidget {
  const MusicPlaylistDetailPage({
    super.key,
    required this.read,
    required this.player,
    required this.globalId,
    this.cloudListId,
    this.title,
    this.coverUrl,
    this.write,
    this.editable,
  });

  final MusicPlaylistReadApi read;
  final MusicPlayerUi player;

  /// 公开歌单标识；云歌单可传空串。
  final String globalId;

  /// 云歌单 id；非空时优先走 playlistTrackAllNew。
  final int? cloudListId;
  final String? title;
  final String? coverUrl;

  /// 歌单写端点；null 表示写功能未接线（不显示删除）。
  final MusicPlaylistWriteApi? write;

  /// 列表页回传的 editable 事实；null 视为不可编辑（删除入口隐藏）。
  final bool? editable;

  @override
  State<MusicPlaylistDetailPage> createState() =>
      _MusicPlaylistDetailPageState();
}

enum _Phase { loading, error, ready }

class _MusicPlaylistDetailPageState extends State<MusicPlaylistDetailPage> {
  /// 公开歌单 1..=200、云歌单 1..=300；50 对两端点都合法。
  static const int _pageSize = 50;

  /// 宽窗下正文收窄居中，避免长行拉满整屏。
  static const double _wideBreakpoint = 720;

  MusicPlaylistDetail? _detail;
  List<MusicPlaylistTrack> _tracks = const <MusicPlaylistTrack>[];
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _deleting = false;
  _Phase _phase = _Phase.loading;
  bool _authError = false;
  String _errorMessage = '';

  bool get _isCloud => widget.cloudListId != null;

  /// 删除歌单（仅可编辑云歌单 + 写端点已接线）。
  bool get _canDelete =>
      _isCloud && widget.write != null && widget.editable == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 数据装配 ────────────────────────────────────────────────────────────

  /// 首屏：曲目失败 = 整页错误（可重试）；公开歌单头部失败静默降级为占位。
  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    // 公开歌单头部与曲目并行取：头部慢/失败都不挡曲目浏览。
    if (!_isCloud && widget.globalId.isNotEmpty) {
      unawaited(_loadHeader());
    }
    try {
      final tracks = await _fetchTracks(page: 1);
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
        _authError = _isAuthError(error);
        _errorMessage = _authError ? '请先登录酷狗账号' : _errorText(error);
      });
    }
  }

  Future<MusicPage<MusicPlaylistTrack>> _fetchTracks({required int page}) {
    final cloudListId = widget.cloudListId;
    if (cloudListId != null) {
      return widget.read
          .playlistTrackAllNew(
            MusicPlaylistTrackAllNewQuery(
              cloudListId: cloudListId,
              page: page,
              pageSize: _pageSize,
            ),
          )
          .then((result) => result.page);
    }
    return widget.read.playlistTrackAll(
      MusicPlaylistTrackAllQuery(
        globalId: widget.globalId,
        page: page,
        pageSize: _pageSize,
      ),
    );
  }

  /// 公开歌单头部；失败/缺失不挡曲目（用传入 title/coverUrl 占位）。
  Future<void> _loadHeader() async {
    if (_isCloud || widget.globalId.isEmpty) return;
    try {
      final details = await widget.read.playlistDetail(
        MusicPlaylistDetailQuery(globalIds: <String>[widget.globalId]),
      );
      if (!mounted) return;
      setState(() => _detail = details.isEmpty ? null : details.first);
    } on Object {
      // 头部是锦上添花：失败保持占位，不打断曲目浏览。
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final tracks = await _fetchTracks(page: _nextPage);
      if (!mounted) return;
      setState(() {
        _tracks = <MusicPlaylistTrack>[..._tracks, ...tracks.items];
        _applyPage(tracks);
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '加载更多失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  /// total 缺省时按「末页不满一页」推断是否还有更多。
  void _applyPage(MusicPage<MusicPlaylistTrack> page) {
    final total = page.total;
    _total = total ?? _tracks.length;
    _hasMore = total != null
        ? _tracks.length < total
        : page.items.length >= _pageSize;
    _nextPage = (page.page ?? 1) + 1;
  }

  // ── 交互 ────────────────────────────────────────────────────────────────

  bool _isAuthError(Object error) =>
      error is KugouApiException && error.kind == 'authentication';

  String _errorText(Object error) =>
      error is KugouApiException ? error.message : '$error';

  String get _displayTitle {
    final detail = _detail;
    final fromDetail = detail?.title ?? '';
    if (fromDetail.isNotEmpty) return fromDetail;
    final fromArg = widget.title ?? '';
    return fromArg.isNotEmpty ? fromArg : '歌单详情';
  }

  String get _displayCover {
    final detail = _detail;
    final fromDetail = detail?.coverUrl ?? '';
    if (fromDetail.isNotEmpty) return fromDetail;
    return widget.coverUrl ?? '';
  }

  void _play(MusicPlaylistTrack track) {
    // 先起播再打开播放页（与音乐模块页同款时序）：页面立刻呈现 loading/错误态。
    widget.player.playSong(track.song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (_) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    if (write == null || cloudListId == null || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「$_displayTitle」吗？删除后不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await write.playlistDel(PlaylistDelQuery(cloudListId: cloudListId));
      if (!mounted) return;
      // pop(true) 告诉列表页「歌单已被删除」→ 列表自动刷新。
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '删除失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  // ── 渲染 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (_canDelete)
            IconButton(
              tooltip: '删除歌单',
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : _confirmDelete,
            ),
        ],
      ),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error => _ErrorView(
          message: _errorMessage,
          auth: _authError,
          onRetry: _authError ? null : _load,
        ),
        _Phase.ready => LayoutBuilder(
          builder: (context, constraints) => _buildReady(constraints),
        ),
      },
    );
  }

  Widget _buildReady(BoxConstraints constraints) {
    final wide = constraints.maxWidth >= _wideBreakpoint;
    final empty = _tracks.isEmpty;
    final itemCount = 1 + (empty ? 1 : _tracks.length + (_hasMore ? 1 : 0));
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? _wideBreakpoint : constraints.maxWidth,
        ),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeader(context);
            if (empty) return const _EmptyHint(text: '歌单里还没有歌曲');
            final trackIndex = index - 1;
            if (trackIndex < _tracks.length) {
              return _buildTrackRow(context, trackIndex);
            }
            return _buildFooter();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detail = _detail;
    final creator = detail?.creatorName ?? '';
    final description = detail?.description ?? '';
    final songCount = detail?.songCount ?? _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _PlaylistCover(url: _displayCover, size: 96),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _displayTitle,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (creator.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '创建者：$creator',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (songCount > 0) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '共 $songCount 首',
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
        if (description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTrackRow(BuildContext context, int index) {
    final track = _tracks[index];
    final song = track.song;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      key: ValueKey<String>('track-$index-${song.id}-${song.hash}'),
      onTap: () => _play(track),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _PlaylistCover(url: song.coverUrl, size: 44),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _loadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
      ),
    );
  }
}

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// 封面缩略图；无 URL / 加载失败 / 离线测试时回退到歌单占位图标。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.url, this.size = 56});

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
      child: Icon(Icons.library_music, color: cs.primary),
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
        // 加载中维持占位（与音乐模块页的 loading 模式对齐，不闪空块）。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

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

/// 错误态：认证类不显示重试（重试也不会成功），其余带重试按钮。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.auth, this.onRetry});

  final String message;
  final bool auth;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              auth ? Icons.account_circle_outlined : Icons.error_outline,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

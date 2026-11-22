// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 音乐「我的」页：收藏 / 历史（C 线）+ 账号收藏（云歌单「我喜欢」）。
///
/// 收藏分两层：本地收藏（[MusicCollectService]，搜索页点心形）与账号收藏
/// （酷狗云歌单「我喜欢」，`is_def == 2`，需登录）。账号收藏直接内联在本页
/// 收藏段，避免用户误以为「收藏没有歌曲」——账号里的歌不在本地库里。
///
/// 续播只经 [MusicLibraryPlayHandler]（集成方接到 `playerUi.playSong`），
/// 本文件不 import 播放线（P）的任何实现——与 P 线保持编译隔离。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/music_library_store.dart';
import 'package:mimao/music/music_projection.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 历史条目点击的续播入口（集成方接线到 `playerStore.playSong`）。
typedef MusicLibraryPlayHandler =
    void Function(MusicSong song, Duration startAt);

/// 双击歌曲行的整列表播放入口（集成方接线到 `playerUi.playList`）：
/// 用整个列表替换播放队列，并从 [startIndex] 开始播放。
typedef MusicLibraryPlayListHandler =
    void Function(List<MusicSong> songs, {int startIndex});

/// 「我的」页。`onPlaySong` 为空时，点击只提示「播放功能未接线」。
///
/// [userLibrary] / [playlistRead] 非空时，收藏段顶部内联账号「我喜欢」歌曲；
/// 两者缺一时只显示本地收藏（旧行为）。[authEpoch] 用于登录/切号后自动重拉。
class MusicLibraryPage extends StatefulWidget {
  const MusicLibraryPage({
    super.key,
    required this.collect,
    required this.history,
    this.onPlaySong,
    this.onPlayList,
    this.userLibrary,
    this.playlistRead,
    this.authEpoch,
    this.initialTab = 0,
    this.showTabSwitch = true,
  });

  final MusicCollectService collect;
  final MusicHistoryService history;
  final MusicLibraryPlayHandler? onPlaySong;

  /// 双击歌曲行：整个当前列表替换为播放队列；为空时提示未接线。
  final MusicLibraryPlayListHandler? onPlayList;

  /// 用户库接口（user_playlist：定位「我喜欢」云歌单）。
  final MusicUserLibraryApi? userLibrary;

  /// 歌单读接口（playlist_track_all_new：取「我喜欢」曲目）。
  final MusicPlaylistReadApi? playlistRead;

  /// 登录态变化信号；非空时登录/切号自动重拉账号收藏。
  final ValueListenable<int>? authEpoch;

  /// 初始分段（0 = 收藏，1 = 历史）；侧栏化后由入口决定，默认收藏。
  final int initialTab;

  /// 是否画「我喜欢 / 历史」分段切换；侧栏把两段拆成两个入口时传 false，
  /// 本页只渲染 [initialTab] 锁定的分段。
  final bool showTabSwitch;

  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  /// 本页是否承载收藏段（含账号「我喜欢」云拉取）：锁定到历史段的实例
  /// 不再拉账号收藏，避免两实例重复翻页（侧栏化时两实例共享服务）。
  bool get _showsFavorites => widget.showTabSwitch || widget.initialTab == 0;

  /// 「我喜欢」曲目分页大小（playlist_track_all_new 上限 300）。
  ///
  /// 账号收藏要求「自动全量」：首屏循环翻页直到取完，不提供「加载更多」；
  /// 取上限值把请求次数压到最少。
  static const int _favoritePageSize = 300;

  /// 云歌单「我喜欢」的默认种类码（wire `is_def`）。实测账号里
  /// `is_def=1` 是空的「默认收藏」，`is_def=2` 才是「我喜欢」。
  static const int _favoriteDefaultKind = 2;

  /// 全量翻页的安全上限（防止服务端 total 异常导致死循环）。
  static const int _favoriteMaxPages = 100;

  late final MusicLibraryStore _store = MusicLibraryStore(
    widget.collect,
    widget.history,
  );

  // ── 账号收藏（我喜欢）──
  int? _favoriteListId;
  bool _favoritesLoading = false;
  Object? _favoritesError;
  final List<MusicPlaylistTrack> _favoriteTracks = <MusicPlaylistTrack>[];

  bool get _accountFavoritesEnabled =>
      widget.userLibrary != null && widget.playlistRead != null;

  @override
  void initState() {
    super.initState();
    // 收藏/历史在搜索页也能被改动（收藏按钮、播放进度），服务写完会通知刷新。
    widget.collect.addListener(_onLibraryChanged);
    widget.history.addListener(_onLibraryChanged);
    widget.authEpoch?.addListener(_onAuthChanged);
    _store
      ..selectTab(widget.initialTab)
      ..refresh();
    if (_accountFavoritesEnabled && _showsFavorites) {
      unawaited(_loadFavorites());
    }
  }

  @override
  void dispose() {
    widget.collect.removeListener(_onLibraryChanged);
    widget.history.removeListener(_onLibraryChanged);
    widget.authEpoch?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    _store.refresh();
  }

  /// 登录/登出/切号：缓存里的 listid 属于旧账号，必须清掉重定位。
  void _onAuthChanged() {
    if (!mounted) return;
    if (!_showsFavorites) return;
    unawaited(_loadFavorites(clearListId: true));
  }

  /// 账号收藏装载：定位「我喜欢」云歌单后**自动翻页取全量**。
  ///
  /// 每取完一页就 setState 追加（用户能看到进度），直到 total 收口或整页
  /// 不满为止；中途失败保留已取得的歌曲并给出错误/重试。
  Future<void> _loadFavorites({bool clearListId = false}) async {
    final library = widget.userLibrary;
    final read = widget.playlistRead;
    if (library == null || read == null) return;
    if (_favoritesLoading) return;

    if (clearListId) _favoriteListId = null;
    setState(() {
      _favoritesLoading = true;
      _favoritesError = null;
      _favoriteTracks.clear();
    });
    try {
      var listId = _favoriteListId;
      if (listId == null) {
        final playlists = await library.userPlaylist(
          const MusicUserPlaylistQuery(page: 1, pageSize: 200),
        );
        listId = _findFavoriteListId(playlists.page.items);
        _favoriteListId = listId;
      }
      if (listId == null) {
        // 账号里没有「我喜欢」歌单（或全空）：不是错误，显示空态。
        if (!mounted) return;
        setState(() => _favoritesLoading = false);
        return;
      }
      var page = 1;
      while (mounted && page <= _favoriteMaxPages) {
        final tracks = await read.playlistTrackAllNew(
          MusicPlaylistTrackAllNewQuery(
            cloudListId: listId,
            page: page,
            pageSize: _favoritePageSize,
          ),
        );
        if (!mounted) return;
        final items = tracks.page.items;
        setState(() => _favoriteTracks.addAll(items));
        final total = tracks.page.total;
        final hasMore = items.isEmpty
            ? false
            : (total != null
                  ? _favoriteTracks.length < total
                  : items.length == _favoritePageSize);
        if (!hasMore) break;
        page++;
      }
      if (!mounted) return;
      setState(() => _favoritesLoading = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _favoritesError = error;
        _favoritesLoading = false;
      });
    }
  }

  /// 定位「我喜欢」：优先 `is_def == 2`，兼容按标题兜底；都没有返回 null。
  int? _findFavoriteListId(List<MusicUserPlaylist> playlists) {
    for (final playlist in playlists) {
      if (playlist.defaultKind == _favoriteDefaultKind &&
          playlist.cloudListId != null) {
        return playlist.cloudListId;
      }
    }
    for (final playlist in playlists) {
      if (playlist.title == '我喜欢' && playlist.cloudListId != null) {
        return playlist.cloudListId;
      }
    }
    return null;
  }

  /// 刷新按钮：本地库与账号收藏一起刷。
  Future<void> _refreshAll() {
    _store.refresh();
    if (!_accountFavoritesEnabled) return Future<void>.value();
    return _loadFavorites();
  }

  void _play(MusicSong song, Duration startAt) {
    // 播完的歌历史位置≈总时长，直接续播会立刻结束；这种起点从 0 重播。
    final total = song.durationMs ?? 0;
    final at = (total > 0 && startAt.inMilliseconds >= total - 2000)
        ? Duration.zero
        : startAt;
    // 打开点校正：以内部权威值刷新投影（失败不影响播放）。
    widget.history.open(song).catchError((Object _) {});
    final handler = widget.onPlaySong;
    if (handler != null) {
      handler(song, at);
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('播放功能未接线')));
  }

  /// 双击：整列表替换播放队列并从 [startIndex] 起播（不跳播放页）。
  void _playListAt(List<MusicSong> songs, int startIndex) {
    if (songs.isEmpty) return;
    final handler = widget.onPlayList;
    if (handler != null) {
      handler(songs, startIndex: startIndex);
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('播放功能未接线')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: <Widget>[
              // 锁定分段（侧栏入口）时不画切换钮，只留刷新。
              if (widget.showTabSwitch)
                Expanded(
                  child: Observer(
                    builder: (_) => SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(
                          value: 0,
                          icon: Icon(Icons.favorite_outline),
                          label: Text('我喜欢'),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          icon: Icon(Icons.history),
                          label: Text('历史'),
                        ),
                      ],
                      selected: <int>{_store.libraryTab},
                      onSelectionChanged: (selection) =>
                          _store.selectTab(selection.first),
                    ),
                  ),
                )
              else
                const Spacer(),
              IconButton.filledTonal(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: _refreshAll,
              ),
            ],
          ),
        ),
        Expanded(
          child: Observer(
            builder: (_) {
              if (_store.isLoading && _store.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final error = _store.error;
              if (error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(error),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _store.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              return _store.libraryTab == 0
                  ? _buildCollected()
                  : _buildHistory();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollected() {
    final local = _store.collected;
    if (!_accountFavoritesEnabled) {
      return _buildLocalCollected(local);
    }
    final playable = _playableSongs(local);
    return ListView(
      key: const Key('library-collected-scroll'),
      children: <Widget>[
        ..._accountFavoriteChildren(),
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('本地收藏'),
        ),
        if (local.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text('还没有本地收藏的歌曲（搜索页点心形收藏）'),
          )
        else
          ...local.map((item) => _localCollectTile(item, playable)),
      ],
    );
  }

  /// 本地收藏中带曲目快照的条目（旧/坏数据没有 song，不进入播放队列）。
  List<MusicSong> _playableSongs(List<MusicCollectItem> items) => <MusicSong>[
    for (final item in items)
      if (item.song != null) item.song!,
  ];

  /// 账号收藏段：定位「我喜欢」云歌单后内联曲目；登录后自动出现。
  List<Widget> _accountFavoriteChildren() {
    final children = <Widget>[];
    final error = _favoritesError;
    if (error != null) {
      final auth = error is KugouApiException && error.kind == 'authentication';
      children.add(
        ListTile(
          key: const Key('library-favorites-error'),
          leading: Icon(auth ? Icons.lock_outline : Icons.error_outline),
          title: Text(auth ? '登录酷狗账号后同步「我喜欢」' : '账号收藏加载失败'),
          subtitle: Text(
            auth ? '登录后会自动刷新，无需手动重试' : '$error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: TextButton(
            onPressed: () => _loadFavorites(),
            child: const Text('重试'),
          ),
        ),
      );
      return children;
    }
    if (_favoritesLoading) return children;
    if (_favoriteTracks.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text('账号「我喜欢」里还没有歌曲'),
        ),
      );
      return children;
    }
    final favoriteSongs = <MusicSong>[
      for (final track in _favoriteTracks) track.song,
    ];
    for (final (index, track) in _favoriteTracks.indexed) {
      final song = track.song;
      children.add(
        MusicSongCard(
          horizontalMargin: 16,
          child: InkWell(
            onTap: () => _play(song, Duration.zero),
            onDoubleTap: () => _playListAt(favoriteSongs, index),
            child: ListTile(
              key: ValueKey<String>('library-favorite-${song.id}'),
              leading: _CoverThumb(
                url: song.coverUrl.isEmpty ? null : song.coverUrl,
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.artistText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.play_circle_outline),
            ),
          ),
        ),
      );
    }
    return children;
  }

  Widget _localCollectTile(MusicCollectItem item, List<MusicSong> playable) {
    final song = item.song;
    final startIndex = song == null
        ? -1
        : playable.indexWhere((candidate) => candidate.id == song.id);
    return MusicSongCard(
      horizontalMargin: 16,
      child: InkWell(
        onTap: song == null ? null : () => _play(song, Duration.zero),
        onDoubleTap: startIndex < 0
            ? null
            : () => _playListAt(playable, startIndex),
        child: ListTile(
          key: ValueKey<String>('library-collect-${item.ref.id}'),
          leading: _CoverThumb(url: item.coverUrl),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.artistText.isEmpty ? '已收藏' : item.artistText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.play_circle_outline),
        ),
      ),
    );
  }

  Widget _buildLocalCollected(List<MusicCollectItem> items) {
    if (items.isEmpty) {
      return const _EmptyHint(text: '还没有收藏的歌曲');
    }
    final playable = _playableSongs(items);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) =>
          _localCollectTile(items[index], playable),
    );
  }

  Widget _buildHistory() {
    final items = _store.history;
    if (items.isEmpty) {
      return const _EmptyHint(text: '还没有播放记录');
    }
    final playable = <MusicSong>[for (final item in items) item.song];
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final song = item.song;
        final progress = musicProgressText(
          positionMs: item.position.inMilliseconds,
          durationMs: item.duration.inMilliseconds,
        );
        final artist = song.artistText;
        return MusicSongCard(
          horizontalMargin: 16,
          child: InkWell(
            onTap: () => _play(song, item.position),
            onDoubleTap: () => _playListAt(playable, index),
            child: ListTile(
              key: ValueKey<String>('library-history-${song.id}'),
              leading: _CoverThumb(
                url: song.coverUrl.isEmpty ? null : song.coverUrl,
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                artist.isEmpty ? progress : '$artist · $progress',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.play_circle_outline),
            ),
          ),
        );
      },
    );
  }
}

/// 封面缩略图；无 URL/加载失败/离线测试时回退到音符占位。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: theme.colorScheme.primary),
    );
    final coverUrl = url;
    if (coverUrl == null || coverUrl.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        coverUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
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

// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 「添加到歌单」底部弹窗：列出当前账号可编辑的云歌单，点一行把当前曲目
/// 加进去。只认 [MusicSongCollection] 接口，不 import 网络实现。
///
/// 加载态/失败重试/空列表都在弹窗内部收口；写操作成功给 SnackBar 并关闭，
/// 失败保留弹窗（方便换个歌单重试或直接返回），文案按 `authentication`
/// 错误换成登录提示（与歌单详情页同款口径）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/player/song_collection.dart';

/// 歌单写操作失败的友好文案：未登录统一提示登录，其余带原始信息。
String musicCollectionErrorText(Object error) {
  if (error is KugouApiException) {
    if (error.kind == 'authentication') return '请先登录酷狗账号';
    return '操作失败：${error.message}';
  }
  return '操作失败：$error';
}

/// 打开「添加到歌单」底部弹窗。
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  MusicSong song,
  MusicSongCollection collection,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) =>
      AddToPlaylistSheet(song: song, collection: collection),
);

/// 弹窗正文：FutureBuilder 驱动 loading / error / 空 / 列表四态。
class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({
    super.key,
    required this.song,
    required this.collection,
  });

  final MusicSong song;
  final MusicSongCollection collection;

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  /// 歌单加载 Future；重试时整体替换并重建 FutureBuilder。
  late Future<List<MusicUserPlaylist>> _playlists;

  /// 正在提交的歌单下标（防重复点击；提交期间整列表禁用）。
  int? _addingIndex;

  @override
  void initState() {
    super.initState();
    _playlists = widget.collection.loadEditablePlaylists();
  }

  void _retry() {
    setState(() {
      _playlists = widget.collection.loadEditablePlaylists();
    });
  }

  Future<void> _add(MusicUserPlaylist playlist, int index) async {
    if (_addingIndex != null) return;
    // 先抓住 messenger：pop 之后弹窗 context 失效，SnackBar 仍要能弹出。
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _addingIndex = index);
    try {
      await widget.collection.addSongToPlaylist(widget.song, playlist);
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('已添加到「${playlist.title}」')),
      );
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _addingIndex = null);
      messenger?.showSnackBar(
        SnackBar(content: Text(musicCollectionErrorText(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 屏高 70% 封顶：歌单多时内部滚动，不把整屏遮住。
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      key: const Key('add-to-playlist-sheet'),
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('添加到歌单', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<MusicUserPlaylist>>(
                future: _playlists,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                          key: Key('add-to-playlist-loading'),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(error: snapshot.error!, onRetry: _retry);
                  }
                  final playlists =
                      snapshot.data ?? const <MusicUserPlaylist>[];
                  if (playlists.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无可添加的歌单')),
                    );
                  }
                  return ListView.builder(
                    key: const Key('add-to-playlist-list'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        key: Key('add-to-playlist-item-$index'),
                        enabled: _addingIndex == null,
                        leading: _PlaylistCover(url: playlist.coverUrl),
                        title: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${playlist.songCount ?? 0} 首'),
                        trailing: _addingIndex == index
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: () => _add(playlist, index),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载失败：主文案「加载失败」+ 未登录提示 + 重试。
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final auth =
        error is KugouApiException &&
        (error as KugouApiException).kind == 'authentication';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(auth ? '请先登录酷狗账号' : '加载失败'),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('add-to-playlist-retry'),
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 歌单封面：有封面走网络图（失败回退图标），无封面直接图标。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.queue_music,
      color: Theme.of(context).colorScheme.primary,
    );
    if (url.isEmpty) {
      return SizedBox(width: 40, height: 40, child: Center(child: fallback));
    }
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            SizedBox(width: 40, height: 40, child: Center(child: fallback)),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 40,
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
      ),
    );
  }
}

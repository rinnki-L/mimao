// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 「歌曲列表 / 播放模式」共享弹窗（迷你播放条与播放页共用）。
///
/// 顶部是播放模式单选（随机 / 单曲循环 / 列表循环），下方是当前队列，
/// 点任意一行切到该曲并关闭弹窗。队列与模式都来自 [MusicPlayerStore]，
/// 用 [Observer] 包裹以跟随 MobX 变化实时刷新。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/player/play_mode.dart';
import 'package:mimao/music/player/player_store.dart';

/// 打开歌曲列表弹窗（模式选择 + 队列切歌）。
Future<void> showMusicQueueSheet(
  BuildContext context,
  MusicPlayerStore player,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Observer(
        builder: (context) {
          final theme = Theme.of(context);
          return ConstrainedBox(
            // 队列可能很长：弹窗最多占 70% 高，列表在内部滚动。
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('播放模式', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<PlayMode>(
                    key: const Key('music-queue-play-mode'),
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: const <ButtonSegment<PlayMode>>[
                      ButtonSegment<PlayMode>(
                        value: PlayMode.shuffle,
                        label: Text('随机'),
                      ),
                      ButtonSegment<PlayMode>(
                        value: PlayMode.repeatOne,
                        label: Text('单曲循环'),
                      ),
                      ButtonSegment<PlayMode>(
                        value: PlayMode.listLoop,
                        label: Text('列表循环'),
                      ),
                    ],
                    selected: <PlayMode>{player.playMode},
                    onSelectionChanged: (selection) =>
                        player.setPlayMode(selection.first),
                  ),
                  const SizedBox(height: 16),
                  Text('当前播放队列', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (player.queue.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('播放队列为空', textAlign: TextAlign.center),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: player.queue.length,
                        itemBuilder: (context, index) {
                          final song = player.queue[index];
                          final current = index == player.index;
                          return ListTile(
                            selected: current,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              current ? Icons.volume_up : Icons.music_note,
                              color: current ? theme.colorScheme.primary : null,
                            ),
                            title: Text(
                              _displayTitle(song.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              player.playAt(index);
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// wire 的 SongName 可能带 `<em>` 高亮标签（复杂搜索命中高亮），展示层剥掉。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

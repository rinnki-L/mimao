/// 播放进度写入口（契约）。
///
/// P 线（播放器）在换歌/暂停/拖动/播完/每 10 秒调用；C 线只提供
/// `saveProgress(...)`，**不实现也不 import 本文件**——适配 lambda 由
/// `music_entry.dart` 在集成时写成 `(song, pos, dur) => history.saveProgress(...)`。
library;

import 'package:mimao/music/models/music_models.dart';

/// 一次进度写入；`duration` 为零表示时长未知（例如刚起播）。
typedef ProgressSink =
    Future<void> Function(MusicSong song, Duration position, Duration duration);

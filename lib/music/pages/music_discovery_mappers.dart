/// 发现组「模型 → 播放链路骨架模型」的映射与展示层小工具。
///
/// 原为发现页的私有函数（`_discoverySongToMusicSong` / `_displayTitle` /
/// `_formatDuration`）；发现页拆出长条列表页 / 风格推荐页 / 热门搜索页后，
/// 多个页面共用同一份映射，抽到这里供组内页面复用。不改共享模型（models/
/// 保持 wire 语义）。
library;

import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 发现组曲目摘要 → 播放链路的 [MusicSong]。发现组保留「专辑名缺失(null)
/// vs 空串」的 wire 区分，播放链路的骨架模型用空串表达缺失。
MusicSong discoverySongToMusicSong(MusicDiscoverySongSummary summary) =>
    MusicSong(
      id: summary.id,
      hash: summary.hash,
      title: summary.title,
      artists: summary.artists,
      albumId: summary.albumId,
      albumTitle: summary.albumTitle ?? '',
      durationMs: summary.durationMs,
      coverUrl: summary.coverUrl,
      privilege: summary.privilege,
    );

/// wire 的 SongName 可能带 `<em>` 高亮标签，展示层统一剥掉；模型层保持
/// 上游 api 的原样语义（与模块页同款）。
String displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

/// 毫秒时长 → 「m:ss」展示串；缺失/非正数返回空串（不渲染）。
String formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

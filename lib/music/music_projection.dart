import 'dart:convert';

import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

import 'models/music_models.dart';
import 'music_db.dart';

/// 音乐投影里"从未播放"的固定文案（壳只展示，不解析）。
const String musicUnplayedText = '尚未播放';

/// 音乐投影里"听过但没有进度信息"的固定文案。
const String musicPlayedText = '听过';

/// 把内部权威进度翻译成壳可展示的 `progressText`。
///
/// 只在**存在历史行**时调用（无历史由调用方直接给 [musicUnplayedText]）：
/// - 有时长 → `已听 N%`（N 夹在 0–100）；
/// - 无时长但位置有效，或位置/时长都是 0（历史行存在但没进度）→ [musicPlayedText]。
String musicProgressText({required int positionMs, required int durationMs}) {
  if (durationMs > 0) {
    final percent = (positionMs * 100 / durationMs).clamp(0, 100).round();
    return '已听 $percent%';
  }
  return musicPlayedText;
}

/// 内部库 payload → 曲目；解析失败/空 payload 返回 null（历史条目仍可展示
/// 标题，只是重建不出完整曲目）。
MusicSong? musicSongFromPayload(String payload) {
  if (payload.isEmpty || payload == '{}') return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    return MusicSong.fromJson(Map<String, Object?>.from(decoded));
  } on Object {
    return null;
  }
}

/// 双记账的唯一投影写入口：读内部库的权威行，写一行 `media_entries`。
///
/// 两个调用时机（docs/architecture.md §3.1）：
/// - **持久化点**：收藏/进度的内部表刚写完，紧接着调本函数；
/// - **打开点**：从时间线/历史点开条目时调本函数，用内部库权威值覆盖投影。
///
/// `fallback*` 只服务于"取消收藏把内部行删掉、但投影行需要改成 starred=false"
/// 这一种场景：删行之前把元数据交给本函数，作为最后一笔投影的标题来源。
/// 两侧都没有权威行且无 fallback 时不写——避免凭空在书架里造条目。
Future<void> syncMusicProjection({
  required MusicDb db,
  required LibraryRepository library,
  required MusicRef ref,
  String? fallbackTitle,
  String? fallbackCoverUrl,
  DateTime? touchedAt,
}) async {
  final collect = await db.collectRow(ref);
  final history = await db.historyRow(ref);
  final title = collect?.title ?? history?.title ?? fallbackTitle;
  if (title == null) return;

  final now = DateTime.now();
  final lastOpenedAt =
      history?.openedAt ?? collect?.collectedAt ?? touchedAt ?? now;
  // 与 lastOpenedAt 顺序相反：createdAt 优先取收藏时间（照 anime 投影语义）。
  final createdAt =
      collect?.collectedAt ?? history?.openedAt ?? touchedAt ?? now;

  // payload 是模块私有 JSON；core 与壳都不解释它（§3.1 规则④）。
  final payload = jsonEncode(<String, Object?>{
    'positionMs': history?.positionMs ?? 0,
    'durationMs': history?.durationMs ?? 0,
  });
  final progressText = history == null
      ? musicUnplayedText
      : musicProgressText(
          positionMs: history.positionMs,
          durationMs: history.durationMs,
        );

  await library.upsert(
    id: ref.id,
    type: MediaType.music,
    sourceName: kugouSourceName,
    title: title,
    coverUrl: collect?.coverUrl ?? history?.coverUrl ?? fallbackCoverUrl,
    payload: payload,
    progressText: progressText,
    starred: collect != null,
    lastOpenedAt: lastOpenedAt,
    createdAt: createdAt,
  );
}

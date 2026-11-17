import 'dart:convert';

import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

import 'anime_db.dart';
import 'anime_models.dart';

/// 番剧投影里"没有观看记录"时的固定文案（壳只展示，不解析）。
const String animeUnwatchedText = '尚未观看';

/// 把内部权威进度翻译成壳可展示的 `progressText`。
///
/// 规则与 core 的注释一致（"看到第 12 话" / "第1432章 · 32%"）：
/// 有时长且位置有效时带百分比，否则只报话数。
String animeProgressText({
  required int episode,
  required int positionSec,
  required int durationSec,
}) {
  if (episode <= 0 && positionSec <= 0) return animeUnwatchedText;
  final displayEpisode = episode < 1 ? 1 : episode;
  if (durationSec > 0 && positionSec > 0) {
    final percent = (positionSec * 100 / durationSec).clamp(0, 100).round();
    return '第 $displayEpisode 话 · $percent%';
  }
  return '看到第 $displayEpisode 话';
}

/// 双记账的唯一投影写入口：读内部库的权威行，写一行 `media_entries`。
///
/// 两个调用时机（docs/architecture.md §3.1）：
/// - **持久化点**：收藏/进度的内部表刚写完，紧接着调本函数；
/// - **打开点**：详情/播放打开时调本函数，用内部库权威值覆盖投影（校正）。
///
/// `fallback*` 只服务于"取消收藏把内部行删掉、但投影行需要改成 starred=false"
/// 这一种场景：删行之前把元数据交给本函数，作为最后一笔投影的标题来源。
/// 两侧都没有权威行且无 fallback 时不写——避免凭空在书架里造条目。
Future<void> syncAnimeProjection({
  required AnimeDb db,
  required LibraryRepository library,
  required AnimeRef ref,
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
  final createdAt =
      collect?.collectedAt ?? history?.openedAt ?? touchedAt ?? now;

  // payload 是模块私有 JSON；core 与壳都不解释它（§3.1 规则④）。
  final payload = jsonEncode(<String, Object?>{
    'episode': history?.episode ?? 0,
    'positionSec': history?.positionSec ?? 0,
    'durationSec': history?.durationSec ?? 0,
  });

  await library.upsert(
    id: ref.id,
    type: MediaType.anime,
    sourceName: ref.sourceName,
    title: title,
    coverUrl: collect?.coverUrl ?? history?.coverUrl ?? fallbackCoverUrl,
    payload: payload,
    progressText: history == null
        ? animeUnwatchedText
        : animeProgressText(
            episode: history.episode,
            positionSec: history.positionSec,
            durationSec: history.durationSec,
          ),
    starred: collect != null,
    lastOpenedAt: lastOpenedAt,
    createdAt: createdAt,
  );
}

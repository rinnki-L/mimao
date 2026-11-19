import 'dart:convert';

import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';

/// 内部库 payload → 书籍；解析失败/空 payload 返回 null（历史条目仍可展示
/// 标题，只是重建不出完整书籍）。
NovelSummary? novelSummaryFromPayload(String payload) {
  if (payload.isEmpty || payload == '{}') return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    return NovelSummary.fromJson(Map<String, Object?>.from(decoded));
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
Future<void> syncNovelProjection({
  required NovelDb db,
  required LibraryRepository library,
  required NovelRef ref,
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
    'chapterIndex': history?.chapterIndex ?? 0,
    'chapterCount': history?.chapterCount ?? 0,
  });
  final progressText = history == null
      ? novelUnreadText
      : novelProgressText(
          chapterIndex: history.chapterIndex,
          chapterCount: history.chapterCount,
        );

  await library.upsert(
    id: ref.id,
    type: MediaType.novel,
    sourceName: novelSourceName,
    title: title,
    coverUrl: collect?.coverUrl ?? history?.coverUrl ?? fallbackCoverUrl,
    payload: payload,
    progressText: progressText,
    starred: collect != null,
    lastOpenedAt: lastOpenedAt,
    createdAt: createdAt,
  );
}

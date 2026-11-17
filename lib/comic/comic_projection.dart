import 'dart:convert';

import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

import 'comic_db.dart';
import 'comic_models.dart';

/// 漫画投影里"没有阅读记录"时的固定文案（壳只展示，不解析）。
const String comicUnreadText = '尚未阅读';

/// 把内部权威进度翻译成壳可展示的 `progressText`。
///
/// 漫画以"页"为单位（番剧用秒）：有总页数时带百分比，否则只报页码。
String comicProgressText({
  required String chapterId,
  required int page,
  required int pageCount,
}) {
  if (page <= 0) return comicUnreadText;
  final displayPage = page < 1 ? 1 : page;
  final chapterPart = chapterId.isEmpty ? '' : '$chapterId · ';
  if (pageCount > 0) {
    final percent = (page * 100 / pageCount).clamp(0, 100).round();
    return '$chapterPart第 $displayPage 页 · $percent%';
  }
  return '$chapterPart看到第 $displayPage 页';
}

/// 双记账的唯一投影写入口：读内部库的权威行，写一行 `media_entries`。
///
/// 两个调用时机（docs/architecture.md §3.1）：
/// - **持久化点**：收藏/进度的内部表刚写完，紧接着调本函数；
/// - **打开点**：详情/阅读器打开时调本函数，用内部库权威值覆盖投影（校正）。
///
/// `fallback*` 只服务于"取消收藏把内部行删掉、但投影行需要改成 starred=false"
/// 这一种场景：删行之前把元数据交给本函数，作为最后一笔投影的标题来源。
/// 两侧都没有权威行且无 fallback 时不写——避免凭空在书架里造条目。
Future<void> syncComicProjection({
  required ComicDb db,
  required LibraryRepository library,
  required ComicRef ref,
  String? fallbackTitle,
  String? fallbackCoverUrl,
  DateTime? touchedAt,
}) async {
  final collect = await db.collectRow(ref);
  final history = await db.historyRow(ref);
  final local = await db.localRow(ref);
  final title =
      collect?.title ?? history?.title ?? local?.title ?? fallbackTitle;
  if (title == null) return;

  final now = DateTime.now();
  final lastOpenedAt =
      history?.openedAt ??
      collect?.collectedAt ??
      local?.importedAt ??
      touchedAt ??
      now;
  final createdAt =
      collect?.collectedAt ??
      local?.importedAt ??
      history?.openedAt ??
      touchedAt ??
      now;

  // payload 是模块私有 JSON；core 与壳都不解释它（§3.1 规则④）。
  final payload = jsonEncode(<String, Object?>{
    'chapterId': history?.chapterId ?? '',
    'page': history?.page ?? 0,
    'pageCount': history?.pageCount ?? 0,
  });

  await library.upsert(
    id: ref.id,
    type: MediaType.comic,
    sourceName: ref.sourceName,
    title: title,
    // 本地漫画封面是本机路径（coverPath），属模块私有，不写入公共 coverUrl。
    coverUrl: collect?.coverUrl ?? history?.coverUrl ?? fallbackCoverUrl,
    payload: payload,
    progressText: history == null
        ? comicUnreadText
        : comicProgressText(
            chapterId: history.chapterId,
            page: history.page,
            pageCount: history.pageCount,
          ),
    starred: collect != null,
    lastOpenedAt: lastOpenedAt,
    createdAt: createdAt,
  );
}

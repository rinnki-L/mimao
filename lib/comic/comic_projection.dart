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
/// chapterId 是源的稳定 epId：纯数值的展示为「第 N 章」，其它原样
/// （closure-02 决策②——Venera 社区源章节键多为数字串）。
String comicProgressText({
  required String chapterId,
  required int page,
  required int pageCount,
}) {
  if (page <= 0) return comicUnreadText;
  final displayPage = page < 1 ? 1 : page;
  final chapterPart = chapterId.isEmpty ? '' : '${_chapterLabel(chapterId)} · ';
  if (pageCount > 0) {
    final percent = (page * 100 / pageCount).clamp(0, 100).round();
    return '$chapterPart第 $displayPage 页 · $percent%';
  }
  return '$chapterPart看到第 $displayPage 页';
}

String _chapterLabel(String chapterId) =>
    int.tryParse(chapterId) == null ? chapterId : '第 $chapterId 章';

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

/// 删除历史行之后的投影一致性收尾（双记账的删除点）。
///
/// 调用时机：内部 `comic_history` 行刚被删掉。此时本函数读三张内部表判断
/// 这条作品在模块侧还有没有「存在理由」：
/// - 还有收藏/本地（或残余历史）行 → 重新 [syncComicProjection]，让投影回到
///   权威状态（历史已删则 progressText 回「尚未阅读」，starred 由收藏决定）；
/// - 三者皆空 → 直接删掉 core 投影行。
///
/// 为什么删 core 行而不是写最后一笔：收藏取消时留投影是因为用户仍可能从
/// 阅读历史点进来（投影还有历史作权威）；历史也删光后 core 行没有任何内部
/// 来源，留在统一书架里就是点开即空的「幽灵条目」，必须一起清掉，
/// 否则双账不一致。
Future<void> removeComicProjection({
  required ComicDb db,
  required LibraryRepository library,
  required ComicRef ref,
}) async {
  final hasCollect = await db.collectRow(ref) != null;
  final hasHistory = await db.historyRow(ref) != null;
  final hasLocal = await db.localRow(ref) != null;
  if (hasCollect || hasHistory || hasLocal) {
    await syncComicProjection(db: db, library: library, ref: ref);
    return;
  }
  await library.delete(
    id: ref.id,
    type: MediaType.comic,
    sourceName: ref.sourceName,
  );
}

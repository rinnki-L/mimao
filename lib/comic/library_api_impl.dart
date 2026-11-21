/// C′ 三个内部服务 → [ComicLibraryApi] 的只读适配。
///
/// 页面只认 [ComicLibraryApi]（id/sourceName/title/coverUrl/subtitle），
/// 这里负责把收藏/历史/本地三张内部表的行翻译成同一形状。放在模块出口
/// 一侧而不是 pages/，保持「页面不 import 服务类」的分层。
library;

import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/comic_projection.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/local_comic_service.dart';

/// 收藏 + 历史 + 本地漫画的只读实现。
class ComicLibraryApiImpl implements ComicLibraryApi {
  ComicLibraryApiImpl({
    required this.collect,
    required this.history,
    this.localService,
  });

  final ComicCollectService collect;
  final ComicHistoryService history;

  /// 本地漫画服务；null 时不返回本地条目（未接线的降级路径）。
  final ComicLocalService? localService;

  @override
  Future<List<ComicLibraryEntry>> collected() async {
    final entries = await collect.all();
    return [
      for (final entry in entries)
        ComicLibraryEntry(
          id: entry.ref.id,
          sourceName: entry.ref.sourceName,
          title: entry.title,
          coverUrl: entry.coverUrl,
        ),
    ];
  }

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async {
    final entries = await history.recent(limit: limit);
    return [
      for (final entry in entries)
        ComicLibraryEntry(
          id: entry.ref.id,
          sourceName: entry.ref.sourceName,
          title: entry.title,
          coverUrl: entry.coverUrl,
          subtitle: comicProgressText(
            chapterId: entry.chapterId,
            page: entry.page,
            pageCount: entry.pageCount,
          ),
        ),
    ];
  }

  @override
  Future<List<ComicLibraryEntry>> local() async {
    final service = localService;
    if (service == null) return const <ComicLibraryEntry>[];
    final entries = await service.all();
    return [
      for (final entry in entries)
        ComicLibraryEntry(
          id: entry.ref.id,
          sourceName: entry.ref.sourceName,
          title: entry.title,
          coverUrl: entry.coverPath,
          subtitle: entry.pageCount > 0 ? '${entry.pageCount} 页' : '本地',
        ),
    ];
  }

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) => history.remove(ComicRef(id: id, sourceName: sourceName));

  @override
  Future<void> clearHistory() => history.clear();
}

/// 本地漫画条目的 [ComicRef]（供详情/阅读接线反查用）。
ComicRef comicLocalRef(ComicLocalEntry entry) => entry.ref;

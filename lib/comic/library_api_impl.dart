/// C′ 三个内部服务 → [ComicLibraryApi] 的只读适配。
///
/// 页面只认 [ComicLibraryApi]（id/sourceName/title/coverUrl/subtitle），
/// 这里负责把收藏/历史/本地三张内部表的行翻译成同一形状。放在模块出口
/// 一侧而不是 pages/，保持「页面不 import 服务类」的分层。
library;

import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/comic_projection.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/local_comic_content.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/comic/read_later_service.dart';

/// 收藏 + 历史 + 本地漫画 + 稍后阅读的读写实现。
class ComicLibraryApiImpl
    implements ComicLibraryApi, ComicReadLaterApi, ComicLocalApi {
  ComicLibraryApiImpl({
    required this.collect,
    required this.history,
    this.localService,
    this.localContent,
    this.readLaterService,
  });

  final ComicCollectService collect;
  final ComicHistoryService history;

  /// 本地漫画服务；null 时不返回本地条目（未接线的降级路径）。
  final ComicLocalService? localService;

  /// 本地内容读取（详情/删除磁盘）；null 时 [detail] 抛错、[remove] 只删库。
  final ComicLocalContent? localContent;

  /// 稍后阅读服务；null 时该能力不可用。
  final ComicReadLaterService? readLaterService;

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
  Future<ComicDetail> detail(ComicSummary item) async {
    final service = localService;
    final content = localContent;
    if (service == null || content == null) {
      throw StateError('本地漫画能力未接线');
    }
    final entry = await service.find(
      ComicRef(id: item.id, sourceName: ComicRef.localSource),
    );
    if (entry == null) {
      throw StateError('本地漫画不存在：${item.title}');
    }
    return content.detail(entry);
  }

  @override
  Future<void> remove(ComicSummary item) async {
    final ref = ComicRef(id: item.id, sourceName: ComicRef.localSource);
    final content = localContent;
    if (content != null) {
      await content.remove(ref);
      return;
    }
    await localService?.remove(ref);
  }

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) => history.remove(ComicRef(id: id, sourceName: sourceName));

  @override
  Future<void> clearHistory() => history.clear();

  @override
  Future<List<ComicLibraryEntry>> readLater() async {
    final service = readLaterService;
    if (service == null) return const <ComicLibraryEntry>[];
    final entries = await service.all();
    return [
      for (final entry in entries)
        ComicLibraryEntry(
          id: entry.ref.id,
          sourceName: entry.ref.sourceName,
          title: entry.title,
          coverUrl: entry.coverUrl,
          detailUrl: entry.detailUrl,
          subtitle: '稍后阅读',
        ),
    ];
  }

  @override
  Future<bool> isReadLater(String id, String sourceName) async {
    final service = readLaterService;
    if (service == null) return false;
    return service.contains(ComicRef(id: id, sourceName: sourceName));
  }

  @override
  Future<void> setReadLater({
    required String id,
    required String sourceName,
    required String title,
    String? coverUrl,
    String detailUrl = '',
    required bool included,
  }) async {
    final service = readLaterService;
    if (service == null) throw StateError('稍后阅读能力未接线');
    await service.set(
      ComicRef(id: id, sourceName: sourceName),
      included: included,
      title: title,
      coverUrl: coverUrl,
      detailUrl: detailUrl,
    );
  }
}

/// 本地漫画条目的 [ComicRef]（供详情/阅读接线反查用）。
ComicRef comicLocalRef(ComicLocalEntry entry) => entry.ref;

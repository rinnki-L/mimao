/// 漫画主页/收藏页要读的本地数据（收藏、阅读历史、本地漫画）的最小接口。
///
/// 与 novel 的 `library_api.dart` 同构：页面只认这三个读方法，不 import
/// 服务类或 drift 行类型。真实实现由模块出口用 C′ 的
/// `ComicCollectService` / `ComicHistoryService` / `ComicLocalService` 组装；
/// 测试可直接给假实现。
library;

import 'package:mimao/comic/data/comic_models.dart';

/// 本地数据的一行（收藏 / 历史 / 本地漫画统一形状）。
///
/// [asSummary] 把行转成页面通用的 [ComicSummary]，让卡片/网格组件复用；
/// 本地漫画的 `sourceName` 为 `local`，没有可抓取的详情地址。
class ComicLibraryEntry {
  const ComicLibraryEntry({
    required this.id,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    this.subtitle,
  });

  final String id;
  final String sourceName;
  final String title;
  final String? coverUrl;

  /// 一行说明（如「第 3 话 · 看到第 12 页」）。
  final String? subtitle;

  /// 本地漫画固定来源名（与 `ComicRef.localSource` 对齐，此处不 import
  /// 存储模型，故用字面量并在此注释锚定）。
  static const String localSource = 'local';

  bool get isLocal => sourceName == localSource;

  ComicSummary asSummary() => ComicSummary(
    id: id,
    title: title,
    coverUrl: coverUrl ?? '',
    detailUrl: '',
    subtitle: subtitle,
    sourceName: sourceName,
  );
}

/// 主页/收藏页的数据入口。
abstract interface class ComicLibraryApi {
  /// 已收藏，按收藏时间倒序。
  Future<List<ComicLibraryEntry>> collected();

  /// 最近阅读（跨源汇总），按打开时间倒序。
  Future<List<ComicLibraryEntry>> recent({int limit = 20});

  /// 已导入的本地漫画。
  Future<List<ComicLibraryEntry>> local();
}

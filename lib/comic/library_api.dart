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
    this.detailUrl = '',
  });

  final String id;
  final String sourceName;
  final String title;
  final String? coverUrl;

  /// 源内详情标识（在线条目通常与 [id] 相同；本地条目为空）。
  final String detailUrl;

  /// 一行说明（如「第 3 话 · 看到第 12 页」）。
  final String? subtitle;

  /// 本地漫画固定来源名（与 `ComicRef.localSource` 对齐，此处不 import
  /// 存储模型，故用字面量并在此注释锚定）。
  static const String localSource = 'local';

  bool get isLocal => sourceName == localSource;

  ComicSummary asSummary({String? detailUrl}) => ComicSummary(
    id: id,
    title: title,
    coverUrl: coverUrl ?? '',
    detailUrl: detailUrl ?? this.detailUrl,
    subtitle: subtitle,
    sourceName: sourceName,
  );
}

/// 主页「稍后阅读」卡片与详情页按钮的数据入口。
///
/// 单独于 [ComicLibraryApi]：现有假实现（测试/未接线宿主）不必为实现新
/// 方法而改签名；页面把本接口当可选能力，null 时卡片隐藏。
abstract interface class ComicReadLaterApi {
  /// 全部稍后阅读，按加入时间倒序。
  Future<List<ComicLibraryEntry>> readLater();

  /// 该作品是否已在稍后阅读。
  Future<bool> isReadLater(String id, String sourceName);

  /// 加入/移出稍后阅读；返回操作后的状态（true = 已在队列中）。
  Future<void> setReadLater({
    required String id,
    required String sourceName,
    required String title,
    String? coverUrl,
    String detailUrl = '',
    required bool included,
  });
}

/// 主页「本地」入口与本地详情页的数据入口。
///
/// 与 [ComicLibraryApi.local]（只读区块）分开：本接口负责打开本地漫画详情
/// 与删除已下载内容（含磁盘文件），属写能力。
abstract interface class ComicLocalApi {
  /// 全部本地漫画（导入或下载），按导入时间倒序。
  Future<List<ComicLibraryEntry>> local();

  /// 打开本地漫画详情：章节与页数来自下载时落盘的 payload。
  Future<ComicDetail> detail(ComicSummary item);

  /// 删除一部本地漫画（元数据 + 磁盘目录）。已下载内容会一并清掉。
  Future<void> remove(ComicSummary item);
}

/// 主页/收藏页的数据入口。
abstract interface class ComicLibraryApi {
  /// 已收藏，按收藏时间倒序。
  Future<List<ComicLibraryEntry>> collected();

  /// 最近阅读（跨源汇总），按打开时间倒序。
  Future<List<ComicLibraryEntry>> recent({int limit = 20});

  /// 已导入的本地漫画。
  Future<List<ComicLibraryEntry>> local();

  /// 删除一条阅读历史（主页「阅读历史」长按删除）。
  ///
  /// 实现方负责投影一致性：该作品若还有收藏/本地则重投影，否则删 core 行。
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  });

  /// 清空全部阅读历史（主页「阅读历史」一键清空）。
  ///
  /// 与 [removeHistoryEntry] 同款投影收尾。
  Future<void> clearHistory();
}

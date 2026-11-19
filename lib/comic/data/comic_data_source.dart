import 'package:mimao/comic/data/comic_models.dart';

/// 漫画 UI 的唯一数据入口（抽象）。
///
/// A′ 源引擎就绪后提供一个实现：把规则抽取结果适配成 [ComicSummary] /
/// [ComicDetail]。页面、fixture 与 widget 测试都只依赖本接口，不认识 dio、
/// 规则模型或存储服务——换实现不改 UI。
///
/// 联调映射（引擎抽取结果 → 本接口）：
///   - `absoluteUrl` → [ComicSummary.detailUrl]（同时可作为 id）
///   - `absoluteCoverUrl` → [ComicSummary.coverUrl]
///   - 章节点击地址 → [ComicChapter.url]；number 按列表顺序生成
/// 空字符串表示「没有封面/没有简介」，页面会显示占位与空态，不需要 null。
abstract interface class ComicDataSource {
  /// 按关键词搜索。空关键词返回推荐/全部（fixture 语义）。
  Future<List<ComicSummary>> search(String keyword);

  /// 取详情（含章节）。实现方用 [item] 的 detailUrl 抓取。
  Future<ComicDetail> detail(ComicSummary item);

  /// 只搜索指定来源；key 为源 key。默认回退到全源 [search]。
  ///
  /// 带默认实现的可选方法：不需要单源搜索的实现（fixture、测试 fake）
  /// 零改动即可继续工作。注意 [ComicDataSource] 是 `abstract interface class`，
  /// Dart 的 `implements` 不继承接口的默认方法体——直接 `implements` 的具体类
  /// 必须提供覆盖实现（一行转发即可）；「既有实现零改动」由下面这条规则保证：
  /// 只有直接 implements 的类需补覆盖，经基类继承的实现自动获得默认体。
  Future<List<ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  /// 可用于按来源筛选的源 key 列表（有序）。默认空 → UI 隐藏筛选器，
  /// 退化为单源（聚合）搜索行为，与引入本能力前一致。
  List<String> availableSourceKeys() => const <String>[];
}

/// 源管理页的数据入口（抽象）。
///
/// 与 [ComicDataSource] 分开：搜索/详情只读远端内容，源管理读写「已导入
/// 来源」清单。A′/C′ 的源存储就绪后实现这个接口即可，UI 不认实现细节。
/// 三个写操作都返回操作后的完整列表，页面据此重建状态，逻辑简单可测。
abstract interface class ComicSourceRepository {
  Future<List<ComicSourceInfo>> listSources();

  /// 从 URL 导入一个来源，返回导入后的完整列表。
  /// 规则非法/重复时抛异常，页面显示错误态。
  Future<List<ComicSourceInfo>> importSource(String url);

  /// 切换启用状态，返回更新后的完整列表。
  Future<List<ComicSourceInfo>> setEnabled(String id, bool enabled);

  /// 删除来源，返回删除后的完整列表。
  Future<List<ComicSourceInfo>> deleteSource(String id);
}

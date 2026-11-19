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

  /// 取走并清空最近一次 [search] 期间累积的失败诊断（每条形如
  /// `来源key：失败原因`）。默认空实现——fixture/fake 与 C 线实现无需改动；
  /// 真实引擎 override 本方法，让「全部源失败 → 空结果」时 UI 能把原因显示出来。
  ///
  /// 语义：取走即清，一次搜索只消费一次；本方法不改变 [search] 的签名。
  List<String> takeSearchDiagnostics() => const <String>[];
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

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

  /// 最近搜索词（真实写库时由搜索历史服务提供）。默认空——fixture/fake
  /// 无需改动；真实引擎 override 后搜索页展示可点回填的历史 chips。
  Future<List<String>> recentSearchTerms() async => const <String>[];
}

/// 聚合搜索能力：按源分组返回 [ComicSourceSearchSection]，每个参与搜索的源
/// 一个 section（含失败/空结果源），section 自带该源诊断。
///
/// 设计取舍（现实约束）：[ComicDataSource] 是 `abstract interface class`，
/// Dart 的 `implements` 不继承接口默认体——把 [searchGrouped] 直接加进接口会
/// 要求所有 `implements` 方（含本切片不可改的测试 fake）都补覆盖，否则编译失败。
/// 因此这里用一个可选能力接口承载 override 点：真实引擎 [EngineComicDataSource]
/// implements 它提供真分组；其余数据源通过 [ComicDataSourceGroupedX] 扩展获得
/// 「调 [ComicDataSource.search] 按 sourceName 分组」的默认语义，零改动。
/// 调用方通过 [groupedSearch] 统一入口，无需关心数据源属于哪一类。
abstract interface class GroupedComicDataSource extends ComicDataSource {
  /// 全源并发搜索并按源分组；失败/空结果源也产出带诊断的 section。
  Future<List<ComicSourceSearchSection>> searchGrouped(String keyword);
}

/// [ComicDataSource.searchGrouped] 的默认实现（扩展形式，兼容所有直接
/// `implements ComicDataSource` 的既有类——它们无需补覆盖即获得分组语义）。
extension ComicDataSourceGroupedX on ComicDataSource {
  /// 调 [ComicDataSource.search] 后按 [ComicSummary.sourceName] 分组；空/缺失
  /// sourceName 归入「默认」组。组按 sourceName 排序，组内保持原顺序。
  /// 走默认路径的数据源没有逐源诊断，section.diagnostics 恒为空。
  Future<List<ComicSourceSearchSection>> searchGrouped(String keyword) async {
    final results = await search(keyword);
    final groups = <String, List<ComicSummary>>{};
    for (final item in results) {
      final key = (item.sourceName ?? '').trim().isEmpty
          ? '默认'
          : item.sourceName!.trim();
      (groups[key] ??= <ComicSummary>[]).add(item);
    }
    final keys = groups.keys.toList()..sort();
    return List<ComicSourceSearchSection>.unmodifiable([
      for (final key in keys)
        ComicSourceSearchSection(
          sourceKey: key,
          items: List<ComicSummary>.unmodifiable(groups[key]!),
        ),
    ]);
  }
}

/// 聚合搜索统一入口：能力源走自己的真分组实现，其余源走扩展默认分组。
///
/// 注意扩展方法是**静态分派**：直接对 [ComicDataSource] 类型的引用调用
/// `searchGrouped` 永远走扩展，即便运行时对象是 [GroupedComicDataSource]。
/// 因此这里先用 `is` 把静态类型收窄到能力接口，才会分派到真实 override。
Future<List<ComicSourceSearchSection>> groupedSearch(
  ComicDataSource source,
  String keyword,
) {
  if (source is GroupedComicDataSource) {
    return source.searchGrouped(keyword);
  }
  return source.searchGrouped(keyword); // 扩展默认分组
}

/// 一个可浏览的源（发现/分类页的来源选择器）。
///
/// 只描述展示所需字段；分类树与发现流是否真的存在，由
/// [ComicBrowseSource.categoryTree] / [ComicBrowseSource.exploreGroups]
/// 在选中该源后按需探测——一次性探测全部源要逐个进 QuickJS runtime，
/// 打开页面时不可接受。
class ComicBrowseSourceInfo {
  const ComicBrowseSourceInfo({
    required this.key,
    required this.name,
    this.enabled = true,
  });

  /// 源注册 key（与 [ComicSummary.sourceName] 同一取值空间）。
  final String key;

  /// 展示名（脚本 `name` 字段，空时回退 key）。
  final String name;

  final bool enabled;
}

/// 发现/分类里的一组漫画：发现页的一个分区，或分类页的一次查询结果。
class ComicBrowseGroup {
  const ComicBrowseGroup({
    required this.title,
    this.comics = const <ComicSummary>[],
    this.exploreIndex = -1,
    this.page = 1,
    this.maxPage,
    this.diagnostics = const <String>[],
  });

  final String title;
  final List<ComicSummary> comics;

  /// 来自源 `explore` 数组的下标；-1 表示不是探索分区（如分类结果）。
  final int exploreIndex;

  /// 本组数据对应的页码（从 1 开始）。
  final int page;

  /// 源声明的总页数；null 表示未知/不分页。
  final int? maxPage;

  /// 本组加载期间的失败原因（空 = 无问题）。页面据此把「分区消失」的
  /// 真实原因显示出来，而不是静默吞掉。
  final List<String> diagnostics;

  bool get hasMore => maxPage != null && page < maxPage!;
}

/// 分类树里的一个分类节点。
class ComicCategoryNode {
  const ComicCategoryNode({required this.name, this.param});

  /// 展示名（分类标签）。
  final String name;

  /// 传给源 `categoryComics.load(category, param, …)` 的第二个参数。
  final String? param;

  @override
  String toString() => 'ComicCategoryNode($name, $param)';
}

/// 分类树的一个分组（源脚本 `category.parts` 的一项）。
class ComicCategoryGroup {
  const ComicCategoryGroup({required this.name, this.nodes = const []});

  final String name;
  final List<ComicCategoryNode> nodes;
}

/// 源的分类树。`groups` 为空表示该源没有 `category`（UI 回退到探索分栏）。
class ComicCategoryTree {
  const ComicCategoryTree({this.title = '', this.groups = const []});

  final String title;
  final List<ComicCategoryGroup> groups;

  bool get isEmpty => groups.every((g) => g.nodes.isEmpty);
}

/// 源站点的「发现 / 分类」浏览能力（抽象）。
///
/// 与 [ComicDataSource] 分开：搜索是用户给定关键词，浏览是源自己提供的
/// 探索流与分类树。真实实现是 A′ 引擎适配层；fixture 提供离线假实现，
/// 页面只认本接口。
abstract interface class ComicBrowseSource {
  /// 可用于浏览的源（通常只含已启用源）。
  Future<List<ComicBrowseSourceInfo>> browseSources();

  /// 某源的全部分区（探索流）；单分区失败只跳过该分区。
  Future<List<ComicBrowseGroup>> exploreGroups(String key, {int page = 1});

  /// 某源探索流里的第 [index] 个分区。
  Future<ComicBrowseGroup> exploreSection(
    String key,
    int index, {
    int page = 1,
  });

  /// 某源的分类树；null 表示该源没有 `category` 定义。
  Future<ComicCategoryTree?> categoryTree(String key);

  /// 按分类取漫画列表。
  Future<ComicBrowseGroup> categoryComics(
    String key,
    ComicCategoryNode node, {
    int page = 1,
  });
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

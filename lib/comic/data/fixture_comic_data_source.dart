import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';

/// 离线假漫画数据源——D′ UI 先用它驱动，A′ 源引擎接入后换实现即可。
///
/// 所有数据固定、可预测：测试直接引用 [defaultSearchResults] 等常量断言，
/// 不发网络请求、不读磁盘。封面统一留空（coverUrl == ''），由 UI 的
/// 渐变占位图兜底，保证 widget 测试完全离线。
class FixtureComicDataSource implements ComicDataSource {
  const FixtureComicDataSource({
    this.searchResults = defaultSearchResults,
    this.details = defaultDetails,
  });

  final List<ComicSummary> searchResults;
  final Map<String, ComicDetail> details;

  @override
  Future<List<ComicSummary>> search(String keyword) async {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return searchResults;
    return searchResults
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              (item.subtitle ?? '').toLowerCase().contains(query) ||
              (item.sourceName ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  // ComicDataSource 是 interface：默认方法体不被 implements 继承，补一行转发。
  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  @override
  List<String> availableSourceKeys() => const <String>[];
  @override
  Future<List<String>> recentSearchTerms() async => const <String>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) async {
    final found = details[item.id];
    if (found != null) return found;
    // 搜索 fixture 之外缺详情时给一个空壳，保证导航不会因假数据缺项崩溃。
    return ComicDetail(
      title: item.title,
      coverUrl: item.coverUrl,
      detailUrl: item.detailUrl,
      description: '',
      sourceName: item.sourceName,
    );
  }

  // Dart 的 interface 契约：implements 方必须显式实现每个成员，接口默认体
  // 不会被 inherits。fixture 无搜索失败诊断，直接返回空（等价于默认语义）。
  @override
  List<String> takeSearchDiagnostics() => const <String>[];

  // ── 固定 fixture ────────────────────────────────────────────────

  static const ComicSummary xingzhou = ComicSummary(
    id: 'xingzhou',
    title: '星舟漫游',
    coverUrl: '',
    detailUrl: 'https://example.com/comic/xingzhou',
    subtitle: '更新至第 30 话',
    sourceName: '漫画DB',
  );
  static const ComicSummary yeyu = ComicSummary(
    id: 'yeyu',
    title: '夜雨剑歌',
    coverUrl: '',
    detailUrl: 'https://example.com/comic/yeyu',
    subtitle: '全 48 话',
    sourceName: '酷漫屋',
  );
  static const ComicSummary mihuan = ComicSummary(
    id: 'mihuan',
    title: '迷幻都市',
    coverUrl: '',
    detailUrl: 'https://example.com/comic/mihuan',
    subtitle: '连载中 · 每周五更新',
    sourceName: '漫画DB',
  );
  static const ComicSummary haibian = ComicSummary(
    id: 'haibian',
    title: '海边文库',
    coverUrl: '',
    detailUrl: 'https://example.com/comic/haibian',
    subtitle: '剧场版',
    sourceName: '酷漫屋',
  );

  /// 搜索页默认显示 4 条（测试断言「N=4 条结果」用这一条）。
  static const List<ComicSummary> defaultSearchResults = <ComicSummary>[
    xingzhou,
    yeyu,
    mihuan,
    haibian,
  ];

  /// 详情 fixture：星舟漫游 5 章（测试断言「渲染 M=5 章」用这一条）。
  static const Map<String, ComicDetail> defaultDetails = <String, ComicDetail>{
    'xingzhou': ComicDetail(
      title: '星舟漫游',
      coverUrl: '',
      detailUrl: 'https://example.com/comic/xingzhou',
      description:
          '一艘失联百年的殖民船在星海深处重新亮起。少年领航员与一支临时拼凑的'
          '船队踏上归途，沿途打捞被遗忘的航线与旧日通信。',
      sourceName: '漫画DB',
      tags: <String>['科幻', '冒险', '治愈'],
      chapters: <ComicChapter>[
        ComicChapter(
          number: 1,
          title: '启航',
          url: 'https://example.com/read/xingzhou/1',
        ),
        ComicChapter(
          number: 2,
          title: '星图',
          url: 'https://example.com/read/xingzhou/2',
        ),
        ComicChapter(
          number: 3,
          title: '失重',
          url: 'https://example.com/read/xingzhou/3',
        ),
        ComicChapter(
          number: 4,
          title: '信号',
          url: 'https://example.com/read/xingzhou/4',
        ),
        ComicChapter(
          number: 5,
          title: '回家',
          url: 'https://example.com/read/xingzhou/5',
        ),
      ],
    ),
    'yeyu': ComicDetail(
      title: '夜雨剑歌',
      coverUrl: '',
      detailUrl: 'https://example.com/comic/yeyu',
      description: '雨夜里的江湖，一柄旧剑和一段未说完的约定。',
      sourceName: '酷漫屋',
      tags: <String>['武侠', '热血'],
      chapters: <ComicChapter>[
        ComicChapter(
          number: 1,
          title: '雨夜来客',
          url: 'https://example.com/read/yeyu/1',
        ),
        ComicChapter(
          number: 2,
          title: '剑起',
          url: 'https://example.com/read/yeyu/2',
        ),
        ComicChapter(
          number: 3,
          title: '旧约',
          url: 'https://example.com/read/yeyu/3',
        ),
      ],
    ),
  };
}

/// 内存版源仓库——源管理页先用它驱动，测试完全离线、状态可预测。
class FixtureComicSourceRepository implements ComicSourceRepository {
  FixtureComicSourceRepository({List<ComicSourceInfo>? sources})
    : _sources = List<ComicSourceInfo>.from(
        sources ?? defaultSources,
        growable: true,
      );

  final List<ComicSourceInfo> _sources;
  int _nextId = 100;

  /// 默认 3 条来源（测试断言「源列表 3 条」用这一条）。
  static const List<ComicSourceInfo> defaultSources = <ComicSourceInfo>[
    ComicSourceInfo(
      id: 'manhuadb',
      name: '漫画DB',
      url: 'https://example.com/src/manhuadb',
      enabled: true,
      comicCount: 1240,
    ),
    ComicSourceInfo(
      id: 'kumanwu',
      name: '酷漫屋',
      url: 'https://example.com/src/kumanwu',
      enabled: true,
      comicCount: 860,
    ),
    ComicSourceInfo(
      id: 'local',
      name: '本地漫画',
      url: 'local://folders',
      enabled: false,
      comicCount: 12,
    ),
  ];

  /// 模拟"从 URL 导入"：从 URL 末段取一个名字，追加到列表末尾。
  @override
  Future<List<ComicSourceInfo>> importSource(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(url, 'url', 'URL 不能为空');
    final segments = Uri.tryParse(trimmed)?.pathSegments ?? const <String>[];
    final name = segments.isNotEmpty ? segments.last : trimmed;
    final source = ComicSourceInfo(
      id: 'imported-${_nextId++}',
      name: name.isEmpty ? '新来源' : name,
      url: trimmed,
      enabled: true,
      comicCount: 0,
    );
    _sources.add(source);
    return snapshot;
  }

  @override
  Future<List<ComicSourceInfo>> setEnabled(String id, bool enabled) async {
    final index = _sources.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _sources[index] = _sources[index].copyWith(enabled: enabled);
    }
    return snapshot;
  }

  @override
  Future<List<ComicSourceInfo>> deleteSource(String id) async {
    _sources.removeWhere((s) => s.id == id);
    return snapshot;
  }

  @override
  Future<List<ComicSourceInfo>> listSources() async => snapshot;

  List<ComicSourceInfo> get snapshot =>
      List<ComicSourceInfo>.unmodifiable(_sources);
}

/// 离线版「发现 / 分类」浏览源——四个分区页的 widget 测试与未接线降级用。
///
/// 两个假源：`fixture` 有分类树，`fixture-plain` 没有分类（验证回退到
/// explore 分栏）。全部固定数据、零网络。
class FixtureComicBrowseSource implements ComicBrowseSource {
  const FixtureComicBrowseSource({
    this.sources = defaultBrowseSources,
    this.groups = defaultGroups,
    this.categories = defaultCategories,
  });

  final List<ComicBrowseSourceInfo> sources;

  /// 每个源 key → 探索分区。
  final Map<String, List<ComicBrowseGroup>> groups;

  /// 每个源 key → 分类树；缺失表示该源没有 category（回退到 explore）。
  final Map<String, ComicCategoryTree> categories;

  static const ComicBrowseSourceInfo fixtureSource = ComicBrowseSourceInfo(
    key: 'fixture',
    name: 'Fixture 源',
  );
  static const ComicBrowseSourceInfo plainSource = ComicBrowseSourceInfo(
    key: 'fixture-plain',
    name: '无分类源',
  );

  static const List<ComicBrowseSourceInfo> defaultBrowseSources =
      <ComicBrowseSourceInfo>[fixtureSource, plainSource];

  /// 两个源共用同一批探索分区（内容差异不影响 UI 断言）。
  static const Map<String, List<ComicBrowseGroup>> defaultGroups =
      <String, List<ComicBrowseGroup>>{
        'fixture': <ComicBrowseGroup>[
          ComicBrowseGroup(
            title: '推荐',
            exploreIndex: 0,
            comics: FixtureComicDataSource.defaultSearchResults,
          ),
          ComicBrowseGroup(
            title: '排行',
            exploreIndex: 1,
            comics: <ComicSummary>[
              FixtureComicDataSource.yeyu,
              FixtureComicDataSource.mihuan,
            ],
          ),
        ],
        'fixture-plain': <ComicBrowseGroup>[
          ComicBrowseGroup(
            title: '最新',
            exploreIndex: 0,
            comics: <ComicSummary>[FixtureComicDataSource.haibian],
          ),
        ],
      };

  static const Map<String, ComicCategoryTree> defaultCategories =
      <String, ComicCategoryTree>{
        'fixture': ComicCategoryTree(
          title: 'Fixture 分类',
          groups: <ComicCategoryGroup>[
            ComicCategoryGroup(
              name: '题材',
              nodes: <ComicCategoryNode>[
                ComicCategoryNode(name: '科幻', param: 'scifi'),
                ComicCategoryNode(name: '武侠', param: 'wuxia'),
              ],
            ),
          ],
        ),
      };

  @override
  Future<List<ComicBrowseSourceInfo>> browseSources() async => sources;

  @override
  Future<List<ComicBrowseGroup>> exploreGroups(
    String key, {
    int page = 1,
  }) async => groups[key] ?? const <ComicBrowseGroup>[];

  @override
  Future<ComicBrowseGroup> exploreSection(
    String key,
    int index, {
    int page = 1,
  }) async {
    for (final group in groups[key] ?? const <ComicBrowseGroup>[]) {
      if (group.exploreIndex == index) return group;
    }
    return ComicBrowseGroup(title: '分区 $index', exploreIndex: index);
  }

  @override
  Future<ComicCategoryTree?> categoryTree(String key) async => categories[key];

  @override
  Future<ComicBrowseGroup> categoryComics(
    String key,
    ComicCategoryNode node, {
    int page = 1,
  }) async => ComicBrowseGroup(
    title: node.name,
    comics: FixtureComicDataSource.defaultSearchResults,
  );
}

// A′ 源引擎 → D′ 数据契约的适配层（closure-02 §1）。
//
// 职责：URL 导入（fetch → parse → 注册执行池 → 落盘 store）、多源搜索聚合
// （结果打标 sourceName=注册 key，单源失败不拖垮其它源）、详情/章节/图片
// 字段映射、启用状态持久化。上层（页面 / comic_entry / app_registry）只依赖
// [ComicDataSource] / [ComicSourceRepository] 接口与本文件暴露的章节 URL
// 编解码助手，不认识 dio、QuickJS 或脚本解析细节。
//
// 源 key 路由约定（docs/comic-integration-decisions.md 决策④）：
// D′ 的 ComicSummary/ComicDetail.sourceName 承载 A′ 的注册 key，每条
// search/detail 结果都必须带上；detail 与图片加载据此反查源。同一作品不同
// 源 = 不同 {id, sourceName}，与 core 投影复合主键对齐。
//
// 章节 URL 约定（决策⑤）：`mimao-ep:///<key>/<comicId>/<epId>`（空权威形式），各段
// Uri.encodeComponent 编码——A′ 搜索结果没有 detailUrl，自描述串保证任意
// 环节都能反查回 epId。

import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart' as source_engine;
import 'package:mimao/comic/search_history_service.dart';

/// 源管理写操作后让执行池与 store 对账的窄能力（comic_entry 探测用）。
abstract interface class ComicSourcePoolSync {
  /// 按 store 现状对执行池注册/释放对账。幂等、零网络（用已落盘脚本注册）。
  Future<void> syncPool();
}

/// 一章的可反查引用（[tryDecodeComicEpisodeUrl] 的解码结果）。
class ComicEpisodeRef {
  final String sourceKey;
  final String comicId;
  final String episodeId;

  const ComicEpisodeRef({
    required this.sourceKey,
    required this.comicId,
    required this.episodeId,
  });

  @override
  String toString() => 'ComicEpisodeRef($sourceKey, $comicId, $episodeId)';
}

/// 章节 URL 的分段编码；各段 component 编码，epId/comicId 可含任意字符。
/// 用空权威形式（`///`）：URI 解析不会把第一段当 host 吞掉。
String comicChapterUrl({
  required String sourceKey,
  required String comicId,
  required String episodeId,
}) =>
    'mimao-ep:///${Uri.encodeComponent(sourceKey)}'
    '/${Uri.encodeComponent(comicId)}'
    '/${Uri.encodeComponent(episodeId)}';

/// 解码 [comicChapterUrl] 生成的章节 URL；不是 mimao-ep 串（如本地章节路径）
/// 返回 null。
///
/// [Uri.pathSegments] 已按组件做一次百分号解码，与 [comicChapterUrl] 的
/// `Uri.encodeComponent` 精确互逆——**不再二次 decodeComponent**（epId 含
/// 字面 `%` 会被错误解码甚至抛异常，对抗性审查 P1）。畸形串一律收敛为 null。
ComicEpisodeRef? tryDecodeComicEpisodeUrl(String url) {
  final Uri uri;
  try {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null || parsed.scheme != 'mimao-ep') return null;
    uri = parsed;
  } on Object {
    return null;
  }
  final List<String> segments;
  try {
    segments = uri.pathSegments;
  } on Object {
    return null;
  }
  if (segments.length != 3) return null;
  return ComicEpisodeRef(
    sourceKey: segments[0],
    comicId: segments[1],
    episodeId: segments[2],
  );
}

/// 从 URL 派生源 key（basename 去扩展名 + 清洗非法字符）。
/// 脚本自带 `key` 字段时优先于派生值（[source_engine.ComicSourceImporter] 的现有语义）。
String deriveSourceKeyFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final segments = uri?.pathSegments ?? const <String>[];
  final file = segments.isEmpty ? '' : segments.last;
  var key = file;
  final dot = key.lastIndexOf('.');
  if (dot > 0) key = key.substring(0, dot);
  key = key.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]+'), '-').trim();
  while (key.startsWith('-')) {
    key = key.substring(1);
  }
  while (key.endsWith('-')) {
    key = key.substring(0, key.length - 1);
  }
  return key.isEmpty ? 'source' : key;
}

/// [ComicDataSource] / [ComicSourceRepository] 的真实实现：包装 A′ 的
/// [source_engine.ComicSourceEngine] + [source_engine.ComicSourceStore] + [source_engine.ComicHttpClient]。
///
/// 通过 [create] 构造：启动时读 store 并把每个源注册进执行池（单源注册失败
/// 不拖垮其它源，原因记入 [takeDiagnostics]）。源清单缓存在内存里，写操作
/// （导入/启删）后刷新。
class EngineComicDataSource
    implements
        ComicDataSource,
        GroupedComicDataSource,
        ComicSourceRepository,
        ComicSourcePoolSync,
        ComicBrowseSource {
  EngineComicDataSource._({
    required this.store,
    required this.engine,
    required this.client,
    ComicSearchHistoryService? searchHistory,
  }) : _searchHistory = searchHistory;

  final source_engine.ComicSourceStore store;
  final source_engine.ComicSourceEngine engine;
  final source_engine.ComicHttpClient client;
  final ComicSearchHistoryService? _searchHistory;

  /// store 的内存缓存（create 与写操作后刷新）。
  List<source_engine.ComicSourceScript> _sources =
      const <source_engine.ComicSourceScript>[];
  final List<String> _diagnostics = <String>[];

  /// 搜索期诊断缓冲：只保留最近一次 [search] 期间逐源的失败原因，供
  /// [takeSearchDiagnostics] 取走上达 UI。与 [_diagnostics]（注册/加载/详情/
  /// 图片等累积诊断，上限 200）分开，避免一次全源失败把长期诊断冲掉，也
  /// 避免长期诊断里夹杂旧搜索的原因误导用户。
  final List<String> _searchDiagnostics = <String>[];

  /// 诊断信息的环形上限：生产路径没有消费者（源管理页尚无诊断出口），
  /// 坏源 + 长会话下不做封顶会无界增长（对抗性审查 P2）。
  static const int _maxDiagnostics = 200;

  /// 搜索期诊断缓冲上限（提示词「已知坑」建议 50）：一次搜索失败源很多时
  /// 也不能让缓冲无界增长。
  static const int _maxSearchDiagnostics = 50;

  void _addDiagnostics(Iterable<String> messages) {
    _diagnostics.addAll(messages);
    if (_diagnostics.length > _maxDiagnostics) {
      _diagnostics.removeRange(0, _diagnostics.length - _maxDiagnostics);
    }
  }

  /// 取走并清空累积的诊断信息（单源失败原因等）。
  List<String> takeDiagnostics() {
    final result = List<String>.from(_diagnostics);
    _diagnostics.clear();
    return result;
  }

  /// 取走并清空最近一次搜索期诊断（契约接口 [ComicDataSource] 的可选出口）。
  /// 与 [takeDiagnostics] 分开：本方法只面向搜索页的错误态。
  @override
  List<String> takeSearchDiagnostics() {
    final result = List<String>.from(_searchDiagnostics);
    _searchDiagnostics.clear();
    return result;
  }

  /// 追加一条搜索期诊断，保持环形上限 [_maxSearchDiagnostics]。
  void _addSearchDiagnostic(String message) {
    _searchDiagnostics.add(message);
    if (_searchDiagnostics.length > _maxSearchDiagnostics) {
      _searchDiagnostics.removeRange(
        0,
        _searchDiagnostics.length - _maxSearchDiagnostics,
      );
    }
  }

  /// 注册期 `init()` 是非阻塞的：异步失败在注册时可能还没落地，这里在
  /// 搜索入口补一次取走，转成长期诊断 + 本次搜索诊断，避免静默吞掉。
  /// 返回诊断文本供 [searchGrouped] 写进该源的 section（调用方可忽略）。
  String? _takeInitError(String key) {
    final error = engine.pool.takeInitError(key);
    if (error == null) return null;
    final message = '$key：初始化失败（$error）';
    _addDiagnostics(<String>[message]);
    _addSearchDiagnostic(message);
    return message;
  }

  /// 读取 store 全部源并注册进执行池。返回加载结果（含坏文件说明）。
  Future<source_engine.ComicSourceLoadResult> reload() async {
    final loaded = await store.loadAllDetailed();
    _sources = List<source_engine.ComicSourceScript>.from(loaded.sources);
    _addDiagnostics(loaded.failures);
    await _registerAll(_sources);
    return loaded;
  }

  /// 按 store 现状对执行池对账：注册缺失/过期的源，释放已删除的源。
  @override
  Future<void> syncPool() async {
    final loaded = await store.loadAllDetailed();
    _sources = List<source_engine.ComicSourceScript>.from(loaded.sources);
    for (final source in _sources) {
      await _registerOne(source);
    }
    for (final key in engine.pool.keys.toList()) {
      if (!_sources.any((s) => s.key == key)) {
        engine.pool.dispose(key);
      }
    }
  }

  Future<void> _registerAll(
    List<source_engine.ComicSourceScript> sources,
  ) async {
    for (final source in sources) {
      await _registerOne(source);
    }
  }

  Future<void> _registerOne(source_engine.ComicSourceScript source) async {
    if (engine.pool.contains(source.key)) {
      final existing = _registeredScripts[source.key];
      if (existing == source.script) return;
      engine.pool.dispose(source.key);
    }
    try {
      await engine.pool.register(source.key, source.script);
      _registeredScripts[source.key] = source.script;
      // init 是注册期非阻塞调用；同步失败此时已记下，异步失败由搜索入口再取。
      final initError = engine.pool.takeInitError(source.key);
      if (initError != null) {
        _addDiagnostics(<String>['${source.key}：初始化失败（$initError）']);
      }
    } on Object catch (error) {
      _addDiagnostics(<String>['${source.key}：脚本注册失败（$error）']);
    }
  }

  final Map<String, String> _registeredScripts = <String, String>{};

  /// 组装：读 store、注册执行池。注册失败的源不进缓存以外的任何分支，
  /// 由 [reload] 的 failures 汇报。
  static Future<EngineComicDataSource> create({
    required source_engine.ComicSourceStore store,
    required source_engine.ComicSourceEngine engine,
    required source_engine.ComicHttpClient client,
    ComicSearchHistoryService? searchHistory,
  }) async {
    final source = EngineComicDataSource._(
      store: store,
      engine: engine,
      client: client,
      searchHistory: searchHistory,
    );
    await source.reload();
    return source;
  }

  // ── ComicDataSource ─────────────────────────────────────────────

  @override
  Future<List<ComicSummary>> search(String keyword) async {
    // 摊平视图直接复用聚合结果，消除两份并发/诊断逻辑漂移：分组按源 key
    // 稳定排序，摊平后的顺序与旧实现（enabled 按 key 排序后逐源合并）一致。
    final sections = await searchGrouped(keyword);
    return List<ComicSummary>.unmodifiable([
      for (final section in sections) ...section.items,
    ]);
  }

  @override
  Future<List<ComicSourceSearchSection>> searchGrouped(String keyword) async {
    // 每次搜索开头清空搜索期缓冲：一次 build 只读一次（取走即清），
    // 保证诊断只对应本次搜索，不混入上一次的失败原因。
    _searchDiagnostics.clear();
    final query = keyword.trim();
    if (query.isNotEmpty) {
      try {
        await _searchHistory?.record(query);
      } on Object {
        // 搜索历史落库失败不挡搜索。
      }
    }
    // 空关键词不做推荐流（决策⑧）：真实源的 search.load('') 语义未定义。
    if (query.isEmpty) return const <ComicSourceSearchSection>[];

    final enabled = _sources.where((s) => s.enabled).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // 并发搜索：33 个源串行 + 单源最长 30s 会让一次搜索拖到数分钟；并行后
    // 总耗时收敛为「最慢的源」。诊断按源 key 顺序合并，结果顺序保持稳定。
    // 单源失败（引擎 throw / 解析异常）只记诊断，不让 Future.wait 整体 reject
    // 成「搜索失败」——否则一个坏源就吞掉其它源的全部结果。
    final entries = await Future.wait(
      enabled.map((source) async {
        try {
          final result = await engine.search(source.key, query);
          return (key: source.key, result: result, error: null);
        } on Object catch (error) {
          return (key: source.key, result: null, error: error);
        }
      }),
    );
    final sections = <ComicSourceSearchSection>[];
    for (final entry in entries) {
      // section 诊断与 _searchDiagnostics 同源：两条出口文案一致，UI 分组模式
      // 读 section.diagnostics，单源/摊平模式读 takeSearchDiagnostics。
      final sectionDiagnostics = <String>[];
      final initError = _takeInitError(entry.key);
      if (initError != null) sectionDiagnostics.add(initError);

      final result = entry.result;
      final items = <ComicSummary>[];
      if (result == null) {
        final message = '${entry.key}：搜索异常（${entry.error}）';
        _addDiagnostics(<String>[message]);
        _addSearchDiagnostic(message);
        sectionDiagnostics.add(message);
      } else {
        final prefixed = result.diagnostics
            .map((d) => '${entry.key}：$d')
            .toList();
        _addDiagnostics(prefixed);
        for (final message in prefixed) {
          _addSearchDiagnostic(message);
        }
        sectionDiagnostics.addAll(prefixed);
        // 源返回空且无任何诊断：错误不得被吞成「没找到」，给出可读原因。
        if (result.items.isEmpty && prefixed.isEmpty) {
          final message = '${entry.key}：搜索无结果且未返回原因';
          _addSearchDiagnostic(message);
          sectionDiagnostics.add(message);
        }
        for (final item in result.items) {
          items.add(_mapSummary(item, entry.key));
        }
      }
      // 每个参与搜索的源都有 section：0 结果带诊断的源也不会静默消失。
      sections.add(
        ComicSourceSearchSection(
          sourceKey: entry.key,
          items: List<ComicSummary>.unmodifiable(items),
          diagnostics: List<String>.unmodifiable(sectionDiagnostics),
        ),
      );
    }
    return List<ComicSourceSearchSection>.unmodifiable(sections);
  }

  @override
  Future<List<ComicSummary>> searchSource(String key, String keyword) async {
    // 与 search 同口径：每次搜索清空搜索期诊断缓冲，且失败原因要上达 UI。
    // 原先只写 _diagnostics（源管理/详情诊断），搜索页取不到，单源失败被
    // 显示成"没有找到"——这里补齐，避免"错误被吞成空结果"。
    _searchDiagnostics.clear();
    final query = keyword.trim();
    if (query.isNotEmpty) {
      try {
        await _searchHistory?.record(query);
      } on Object {
        // 搜索历史落库失败不挡搜索（与 search 同语义）。
      }
    }
    // 空关键词不做推荐流（决策⑧）：与 search 保持一致。
    if (query.isEmpty) return const <ComicSummary>[];

    final source_engine.ComicSourceResult<source_engine.ComicSummary> result;
    try {
      result = await engine.search(key, query);
    } on Object catch (error) {
      final message = '$key：搜索异常（$error）';
      _addDiagnostics(<String>[message]);
      _addSearchDiagnostic(message);
      return const <ComicSummary>[];
    }
    _takeInitError(key);
    final prefixed = result.diagnostics.map((d) => '$key：$d').toList();
    _addDiagnostics(prefixed);
    for (final message in prefixed) {
      _addSearchDiagnostic(message);
    }
    if (result.items.isEmpty && prefixed.isEmpty) {
      _addSearchDiagnostic('$key：搜索无结果且未返回原因');
    }
    return List<ComicSummary>.unmodifiable(
      result.items.map((item) => _mapSummary(item, key)),
    );
  }

  @override
  List<String> availableSourceKeys() => List<String>.unmodifiable(
    _sources.where((s) => s.enabled).map((s) => s.key).toList()..sort(),
  );

  @override
  Future<List<String>> recentSearchTerms() async =>
      (await _searchHistory?.recent()) ?? const <String>[];

  @override
  Future<ComicDetail> detail(ComicSummary item) async {
    final key = (item.sourceName ?? '').trim();
    if (key.isEmpty) {
      throw ArgumentError.value(item, 'item', '结果缺少来源 key（sourceName）');
    }
    final result = await engine.detail(key, item.id);
    if (result.items.isEmpty) {
      throw StateError('详情获取失败（$key）：${result.diagnostics.join('；')}');
    }
    return _mapDetail(result.items.single, key, comicId: item.id);
  }

  // ── 图片加载（不在 ComicDataSource 契约里，供阅读接线用）─────────

  /// 取一章的图片引用（地址 + 源 `onImageLoad` 请求头）。引擎失败/空图返回空
  /// 列表（阅读控制器负责跳过空章）；诊断照旧收集，不因返回引用而丢。
  Future<List<source_engine.ComicImageRef>> loadEpImages({
    required String key,
    required String comicId,
    required String episodeId,
  }) async {
    final result = await engine.images(key, comicId, episodeId: episodeId);
    _addDiagnostics(result.diagnostics.map((d) => '$key：$d'));
    return List<source_engine.ComicImageRef>.unmodifiable(result.items);
  }

  /// 按 D′ 章节加载图片引用：解码章节 URL 反查 epId，按条目来源 key 调引擎。
  /// 返回空列表表示「该章不可加载」（坏 URL / 引擎失败 / 空图）。
  Future<List<source_engine.ComicImageRef>> loadImagesForChapter(
    ComicSummary item,
    ComicChapter chapter,
  ) async {
    final ep = tryDecodeComicEpisodeUrl(chapter.url);
    if (ep == null) {
      _addDiagnostics(<String>['章节地址无法反查：${chapter.url}']);
      return const <source_engine.ComicImageRef>[];
    }
    final key = (item.sourceName ?? '').trim();
    if (key.isEmpty || key != ep.sourceKey) {
      _addDiagnostics(<String>['章节来源不匹配：${ep.sourceKey} vs $key']);
      return const <source_engine.ComicImageRef>[];
    }
    return loadEpImages(key: key, comicId: ep.comicId, episodeId: ep.episodeId);
  }

  // ── ComicBrowseSource（发现 / 分类）──────────────────────────────

  @override
  Future<List<ComicBrowseSourceInfo>> browseSources() async => [
    for (final source in _sources.where((s) => s.enabled))
      ComicBrowseSourceInfo(
        key: source.key,
        name: source.name.isEmpty ? source.key : source.name,
      ),
  ];

  @override
  Future<List<ComicBrowseGroup>> exploreGroups(
    String key, {
    int page = 1,
  }) async {
    _searchDiagnostics.clear();
    final result = await engine.exploreGroups(key, page: page);
    _absorbBrowseDiagnostics(key, result.diagnostics);
    return [
      for (final group in result.items)
        ComicBrowseGroup(
          title: group.title,
          comics: _mapSummaries(group.comics, key),
          exploreIndex: group.index,
          page: group.page,
          maxPage: group.maxPage,
          diagnostics: group.diagnostics,
        ),
    ];
  }

  @override
  Future<ComicBrowseGroup> exploreSection(
    String key,
    int index, {
    int page = 1,
  }) async {
    _searchDiagnostics.clear();
    final result = await engine.exploreSection(key, index, page: page);
    _absorbBrowseDiagnostics(key, result.diagnostics);
    if (result.items.isEmpty) {
      return ComicBrowseGroup(
        title: '推荐',
        exploreIndex: index,
        page: page,
        diagnostics: result.diagnostics,
      );
    }
    final group = result.items.first;
    return ComicBrowseGroup(
      title: group.title,
      comics: _mapSummaries(group.comics, key),
      exploreIndex: index,
      page: group.page,
      maxPage: group.maxPage,
      diagnostics: group.diagnostics,
    );
  }

  @override
  Future<ComicCategoryTree?> categoryTree(String key) async {
    _searchDiagnostics.clear();
    final category = await engine.category(key);
    _takeInitError(key);
    if (category == null || category.isEmpty) return null;
    return ComicCategoryTree(
      title: category.title,
      groups: [
        for (final part in category.parts)
          ComicCategoryGroup(
            name: part.name,
            nodes: [
              for (final item in part.items)
                ComicCategoryNode(name: item.name, param: item.param),
            ],
          ),
      ],
    );
  }

  @override
  Future<ComicBrowseGroup> categoryComics(
    String key,
    ComicCategoryNode node, {
    int page = 1,
  }) async {
    _searchDiagnostics.clear();
    final result = await engine.categoryComics(
      key,
      source_engine.ComicCategoryItem(name: node.name, param: node.param),
      page: page,
    );
    _absorbBrowseDiagnostics(key, result.diagnostics);
    if (result.items.isEmpty) {
      return ComicBrowseGroup(
        title: node.name,
        page: page,
        diagnostics: result.diagnostics,
      );
    }
    final group = result.items.first;
    return ComicBrowseGroup(
      title: node.name,
      comics: _mapSummaries(group.comics, key),
      exploreIndex: -1,
      page: group.page,
      maxPage: group.maxPage,
      diagnostics: group.diagnostics,
    );
  }

  /// 浏览期诊断并入长期缓冲与搜索期缓冲（发现/分类页与搜索页共用同一
  /// 「取走即清」的诊断出口，失败原因不会静默）。
  void _absorbBrowseDiagnostics(String key, List<String> diagnostics) {
    if (diagnostics.isEmpty) return;
    final prefixed = [for (final d in diagnostics) '$key：$d'];
    _addDiagnostics(prefixed);
    for (final message in prefixed) {
      _addSearchDiagnostic(message);
    }
  }

  List<ComicSummary> _mapSummaries(
    List<source_engine.ComicSummary> items,
    String key,
  ) => [for (final item in items) _mapSummary(item, key)];

  // ── 字段映射（决策④：sourceName = 注册 key）────────────────────

  /// A′ `ComicSummary` → D′ [ComicSummary]。A′ 没有详情地址，`detailUrl`
  /// 恒为空串；tags/description/maxPage 等列表页不展示的字段丢弃。
  ComicSummary _mapSummary(source_engine.ComicSummary item, String key) =>
      ComicSummary(
        id: item.id,
        title: item.title,
        coverUrl: item.cover,
        detailUrl: '',
        subtitle: item.subtitle.isEmpty ? null : item.subtitle,
        sourceName: key,
      );

  /// A′ `ComicDetail` → D′ [ComicDetail]：cover→coverUrl、url→detailUrl、
  /// 标签分组展平、章节按列表序编号并编成 mimao-ep 串。
  ComicDetail _mapDetail(
    source_engine.ComicDetail detail,
    String key, {
    required String comicId,
  }) => ComicDetail(
    title: detail.title,
    coverUrl: detail.cover,
    detailUrl: detail.url,
    description: detail.description,
    sourceName: key,
    tags: _flattenTags(detail.tags),
    chapters: <ComicChapter>[
      for (var i = 0; i < detail.chapters.length; i++)
        ComicChapter(
          number: i + 1,
          title: detail.chapters[i].title,
          url: comicChapterUrl(
            sourceKey: key,
            comicId: comicId,
            episodeId: detail.chapters[i].id,
          ),
        ),
    ],
  );

  /// `Map<分组, 标签列表>` → 展平去重保序的标签列表。
  List<String> _flattenTags(Map<String, List<String>> tags) {
    final result = <String>[];
    for (final values in tags.values) {
      for (final value in values) {
        if (value.isNotEmpty && !result.contains(value)) {
          result.add(value);
        }
      }
    }
    return List<String>.unmodifiable(result);
  }

  // ── ComicSourceRepository ───────────────────────────────────────

  @override
  Future<List<ComicSourceInfo>> listSources() async => _mapSourceInfos();

  @override
  Future<List<ComicSourceInfo>> importSource(String url) async {
    final script = await _fetchAndParse(url);
    // 同 key 重导（更新）：保留用户已有的启用状态——name/version 随新脚本
    // 刷新是预期更新行为，但禁用选择不该被静默重置（对抗性审查 P2）。
    final existingIndex = _sources.indexWhere((s) => s.key == script.key);
    final merged = existingIndex >= 0
        ? script.copyWith(enabled: _sources[existingIndex].enabled)
        : script;
    // 先注册后落盘（决策⑦）：注册失败的畸形脚本不留下半成品。
    try {
      await engine.pool.register(merged.key, merged.script);
    } on Object catch (error) {
      throw StateError('${merged.key}：脚本无法注册（$error）');
    }
    try {
      await store.save(merged);
    } on Object {
      // 落盘失败：回滚执行池条目，避免池内驻留一个未落盘的源（审查 P2）。
      engine.pool.dispose(merged.key);
      _registeredScripts.remove(merged.key);
      rethrow;
    }
    _registeredScripts[merged.key] = merged.script;
    await reload();
    return _mapSourceInfos();
  }

  @override
  Future<List<ComicSourceInfo>> setEnabled(String id, bool enabled) async {
    final source = _find(id);
    await store.save(source.copyWith(enabled: enabled));
    await reload();
    return _mapSourceInfos();
  }

  @override
  Future<List<ComicSourceInfo>> deleteSource(String id) async {
    final removed = await store.delete(id);
    if (!removed) {
      throw StateError('来源不存在：$id');
    }
    engine.pool.dispose(id);
    _registeredScripts.remove(id);
    await reload();
    return _mapSourceInfos();
  }

  source_engine.ComicSourceScript _find(String key) {
    final index = _sources.indexWhere((s) => s.key == key);
    if (index < 0) {
      throw StateError('来源不存在：$key');
    }
    return _sources[index];
  }

  List<ComicSourceInfo> _mapSourceInfos() =>
      List<ComicSourceInfo>.unmodifiable(<ComicSourceInfo>[
        for (final source in _sources)
          ComicSourceInfo(
            id: source.key,
            name: source.name.isEmpty ? source.key : source.name,
            url: source.url,
            enabled: source.enabled,
          ),
      ]);

  /// URL 导入主流程，失败以 [ComicSourceImportResult.failures] 语义收敛成
  /// 带可读原因的异常（决策⑦：repository 层抛异常 → 页面错误态）。
  Future<source_engine.ComicSourceScript> _fetchAndParse(String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw FormatException('不是有效的绝对 URL：$trimmed');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('仅支持 http(s) 地址：$trimmed');
    }

    final source_engine.ComicHttpResponse response;
    try {
      response = await client.fetch(trimmed);
    } on Object catch (error) {
      throw StateError('下载源脚本失败：$error');
    }
    if (!response.isSuccessful) {
      throw StateError('下载源脚本失败：HTTP ${response.statusCode}');
    }
    if (response.body.trim().isEmpty) {
      throw StateError('源脚本内容为空');
    }

    final result = source_engine.ComicSourceImporter().parseSingle(
      response.body,
      fallbackKey: deriveSourceKeyFromUrl(trimmed),
    );
    if (result.sources.isEmpty) {
      throw StateError(result.failures.join('；'));
    }
    // 导入的 URL 写进元数据（决策⑦）：脚本自带 url 也覆盖为导入地址。
    return result.sources.single.copyWith(url: trimmed);
  }
}

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
ComicEpisodeRef? tryDecodeComicEpisodeUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'mimao-ep') return null;
  final segments = uri.pathSegments;
  if (segments.length != 3) return null;
  return ComicEpisodeRef(
    sourceKey: Uri.decodeComponent(segments[0]),
    comicId: Uri.decodeComponent(segments[1]),
    episodeId: Uri.decodeComponent(segments[2]),
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
    implements ComicDataSource, ComicSourceRepository, ComicSourcePoolSync {
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

  /// 取走并清空累积的诊断信息（单源失败原因等）。
  List<String> takeDiagnostics() {
    final result = List<String>.from(_diagnostics);
    _diagnostics.clear();
    return result;
  }

  /// 读取 store 全部源并注册进执行池。返回加载结果（含坏文件说明）。
  Future<source_engine.ComicSourceLoadResult> reload() async {
    final loaded = await store.loadAllDetailed();
    _sources = List<source_engine.ComicSourceScript>.from(loaded.sources);
    _diagnostics.addAll(loaded.failures);
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
    } on Object catch (error) {
      _diagnostics.add('${source.key}：脚本注册失败（$error）');
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
    final query = keyword.trim();
    if (query.isNotEmpty) {
      try {
        await _searchHistory?.record(query);
      } on Object {
        // 搜索历史落库失败不挡搜索。
      }
    }
    // 空关键词不做推荐流（决策⑧）：真实源的 search.load('') 语义未定义。
    if (query.isEmpty) return const <ComicSummary>[];

    final enabled = _sources.where((s) => s.enabled).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final merged = <ComicSummary>[];
    for (final source in enabled) {
      final result = await engine.search(source.key, query);
      _diagnostics.addAll(result.diagnostics.map((d) => '${source.key}：$d'));
      for (final item in result.items) {
        merged.add(_mapSummary(item, source.key));
      }
    }
    return List<ComicSummary>.unmodifiable(merged);
  }

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

  /// 取一章的图片地址列表。引擎失败/空图返回空列表（调用方跳过空章）。
  Future<List<String>> loadEpImages({
    required String key,
    required String comicId,
    required String episodeId,
  }) async {
    final result = await engine.images(key, comicId, episodeId: episodeId);
    _diagnostics.addAll(result.diagnostics.map((d) => '$key：$d'));
    return List<String>.unmodifiable(result.items.map((image) => image.url));
  }

  /// 按 D′ 章节加载图片：解码章节 URL 反查 epId，按条目来源 key 调引擎。
  /// 返回空列表表示「该章不可加载」（坏 URL / 引擎失败 / 空图）。
  Future<List<String>> loadImagesForChapter(
    ComicSummary item,
    ComicChapter chapter,
  ) async {
    final ep = tryDecodeComicEpisodeUrl(chapter.url);
    if (ep == null) {
      _diagnostics.add('章节地址无法反查：${chapter.url}');
      return const <String>[];
    }
    final key = (item.sourceName ?? '').trim();
    if (key.isEmpty || key != ep.sourceKey) {
      _diagnostics.add('章节来源不匹配：${ep.sourceKey} vs $key');
      return const <String>[];
    }
    return loadEpImages(key: key, comicId: ep.comicId, episodeId: ep.episodeId);
  }

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
    // 先注册后落盘（决策⑦）：注册失败的畸形脚本不留下半成品。
    try {
      await engine.pool.register(script.key, script.script);
      _registeredScripts[script.key] = script.script;
    } on Object catch (error) {
      throw StateError('${script.key}：脚本无法注册（$error）');
    }
    await store.save(script);
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

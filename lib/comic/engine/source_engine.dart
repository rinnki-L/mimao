/// 源引擎编排层：调用已注册源的方法，把 JS 原始结果收敛成纯数据模型。
///
/// 上层只依赖这里与 [models.dart]；网络/解析/QuickJS 细节全在下面几层。
library;

import 'js_host.dart';
import 'models.dart';

/// 漫画源引擎。
class ComicSourceEngine {
  ComicSourceEngine({SourceExecutionPool? pool})
    : _pool = pool ?? SourceExecutionPool();

  final SourceExecutionPool _pool;

  SourceExecutionPool get pool => _pool;

  /// 搜索：`source.search.load(keyword, options, page)` → `{comics, maxPage}`。
  ///
  /// 未显式传 [options] 时按 Venera 的搜索页语义，用每个
  /// `source.search.optionList` 项的 `defaultValue` 作为默认选项（有 `default`
  /// 取 `JSON.stringify(default)`，否则取第一个合法 option 的 value）。默认值
  /// 必须在 JS 侧算：`optionList` 是运行期存活的源数据，Dart 看不到，另起一次
  /// 执行又多一轮 roundtrip。
  ///
  /// 只实现了 `search.loadNext` 的源（如 ehentai）没有 `search.load`，回退到
  /// `search.loadNext(keyword, options, null)`——首屏没有 next token；这种源
  /// 不支持翻页，maxPage 固定为 null。
  Future<ComicSourceResult<ComicSummary>> search(
    String key,
    String keyword, {
    List<String?> options = const <String?>[],
    int page = 1,
  }) async {
    final keywordJs = _q(keyword);
    final optionsJs = options.isEmpty
        ? _defaultSearchOptionsJs
        : _jsonList(options);
    // 三元而不是 IIFE：既有测试/宿主按 `source.search.load` 前缀识别搜索调用。
    final expression =
        'source.search.load && typeof source.search.load === "function"'
        ' ? source.search.load($keywordJs, $optionsJs, $page)'
        ' : Promise.resolve(source.search.loadNext($keywordJs, $optionsJs, null))'
        '.then((r) => Array.isArray(r) ? r : { comics: r && r.comics, maxPage: null })';
    final execution = await _pool.execute(key, expression);
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    return parseComicList(execution.value, 'maxPage');
  }

  /// 详情：`source.comic.loadInfo(id)` → `ComicDetails`。
  Future<ComicSourceResult<ComicDetail>> detail(
    String key,
    String comicId,
  ) async {
    final execution = await _pool.execute(
      key,
      'source.comic.loadInfo(${_q(comicId)})',
    );
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    final detail = parseComicDetail(execution.value);
    return detail == null
        ? ComicSourceResult(diagnostics: const <String>['详情结果无法解析'])
        : ComicSourceResult(items: <ComicDetail>[detail]);
  }

  /// 章节图片：`source.comic.loadEp(comicId, epId)` → `{images: string[]}`。
  Future<ComicSourceResult<ComicImageRef>> images(
    String key,
    String comicId, {
    String? episodeId,
  }) async {
    final ep = episodeId == null ? 'null' : _q(episodeId);
    final execution = await _pool.execute(
      key,
      'source.comic.loadEp(${_q(comicId)}, $ep)',
    );
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    return parseImages(execution.value);
  }

  /// 单张图懒解析 `comic.onImageLoad`：返回该图的请求头。
  ///
  /// 阅读器预取到哪张才解析哪张，避免打开一章就把整章 N 次钩子全跑一遍
  /// （钩子内部可能有网络请求）。源未定义钩子、钩子抛错或返回非 map 时
  /// 返回空 map，加载器继续用默认 UA/Referer。
  Future<Map<String, String>> imageHeaders(
    String key,
    String imageKey,
    String comicId, {
    String? episodeId,
  }) async {
    final ep = episodeId == null ? 'null' : _q(episodeId);
    final execution = await _pool.execute(key, '''
(async () => {
  if (typeof source.comic.onImageLoad !== 'function') return null;
  try {
    const config = await source.comic.onImageLoad(
      ${_q(imageKey)}, ${_q(comicId)}, $ep
    );
    return config && config.headers ? config.headers : null;
  } catch (error) {
    return null;
  }
})()
''');
    if (!execution.isOk) return const <String, String>{};
    return _stringMap(execution.value);
  }

  /// 章节图片 + 源注入的加载配置：一次 JS 调用里跑完 `loadEp` 与逐图
  /// `comic.onImageLoad`，返回 `{images, headers: {url: {headers}}}`。
  ///
  /// 单张图的 onImageLoad 抛错不影响整章：该图退回无头请求。源没有定义
  /// onImageLoad 时直接把 headers 留空。这样阅读器每打开一章只多一次
  /// Host 往返，而不是每张图一次。
  Future<ComicSourceResult<ComicImageRef>> imagesWithHeaders(
    String key,
    String comicId, {
    String? episodeId,
  }) async {
    final ep = episodeId == null ? 'null' : _q(episodeId);
    final cid = _q(comicId);
    final execution = await _pool.execute(key, '''
(async () => {
  if (typeof source.comic.loadEp !== 'function') return null;
  const result = await source.comic.loadEp($cid, $ep);
  const images = Array.isArray(result) ? result : (result && result.images) || [];
  const headers = {};
  if (typeof source.comic.onImageLoad === 'function') {
    for (const image of images) {
      if (typeof image !== 'string') continue;
      try {
        const config = await source.comic.onImageLoad(image, $cid, $ep);
        if (config && config.headers) headers[image] = config.headers;
      } catch (error) {
        // 单张失败不影响整章；该图退回默认请求头。
      }
    }
  }
  return {images, headers};
})()
''');
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    return parseImages(execution.value);
  }

  /// 探索页：`source.explore[i].load(page)` → 漫画列表。
  Future<ComicSourceResult<ComicSummary>> explore(
    String key,
    int index, {
    int page = 1,
  }) async {
    final execution = await _pool.execute(
      key,
      'source.explore[$index].load($page)',
    );
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    return parseComicList(execution.value, null);
  }

  // ── 发现（explore）/ 分类（category）──────────────────────────────
  //
  // 社区源这两块的形状差异很大（Venera 模板允许 multiPartPage /
  // multiPageComicList / mixed / singlePageWithMultiPart；分类还可能是
  // dynamic loader），所以解析全部走「宽松 + 逐分区容错」：任何一段解析不出
  // 就只丢这一段并记诊断，不让整页失败。

  /// 一次执行取某源 `explore` 的**全部分区**（分区内失败只影响该分区）。
  ///
  /// 表达式在 JS 侧 `Promise.all` 逐分区 catch：一个分区抛错不会让整次
  /// 调用 reject（与搜索「单源失败不拖垮其它源」同一口径）。
  Future<ComicSourceResult<ComicExploreGroup>> exploreGroups(
    String key, {
    int page = 1,
  }) async {
    final execution = await _pool.execute(key, _exploreAllExpression(page));
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    final raw = execution.value;
    if (raw is! List) {
      return const ComicSourceResult(
        diagnostics: <String>['探索结果无法解析（源未提供 explore）'],
      );
    }
    final groups = <ComicExploreGroup>[];
    final diagnostics = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = _asMap(raw[i]);
      if (entry == null) continue;
      final title = _string(entry['title']);
      final index = _int(entry['index']) ?? i;
      final error = _string(entry['error']);
      if (error.isNotEmpty) {
        // 失败分区也保留成一个「空数据 + 诊断」的分区：上层据此把真实
        // 原因显示出来（否则分区凭空消失，用户只看到少了一栏）。
        final sectionTitle = title.isEmpty ? '分区 $index' : title;
        diagnostics.add('$sectionTitle：$error');
        groups.add(
          ComicExploreGroup(
            title: sectionTitle,
            index: index,
            page: page,
            diagnostics: <String>[error],
          ),
        );
        continue;
      }
      final parsed = parseExplorePayload(
        entry['data'],
        title: title,
        index: index,
        page: page,
      );
      groups.addAll(parsed.groups);
      diagnostics.addAll(parsed.diagnostics);
    }
    return ComicSourceResult(items: groups, diagnostics: diagnostics);
  }

  /// 取某源 `explore[index]` 一个分区（翻页用；也用于只加载单栏的场景）。
  Future<ComicSourceResult<ComicExploreGroup>> exploreSection(
    String key,
    int index, {
    int page = 1,
  }) async {
    final execution = await _pool.execute(
      key,
      _exploreOneExpression(index, page),
    );
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    final map = _asMap(execution.value);
    if (map == null) {
      return const ComicSourceResult(diagnostics: <String>['探索结果无法解析']);
    }
    final title = _string(map['title']);
    final error = _string(map['error']);
    if (error.isNotEmpty) {
      final sectionTitle = title.isEmpty ? '分区 $index' : title;
      return ComicSourceResult(
        items: <ComicExploreGroup>[
          ComicExploreGroup(
            title: sectionTitle,
            index: index,
            page: page,
            diagnostics: <String>[error],
          ),
        ],
        diagnostics: <String>['$sectionTitle：$error'],
      );
    }
    final parsed = parseExplorePayload(
      map['data'],
      title: title,
      index: index,
      page: page,
    );
    return ComicSourceResult(
      items: parsed.groups,
      diagnostics: parsed.diagnostics,
    );
  }

  /// 源分类树；null 表示源没有 `category`（UI 回退到探索分栏）。
  Future<ComicCategory?> category(String key) async {
    final execution = await _pool.execute(key, _categoryExpression);
    if (!execution.isOk) return null;
    final map = _asMap(execution.value);
    if (map == null) return null;
    final parts = <ComicCategoryPart>[];
    final rawParts = map['parts'];
    if (rawParts is List) {
      for (final rawPart in rawParts) {
        final part = _asMap(rawPart);
        if (part == null) continue;
        final items = <ComicCategoryItem>[];
        // dynamic loader 分区：JS 侧已把 loader() 的返回值归一化成
        // `items: [{name, param}]`（name 即 categoryComics.load 的 category）。
        final rawItems = part['items'];
        if (rawItems is List) {
          for (final rawItem in rawItems) {
            final item = _asMap(rawItem);
            if (item == null) continue;
            final name = _string(item['name']);
            if (name.isEmpty) continue;
            final param = _string(item['param']);
            items.add(
              ComicCategoryItem(
                name: name,
                param: param.isEmpty ? null : param,
              ),
            );
          }
        }
        // 静态分类：`categories`（字符串或 {label,target}）+ 平行 `categoryParams`。
        final categories = part['categories'];
        final params = part['categoryParams'] ?? part['params'];
        if (categories is List) {
          for (var i = 0; i < categories.length; i++) {
            final entry = categories[i];
            final param = _stringAt(params, i);
            if (entry is Map) {
              final label = _string(
                entry['label'],
                fallback: entry['name'] ?? entry['title'],
              );
              if (label.isEmpty) continue;
              items.add(
                ComicCategoryItem(
                  name: label,
                  param: _string(entry['target']).isEmpty
                      ? (param.isEmpty ? null : param)
                      : _string(entry['target']),
                ),
              );
            } else {
              final label = entry?.toString().trim() ?? '';
              if (label.isEmpty) continue;
              items.add(
                ComicCategoryItem(
                  name: label,
                  param: param.isEmpty ? null : param,
                ),
              );
            }
          }
        } else if (categories is Map) {
          // 少数源写成 {显示名: param} 的映射。
          for (final e in categories.entries) {
            final label = e.key?.toString().trim() ?? '';
            if (label.isEmpty) continue;
            final param = e.value?.toString() ?? '';
            items.add(
              ComicCategoryItem(
                name: label,
                param: param.isEmpty ? null : param,
              ),
            );
          }
        }
        final name = _string(part['name']);
        if (items.isEmpty && name.isEmpty) continue;
        parts.add(ComicCategoryPart(name: name, items: items));
      }
    }
    if (parts.isEmpty || parts.every((part) => part.items.isEmpty)) {
      // 只有空分组（如全部是 dynamic loader、需要用户先选分类）等价于没有
      // 可点的分类项——返回 null，让 UI 回退到探索分栏而不是画空页。
      return null;
    }
    return ComicCategory(title: _string(map['title']), parts: parts);
  }

  /// 分类漫画列表：`categoryComics.load(category, param, options, page)`。
  ///
  /// 只实现 `loadNext` 的源回退到 `loadNext(category, param, options, null)`，
  /// 与搜索的 load/loadNext 回退同口径。
  Future<ComicSourceResult<ComicExploreGroup>> categoryComics(
    String key,
    ComicCategoryItem item, {
    int page = 1,
  }) async {
    final execution = await _pool.execute(
      key,
      _categoryComicsExpression(item, page),
    );
    if (!execution.isOk) {
      return ComicSourceResult(diagnostics: <String>[execution.error!]);
    }
    // 源没有 categoryComics：表达式返回 {comics: [], maxPage: null}，与
    // 「分类下确实没有漫画」同形，都是空结果——不额外记诊断（不是错误）。
    final parsed = parseExplorePayload(
      execution.value,
      title: item.name,
      index: -1,
      page: page,
    );
    return ComicSourceResult(
      items: parsed.groups,
      diagnostics: parsed.diagnostics,
    );
  }

  /// 把一次 explore / categoryComics 的原始返回收敛成若干分区。
  ///
  /// 支持的形状（对齐 Venera 模板）：
  /// - `{comics, maxPage?}` → 单分区（multiPageComicList）；
  /// - `{data: …, maxPage?}` → 递归解析 data（mixed，maxPage 逐层下传）；
  /// - `{标题: 漫画数组 | {comics}}` → 每键一个分区（multiPartPage）；
  /// - `[{title, comics}]` → 每项一个分区；
  /// - `[Comic…]` → 单分区（用源给的分区标题兜底）。
  ({List<ComicExploreGroup> groups, List<String> diagnostics})
  parseExplorePayload(
    Object? raw, {
    required String title,
    required int index,
    required int page,
  }) {
    final groups = <ComicExploreGroup>[];
    final diagnostics = <String>[];
    final fallbackTitle = title.isEmpty ? '推荐' : title;

    void addFlat(Object? value, String groupTitle, {int? maxPage}) {
      final map = _asMap(value);
      // mixed：外层 `{data, maxPage}` 只做包装，maxPage 传给内层。
      // 必须「除 data/maxPage 外没有别的键」才算包装——否则源里恰好有个
      // 名叫 "data" 的分区时，其它分区会被整片吞掉。
      if (map != null &&
          map['data'] != null &&
          map.keys.every((k) => k == 'data' || k == 'maxPage')) {
        addFlat(
          map['data'],
          groupTitle,
          maxPage: _int(map['maxPage']) ?? maxPage,
        );
        return;
      }
      final list = value is List ? value : map?['comics'];
      if (list is List) {
        final comics = <ComicSummary>[];
        for (var i = 0; i < list.length; i++) {
          final comic = parseComic(list[i]);
          if (comic == null) {
            diagnostics.add('$groupTitle：第 ${i + 1} 个漫画无法解析');
          } else {
            comics.add(comic);
          }
        }
        groups.add(
          ComicExploreGroup(
            title: groupTitle,
            comics: comics,
            index: index,
            page: page,
            maxPage: maxPage ?? _int(map?['maxPage']),
          ),
        );
        return;
      }
      // 多分区映射 `{分区标题: 漫画数组}`（multiPartPage 的 data）。
      if (map != null && map.isNotEmpty) {
        var emitted = false;
        for (final entry in map.entries) {
          if (entry.key == 'maxPage') continue;
          final child = entry.value;
          if (child is! List && child is! Map) continue;
          final sectionTitle = entry.key?.toString().trim() ?? '';
          addFlat(
            child,
            sectionTitle.isEmpty ? groupTitle : sectionTitle,
            maxPage: maxPage,
          );
          emitted = true;
        }
        if (emitted) return;
      }
      diagnostics.add('$groupTitle：结果缺少 comics 数组');
    }

    if (raw is List) {
      // 分区分片：全部元素都是带 comics/data 的 Map 时按分区展开。
      final isSectionList =
          raw.isNotEmpty &&
          raw.every((e) {
            final map = _asMap(e);
            return map != null &&
                (map.containsKey('comics') || map.containsKey('data'));
          });
      if (isSectionList) {
        for (final entry in raw) {
          final map = _asMap(entry)!;
          final sectionTitle = _string(
            map['title'],
            fallback: map['name'] ?? fallbackTitle,
          );
          addFlat(map['data'] ?? map, sectionTitle);
        }
      } else {
        addFlat(raw, fallbackTitle);
      }
    } else if (raw is Map) {
      addFlat(raw, fallbackTitle);
    } else {
      diagnostics.add('$fallbackTitle：探索结果无法解析');
    }
    return (groups: groups, diagnostics: diagnostics);
  }

  /// 从并行数组里按下标取字符串（`categoryParams[i]`），越界返回空串。
  String _stringAt(Object? raw, int index) {
    if (raw is List && index < raw.length) {
      return raw[index]?.toString().trim() ?? '';
    }
    return '';
  }

  /// `{comics: [...], maxPage?}` / `[...]` → 列表。
  ComicSourceResult<ComicSummary> parseComicList(
    Object? raw,
    String? maxPageField,
  ) {
    final diagnostics = <String>[];
    final map = _asMap(raw);
    Object? comicsRaw = map?['comics'] ?? raw;
    if (comicsRaw is! List) {
      return ComicSourceResult(diagnostics: const <String>['结果缺少 comics 数组']);
    }
    final items = <ComicSummary>[];
    for (var i = 0; i < comicsRaw.length; i++) {
      final comic = parseComic(comicsRaw[i]);
      if (comic == null) {
        diagnostics.add('第 ${i + 1} 个漫画无法解析');
      } else {
        items.add(comic);
      }
    }
    return ComicSourceResult(
      items: items,
      diagnostics: diagnostics,
      maxPage: maxPageField == null ? null : _int(map?[maxPageField]),
    );
  }

  /// `Comic` → [ComicSummary]。
  ComicSummary? parseComic(Object? raw) {
    final map = _asMap(raw);
    if (map == null) return null;
    final id = _string(map['id']);
    final title = _string(map['title']);
    if (id.isEmpty || title.isEmpty) return null;
    return ComicSummary(
      id: id,
      title: title,
      subtitle: _string(map['subtitle'], fallback: map['subTitle']),
      cover: _string(map['cover']),
      tags: _stringList(map['tags']),
      description: _string(map['description']),
      maxPage: _int(map['maxPage']),
      language: _string(map['language']),
      favoriteId: _string(map['favoriteId']),
      stars: _double(map['stars']),
    );
  }

  /// `ComicDetails` → [ComicDetail]。
  ComicDetail? parseComicDetail(Object? raw) {
    final map = _asMap(raw);
    if (map == null) return null;
    final title = _string(map['title']);
    if (title.isEmpty) return null;
    return ComicDetail(
      title: title,
      subtitle: _string(map['subtitle'], fallback: map['subTitle']),
      cover: _string(map['cover']),
      description: _string(map['description']),
      tags: _stringMapList(map['tags']),
      chapters: _chapters(map['chapters']),
      thumbnails: _stringList(map['thumbnails']),
      recommend: _recommend(map['recommend']),
      url: _string(map['url']),
      stars: _double(map['stars']),
      maxPage: _int(map['maxPage']),
    );
  }

  /// `{images: [...], headers?: {url: {headers}}}` → [ComicImageRef] 列表。
  ComicSourceResult<ComicImageRef> parseImages(Object? raw) {
    final map = _asMap(raw);
    final imagesRaw = map?['images'] ?? raw;
    if (imagesRaw is! List) {
      return ComicSourceResult(diagnostics: const <String>['结果缺少 images 数组']);
    }
    final configHeaders = _asMap(map?['headers']);
    final items = <ComicImageRef>[];
    final diagnostics = <String>[];
    for (var i = 0; i < imagesRaw.length; i++) {
      final url = _string(imagesRaw[i]);
      if (url.isEmpty) {
        diagnostics.add('第 ${i + 1} 张图片地址为空');
      } else {
        items.add(
          ComicImageRef(url: url, headers: _stringMap(configHeaders?[url])),
        );
      }
    }
    return ComicSourceResult(items: items, diagnostics: diagnostics);
  }

  Map<dynamic, dynamic>? _asMap(Object? raw) =>
      raw is Map ? Map<dynamic, dynamic>.from(raw) : null;

  /// 只保留字符串键值对；非字符串值（回调等）不进入图片请求头。
  Map<String, String> _stringMap(Object? raw) {
    final map = _asMap(raw);
    if (map == null) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) result[key] = value;
    }
    return result;
  }

  List<ComicChapter> _chapters(Object? raw) {
    if (raw is! Map) return const <ComicChapter>[];
    return raw.entries
        .map(
          (e) => ComicChapter(
            id: e.key?.toString() ?? '',
            title: e.value?.toString() ?? '',
          ),
        )
        .where((c) => c.id.isNotEmpty)
        .toList(growable: false);
  }

  List<ComicSummary> _recommend(Object? raw) {
    if (raw is! List) return const <ComicSummary>[];
    return raw
        .map(parseComic)
        .whereType<ComicSummary>()
        .toList(growable: false);
  }

  String _string(Object? raw, {Object? fallback}) {
    final value = raw ?? fallback;
    if (value == null) return '';
    return value.toString().trim();
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, List<String>> _stringMapList(Object? raw) {
    if (raw is! Map) return const <String, List<String>>{};
    return <String, List<String>>{
      for (final entry in raw.entries) '${entry.key}': _stringList(entry.value),
    };
  }

  int? _int(Object? raw) {
    // JS 侧 `Math.ceil(undefined / 21)` 会得到 NaN、除零得到 Infinity（多个
    // 源在 total 缺失时这么算 maxPage）；直接 toInt() 会抛
    // "Infinity or NaN toInt"，一个源就能把整次聚合搜索打崩。
    if (raw is num) return raw.isFinite ? raw.toInt() : null;
    if (raw is String) {
      final text = raw.trim();
      final direct = int.tryParse(text);
      if (direct != null) return direct;
      // "12.0" / "12.5" 这类字符串（有的源把 maxPage 算成浮点再转串）。
      final asDouble = double.tryParse(text);
      return asDouble != null && asDouble.isFinite ? asDouble.toInt() : null;
    }
    return null;
  }

  double? _double(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toDouble() : null;
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  String _q(String value) => '"${_escapeJs(value)}"';

  /// JS 字符串字面量转义。除引号/反斜杠/换行外还处理 CR 与 U+2028/U+2029
  /// ——它们在 JS 字符串里非法（旧引擎直接 SyntaxError），而源数据
  /// （关键词、分类名）完全可能带上。
  static String _escapeJs(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  String _jsonList(List<String?> values) =>
      '[${values.map((v) => v == null ? 'null' : _q(v)).join(',')}]';

  /// 一次执行取全部分区：逐分区 `Promise.all` + 单个 catch，返回
  /// `[{index, title, data} | {index, title, error}]`。
  ///
  /// `loadNext` 回退与 Venera 一致：没有 `load` 的分区用 `loadNext(page)`。
  String _exploreAllExpression(int page) =>
      '''
(() => {
  const list = source.explore;
  if (!Array.isArray(list)) return Promise.resolve([]);
  return Promise.all(list.map((item, i) => {
    if (!item || typeof item !== 'object') {
      return { index: i, title: '', error: '分区定义无效' };
    }
    const title = item.title === undefined ? '' : String(item.title);
    let call;
    try {
      if (typeof item.load === 'function') {
        call = item.load($page);
      } else if (typeof item.loadNext === 'function') {
        // 只有 loadNext 的分区（如 ehentai）第一个参数是「下一页 token/URL」
        // 而非页码：首屏没有 token 必须传 null，传 1 会被拼进 URL 触发
        // “必须是绝对 URL: 1”。翻页时才由上层带上一页返回的 next。
        call = item.loadNext(null);
      } else {
        return { index: i, title: title, error: '分区没有 load/loadNext' };
      }
    } catch (error) {
      // 同步抛错也会让 Promise.all 整体 reject（丢掉其它分区），单独收敛。
      return { index: i, title: title, error: String(error) };
    }
    return Promise.resolve(call).then(
      (data) => ({ index: i, title: title, data: data }),
      (error) => ({ index: i, title: title, error: String(error) })
    );
  }));
})()''';

  /// 单个分区（翻页）：返回 `{index, title, data} | {index, title, error}`。
  String _exploreOneExpression(int index, int page) =>
      '''
(() => {
  const item = source.explore && source.explore[$index];
  if (!item || typeof item !== 'object') {
    return { index: $index, title: '', error: '分区不存在' };
  }
  const title = item.title === undefined ? '' : String(item.title);
  let call;
  try {
    if (typeof item.load === 'function') {
      call = item.load($page);
    } else if (typeof item.loadNext === 'function') {
      // 同 _exploreAllExpression：loadNext 首参是 token 而非页码。
      call = item.loadNext(null);
    } else {
      return { index: $index, title: title, error: '分区没有 load/loadNext' };
    }
  } catch (error) {
    return { index: $index, title: title, error: String(error) };
  }
  return Promise.resolve(call).then(
    (data) => ({ index: $index, title: title, data: data }),
    (error) => ({ index: $index, title: title, error: String(error) })
  );
})()''';

  /// 分类树：`title` / `parts[].name` / `parts[].categories` / `categoryParams`，
  /// 外加 `type: "dynamic"` 分区的 `loader()` 展开。
  ///
  /// Venera 模板允许分区用 dynamic loader 现场生成标签（manga_dex 的 Tags、
  /// kavita/komga/lanraragi 的书库/题材等）。loader 返回
  /// `[{label, target}]`，target 有两种形状：
  /// * `{page:'category', attributes:{category, param}}`（kavita/komga/lanraragi）；
  /// * `{action:'category', keyword, param}`（manga_dex）。
  /// 两者都归一化成 `items: [{name, param}]`——`name` 是 `categoryComics.load`
  /// 的第一个参数（category），`param` 是第二个。loader 是同步或 Promise 都
  /// 支持（JS 侧 `Promise.all` + 单分区 catch，一个分区炸了不影响其它分区）。
  ///
  /// 静态分区仍走 `categories`/`categoryParams` 原路，Dart 解析器把两路合并；
  /// 不展开 dynamic loader 会让这些源的分类页整体为空（UI 回退探索），所以
  /// 这里必须现场调用——loader 只读源内存里的引用数据（loadData），不发网络。
  static const String _categoryExpression = '''
(() => {
  const category = source.category;
  if (!category || typeof category !== 'object') return null;
  const parts = Array.isArray(category.parts) ? category.parts : [];
  const normalizeTarget = (entry) => {
    const target = entry && typeof entry === 'object' ? entry.target : entry;
    const attrs = target && typeof target === 'object' && target.attributes &&
                  typeof target.attributes === 'object' ? target.attributes : null;
    const name = entry && typeof entry === 'object'
      ? String(entry.label === undefined ? (entry.name === undefined ? '' : entry.name) : entry.label)
      : String(entry === undefined ? '' : entry);
    let param;
    if (attrs) {
      param = attrs.param;
      return { name: String(attrs.category === undefined ? name : attrs.category),
               param: param === undefined || param === null ? null : String(param) };
    }
    if (target && typeof target === 'object') {
      param = target.param === undefined ? target.keyword : target.param;
      const nm = target.keyword !== undefined ? target.keyword : name;
      return { name: String(nm === undefined ? '' : nm),
               param: param === undefined || param === null ? null : String(param) };
    }
    return { name: name, param: target === undefined || target === null ? null : String(target) };
  };
  return Promise.all(parts.map((part) => {
    if (!part || typeof part !== 'object') return Promise.resolve({ name: '', categories: [], items: [] });
    const name = part.name === undefined ? '' : String(part.name);
    let categories = part.categories;
    if (categories === undefined && Array.isArray(part.categoryParams)) {
      categories = part.categoryParams;
    }
    if (part.type === 'dynamic' && typeof part.loader === 'function') {
      return Promise.resolve()
        .then(() => part.loader())
        .then((loaded) => ({
          name: name,
          categories: [],
          items: Array.isArray(loaded) ? loaded.map(normalizeTarget) : []
        }))
        .catch(() => ({ name: name, categories: [], items: [] }));
    }
    return Promise.resolve({
      name: name,
      categories: categories === undefined ? [] : categories,
      categoryParams: Array.isArray(part.categoryParams) ? part.categoryParams : [],
      items: []
    });
  })).then((resolvedParts) => ({
    title: category.title === undefined ? '' : String(category.title),
    parts: resolvedParts
  }));
})()''';

  /// 分类漫画：`categoryComics.load(category, param, options, page)`，
  /// 缺 `load` 时回退 `loadNext(category, param, options, null)`。
  ///
  /// 与搜索同口径：未显式传 options 时用每个
  /// `source.categoryComics.optionList` 项的默认值（有 `default` 取
  /// `JSON.stringify(default)`，否则取第一个合法 option 的 value）。绝大多数
  /// Venera 源的 `categoryComics.load` 直接读 `options[0].split('-')` 等，
  /// 传空数组会 `TypeError: cannot read property '...' of undefined`（baozi、
  /// ykmh、copy_manga 等实测）——这是与 manga_dex 搜索同类缺口。默认值在 JS
  /// 侧算：`optionList` 是运行期存活的源数据，Dart 看不到。
  String _categoryComicsExpression(ComicCategoryItem item, int page) {
    final category = _q(item.name);
    final param = item.param == null ? 'null' : _q(item.param!);
    return '''
(() => {
  const c = source.categoryComics;
  if (!c || typeof c !== 'object') {
    return { comics: [], maxPage: null };
  }
  const __defaults = (() => {
    const list = c.optionList;
    if (!Array.isArray(list)) return [];
    return list.map((item) => {
      if (item && typeof item === 'object' &&
          Object.prototype.hasOwnProperty.call(item, 'default') &&
          item.default !== undefined) {
        const encoded = JSON.stringify(item.default);
        return encoded === undefined ? "" : encoded;
      }
      const entries = item && Array.isArray(item.options) ? item.options : [];
      for (const entry of entries) {
        if (typeof entry !== 'string') continue;
        const dash = entry.indexOf("-");
        if (dash < 0) continue;
        return entry.slice(0, dash);
      }
      return "";
    });
  })();
  let call;
  try {
    if (typeof c.load === 'function') {
      call = c.load($category, $param, __defaults, $page);
    } else if (typeof c.loadNext === 'function') {
      call = c.loadNext($category, $param, __defaults, null);
    } else {
      return { comics: [], maxPage: null };
    }
  } catch (error) {
    return { comics: [], maxPage: null, error: String(error) };
  }
  return Promise.resolve(call).then(
    (r) => Array.isArray(r) ? { comics: r, maxPage: null }
                            : (r || { comics: [], maxPage: null })
  );
})()''';
  }
}

/// 在 JS 侧算默认搜索选项（对齐 Venera `source_search_parser.dart`）：
///
/// * `optionList` 不存在 / 不是数组 → `[]`，不抛错；
/// * 项有 `default` → `JSON.stringify(default)`（multi-select 得到
///   `["0","1"]`，源脚本自行 `JSON.parse`）；
/// * 否则取 `options` 里第一个 `"value-显示名"` 的 value；没有合法项 → `""`。
///
/// 表达式整体是字符串字面量，不拼接任何源数据；关键词仍由调用方 [_q] 转义，
/// 因此不存在注入面。
const String _defaultSearchOptionsJs = '''
(() => {
  const list = source.search && source.search.optionList;
  if (!Array.isArray(list)) return [];
  return list.map((item) => {
    if (item && typeof item === 'object' &&
        Object.prototype.hasOwnProperty.call(item, 'default') &&
        item.default !== undefined) {
      const encoded = JSON.stringify(item.default);
      return encoded === undefined ? "" : encoded;
    }
    const entries = item && Array.isArray(item.options) ? item.options : [];
    for (const entry of entries) {
      if (typeof entry !== "string") continue;
      const dash = entry.indexOf("-");
      if (dash < 0) continue;
      return entry.slice(0, dash);
    }
    return "";
  });
})()''';

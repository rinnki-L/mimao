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

  /// `{images: [...]}` → [ComicImageRef] 列表。
  ComicSourceResult<ComicImageRef> parseImages(Object? raw) {
    final map = _asMap(raw);
    final imagesRaw = map?['images'] ?? raw;
    if (imagesRaw is! List) {
      return ComicSourceResult(diagnostics: const <String>['结果缺少 images 数组']);
    }
    final items = <ComicImageRef>[];
    final diagnostics = <String>[];
    for (var i = 0; i < imagesRaw.length; i++) {
      final url = _string(imagesRaw[i]);
      if (url.isEmpty) {
        diagnostics.add('第 ${i + 1} 张图片地址为空');
      } else {
        items.add(ComicImageRef(url: url));
      }
    }
    return ComicSourceResult(items: items, diagnostics: diagnostics);
  }

  Map<dynamic, dynamic>? _asMap(Object? raw) =>
      raw is Map ? Map<dynamic, dynamic>.from(raw) : null;

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
    if (raw is String) return int.tryParse(raw.trim());
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

  String _q(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  String _jsonList(List<String?> values) =>
      '[${values.map((v) => v == null ? 'null' : _q(v)).join(',')}]';
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

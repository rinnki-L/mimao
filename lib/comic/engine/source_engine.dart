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
  Future<ComicSourceResult<ComicSummary>> search(
    String key,
    String keyword, {
    List<String?> options = const <String?>[],
    int page = 1,
  }) async {
    final expression =
        'source.search.load(${_q(keyword)}, ${_jsonList(options)}, $page)';
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

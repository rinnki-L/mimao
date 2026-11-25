/// 跨源搜索结果去重合并与排序。
///
/// 同一本书在不同书源里是不同实体（`sourceKey` 不同），但用户眼里是同一本；
/// 这里按「归一化书名 + 归一化作者」聚成一条，保留每个源各自的命中，供详情
/// 面板展开看「哪些源有这本、每本源内地址」。
///
/// 纯函数：输入 [NovelSearchHit]（每条带来源书源与页码），输出
/// [NovelMergedBook] 列表；排序规则固定且可测。
library;

import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 结果排序方式。
enum NovelSearchSort {
  /// 相关度：书名精确 > 书名包含 > 作者包含 > 简介包含，再按源权重。
  relevance('相关度'),

  /// 源权重：权重高的源排前（同权重按命中数、相关度）。
  sourceWeight('源权重'),

  /// 字数：解析到的字数从多到少（解析不出字数的排最后）。
  wordCount('字数');

  const NovelSearchSort(this.label);

  final String label;
}

/// 一条「某源搜到的某本书」。
class NovelSearchHit {
  const NovelSearchHit({
    required this.source,
    required this.book,
    this.page = 1,
  });

  final NovelBookSource source;
  final NovelSummary book;

  /// 命中来自第几页搜索结果（分页追加时用于去重）。
  final int page;

  /// 源内唯一键：同一源同一本书只保留一条（翻页重复命中不重复计入）。
  String get identity => '${source.key}|${book.bookUrl}';
}

/// 跨源合并后的一本书。
class NovelMergedBook {
  NovelMergedBook({required this.key, required List<NovelSearchHit> hits})
    : hits = List<NovelSearchHit>.unmodifiable(hits);

  /// 归一化「书名|作者」，同键即同一本书。
  final String key;

  /// 各源命中，已按「源权重→源名」排序；首条是默认展示与跳转依据。
  final List<NovelSearchHit> hits;

  NovelSearchHit get primary => hits.first;
  NovelSummary get book => primary.book;
  List<NovelBookSource> get sources => <NovelBookSource>[
    for (final hit in hits) hit.source,
  ];
  List<String> get sourceNames => <String>[
    for (final hit in hits) hit.source.name,
  ];

  /// 覆盖的源数量（UI 上「N 个源」）。
  int get sourceCount => hits.length;

  /// 覆盖源里的最高权重。
  int get bestWeight =>
      hits.map((hit) => hit.source.weight).reduce((a, b) => a > b ? a : b);

  /// 各源字数里的最大值（解析不出为 null）。
  int? get wordCount {
    int? best;
    for (final hit in hits) {
      final parsed = parseNovelWordCount(hit.book.wordCount);
      if (parsed == null) continue;
      if (best == null || parsed > best) best = parsed;
    }
    return best;
  }

  /// 展示用书对象：标题/作者取首条，简介、字数等在首条为空时由其他源补齐。
  NovelSummary get displayBook {
    final base = primary.book;
    if (base.intro.isNotEmpty && base.wordCount.isNotEmpty) return base;
    String firstNonEmpty(String Function(NovelSummary) pick) {
      if (pick(base).isNotEmpty) return pick(base);
      for (final hit in hits) {
        final value = pick(hit.book);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return NovelSummary(
      id: base.id,
      title: base.title,
      coverUrl: base.coverUrl.isNotEmpty
          ? base.coverUrl
          : firstNonEmpty((book) => book.coverUrl),
      author: base.author,
      sourceName: base.sourceName,
      sourceKey: base.sourceKey,
      bookUrl: base.bookUrl,
      intro: firstNonEmpty((book) => book.intro),
      kind: firstNonEmpty((book) => book.kind),
      latestChapter: firstNonEmpty((book) => book.latestChapter),
      wordCount: firstNonEmpty((book) => book.wordCount),
      type: base.type,
    );
  }
}

/// 合并跨源命中：按 [NovelSearchHit.identity] 去重，再按书名+作者聚组。
///
/// [keyword] 只参与相关度排序；空关键词时相关度退化为「谁先命中」。
List<NovelMergedBook> mergeNovelSearchHits(
  Iterable<NovelSearchHit> hits, {
  NovelSearchSort sort = NovelSearchSort.relevance,
  String keyword = '',
}) {
  final unique = <String, NovelSearchHit>{};
  for (final hit in hits) {
    unique.putIfAbsent(hit.identity, () => hit);
  }

  final groups = <String, List<NovelSearchHit>>{};
  for (final hit in unique.values) {
    final key = novelBookMergeKey(hit.book);
    (groups[key] ??= <NovelSearchHit>[]).add(hit);
  }

  final merged = <NovelMergedBook>[
    for (final entry in groups.entries)
      NovelMergedBook(
        key: entry.key,
        hits: entry.value
          ..sort((a, b) {
            final weight = b.source.weight.compareTo(a.source.weight);
            if (weight != 0) return weight;
            return a.source.name.compareTo(b.source.name);
          }),
      ),
  ];

  final needle = keyword.trim().toLowerCase();
  merged.sort((a, b) {
    final bySort = switch (sort) {
      NovelSearchSort.relevance => _compareRelevance(a, b, needle),
      NovelSearchSort.sourceWeight => _compareSourceWeight(a, b, needle),
      NovelSearchSort.wordCount => _compareWordCount(a, b, needle),
    };
    if (bySort != 0) return bySort;
    return a.book.title.compareTo(b.book.title);
  });
  return List<NovelMergedBook>.unmodifiable(merged);
}

/// 合并键：归一化书名 + 归一化作者。作者只在一侧为空时仍可合并（未知作者
/// 通常是同一个源没配作者规则），两侧都有且不同则视为两本书。
String novelBookMergeKey(NovelSummary book) {
  final title = _normalize(book.title);
  final author = _normalize(book.author);
  return '$title|$author';
}

/// 归一化：去空白/常见标点、全角转半角（仅 ASCII 范围）、转小写。
///
/// 不做繁简转换——那会把两本真不同的书误合并；标点差异（《》、全角括号）
/// 是跨源最常见的差异，收在这里。
String _normalize(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    // 全角 ASCII（！到 ～）映射回半角。
    var code = rune;
    if (code >= 0xFF01 && code <= 0xFF5E) code -= 0xFEE0;
    if (code == 0x3000) continue; // 全角空格
    final char = String.fromCharCode(code).toLowerCase();
    if (_punctuation.hasMatch(char)) continue;
    buffer.write(char);
  }
  return buffer.toString();
}

final RegExp _punctuation = RegExp(
  r'''[\s·,，.。:：;；!！?？"“”‘’()（）\[\]【】<>《》\-—_/\\|']''',
);

/// 解析 legado 常见字数文案：`12345` / `12.3万` / `1.2万字` / `100万字`。
///
/// 解析不出返回 null（排序时排最后）；`0` 也视为无效（很多源写 `0` 占位）。
int? parseNovelWordCount(String text) {
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*(万|亿|千)?').firstMatch(text.trim());
  if (match == null) return null;
  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return null;
  final unit = match.group(2);
  final multiplier = switch (unit) {
    '万' => 10000,
    '亿' => 100000000,
    '千' => 1000,
    _ => 1,
  };
  final count = (value * multiplier).round();
  return count <= 0 ? null : count;
}

int _compareRelevance(NovelMergedBook a, NovelMergedBook b, String needle) {
  final score = _relevanceOf(b, needle).compareTo(_relevanceOf(a, needle));
  if (score != 0) return score;
  final weight = b.bestWeight.compareTo(a.bestWeight);
  if (weight != 0) return weight;
  return (b.wordCount ?? 0).compareTo(a.wordCount ?? 0);
}

int _compareSourceWeight(NovelMergedBook a, NovelMergedBook b, String needle) {
  final weight = b.bestWeight.compareTo(a.bestWeight);
  if (weight != 0) return weight;
  final coverage = b.sourceCount.compareTo(a.sourceCount);
  if (coverage != 0) return coverage;
  return _compareRelevance(a, b, needle);
}

int _compareWordCount(NovelMergedBook a, NovelMergedBook b, String needle) {
  final aw = a.wordCount;
  final bw = b.wordCount;
  if (aw == null && bw != null) return 1;
  if (aw != null && bw == null) return -1;
  if (aw != null && bw != null) {
    final byWord = bw.compareTo(aw);
    if (byWord != 0) return byWord;
  }
  return _compareRelevance(a, b, needle);
}

/// 相关度打分：书名精确 100、书名包含 60、作者包含 30、简介包含 10。
int _relevanceOf(NovelMergedBook book, String needle) {
  if (needle.isEmpty) return 0;
  final title = book.book.title.toLowerCase();
  final author = book.book.author.toLowerCase();
  if (title == needle) return 100;
  if (title.contains(needle)) return 60;
  if (author.contains(needle)) return 30;
  for (final hit in book.hits) {
    if (hit.book.intro.toLowerCase().contains(needle)) return 10;
  }
  return 0;
}

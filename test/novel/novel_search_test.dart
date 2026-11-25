// 搜索纯逻辑测试：选源范围过滤、跨源去重合并、排序与字数解析。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/search/novel_search_merge.dart';
import 'package:mimao/novel/search/novel_search_scope.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

NovelBookSource _source(
  String name, {
  String? url,
  bool enabled = true,
  int type = 0,
  String? searchUrl,
  String group = '',
  int weight = 0,
}) {
  final sourceUrl = url ?? 'https://$name.example';
  return NovelBookSource(
    key: NovelBookSource.keyFor(sourceUrl),
    name: name,
    url: sourceUrl,
    type: type,
    enabled: enabled,
    raw: <String, dynamic>{
      'bookSourceName': name,
      'bookSourceUrl': sourceUrl,
      'bookSourceType': type,
      'searchUrl': searchUrl ?? '/search?q={{key}}',
      'bookSourceGroup': group,
      'weight': weight,
    },
  );
}

NovelSummary _book(
  String title, {
  String author = '作者甲',
  String intro = '',
  String wordCount = '',
  String bookUrl = '',
}) => NovelSummary(
  id: title,
  title: title,
  author: author,
  intro: intro,
  wordCount: wordCount,
  bookUrl: bookUrl.isEmpty ? 'https://book/$title' : bookUrl,
);

void main() {
  group('搜索选源范围', () {
    test('可搜索源：启用 + 文本 + 有搜索地址且不是占位符', () {
      final ok = _source('ok');
      final disabled = _source('disabled', enabled: false);
      final audio = _source('audio', type: 1);
      final noSearch = _source('noSearch', searchUrl: '');
      final placeholder = _source('placeholder', searchUrl: '-');

      expect(isSearchableNovelSource(ok), isTrue);
      expect(isSearchableNovelSource(disabled), isFalse);
      expect(isSearchableNovelSource(audio), isFalse);
      expect(isSearchableNovelSource(noSearch), isFalse);
      expect(isSearchableNovelSource(placeholder), isFalse);
    });

    test('全部模式按权重降序、同权重按名称', () {
      final sources = <NovelBookSource>[
        _source('beta', weight: 1),
        _source('alpha'),
        _source('zeta', weight: 5),
        _source('off', enabled: false, weight: 99),
      ];
      final selected = const NovelSearchScope().select(sources);
      expect(selected.map((s) => s.name), <String>['zeta', 'beta', 'alpha']);
    });

    test('分组模式只选勾选分组；未分组用「未分组」标签命中', () {
      final sources = <NovelBookSource>[
        _source('a', group: '玄幻'),
        _source('b', group: '都市'),
        _source('c'),
        _source('d', group: '玄幻,都市'),
      ];
      const scope = NovelSearchScope(
        mode: NovelSearchScopeMode.group,
        groups: <String>{'玄幻'},
      );
      expect(scope.select(sources).map((s) => s.name), <String>['a', 'd']);

      const ungrouped = NovelSearchScope(
        mode: NovelSearchScopeMode.group,
        groups: <String>{novelUngroupedLabel},
      );
      expect(ungrouped.select(sources).map((s) => s.name), <String>['c']);
    });

    test('手选模式只选手选源；清空勾选回落到全部', () {
      final sources = <NovelBookSource>[_source('a'), _source('b')];
      final keyA = sources.first.key;
      final manual = NovelSearchScope(
        mode: NovelSearchScopeMode.manual,
        sourceKeys: <String>{keyA},
      );
      expect(manual.select(sources).map((s) => s.name), <String>['a']);

      const cleared = NovelSearchScope(mode: NovelSearchScopeMode.manual);
      expect(cleared.select(sources), hasLength(2));
    });

    test('分组列表去重排序，「未分组」排最后', () {
      final values = novelSourceGroups(<NovelBookSource>[
        _source('a', group: '都市'),
        _source('b', group: '玄幻'),
        _source('c', group: '都市'),
        _source('d'),
        _source('e', enabled: false),
      ]);
      expect(values, <String>['玄幻', '都市', novelUngroupedLabel]);
    });

    test('describe 文案与 toggle 行为', () {
      var scope = const NovelSearchScope();
      expect(scope.describe(total: 3), '全部源（3）');
      scope = scope.toggleSource('k1');
      expect(scope.mode, NovelSearchScopeMode.manual);
      expect(scope.describe(), '手选 1 个源');
      scope = scope.toggleSource('k1');
      expect(scope.sourceKeys, isEmpty);
    });
  });

  group('跨源去重合并', () {
    test('同书名+作者跨源合并，保留各源命中并按源权重排序', () {
      final low = _source('低权重', weight: 0);
      final high = _source('高权重', weight: 9);
      final merged = mergeNovelSearchHits(<NovelSearchHit>[
        NovelSearchHit(
          source: low,
          book: _book('剑来', bookUrl: 'https://low/1'),
        ),
        NovelSearchHit(
          source: high,
          book: _book('《剑来》', bookUrl: 'https://high/1', intro: '简介'),
        ),
      ]);
      expect(merged, hasLength(1));
      expect(merged.first.sourceCount, 2);
      expect(merged.first.primary.source.name, '高权重');
      expect(merged.first.displayBook.intro, '简介');
    });

    test('作者不同或书名不同不合并', () {
      final source = _source('s');
      final merged = mergeNovelSearchHits(<NovelSearchHit>[
        NovelSearchHit(
          source: source,
          book: _book('剑来', author: '甲', bookUrl: 'https://book/a'),
        ),
        NovelSearchHit(
          source: source,
          book: _book('剑来', author: '乙', bookUrl: 'https://book/b'),
        ),
        NovelSearchHit(
          source: source,
          book: _book('雪中悍刀行', author: '甲', bookUrl: 'https://book/c'),
        ),
      ]);
      expect(merged, hasLength(3));
    });

    test('同一源同一本书的重复命中只算一次', () {
      final source = _source('s');
      final merged = mergeNovelSearchHits(<NovelSearchHit>[
        NovelSearchHit(
          source: source,
          book: _book('剑来', bookUrl: 'https://book/1'),
          page: 1,
        ),
        NovelSearchHit(
          source: source,
          book: _book('剑来', bookUrl: 'https://book/1'),
          page: 2,
        ),
      ]);
      expect(merged, hasLength(1));
      expect(merged.first.sourceCount, 1);
    });

    test('中文标点/全角/大小写差异视为同一本', () {
      final a = _source('a');
      final b = _source('b');
      final merged = mergeNovelSearchHits(<NovelSearchHit>[
        NovelSearchHit(source: a, book: _book('Hello, World！')),
        NovelSearchHit(source: b, book: _book('ｈｅｌｌｏ ｗｏｒｌｄ')),
      ]);
      expect(merged, hasLength(1));
    });
  });

  group('结果排序', () {
    final source = _source('s', weight: 1);
    final hits = <NovelSearchHit>[
      NovelSearchHit(
        source: source,
        book: _book('无关书', author: '甲', wordCount: '100万'),
      ),
      NovelSearchHit(
        source: source,
        book: _book('剑来外传', author: '乙', wordCount: '10万'),
      ),
      NovelSearchHit(
        source: source,
        book: _book('剑来', author: '丙', wordCount: '5万'),
      ),
    ];

    test('相关度：书名精确 > 包含', () {
      final merged = mergeNovelSearchHits(hits, keyword: '剑来');
      expect(merged.map((b) => b.book.title), <String>['剑来', '剑来外传', '无关书']);
    });

    test('字数：解析万字并从多到少，解析不出的排最后', () {
      final merged = mergeNovelSearchHits(
        hits,
        sort: NovelSearchSort.wordCount,
        keyword: '剑来',
      );
      expect(merged.map((b) => b.book.title), <String>['无关书', '剑来外传', '剑来']);
    });

    test('源权重：权重高的源命中优先', () {
      final low = _source('低', weight: 0);
      final high = _source('高', weight: 8);
      final merged = mergeNovelSearchHits(<NovelSearchHit>[
        NovelSearchHit(source: low, book: _book('书一')),
        NovelSearchHit(source: high, book: _book('书二')),
      ], sort: NovelSearchSort.sourceWeight);
      expect(merged.first.book.title, '书二');
    });

    test('parseNovelWordCount 解析常见文案', () {
      expect(parseNovelWordCount('12345'), 12345);
      expect(parseNovelWordCount('12.3万字'), 123000);
      expect(parseNovelWordCount('100万'), 1000000);
      expect(parseNovelWordCount('2亿'), 200000000);
      expect(parseNovelWordCount('0'), isNull);
      expect(parseNovelWordCount('连载中'), isNull);
    });
  });
}

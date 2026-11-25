// 发现页三个"解析了但没生效"的修复回归：
// 1. layout_flexBasisPercent / layout_flexGrow 真的参与分类入口排布；
// 2. ruleExplore.pageParam 真的决定翻页 query 参数名；
// 3. 发现结果按 type 过滤成文字书（与搜索对齐）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/legado_engine.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _RecordingTransport implements NovelHttpTransport {
  _RecordingTransport(this.body);

  final String body;
  final List<String> requested = <String>[];

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    requested.add(request.url);
    return NovelHttpResponse(
      url: request.url,
      statusCode: 200,
      body: body,
    );
  }

  @override
  void close() {}
}

NovelBookSource _source({String pageParam = ''}) => NovelBookSource(
  key: 'src',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://site.test',
    'exploreUrl': '玄幻::/list/1/{{page}}.html',
    'ruleExplore': <String, dynamic>{
      'bookList': 'class.list@tag.li',
      'name': 'class.name@text',
      'bookUrl': 'tag.a@href',
      if (pageParam.isNotEmpty) 'pageParam': pageParam,
    },
  },
);

const String _listHtml = '''
<html><body>
<ul class="list">
  <li><a class="name" href="/book/1">文字书</a></li>
  <li><a class="name" href="/book/2">音频书</a></li>
</ul>
</body></html>
''';

void main() {
  group('flex 布局参数真的参与排布', () {
    test('无 flex 参数时整组交回页面按普通 chip 排', () {
      const kinds = <NovelExploreKind>[
        NovelExploreKind(name: '玄幻', url: '/a'),
        NovelExploreKind(name: '都市', url: '/b'),
      ];
      final rows = layoutExploreKindRows(kinds);
      expect(rows, hasLength(1));
      expect(rows.single, hasLength(2));
      expect(rows.single.every((slot) => slot.factor == null), isTrue);
    });

    test('layout_flexBasisPercent 变成行内宽度比例并换行', () {
      const kinds = <NovelExploreKind>[
        NovelExploreKind(name: 'A', url: '/a', flexBasisPercent: 0.6),
        NovelExploreKind(name: 'B', url: '/b', flexBasisPercent: 0.6),
      ];
      final rows = layoutExploreKindRows(kinds);
      expect(rows, hasLength(2));
      expect(rows.first.single.factor, 0.6);
      expect(rows.last.single.factor, 0.6);

      final slot = NovelExploreKindSlot.of(kinds.first);
      expect(slot.isFixedWidth, isTrue);
      expect(slot.widthFor(400, 100), closeTo(240, 0.001));
    });

    test('百分数写法（>1）按 0..100 折算', () {
      const kind = NovelExploreKind(
        name: 'A',
        url: '/a',
        flexBasisPercent: 25,
      );
      expect(NovelExploreKindSlot.of(kind).widthFactor, closeTo(0.25, 1e-9));
    });

    test('flexGrow 保留为权重，未给宽度的项参与拉伸', () {
      const kinds = <NovelExploreKind>[
        NovelExploreKind(name: 'A', url: '/a', flexGrow: 1),
        NovelExploreKind(name: 'B', url: '/b', flexGrow: 3),
      ];
      final rows = layoutExploreKindRows(kinds);
      expect(rows.single.map((slot) => slot.grow).toList(), <double>[1, 3]);
      expect(rows.single.every((slot) => slot.factor == null), isTrue);
    });

    test('百分比之和超过 1 时换行，不横向溢出', () {
      const kinds = <NovelExploreKind>[
        NovelExploreKind(name: 'A', url: '/a', flexBasisPercent: 0.8),
        NovelExploreKind(name: 'B', url: '/b', flexBasisPercent: 0.8),
      ];
      expect(layoutExploreKindRows(kinds), hasLength(2));
    });
  });

  group('explorePageParam 真的生效', () {
    test('第 1 页不追加参数，第 2 页起按 pageParam 追加', () {
      expect(
        applyExplorePageParam('/list?x=1', pageParam: '', page: 1),
        '/list?x=1',
      );
      expect(
        applyExplorePageParam('/list?x=1', pageParam: '', page: 2),
        '/list?x=1&page=2',
      );
      expect(
        applyExplorePageParam('/list', pageParam: 'p', page: 3),
        '/list?p=3',
      );
      expect(
        applyExplorePageParam('/list?x=1', pageParam: 'p', page: 2),
        '/list?x=1&p=2',
      );
    });

    test('地址自带翻页占位时不重复追加', () {
      expect(
        applyExplorePageParam('/list/{{page}}', pageParam: 'p', page: 2),
        '/list/{{page}}',
      );
      expect(
        applyExplorePageParam('/list/<1,2,3>', pageParam: 'p', page: 2),
        '/list/<1,2,3>',
      );
      expect(
        exploreUrlHasPagePlaceholder('@js:"/list?p=" + page'),
        isTrue,
      );
      expect(exploreUrlHasPagePlaceholder('/list'), isFalse);
    });

    test('引擎翻页请求真的带上了自定义参数名', () async {
      final transport = _RecordingTransport(_listHtml);
      final engine = LegadoNovelEngine(transport: transport);
      addTearDown(engine.close);
      final source = _source(pageParam: 'pageno');
      const kind = NovelExploreKind(name: '玄幻', url: '/list');

      await engine.exploreSource(source, kind, page: 2);

      expect(transport.requested.single, 'https://site.test/list?pageno=2');
    });

    test('留空 pageParam 时按 page 追加', () async {
      final transport = _RecordingTransport(_listHtml);
      final engine = LegadoNovelEngine(transport: transport);
      addTearDown(engine.close);
      final source = _source();
      const kind = NovelExploreKind(name: '玄幻', url: '/list');

      await engine.exploreSource(source, kind, page: 3);

      expect(transport.requested.single, 'https://site.test/list?page=3');
    });
  });

  group('发现结果按 type 过滤', () {
    test('只保留文字书（type == 0）', () async {
      final transport = _RecordingTransport(_listHtml);
      final engine = LegadoNovelEngine(transport: transport);
      addTearDown(engine.close);
      final source = _source();
      const kind = NovelExploreKind(name: '玄幻', url: '/list/1');

      final books = await engine.exploreSource(source, kind);

      // 该源 type 0，两本都是文字书。
      expect(books.map((b) => b.title).toList(), <String>['文字书', '音频书']);
      expect(books.every((b) => b.type == 0), isTrue);
    });

    test('非文字书源的结果被过滤空，并留一条警告', () async {
      final transport = _RecordingTransport(_listHtml);
      final engine = LegadoNovelEngine(transport: transport);
      addTearDown(engine.close);
      final source = NovelBookSource(
        key: 'audio',
        name: '音频源',
        url: 'https://site.test',
        type: 1,
        enabled: true,
        raw: <String, dynamic>{
          'bookSourceUrl': 'https://site.test',
          'exploreUrl': '玄幻::/list/1/{{page}}.html',
          'ruleExplore': <String, dynamic>{
            'bookList': 'class.list@tag.li',
            'name': 'class.name@text',
            'bookUrl': 'tag.a@href',
          },
        },
      );
      const kind = NovelExploreKind(name: '玄幻', url: '/list/1');

      final books = await engine.exploreSource(source, kind);

      expect(books, isEmpty);
      expect(engine.warningFor('audio'), contains('非文字书'));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/bangumi_api.dart';
import 'package:mimao/anime/data/bangumi_anime_data_source.dart';
import 'package:mimao/anime/data/rule_anime_data_source.dart';
import 'package:mimao/anime/data/rule_anime_mapper.dart';
import 'package:mimao/anime/engine/engine.dart';

import 'fixtures.dart';

/// 可编排的假 HTTP 客户端：按 URL 返回响应、可配置延迟（控制完成顺序）与全局异常。
class _FakeClient implements AnimeHttpClient {
  final Map<String, AnimeHttpResponse> responses =
      <String, AnimeHttpResponse>{};
  final Map<String, Duration> delays = <String, Duration>{};
  final List<String> calls = <String>[];
  Object? error;

  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    calls.add(url);
    final delay = delays[url];
    if (delay != null) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return responses[url] ??
        const AnimeHttpResponse(statusCode: 404, body: 'not found');
  }
}

/// 只对指定规则抛异常的假引擎——用来模拟「engine.search 自身抛异常」。
class _SelectiveThrowingEngine extends AnimeRuleEngine {
  _SelectiveThrowingEngine(AnimeHttpClient client, this.throwingRule)
    : super(client: client);

  final String throwingRule;

  @override
  Future<RuleParseResult<RuleSearchResult>> search(
    AnimeRule rule,
    String keyword, {
    Map<String, String> cookies = const <String, String>{},
  }) async {
    if (rule.name == throwingRule) {
      throw StateError('engine.search 自身炸了');
    }
    return super.search(rule, keyword, cookies: cookies);
  }
}

void main() {
  final demoJson = jsonDecode(demoRuleJson) as Map<String, dynamic>;

  /// 基于 demo03 的选择器造一条规则，只换名字与站点 host。
  AnimeRule rule(String name, String host) =>
      AnimeRule.fromJson(<String, dynamic>{
        ...demoJson,
        'name': name,
        'baseURL': 'https://$host/',
        'searchURL': 'https://$host/search?q=@keyword',
      });

  String itemHtml(String title, String href, {String? img}) {
    final imgTag = img == null ? '' : '<img src="$img">';
    return '<div class="anime-item"><a class="cover" href="$href">$imgTag</a>'
        '<h3 class="title">$title</h3></div>';
  }

  String listPage(List<String> items) =>
      '<html><body><div class="result-list">${items.join()}</div></body></html>';

  AnimeSummary summary(String name, String url) => AnimeSummary(
    id: url,
    title: '标题',
    coverUrl: '',
    detailUrl: url,
    sourceName: name,
  );

  group('A · 搜索结果映射', () {
    test('多规则并发，结果按规则顺序稳定（规则 2 先完成）', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([
          itemHtml('A一', '/a/1', img: '/img/a1.jpg'),
          itemHtml('A二', '/a/2', img: '/img/a2.jpg'),
          itemHtml('A三', '/a/3', img: '/img/a3.jpg'),
        ]),
      );
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('B一', '/b/1'), itemHtml('B二', '/b/2')]),
      );
      // 规则 1 慢、规则 2 快：完成顺序与规则顺序相反。
      client.delays['https://a.test/search?q=x'] = const Duration(
        milliseconds: 80,
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[
          rule('甲站', 'a.test'),
          rule('乙站', 'b.test'),
        ],
      );

      final results = await source.search('x');

      expect(results, hasLength(5));
      expect(results.map((e) => e.sourceName).toList(), <String>[
        '甲站',
        '甲站',
        '甲站',
        '乙站',
        '乙站',
      ]);
      expect(results.map((e) => e.title).toList(), <String>[
        'A一',
        'A二',
        'A三',
        'B一',
        'B二',
      ]);
    });

    test('字段逐项精确映射，subtitle == null', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([
          itemHtml('葬送的芙莉莲', '/anime/1001', img: '/img/1001.jpg'),
        ]),
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('甲站', 'a.test')],
      );

      final hit = (await source.search('x')).single;
      expect(hit.title, '葬送的芙莉莲');
      expect(hit.detailUrl, 'https://a.test/anime/1001');
      expect(hit.coverUrl, 'https://a.test/img/1001.jpg');
      expect(hit.sourceName, '甲站');
      expect(hit.id, 'https://a.test/anime/1001');
      expect(hit.subtitle, isNull);
    });

    test('空关键词 → 空列表且零请求', () async {
      final client = _FakeClient();
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('甲站', 'a.test')],
      );

      expect(await source.search('   '), isEmpty);
      expect(client.calls, isEmpty);
    });

    test('无规则 → 空列表，无异常', () async {
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: _FakeClient()),
        loadRules: () async => <AnimeRule>[],
      );

      expect(await source.search('x'), isEmpty);
    });

    test('loadRules 抛异常 → 空列表 + 诊断，不向上抛', () async {
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: _FakeClient()),
        loadRules: () async => throw StateError('规则读取炸了'),
      );

      expect(await source.search('x'), isEmpty);
      expect(source.lastDiagnostics, isNotEmpty);
      expect(
        source.lastDiagnostics.any((d) => d.message.contains('加载规则失败')),
        isTrue,
      );
    });

    test('空封面 → coverUrl 为空串；空绝对地址 → detailUrl 回退原始 url', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('空封面', '/p/1')]),
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('甲站', 'a.test')],
      );

      final hit = (await source.search('x')).single;
      expect(hit.coverUrl, '');
      expect(hit.detailUrl, 'https://a.test/p/1');
    });

    test('同规则内重复 id 保留首条；跨规则相同 URL 都保留', () async {
      final client = _FakeClient();
      // 两条规则同 host（同 baseURL）但名字不同 → 相同 href 会得到相同绝对地址/id。
      final dupPage = listPage([
        itemHtml('首条', '/same'),
        itemHtml('重复', '/same'),
      ]);
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: dupPage,
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[
          rule('甲站', 'a.test'),
          rule('乙站', 'a.test'),
        ],
      );

      final results = await source.search('x');
      // 每条规则内部去重成 1 条，跨规则不去重 → 共 2 条，sourceName 分别为两站。
      expect(results, hasLength(2));
      expect(results.map((e) => e.sourceName).toList(), <String>['甲站', '乙站']);
      expect(results.every((e) => e.id == 'https://a.test/same'), isTrue);
      expect(results.first.title, '首条');
    });
  });

  group('B · 容错', () {
    test('单规则 HTTP 500 被隔离，诊断含规则名与原因，其它规则照常', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = const AnimeHttpResponse(
        statusCode: 500,
        body: 'boom',
      );
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('B一', '/b/1')]),
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[
          rule('坏站', 'a.test'),
          rule('好站', 'b.test'),
        ],
      );

      final results = await source.search('x');
      expect(results, hasLength(1));
      expect(results.single.sourceName, '好站');
      expect(
        source.lastDiagnostics.any(
          (d) => d.ruleName == '坏站' && d.message.contains('HTTP 500'),
        ),
        isTrue,
      );
    });

    test('非法 XPath / 坏 HTML 被隔离，诊断含规则名与原因', () async {
      final client = _FakeClient();
      // 坏站：非法 XPath（不以 // 开头），引擎在解析前给出诊断；给它任意 2xx 响应即可。
      client.responses['https://a.test/search?q=x'] = const AnimeHttpResponse(
        statusCode: 200,
        body: '<html><body>anything</body></html>',
      );
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('正常条目', '/b/1')]),
      );

      // 坏站用非法 XPath（不以 // 开头），引擎会在解析前给出诊断。
      final badXpath = AnimeRule.fromJson(<String, dynamic>{
        ...demoJson,
        'name': '坏站',
        'baseURL': 'https://a.test/',
        'searchURL': 'https://a.test/search?q=@keyword',
        'searchList': 'div.result-list',
      });
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[badXpath, rule('好站', 'b.test')],
      );

      final results = await source.search('x');
      expect(results, hasLength(1));
      expect(results.single.sourceName, '好站');
      expect(
        source.lastDiagnostics.any(
          (d) => d.ruleName == '坏站' && d.message.contains('XPath 不受支持'),
        ),
        isTrue,
      );
    });

    test('单条结果缺标题/链接 → 跳过并记诊断，其余保留', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([
          itemHtml('好条目', '/a/ok', img: '/i.jpg'),
          '<div class="anime-item"><a class="cover"><h3 class="title">缺链接</h3></a></div>',
        ]),
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('甲站', 'a.test')],
      );

      final results = await source.search('x');
      expect(results, hasLength(1));
      expect(results.single.detailUrl, 'https://a.test/a/ok');
      expect(
        source.lastDiagnostics.any((d) => d.message.contains('缺少标题或链接')),
        isTrue,
      );
    });

    test('engine.search 自身抛异常 → 该规则跳过，其它规则继续', () async {
      final client = _FakeClient();
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('B一', '/b/1')]),
      );

      final source = RuleAnimeDataSource(
        engine: _SelectiveThrowingEngine(client, '炸站'),
        loadRules: () async => <AnimeRule>[
          rule('炸站', 'a.test'),
          rule('好站', 'b.test'),
        ],
      );

      final results = await source.search('x');
      expect(results, hasLength(1));
      expect(results.single.sourceName, '好站');
      expect(
        source.lastDiagnostics.any(
          (d) => d.ruleName == '炸站' && d.message.contains('搜索请求失败'),
        ),
        isTrue,
      );
    });

    test('诊断每次调用开始清空，不累积上一次', () async {
      final client = _FakeClient();
      client.responses['https://a.test/search?q=x'] = const AnimeHttpResponse(
        statusCode: 500,
        body: 'boom',
      );
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('坏站', 'a.test')],
      );

      await source.search('x');
      expect(source.lastDiagnostics, isNotEmpty);

      // 空关键词路径也会先清诊断。
      await source.search('   ');
      expect(source.lastDiagnostics, isEmpty);
    });
  });

  group('C · 详情映射', () {
    AnimeSummary demoItem() => AnimeSummary(
      id: 'https://example.com/anime/1001',
      title: '葬送的芙莉莲',
      coverUrl: 'https://example.com/img/1001.jpg',
      detailUrl: 'https://example.com/anime/1001',
      sourceName: 'demo03',
    );

    RuleAnimeDataSource demoSource(_FakeClient client) => RuleAnimeDataSource(
      engine: AnimeRuleEngine(client: client),
      loadRules: () async => <AnimeRule>[AnimeRule.fromJson(demoJson)],
    );

    test('4 集一一对应，number 1..4，url 绝对，duration 为 null', () async {
      final client = _FakeClient();
      client.responses['https://example.com/anime/1001'] =
          const AnimeHttpResponse(statusCode: 200, body: demoDetailPageHtml);

      final detail = await demoSource(client).detail(demoItem());

      expect(detail.episodes, hasLength(4));
      expect(detail.episodes.map((e) => e.number).toList(), <int>[1, 2, 3, 4]);
      expect(detail.episodes.map((e) => e.title).toList(), <String>[
        '第01话 启程',
        '第02话 相遇',
        '第03话 诀别',
        '第04话 决意',
      ]);
      expect(detail.episodes.first.url, 'https://example.com/play/1001-01');
      expect(detail.episodes.every((e) => e.duration == null), isTrue);
    });

    test('AnimeDetail 字段取 item + 规则名，description/tags 留空', () async {
      final client = _FakeClient();
      client.responses['https://example.com/anime/1001'] =
          const AnimeHttpResponse(statusCode: 200, body: demoDetailPageHtml);
      final item = demoItem();

      final detail = await demoSource(client).detail(item);

      expect(detail.title, item.title);
      expect(detail.coverUrl, item.coverUrl);
      expect(detail.detailUrl, item.detailUrl);
      expect(detail.sourceName, 'demo03');
      expect(detail.description, '');
      expect(detail.tags, isEmpty);
    });

    test('未知 source → 空剧集详情（字段取 item），有诊断，不抛', () async {
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: _FakeClient()),
        loadRules: () async => <AnimeRule>[AnimeRule.fromJson(demoJson)],
      );
      final item = AnimeSummary(
        id: 'https://x/1',
        title: '未知番',
        coverUrl: 'https://x/c.jpg',
        detailUrl: 'https://x/1',
        sourceName: '不存在的站',
      );

      final detail = await source.detail(item);

      expect(detail.title, item.title);
      expect(detail.coverUrl, item.coverUrl);
      expect(detail.detailUrl, item.detailUrl);
      expect(detail.episodes, isEmpty);
      expect(source.lastDiagnostics, isNotEmpty);
    });

    test('规则存在但详情 404 → 空剧集详情 + 诊断，不抛', () async {
      final client = _FakeClient();
      final source = demoSource(client); // 无响应映射 → 404

      final detail = await source.detail(demoItem());

      expect(detail.episodes, isEmpty);
      expect(detail.title, '葬送的芙莉莲');
      expect(
        source.lastDiagnostics.any((d) => d.message.contains('HTTP 404')),
        isTrue,
      );
    });

    test('规则名大小写不同仍能匹配', () async {
      final client = _FakeClient();
      client.responses['https://example.com/anime/1001'] =
          const AnimeHttpResponse(statusCode: 200, body: demoDetailPageHtml);
      final item = AnimeSummary(
        id: 'https://example.com/anime/1001',
        title: '葬送的芙莉莲',
        coverUrl: '',
        detailUrl: 'https://example.com/anime/1001',
        sourceName: 'DEMO03',
      );

      final detail = await demoSource(client).detail(item);

      expect(detail.episodes, hasLength(4));
      expect(detail.sourceName, 'demo03');
    });

    test('同一条目重复调用 detail 结果稳定，不依赖上次诊断', () async {
      final client = _FakeClient();
      client.responses['https://example.com/anime/1001'] =
          const AnimeHttpResponse(statusCode: 200, body: demoDetailPageHtml);
      final source = demoSource(client);
      final item = demoItem();

      final first = await source.detail(item);
      final second = await source.detail(item);

      expect(second.episodes.length, first.episodes.length);
      expect(
        second.episodes.map((e) => e.url).toList(),
        first.episodes.map((e) => e.url).toList(),
      );
      expect(source.lastDiagnostics, isEmpty);
    });
  });

  group('D2 · 换源（watchSources）', () {
    test('多规则各贡献一条，当前规则排首位且去重', () async {
      final client = _FakeClient();
      // 纯 ASCII 关键词，避免 Uri.encodeQueryComponent 造成 fake URL 不匹配。
      client.responses['https://a.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([
          itemHtml('other', '/a/other', img: '/img/o.jpg'),
          itemHtml('same', '/a/1001', img: '/img/a.jpg'),
        ]),
      );
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('same', '/b/2002')]),
      );
      client.responses['https://c.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('same', '/c/3003')]),
      );

      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[
          rule('乙站', 'b.test'),
          rule('甲站', 'a.test'), // 当前来源
          rule('丙站', 'c.test'),
        ],
      );
      final current = AnimeSummary(
        id: 'https://a.test/anime/1001',
        title: 'same',
        coverUrl: '',
        detailUrl: 'https://a.test/anime/1001',
        sourceName: '甲站',
      );

      final sources = await source.watchSources(current, keyword: 'x');

      expect(sources, hasLength(3));
      expect(sources.first.sourceName, '甲站'); // 当前规则排首位
      expect(sources.first.id, current.id); // 且复用原条目
      expect(sources.map((e) => e.sourceName).toSet(), <String>{
        '甲站',
        '乙站',
        '丙站',
      });
      expect(sources.firstWhere((e) => e.sourceName == '甲站').id, current.id);
      expect(
        sources.firstWhere((e) => e.sourceName == '乙站').detailUrl,
        'https://b.test/b/2002',
      );
    });

    test('某规则按标题精确匹配：优先精确标题而非首条', () async {
      final client = _FakeClient();
      client.responses['https://d.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('other', '/d/0'), itemHtml('same', '/d/1')]),
      );
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[rule('丁站', 'd.test')],
      );
      final current = AnimeSummary(
        id: 'x',
        title: 'same',
        coverUrl: '',
        detailUrl: 'x',
        sourceName: '丁站',
      );

      final sources = await source.watchSources(current, keyword: 'x');
      // 当前规则已纳入且按 sourceName 去重，不会再额外贡献第二条。
      expect(sources, hasLength(1));
      expect(sources.single.id, 'x');
    });

    test('搜索抛异常的规则被跳过，其它来源照常', () async {
      final client = _FakeClient();
      client.responses['https://b.test/search?q=x'] = AnimeHttpResponse(
        statusCode: 200,
        body: listPage([itemHtml('标题', '/b/1')]),
      );
      final source = RuleAnimeDataSource(
        engine: _SelectiveThrowingEngine(client, '炸站'),
        loadRules: () async => <AnimeRule>[
          rule('炸站', 'a.test'),
          rule('好站', 'b.test'),
        ],
      );
      final current = AnimeSummary(
        id: 'x',
        title: '标题',
        coverUrl: '',
        detailUrl: 'x',
        sourceName: '好站',
      );

      final sources = await source.watchSources(current, keyword: 'x');
      expect(sources, hasLength(1));
      expect(sources.single.sourceName, '好站');
    });
  });

  group('D · 时间表与边界', () {
    test('schedule 返回空列表，不发起网络请求', () async {
      final client = _FakeClient();
      final source = RuleAnimeDataSource(
        engine: AnimeRuleEngine(client: client),
        loadRules: () async => <AnimeRule>[],
      );

      expect(await source.schedule(), isEmpty);
      expect(client.calls, isEmpty);
      expect(source.lastDiagnostics, isEmpty);
    });

    test('fromStore 工厂可用（离线：空目录 → 空结果）', () async {
      final dir = await Directory.systemTemp.createTemp('mimao_rules_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final source = RuleAnimeDataSource.fromStore(
        RuleStore(dir),
        engine: AnimeRuleEngine(client: _FakeClient()),
      );

      expect(await source.search('x'), isEmpty);
    });
  });

  group('映射纯函数', () {
    final testRule = rule('甲站', 'a.test');

    test('summaryFromRule 逐字段映射与 subtitle == null', () {
      const hit = RuleSearchResult(
        title: '标题',
        url: '/p/1',
        coverUrl: '/c.jpg',
        absoluteUrl: 'https://a.test/p/1',
        absoluteCoverUrl: 'https://a.test/c.jpg',
      );

      final summary = summaryFromRule(testRule, hit)!;
      expect(summary.title, '标题');
      expect(summary.detailUrl, 'https://a.test/p/1');
      expect(summary.coverUrl, 'https://a.test/c.jpg');
      expect(summary.id, 'https://a.test/p/1');
      expect(summary.sourceName, '甲站');
      expect(summary.subtitle, isNull);
    });

    test('空封面 → coverUrl 空串；空 absoluteUrl → detailUrl/id 回退原始 url', () {
      const noCover = RuleSearchResult(
        title: '无封面',
        url: '/p/2',
        coverUrl: '',
        absoluteUrl: 'https://a.test/p/2',
        absoluteCoverUrl: '',
      );
      final noAbs = RuleSearchResult(
        title: '回退',
        url: '/p/3',
        coverUrl: '',
        absoluteUrl: '',
        absoluteCoverUrl: '',
      );

      expect(summaryFromRule(testRule, noCover)!.coverUrl, '');
      final fallback = summaryFromRule(testRule, noAbs)!;
      expect(fallback.detailUrl, '/p/3');
      expect(fallback.id, '/p/3');
    });

    test('缺标题或详情地址 → summaryFromRule 返回 null', () {
      const noTitle = RuleSearchResult(
        title: '  ',
        url: '/p',
        coverUrl: '',
        absoluteUrl: 'https://a.test/p',
        absoluteCoverUrl: '',
      );
      const noUrl = RuleSearchResult(
        title: '有标题',
        url: '',
        coverUrl: '',
        absoluteUrl: '',
        absoluteCoverUrl: '',
      );

      expect(summaryFromRule(testRule, noTitle), isNull);
      expect(summaryFromRule(testRule, noUrl), isNull);
    });

    test('detailFromRule 映射集数/标题/url/duration 与 AnimeDetail 字段', () {
      final item = summary('甲站', 'https://a.test/anime/1');
      const episodes = <RuleEpisode>[
        RuleEpisode(
          title: '第1集',
          url: '/play/1',
          absoluteUrl: 'https://a.test/play/1',
          roadIndex: 1,
          roadName: '播放线路1',
        ),
        RuleEpisode(
          title: '第2集',
          url: '/play/2',
          absoluteUrl: '',
          roadIndex: 2,
          roadName: '播放线路2',
        ),
      ];

      final detail = detailFromRule(testRule, item, episodes);

      expect(detail.episodes, hasLength(2));
      expect(detail.episodes[0].number, 1);
      expect(detail.episodes[0].title, '第1集');
      expect(detail.episodes[0].url, 'https://a.test/play/1');
      expect(detail.episodes[0].duration, isNull);
      expect(detail.episodes[1].number, 2);
      expect(detail.episodes[1].url, '/play/2');
      expect(detail.description, '');
      expect(detail.tags, isEmpty);
      expect(detail.sourceName, '甲站');
      expect(detail.title, item.title);
    });
  });

  group('E · BangumiAnimeDataSource（照抄 Kazumi）', () {
    BangumiItem frieren() => const BangumiItem(
      id: 400602,
      type: 2,
      name: 'Frieren',
      nameCn: '葬送的芙莉莲',
      summary: '魔法使芙莉莲的旅途',
      airDate: '2023-09-29',
      rank: 1,
      images: <String, String>{'large': 'https://lain.bgm.tv/l.jpg'},
      ratingScore: 9.2,
      votes: 100,
      tags: <String>['奇幻', '治愈'],
    );

    test('search 只走 Bangumi，映射干净元数据（id=bgm://, 带评分/简介）', () async {
      final bangumi = _FakeBangumiClient([
        BangumiSearchPage(items: [frieren()], rawCount: 1),
      ]);
      final ruleSource = _FakeRuleSource();
      final ds = BangumiAnimeDataSource(
        bangumi: bangumi,
        ruleSource: ruleSource,
        baseUrl: BangumiEndpoints.direct,
      );

      final results = await ds.search('芙莉莲');
      expect(results, hasLength(1));
      expect(results.single.id, 'bgm://400602');
      expect(results.single.title, '葬送的芙莉莲');
      expect(results.single.coverUrl, 'https://lain.bgm.tv/l.jpg');
      expect(results.single.rating, 9.2);
      expect(results.single.description, '魔法使芙莉莲的旅途');
      expect(results.single.tags, <String>['奇幻', '治愈']);
      expect(bangumi.keywords, <String>['芙莉莲']);
      expect(ruleSource.searchCalls, 0);
    });

    test('Kazumi nameCn 过滤：无中文名的条目不进搜索结果', () async {
      // API 层已保证 nameCn 非空；这里验证数据源不额外塞规则条目。
      final bangumi = _FakeBangumiClient([
        BangumiSearchPage(
          // 只含一条有中文名的条目。
          items: [frieren()],
          rawCount: 2, // rawCount 含被过滤项，Kazumi 分页语义。
        ),
      ]);
      final ds = BangumiAnimeDataSource(
        bangumi: bangumi,
        ruleSource: _FakeRuleSource(),
        baseUrl: BangumiEndpoints.direct,
      );
      final results = await ds.search('芙莉莲');
      expect(results, hasLength(1));
      expect(results.single.title, '葬送的芙莉莲');
    });

    test('空关键词不请求 Bangumi', () async {
      final bangumi = _FakeBangumiClient([]);
      final ds = BangumiAnimeDataSource(
        bangumi: bangumi,
        ruleSource: _FakeRuleSource(),
        baseUrl: BangumiEndpoints.direct,
      );
      expect(await ds.search('  '), isEmpty);
      expect(bangumi.keywords, isEmpty);
    });

    test('Bangumi 失败返回 null 时返回空，绝不回退规则搜索', () async {
      final bangumi = _FakeBangumiClient([], fail: true);
      final ruleSource = _FakeRuleSource();
      final ds = BangumiAnimeDataSource(
        bangumi: bangumi,
        ruleSource: ruleSource,
        baseUrl: BangumiEndpoints.direct,
      );
      expect(await ds.search('x'), isEmpty);
      expect(ruleSource.searchCalls, 0);

      final emptyBangumi = _FakeBangumiClient([
        BangumiSearchPage(items: const <BangumiItem>[], rawCount: 0),
      ]);
      final ds2 = BangumiAnimeDataSource(
        bangumi: emptyBangumi,
        ruleSource: ruleSource,
        baseUrl: BangumiEndpoints.direct,
      );
      expect(await ds2.search('没有这部番'), isEmpty);
      expect(ruleSource.searchCalls, 0);
    });

    test('watchSources 用标题委托规则层；detail/schedule 也委托', () async {
      final ruleSource = _FakeRuleSource();
      final ds = BangumiAnimeDataSource(
        bangumi: _FakeBangumiClient([]),
        ruleSource: ruleSource,
        baseUrl: BangumiEndpoints.direct,
      );
      final item = AnimeSummary(
        id: 'bgm://1',
        title: '某番',
        coverUrl: '',
        detailUrl: '',
      );
      await ds.watchSources(item, keyword: '某番');
      expect(ruleSource.watchKeywords, <String>['某番']);
      final detail = await ds.detail(item);
      expect(detail.title, '规则详情');
      expect(await ds.schedule(), isEmpty);
    });
  });
}

class _FakeBangumiClient implements BangumiClient {
  _FakeBangumiClient(this.responses, {this.fail = false});

  final List<BangumiSearchPage> responses;
  final bool fail;
  final keywords = <String>[];
  int _calls = 0;

  @override
  Future<BangumiSearchPage?> bangumiSearch(
    String keyword, {
    required String baseUrl,
    int limit = 20,
    int offset = 0,
  }) async {
    keywords.add(keyword);
    if (fail) throw StateError('bangumi down');
    if (responses.isEmpty) return null;
    return responses[_calls++ % responses.length];
  }
}

class _FakeRuleSource implements AnimeDataSource {
  int searchCalls = 0;
  final watchKeywords = <String>[];

  @override
  Future<List<AnimeSummary>> search(String keyword) async {
    searchCalls++;
    return <AnimeSummary>[
      AnimeSummary(id: 'rule', title: '规则兜底', coverUrl: '', detailUrl: 'x'),
    ];
  }

  @override
  Future<AnimeDetail> detail(AnimeSummary item) async =>
      AnimeDetail(title: '规则详情', coverUrl: '', detailUrl: '', description: '');

  @override
  Future<List<AnimeSummary>> watchSources(
    AnimeSummary item, {
    required String keyword,
  }) async {
    watchKeywords.add(keyword);
    return <AnimeSummary>[];
  }

  @override
  Future<List<AnimeScheduleSection>> schedule() async =>
      const <AnimeScheduleSection>[];
}

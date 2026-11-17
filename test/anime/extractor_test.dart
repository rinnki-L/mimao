import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/extractor.dart';
import 'package:mimao/anime/engine/result.dart';
import 'package:mimao/anime/engine/rule.dart';

import 'fixtures.dart';

void main() {
  const extractor = RuleExtractor();
  final demoRule = AnimeRule.fromJson(
    jsonDecode(demoRuleJson) as Map<String, dynamic>,
  );
  final mxdmRule = AnimeRule.fromJson(
    jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
  );

  test('fixture 与 demos/03 内嵌 HTML 逐字一致（防止 fixture 漂移）', () {
    final demo = File('demos/03_mini_rule_engine/main.dart');
    // demos/ 只在本地保留（公开仓库 .gitignore 排除），缺失时跳过来源校验；
    // fixture 本身已在下方用精确断言锁死。
    if (!demo.existsSync()) return;
    final demoSource = demo.readAsStringSync();
    expect(demoSource, contains(demoListPageHtml));
    expect(demoSource, contains(demoDetailPageHtml));
  });

  group('列表抽取（demo 03 fixture）', () {
    test('4 条结果，标题/链接/封面逐字段精确匹配', () {
      final result = extractor.parseSearch(demoListPageHtml, demoRule);

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(4));
      expect(result.items.map((item) => item.title).toList(), [
        '葬送的芙莉莲',
        '药屋少女的呢喃',
        '败犬女主太多了！',
        '孤独摇滚！',
      ]);
      expect(result.items.map((item) => item.url).toList(), [
        '/anime/1001',
        '/anime/1002',
        '/anime/1003',
        '/anime/1004',
      ]);
      expect(result.items.map((item) => item.coverUrl).toList(), [
        '/img/1001.jpg',
        '/img/1002.jpg',
        '/img/1003.jpg',
        '/img/1004.jpg',
      ]);
      // 绝对地址由规则 baseURL 归一化得到，供上层直接请求/展示。
      expect(result.items.first.absoluteUrl, 'https://example.com/anime/1001');
      expect(
        result.items.first.absoluteCoverUrl,
        'https://example.com/img/1001.jpg',
      );
    });

    test('搜索命中过滤：标题包含关键词（大小写不敏感）', () {
      final all = extractor.parseSearch(demoListPageHtml, demoRule).items;

      final hit = filterSearchResults(all, '芙莉莲');
      expect(hit, hasLength(1));
      expect(hit.single.title, '葬送的芙莉莲');

      expect(filterSearchResults(all, '  '), hasLength(4));
      expect(filterSearchResults(all, '不存在的番'), isEmpty);
      expect(
        filterSearchResults(<RuleSearchResult>[
          const RuleSearchResult(
            title: 'Solo Leveling',
            url: '/a',
            coverUrl: '',
            absoluteUrl: 'https://a.test/a',
            absoluteCoverUrl: '',
          ),
        ], 'solo'),
        hasLength(1),
      );
    });

    test('真实 KazumiRules（MXdm）直接吃：3 条结果与原始 href 一致', () {
      final result = extractor.parseSearch(mxdmSearchHtml, mxdmRule);

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(3));
      expect(result.items.map((item) => item.title).toList(), [
        '葬送的芙莉莲',
        '药屋少女的呢喃',
        '孤独摇滚！',
      ]);
      expect(result.items.map((item) => item.url).toList(), [
        '/detail/201',
        '/detail/202',
        '/detail/203',
      ]);
      expect(result.items.first.absoluteUrl, 'https://www.dcc3.com/detail/201');
      // 该规则没有 searchCover 扩展，封面保持空串。
      expect(result.items.every((item) => item.coverUrl.isEmpty), isTrue);
    });
  });

  group('详情抽取', () {
    test('demo 03：4 集，标题与播放地址一一对应', () {
      final result = extractor.parseDetail(demoDetailPageHtml, demoRule);

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(4));
      expect(result.items.map((item) => item.title).toList(), [
        '第01话 启程',
        '第02话 相遇',
        '第03话 诀别',
        '第04话 决意',
      ]);
      expect(result.items.map((item) => item.url).toList(), [
        '/play/1001-01',
        '/play/1001-02',
        '/play/1001-03',
        '/play/1001-04',
      ]);
      expect(result.items.map((item) => item.absoluteUrl).toList(), [
        'https://example.com/play/1001-01',
        'https://example.com/play/1001-02',
        'https://example.com/play/1001-03',
        'https://example.com/play/1001-04',
      ]);
      expect(result.items.every((item) => item.roadName == '播放线路1'), isTrue);
      expect(result.items.every((item) => item.roadIndex == 1), isTrue);
    });

    test('真实 KazumiRules（MXdm）：两条线路共 4 集，线路名正确', () {
      final result = extractor.parseDetail(mxdmDetailHtml, mxdmRule);

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(4));
      expect(result.items.map((item) => item.roadName).toList(), [
        '播放线路1',
        '播放线路1',
        '播放线路2',
        '播放线路2',
      ]);
      expect(
        result.items.first.absoluteUrl,
        'https://www.dcc3.com/play/201-01',
      );
      expect(
        result.items.last.absoluteUrl,
        'https://www.dcc3.com/play/backup/201-02',
      );
    });
  });

  group('容错：非法规则/页面返回空而不是崩溃', () {
    test('选择器不以 // 开头', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '坏选择器',
        'baseURL': 'https://bad.test',
        'searchList': 'div.item',
        'searchName': '//h3',
        'searchResult': '//a',
        'chapterRoads': 'div.playlist',
        'chapterResult': '//a',
      });

      final search = extractor.parseSearch(demoListPageHtml, rule);
      expect(search.isEmpty, isTrue);
      expect(search.diagnostics, isNotEmpty);

      final detail = extractor.parseDetail(demoDetailPageHtml, rule);
      expect(detail.isEmpty, isTrue);
      expect(detail.diagnostics, isNotEmpty);
    });

    test('选择器语法损坏（谓词缺值）', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '语法坏',
        'baseURL': 'https://bad.test',
        'searchList': '//div[@class=]',
        'searchName': '//a',
        'searchResult': '//a',
      });

      final result = extractor.parseSearch(demoListPageHtml, rule);
      expect(result.isEmpty, isTrue);
      expect(result.diagnostics, isNotEmpty);
    });

    test('空 HTML / 无根节点', () {
      expect(extractor.parseSearch('', demoRule).isEmpty, isTrue);
      expect(extractor.parseDetail('', demoRule).isEmpty, isTrue);
    });

    test('详情规则缺少线路选择器', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '缺线路',
        'baseURL': 'https://bad.test',
        'chapterRoads': '',
        'chapterResult': '//a',
      });

      final result = extractor.parseDetail(demoDetailPageHtml, rule);
      expect(result.isEmpty, isTrue);
      expect(result.diagnostics, isNotEmpty);
    });

    test('单条缺链接时跳过，其余照常', () {
      const html = '''
<div class="result-list">
  <div class="anime-item">
    <a class="cover" href="/anime/1"><img src="/img/1.jpg"></a>
    <h3 class="title">有链接</h3>
  </div>
  <div class="anime-item">
    <a class="cover"><img src="/img/2.jpg"></a>
    <h3 class="title">没有链接</h3>
  </div>
</div>''';

      final result = extractor.parseSearch(html, demoRule);
      expect(result.items, hasLength(1));
      expect(result.items.single.title, '有链接');
      expect(result.diagnostics, isNotEmpty);
    });
  });

  group('URL 归一化（对齐 Kazumi normalizeEpisodeUrl）', () {
    test('相对路径、尾斜杠、空 query、跨站协议', () {
      expect(
        normalizeRuleUrl('https://a.test/', '/anime/1'),
        'https://a.test/anime/1',
      );
      expect(
        normalizeRuleUrl('https://a.test/', 'https://a.test/anime/1/'),
        'https://a.test/anime/1',
      );
      expect(
        normalizeRuleUrl('https://a.test/', '/anime/1?'),
        'https://a.test/anime/1',
      );
      // 同站且协议不同：统一到 baseURL 的协议。
      expect(
        normalizeRuleUrl('http://a.test/', 'https://a.test/anime/1'),
        'http://a.test/anime/1',
      );
      // 跨站保持原协议。
      expect(
        normalizeRuleUrl('https://a.test/', 'http://other.test/anime/1'),
        'http://other.test/anime/1',
      );
      expect(normalizeRuleUrl('https://a.test/', '  '), '');
    });
  });
}

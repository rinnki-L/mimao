import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/rule.dart';

import 'fixtures.dart';

void main() {
  group('AnimeRule JSON（Kazumi 兼容）', () {
    test('真实 KazumiRules 规则可直接解析，字段齐全', () {
      final rule = AnimeRule.fromJson(
        jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
      );

      expect(rule.name, 'MXdm');
      expect(rule.api, '5');
      expect(rule.type, 'anime');
      expect(rule.version, '2.4');
      expect(rule.baseUrl, 'https://www.dcc3.com');
      expect(rule.multiSources, isTrue);
      expect(rule.usePost, isFalse);
      expect(rule.adBlocker, isTrue);
      expect(rule.search.url, 'https://www.dcc3.com/search/?wd=@keyword');
      expect(rule.search.list, "//div[contains(@class, 'search')]/ul/li");
      expect(rule.search.title, '//h3/a');
      expect(rule.search.link, '//h3/a');
      expect(
        rule.detail.roads,
        "//div[@class='playlist']/div[@class='row']/ul",
      );
      expect(rule.detail.episodes, '//li/a');
      expect(rule.play.urlAttribute, 'href');
      expect(rule.extras, isEmpty);
      expect(rule.isDeprecated, isFalse);
      expect(rule.validate(), isEmpty);
    });

    test('JSON 序列化往返：Kazumi 键名与扩展键都不丢', () {
      final original = AnimeRule.fromJson(
        jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
      );
      final encoded = original.toJson();

      // 输出必须是 Kazumi 的键名，社区工具可直接读。
      expect(encoded['baseURL'], 'https://www.dcc3.com');
      expect(encoded['searchURL'], 'https://www.dcc3.com/search/?wd=@keyword');
      expect(encoded['muliSources'], isTrue);
      expect(encoded['chapterRoads'], isNotNull);

      final restored = AnimeRule.fromJson(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      );
      expect(restored.toJson(), encoded);
      expect(restored.name, original.name);
      expect(restored.search.title, original.search.title);
      expect(restored.detail.episodes, original.detail.episodes);
    });

    test('未识别字段进 extras 并原样写回', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '带扩展的规则',
        'searchList': '//div',
        'searchName': '//a',
        'searchResult': '//a',
        'deprecated': true,
        'antiCrawlerConfig': <String, dynamic>{'enabled': true},
      });

      expect(rule.isDeprecated, isTrue);
      expect(rule.extras['antiCrawlerConfig'], isA<Map<String, dynamic>>());
      final encoded = rule.toJson();
      expect(encoded['deprecated'], isTrue);
      expect(encoded['antiCrawlerConfig'], isA<Map<String, dynamic>>());
    });

    test('字段别名与松散类型容错（baseUrl/searchUrl/字符串布尔）', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '别名规则',
        'baseUrl': 'https://alias.test',
        'searchUrl': 'https://alias.test/s?q=@keyword',
        'searchList': '//div',
        'searchName': '//a',
        'searchResult': '//a',
        'chapterRoads': '//ul',
        'chapterResult': '//li/a',
        'muliSources': 'false',
        'usePost': 1,
        'api': 5,
      });

      expect(rule.baseUrl, 'https://alias.test');
      expect(rule.search.url, 'https://alias.test/s?q=@keyword');
      expect(rule.multiSources, isFalse);
      expect(rule.usePost, isTrue);
      expect(rule.api, '5');
      // 序列化统一回 Kazumi 键名。
      expect(rule.toJson()['baseURL'], 'https://alias.test');
      expect(rule.toJson()['muliSources'], isFalse);
    });

    test('XPath 只接受 // 开头；非法选择器被 validate 指出', () {
      expect(isSupportedXPathSelector('//div[@class="x"]'), isTrue);
      expect(isSupportedXPathSelector('  //div  '), isTrue);
      expect(isSupportedXPathSelector('div'), isFalse);
      expect(isSupportedXPathSelector('/div'), isFalse);
      expect(isSupportedXPathSelector('//'), isFalse);
      expect(isSupportedXPathSelector('///div'), isFalse);

      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '坏规则',
        'searchURL': 'https://bad.test/s?q=@keyword',
        'searchList': 'div.item',
        'searchName': '//a',
        'searchResult': '//a',
        'chapterRoads': '//ul',
        'chapterResult': '//li/a',
      });
      expect(rule.validate(), contains(contains('搜索规则 XPath 无效')));
    });

    test('searchURL 的 @keyword 占位会被 URL 编码', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        'name': '编码规则',
        'searchURL': 'https://a.test/search?q=@keyword',
      });

      expect(
        rule.search.buildUrl('芙 莉莲'),
        'https://a.test/search?q=%E8%8A%99+%E8%8E%89%E8%8E%B2',
      );
      expect(rule.search.buildUrl(''), 'https://a.test/search?q=');
    });
  });
}

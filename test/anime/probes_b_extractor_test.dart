// B 线 · extractor 详情封面抽取单测。
// 覆盖：带 detailCover 的扩展规则抽出封面（含绝对化）、Kazumi 原生规则仍空串。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/extractor.dart';
import 'package:mimao/anime/engine/rule.dart';

import 'fixtures.dart';

void main() {
  const extractor = RuleExtractor();

  const detailWithCoverHtml = '''
<!doctype html><html><body>
<img class="poster" src="/posters/1001.jpg">
<div class="playlist">
  <a href="/play/1">第01话</a>
  <a href="/play/2">第02话</a>
</div>
</body></html>''';

  AnimeRule ruleWithDetailCover(String selector) =>
      AnimeRule.fromJson(<String, dynamic>{
        'name': '带详情封面',
        'baseURL': 'https://a.test',
        'chapterRoads': '//div[@class="playlist"]',
        'chapterResult': '//a',
        'detailCover': selector,
      });

  test('带 detailCover 的扩展规则：抽出封面并绝对化', () {
    final result = extractor.parseDetail(
      detailWithCoverHtml,
      ruleWithDetailCover('//img[@class="poster"]/@src'),
    );

    expect(result.diagnostics, isEmpty);
    expect(result.coverUrl, 'https://a.test/posters/1001.jpg');
    expect(result.items, hasLength(2));
  });

  test('detailCover 选择器指向 <img> 节点时读 src 属性', () {
    final result = extractor.parseDetail(
      detailWithCoverHtml,
      ruleWithDetailCover('//img[@class="poster"]'),
    );
    expect(result.coverUrl, 'https://a.test/posters/1001.jpg');
  });

  test('Kazumi 原生规则无 detailCover：coverUrl 仍空串', () {
    final native = AnimeRule.fromJson(
      jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
    );
    final result = extractor.parseDetail(mxdmDetailHtml, native);

    expect(result.items, hasLength(4));
    expect(result.coverUrl, '');
  });

  test('详情封面选择器命中不到元素：空串且不产生诊断', () {
    final result = extractor.parseDetail(
      detailWithCoverHtml,
      ruleWithDetailCover('//img[@class="missing"]/@src'),
    );
    expect(result.coverUrl, '');
    expect(result.diagnostics, isEmpty);
  });

  test('detailCover/cover 别名都进 DetailRule，hasValidSelectors 不因可选封面变严', () {
    final viaCover = ruleWithDetailCover('//img/@src');
    final viaDetailCover = AnimeRule.fromJson(<String, dynamic>{
      'name': '别名',
      'chapterRoads': '//div',
      'chapterResult': '//a',
      'cover': '//img/@src',
    });
    expect(viaCover.detail.cover, '//img/@src');
    expect(viaDetailCover.detail.cover, '//img/@src');
    // 可选封面不参与严格性判定：没有详情选择器时依然只按线路/剧集判定。
    expect(viaDetailCover.detail.hasValidSelectors, isTrue);
  });
}

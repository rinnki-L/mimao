import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/anime_rule_engine.dart';
import 'package:mimao/anime/engine/result.dart';
import 'package:mimao/anime/engine/rule.dart';
import 'package:mimao/anime/request/web_client.dart';

import 'fixtures.dart';

class _FakeClient implements AnimeHttpClient {
  final Map<String, AnimeHttpResponse> responses =
      <String, AnimeHttpResponse>{};
  final List<({String url, AnimeFetchOptions options})> calls =
      <({String url, AnimeFetchOptions options})>[];
  Object? error;

  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    calls.add((url: url, options: options));
    final failure = error;
    if (failure != null) throw failure;
    return responses[url] ??
        const AnimeHttpResponse(statusCode: 404, body: 'not found');
  }
}

void main() {
  final demoRule = AnimeRule.fromJson(
    jsonDecode(demoRuleJson) as Map<String, dynamic>,
  );
  final mxdmRule = AnimeRule.fromJson(
    jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
  );

  test('搜索编排：替换 @keyword → 请求 → XPath 解析', () async {
    final client = _FakeClient();
    const searchUrl =
        'https://example.com/search?q=%E8%8A%99%E8%8E%89%E8%8E%B2';
    client.responses[searchUrl] = const AnimeHttpResponse(
      statusCode: 200,
      body: demoListPageHtml,
    );

    final engine = AnimeRuleEngine(client: client);
    final result = await engine.search(demoRule, '芙莉莲');

    expect(result.items, hasLength(4));
    expect(result.items.first.title, '葬送的芙莉莲');
    expect(client.calls, hasLength(1));
    expect(client.calls.single.url, searchUrl);
    expect(client.calls.single.options.method, 'GET');
  });

  test('详情编排：相对地址基于 baseURL 补全后请求并解析 4 集', () async {
    final client = _FakeClient();
    client.responses['https://example.com/anime/1001'] =
        const AnimeHttpResponse(statusCode: 200, body: demoDetailPageHtml);

    final engine = AnimeRuleEngine(client: client);
    final result = await engine.detail(demoRule, '/anime/1001');

    expect(result.items, hasLength(4));
    expect(result.items.first.title, '第01话 启程');
    expect(result.items.first.absoluteUrl, 'https://example.com/play/1001-01');
    expect(client.calls.single.url, 'https://example.com/anime/1001');
    expect(client.calls.single.options.referer, 'https://example.com/');
  });

  test('usePost 规则：query 改为表单体，URL 去掉 query', () async {
    final client = _FakeClient();
    client.responses['https://post.test/search'] = const AnimeHttpResponse(
      statusCode: 200,
      body: demoListPageHtml,
    );
    final rule = AnimeRule.fromJson(<String, dynamic>{
      ...demoRule.toJson(),
      'usePost': true,
      'searchURL': 'https://post.test/search?q=@keyword&page=1',
    });

    final result = await AnimeRuleEngine(client: client).search(rule, '芙莉莲');

    expect(result.items, hasLength(4));
    final call = client.calls.single;
    expect(call.options.method, 'POST');
    expect(call.url, 'https://post.test/search');
    expect(call.options.formData, <String, String>{'q': '芙莉莲', 'page': '1'});
  });

  test('HTTP 非 2xx / 网络异常 → 空结果 + 诊断，不抛异常', () async {
    final engine = AnimeRuleEngine(client: _FakeClient());
    final notFound = await engine.search(demoRule, '芙莉莲');
    expect(notFound.isEmpty, isTrue);
    expect(notFound.diagnostics.single, contains('HTTP 404'));

    final client = _FakeClient()..error = Exception('boom');
    final failed = await AnimeRuleEngine(
      client: client,
    ).detail(demoRule, '/anime/1001');
    expect(failed.isEmpty, isTrue);
    expect(failed.diagnostics.single, contains('详情请求失败'));
  });

  test('非法 searchURL 直接返回诊断，不发请求', () async {
    final client = _FakeClient();
    final rule = AnimeRule.fromJson(<String, dynamic>{
      'name': '没有搜索地址',
      'searchList': '//div',
      'searchName': '//a',
      'searchResult': '//a',
    });

    final result = await AnimeRuleEngine(client: client).search(rule, 'x');

    expect(result.isEmpty, isTrue);
    expect(result.diagnostics.single, contains('searchURL'));
    expect(client.calls, isEmpty);
  });

  test('playTarget：绝对地址 + 规则 UA/Referer', () {
    final engine = AnimeRuleEngine(client: _FakeClient());
    const episode = RuleEpisode(
      title: '第01话',
      url: '/play/201-01',
      absoluteUrl: 'https://www.dcc3.com/play/201-01',
      roadIndex: 1,
      roadName: '播放线路1',
    );

    final target = engine.playTarget(mxdmRule, episode);
    expect(target.url, 'https://www.dcc3.com/play/201-01');
    expect(target.headers['User-Agent'], defaultAnimeUserAgent);
    expect(target.headers['Referer'], 'https://www.dcc3.com');

    final customRule = AnimeRule.fromJson(<String, dynamic>{
      ...mxdmRule.toJson(),
      'userAgent': 'custom-UA',
      'referer': 'https://ref.test/',
    });
    final custom = engine.playTarget(customRule, episode);
    expect(custom.headers['User-Agent'], 'custom-UA');
    expect(custom.headers['Referer'], 'https://ref.test/');
  });
}

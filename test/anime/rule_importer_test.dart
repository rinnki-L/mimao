import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/rule_importer.dart';
import 'package:mimao/anime/request/web_client.dart';

import 'fixtures.dart';

class _StubClient implements AnimeHttpClient {
  _StubClient(this.response);

  final AnimeHttpResponse response;
  String? lastUrl;
  AnimeFetchOptions? lastOptions;
  Object? throwError;

  @override
  Future<AnimeHttpResponse> fetch(
    String url, {
    AnimeFetchOptions options = const AnimeFetchOptions(),
  }) async {
    lastUrl = url;
    lastOptions = options;
    final error = throwError;
    if (error != null) throw error;
    return response;
  }
}

void main() {
  group('RuleImporter.parseJson', () {
    test('单个真实 KazumiRules JSON → 一条规则', () {
      final result = RuleImporter().parseJson(kazumiMxdmRuleJson);

      expect(result.rules, hasLength(1));
      expect(result.failures, isEmpty);
      expect(result.rules.single.name, 'MXdm');
      expect(result.duplicateCount, 0);
    });

    test('JSON 数组 → 多条规则；同名后者覆盖并计数', () {
      final input =
          '[$kazumiMxdmRuleJson,$demoRuleJson,'
          '${kazumiMxdmRuleJson.replaceFirst('"version": "2.4"', '"version": "9.9"')}]';
      final result = RuleImporter().parseJson(input);

      expect(result.rules, hasLength(2));
      expect(result.duplicateCount, 1);
      final names = result.rules.map((rule) => rule.name).toList();
      expect(names, containsAll(<String>['MXdm', 'demo03']));
      final mxdm = result.rules.singleWhere((rule) => rule.name == 'MXdm');
      expect(mxdm.version, '9.9');
    });

    test('坏条目逐条容错：非 object、缺 name、无选择器', () {
      final result = RuleImporter().parseJson(
        '[42,{"searchList":"//div"},$demoRuleJson]',
      );

      expect(result.rules, hasLength(1));
      expect(result.rules.single.name, 'demo03');
      expect(result.failures, hasLength(2));
      expect(result.failures.first, contains('不是 JSON object'));
      expect(result.failures.last, contains('缺少 name'));
    });

    test('空文本 / 非 JSON / 非 object', () {
      final importer = RuleImporter();

      expect(importer.parseJson('  ').failures.single, contains('为空'));
      expect(
        importer.parseJson('not json').failures.single,
        contains('不是合法 JSON'),
      );
      expect(importer.parseJson('"a string"').failures, isNotEmpty);
      expect(importer.parseJson('null').failures, isNotEmpty);
    });
  });

  group('RuleImporter.importFromUrl', () {
    test('下载成功后解析，并带上调用方给的请求参数', () async {
      final client = _StubClient(
        AnimeHttpResponse(statusCode: 200, body: kazumiMxdmRuleJson),
      );
      final importer = RuleImporter(client: client);

      final result = await importer.importFromUrl(
        'https://rules.test/mxdm.json',
        options: const AnimeFetchOptions(
          userAgent: 'mimao-test',
          cookies: <String, String>{'sid': 'abc'},
        ),
      );

      expect(result.rules.single.name, 'MXdm');
      expect(client.lastUrl, 'https://rules.test/mxdm.json');
      expect(client.lastOptions?.userAgent, 'mimao-test');
      expect(client.lastOptions?.cookies, <String, String>{'sid': 'abc'});
    });

    test('HTTP 非 2xx 返回 failures 而不是抛异常', () async {
      final client = _StubClient(
        const AnimeHttpResponse(statusCode: 404, body: 'not found'),
      );

      final result = await RuleImporter(
        client: client,
      ).importFromUrl('https://rules.test/missing.json');

      expect(result.isEmpty, isTrue);
      expect(result.failures.single, contains('HTTP 404'));
    });

    test('网络异常返回 failures 而不是抛异常', () async {
      final client = _StubClient(
        const AnimeHttpResponse(statusCode: 200, body: '{}'),
      )..throwError = Exception('boom');

      final result = await RuleImporter(
        client: client,
      ).importFromUrl('https://rules.test/x.json');

      expect(result.isEmpty, isTrue);
      expect(result.failures.single, contains('规则下载失败'));
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/engine/rule_importer.dart';
import 'package:mimao/anime/request/web_client.dart';

import 'fixtures.dart';

const String _repoBase =
    'https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/';

String _indexJson(List<dynamic> entries) => jsonEncode(entries);

Map<String, dynamic> _indexEntry(
  String name, {
  String version = '1.0',
  int lastUpdate = 0,
}) => <String, dynamic>{
  'name': name,
  'version': version,
  'useNativePlayer': true,
  'antiCrawlerEnabled': false,
  'author': '',
  'lastUpdate': lastUpdate,
};

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

  group('normalizeRepositoryBaseUrl', () {
    test('接受 http(s) 并补齐结尾斜杠', () {
      expect(
        normalizeRepositoryBaseUrl('https://rules.test/repo')?.toString(),
        'https://rules.test/repo/',
      );
      expect(
        normalizeRepositoryBaseUrl('http://rules.test/repo/')?.toString(),
        'http://rules.test/repo/',
      );
    });

    test('拒绝非 http(s)、空 host、user-info、query、fragment', () {
      for (final input in <String>[
        'ftp://rules.test/',
        'rules.test/repo',
        'https://user:pw@rules.test/',
        'https://rules.test/?x=1',
        'https://rules.test/#frag',
        '',
      ]) {
        expect(normalizeRepositoryBaseUrl(input), isNull, reason: input);
      }
    });
  });

  group('isSafeRuleName / ruleUrl', () {
    test('安全的名字拼接为 {base}{name}.json', () {
      expect(isSafeRuleName('MXdm'), isTrue);
      expect(isSafeRuleName('A-1.b_c'), isTrue);
      expect(
        RuleImporter().ruleUrl(_repoBase, 'MXdm'),
        '${_repoBase}MXdm.json',
      );
      expect(
        RuleImporter().ruleUrl('https://rules.test/repo', 'AGE'),
        'https://rules.test/repo/AGE.json',
      );
    });

    test('拒绝路径穿越与非法字符', () {
      for (final name in <String>[
        '',
        '../etc/passwd',
        'a/b',
        'a?b',
        'a#b',
        '..',
        'a..b',
        '名字',
      ]) {
        expect(isSafeRuleName(name), isFalse, reason: name);
        expect(
          () => RuleImporter().ruleUrl(_repoBase, name),
          throwsArgumentError,
          reason: name,
        );
      }
    });
  });

  group('RuleImporter.fetchIndex', () {
    test('解析清单条目与字段，坏条目逐条跳过', () async {
      final body = _indexJson(<dynamic>[
        _indexEntry('MXdm', version: '2.4', lastUpdate: 1790853597000),
        _indexEntry('AGE', version: '1.6'),
        <String, dynamic>{'version': '1.0'}, // 缺 name
        <String, dynamic>{'name': 'bad/name', 'version': '1.0'}, // 非法名字
        42, // 非 object
      ]);
      final client = _StubClient(
        AnimeHttpResponse(statusCode: 200, body: body),
      );
      final result = await RuleImporter(client: client).fetchIndex(_repoBase);

      expect(client.lastUrl, '${_repoBase}index.json');
      expect(result.entries, hasLength(2));
      expect(result.entries.first.name, 'MXdm');
      expect(result.entries.first.version, '2.4');
      expect(result.entries.first.lastUpdate, 1790853597000);
      expect(result.entries.first.lastUpdateLabel, contains('2026'));
      expect(result.entries.last.name, 'AGE');
      expect(result.failures, hasLength(3));
    });

    test('合法但与清单同形的对象（非数组）报格式错误', () async {
      final client = _StubClient(
        const AnimeHttpResponse(statusCode: 200, body: '{"name":"MXdm"}'),
      );
      final result = await RuleImporter(client: client).fetchIndex(_repoBase);

      expect(result.entries, isEmpty);
      expect(result.failures.single, contains('格式错误'));
    });

    test('非法仓库地址不发请求', () async {
      final client = _StubClient(
        AnimeHttpResponse(statusCode: 200, body: _indexJson(<dynamic>[])),
      );
      final result = await RuleImporter(
        client: client,
      ).fetchIndex('https://user:pw@rules.test/');

      expect(client.lastUrl, isNull);
      expect(result.failures.single, contains('仓库地址不合法'));
    });

    test('HTTP 非 2xx / 坏 JSON / 网络异常收敛为 failures', () async {
      final http = _StubClient(
        const AnimeHttpResponse(statusCode: 404, body: 'not found'),
      );
      expect(
        (await RuleImporter(
          client: http,
        ).fetchIndex(_repoBase)).failures.single,
        contains('HTTP 404'),
      );

      final badJson = _StubClient(
        const AnimeHttpResponse(statusCode: 200, body: 'not json'),
      );
      expect(
        (await RuleImporter(
          client: badJson,
        ).fetchIndex(_repoBase)).failures.single,
        contains('不是合法 JSON'),
      );

      final broken = _StubClient(
        const AnimeHttpResponse(statusCode: 200, body: '[]'),
      )..throwError = Exception('offline');
      expect(
        (await RuleImporter(
          client: broken,
        ).fetchIndex(_repoBase)).failures.single,
        contains('读取规则清单失败'),
      );
    });
  });
}

// 词典规则：URL 展开 / 导入导出 / 查询链路（含离线 data: 规则）/ 存储服务。
//
// 全程离线：查询用假传输 + `data:` URL，不碰插件与网络；存储用内存 drift。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/dict/novel_dict_rule.dart';
import 'package:mimao/novel/dict/novel_dict_service.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/novel_db.dart';

class _FakeTransport implements NovelHttpTransport {
  _FakeTransport(this.responder);

  final NovelHttpResponse Function(NovelHttpRequest request) responder;
  final List<NovelHttpRequest> requests = <NovelHttpRequest>[];
  bool closed = false;

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    requests.add(request);
    return responder(request);
  }

  @override
  void close() => closed = true;
}

NovelHttpResponse _html(String url, String body, {int status = 200}) =>
    NovelHttpResponse(url: url, statusCode: status, body: body);

void main() {
  group('模型', () {
    test('normalizeNovelDictWord：去标点、压空白、限长', () {
      expect(normalizeNovelDictWord('  「你好」\n '), '你好');
      expect(normalizeNovelDictWord('hello   world'), 'hello world');
      final long = normalizeNovelDictWord('啊' * 60);
      expect(long.length, 40);
      expect(normalizeNovelDictWord('   '), '');
    });

    test('expandNovelDictUrl：{{key}} 按 UTF-8 编码，其余规则原样', () {
      final url = expandNovelDictUrl('https://www.zdic.net/hans/{{key}}', '中文');
      expect(url, 'https://www.zdic.net/hans/%E4%B8%AD%E6%96%87');
      expect(
        expandNovelDictUrl('https://a.test/q=1', '词'),
        'https://a.test/q=1',
      );
    });

    test('toJson 字段名与 Legado dictRules.json 一致', () {
      const rule = NovelDictRule(
        name: '汉典',
        urlRule: 'https://www.zdic.net/hans/{{key}}',
        showRule: '#jbjs@html',
        sortOrder: 3,
      );
      final json = rule.toJson();
      expect(json['urlRule'], rule.urlRule);
      expect(json['showRule'], rule.showRule);
      expect(json['sortNumber'], 3);
      expect(json.containsKey('sortOrder'), isFalse);
    });

    test('decodeNovelDictRules：数组 / 单对象 / dictRules 包壳', () {
      const array = '[{"name":"A","urlRule":"https://a/{{key}}"}]';
      expect(decodeNovelDictRules(array).single.name, 'A');

      const single = '{"name":"B","urlRule":"https://b/{{key}}"}';
      expect(decodeNovelDictRules(single).single.name, 'B');

      const wrapped =
          '{"dictRules":[{"name":"C","urlRule":"https://c/{{key}}"}]}';
      expect(decodeNovelDictRules(wrapped).single.name, 'C');
    });

    test('decodeNovelDictRules：跳过缺字段条目，全空则报错', () {
      const text = '[{"name":"","urlRule":""},{"name":"D","urlRule":"u"}]';
      expect(decodeNovelDictRules(text).single.name, 'D');
      expect(
        () => decodeNovelDictRules('[{"name":""}]'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeNovelDictRules('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('encodeNovelDictRules 与 decode 往返', () {
      const rules = <NovelDictRule>[
        NovelDictRule(name: 'A', urlRule: 'https://a/{{key}}', sortOrder: 2),
        NovelDictRule(
          name: 'B',
          urlRule: 'https://b/{{key}}',
          showRule: 'tag.body@all',
          enabled: false,
        ),
      ];
      final decoded = decodeNovelDictRules(encodeNovelDictRules(rules));
      expect(decoded.map((r) => r.name), <String>['A', 'B']);
      expect(decoded[1].enabled, isFalse);
      expect(decoded[0].sortOrder, 2);
    });

    test('内置规则齐全：包含一条离线 data: 规则', () {
      expect(novelDefaultDictRules, isNotEmpty);
      expect(
        novelDefaultDictRules.where((r) => r.urlRule.startsWith('data:')),
        isNotEmpty,
      );
      expect(novelDefaultDictRules.every((r) => r.builtin), isTrue);
    });
  });

  group('查询', () {
    test('data: 规则离线出结果，不发任何请求', () async {
      final transport = _FakeTransport(
        (_) => _html('unused', '<html><body>不该被请求</body></html>'),
      );
      final lookup = NovelDictService(transport: transport);
      addTearDown(lookup.close);
      final rule = novelDefaultDictRules.firstWhere(
        (r) => r.urlRule.startsWith('data:'),
      );
      final result = await lookup.lookup(rule, '词典');
      expect(result.ok, isTrue, reason: result.error);
      expect(result.text, contains('词条：词典'));
      expect(transport.requests, isEmpty);
    });

    test('选择器解析 + 请求地址正确（词已编码）', () async {
      final transport = _FakeTransport((request) {
        expect(request.url, contains('%E8%AF%8D%E5%85%B8'));
        return _html(
          request.url,
          '<html><body><div id="def"><p>第一段</p><p>第二段</p></div>'
          '<script>bad()</script></body></html>',
        );
      });
      final lookup = NovelDictService(transport: transport);
      addTearDown(lookup.close);
      const rule = NovelDictRule(
        name: '测试站',
        urlRule: 'https://dict.test/query/{{key}}',
        showRule: '#def@html',
      );
      final result = await lookup.lookup(rule, '词典');
      expect(result.ok, isTrue, reason: result.error);
      expect(result.text, contains('第一段'));
      expect(result.text, contains('第二段'));
      expect(result.text, isNot(contains('bad()')));
    });

    test('showRule 为空时直接展示正文', () async {
      final transport = _FakeTransport(
        (request) => _html(request.url, '<p>整页正文</p>'),
      );
      final lookup = NovelDictService(transport: transport);
      addTearDown(lookup.close);
      const rule = NovelDictRule(
        name: '整页',
        urlRule: 'https://dict.test/{{key}}',
      );
      final result = await lookup.lookup(rule, '词');
      expect(result.ok, isTrue, reason: result.error);
      expect(result.text, '整页正文');
    });

    test('空查询词不请求', () async {
      final transport = _FakeTransport((_) => _html('unused', '<p>x</p>'));
      final lookup = NovelDictService(transport: transport);
      addTearDown(lookup.close);
      final result = await lookup.lookup(novelDefaultDictRules.first, '  ');
      expect(result.ok, isFalse);
      expect(result.error, contains('先选一段'));
      expect(transport.requests, isEmpty);
    });

    test('HTTP 失败与空解析都收敛成可读错误', () async {
      final failing = NovelDictService(
        transport: _FakeTransport(
          (request) => _html(request.url, '', status: 502),
        ),
      );
      addTearDown(failing.close);
      final httpResult = await failing.lookup(novelDefaultDictRules.first, '词');
      expect(httpResult.ok, isFalse);
      expect(httpResult.error, contains('HTTP 502'));

      final empty = NovelDictService(
        transport: _FakeTransport(
          (request) => _html(request.url, '<html><body></body></html>'),
        ),
      );
      addTearDown(empty.close);
      final emptyResult = await empty.lookup(
        const NovelDictRule(
          name: '空',
          urlRule: 'https://dict.test/{{key}}',
          showRule: '#def@html',
        ),
        '词',
      );
      expect(emptyResult.ok, isFalse);
      expect(emptyResult.error, contains('showRule'));
    });

    test('lookupAll：只查启用规则，顺序与规则一致，单条失败不影响其它', () async {
      final lookup = NovelDictService(
        transport: _FakeTransport((request) {
          if (request.url.contains('bad')) {
            return _html(request.url, '', status: 500);
          }
          return _html(request.url, '<div id="def">${request.url}</div>');
        }),
      );
      addTearDown(lookup.close);
      const rules = <NovelDictRule>[
        NovelDictRule(
          name: 'A',
          urlRule: 'https://dict.test/a/{{key}}',
          showRule: '#def@text',
        ),
        NovelDictRule(
          name: '停用',
          urlRule: 'https://dict.test/off/{{key}}',
          enabled: false,
        ),
        NovelDictRule(
          name: 'B',
          urlRule: 'https://dict.test/bad/{{key}}',
          showRule: '#def@text',
        ),
      ];
      final results = await lookup.lookupAll(rules, '词');
      expect(results.map((r) => r.ruleName), <String>['A', 'B']);
      expect(results.first.ok, isTrue);
      expect(results.last.ok, isFalse);
    });
  });

  group('存储', () {
    late NovelDb db;
    late NovelDictRuleService service;

    setUp(() {
      db = NovelDb.forTesting(NativeDatabase.memory());
      service = NovelDictRuleService(db);
    });

    tearDown(() => db.close());

    test('首次读取补内置规则', () async {
      final rules = await service.loadAll();
      expect(rules.length, novelDefaultDictRules.length);
      expect(rules.every((r) => r.builtin), isTrue);
      // 第二次读取不再重复插入。
      expect((await service.loadAll()).length, rules.length);
    });

    test('新建 / 启停 / 删除', () async {
      await service.loadAll();
      final saved = await service.save(
        const NovelDictRule(name: '自建', urlRule: 'https://x/{{key}}'),
      );
      expect(saved.id, isNotNull);
      final list = await service.loadAll();
      expect(list.last.name, '自建');

      await service.setEnabled(saved.id!, false);
      expect(
        (await service.loadAll()).firstWhere((r) => r.id == saved.id).enabled,
        isFalse,
      );

      expect(await service.delete(saved.id!), isTrue);
      expect((await service.loadAll()).any((r) => r.id == saved.id), isFalse);
    });

    test('replaceAll：自建整体替换，内置保留', () async {
      await service.loadAll();
      await service.save(
        const NovelDictRule(name: '旧自建', urlRule: 'https://old/{{key}}'),
      );
      await service.replaceAll(const <NovelDictRule>[
        NovelDictRule(name: '新站', urlRule: 'https://new/{{key}}'),
      ]);
      final rules = await service.loadAll();
      expect(rules.any((r) => r.name == '旧自建'), isFalse);
      expect(rules.any((r) => r.name == '新站'), isTrue);
      expect(
        rules.where((r) => r.builtin).length,
        novelDefaultDictRules.length,
      );
    });

    test('restoreDefaults 找回被删的内置规则', () async {
      final rules = await service.loadAll();
      final builtin = rules.firstWhere((r) => r.builtin);
      await service.delete(builtin.id!);
      expect(
        (await service.loadAll()).any((r) => r.name == builtin.name),
        isFalse,
      );
      await service.restoreDefaults();
      expect(
        (await service.loadAll()).any((r) => r.name == builtin.name),
        isTrue,
      );
    });
  });
}

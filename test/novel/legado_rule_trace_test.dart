// 规则执行追踪测试：analyzer 的 traceRule 回调按规则逐条回报。
//
// 不碰 native JS（只测选择器 / JSONPath / 正则路径）；JS 日志的搬运在
// `legado_engine` 的 `_flushJsLogs`，由调试页截图验收覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';

const String _html = '''
<html><body>
<ul class="list">
  <li><a href="/b/1">剑来</a><span class="au">甲</span></li>
  <li><a href="/b/2">雪中</a><span class="au">乙</span></li>
</ul>
</body></html>
''';

void main() {
  test('getString 命中时回报规则串与结果摘要', () async {
    final traces = <(String, String)>[];
    final analyzer = LegadoRuleAnalyzer(
      content: _html,
      baseUrl: 'https://s.example/',
      traceRule: (rule, summary) => traces.add((rule, summary)),
    );

    // 多匹配时 getString 按换行拼起来（与 legado 的 getString 语义一致）。
    final title = await analyzer.getString('//li/a/text()');
    expect(title, contains('剑来'));
    expect(traces, hasLength(1));
    expect(traces.single.$1, '//li/a/text()');
    expect(traces.single.$2, contains('剑来'));
  });

  test('规则空结果明确写「空列表」，不静默', () async {
    final traces = <(String, String)>[];
    final analyzer = LegadoRuleAnalyzer(
      content: _html,
      baseUrl: 'https://s.example/',
      traceRule: (rule, summary) => traces.add((rule, summary)),
    );

    final elements = await analyzer.getElements('//div[@class="nope"]');
    expect(elements, isEmpty);
    expect(traces, hasLength(1));
    expect(traces.single.$2, contains('空列表'));
  });

  test('getStringList 回报条数与前几项', () async {
    final traces = <(String, String)>[];
    final analyzer = LegadoRuleAnalyzer(
      content: _html,
      baseUrl: 'https://s.example/',
      traceRule: (rule, summary) => traces.add((rule, summary)),
    );

    final list = await analyzer.getStringList('//li/a/text()');
    expect(list, <String>['剑来', '雪中']);
    expect(traces.single.$2, contains('2 项'));
    expect(traces.single.$2, contains('剑来'));
  });

  test('没挂 traceRule 时零开销且不抛（生产路径）', () async {
    final analyzer = LegadoRuleAnalyzer(
      content: _html,
      baseUrl: 'https://s.example/',
    );
    expect(await analyzer.getString('//li/a/text()'), contains('剑来'));
    expect(await analyzer.getElements('//li'), hasLength(2));
  });

  test('JSON 内容的 JSONPath 规则也会回报', () async {
    final traces = <(String, String)>[];
    final analyzer = LegadoRuleAnalyzer(
      content: '{"data":{"books":[{"name":"甲"},{"name":"乙"}]}}',
      baseUrl: 'https://s.example/',
      traceRule: (rule, summary) => traces.add((rule, summary)),
    );
    final names = await analyzer.getStringList(r'$.data.books[*].name');
    expect(names, <String>['甲', '乙']);
    expect(traces, isNotEmpty);
  });
}

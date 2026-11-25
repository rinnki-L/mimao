// 回归：getElements / getElement 的 JS 规则必须 await，否则拿到 Future 而非值。
//
// 现象（2026-11-25 真源发现）：书旗小说目录规则
// `$.data.chapterList[*].volumeList.[*]<js>…</js>` 用 JS 段取章节列表，
// getElements 里写成 `result = evalJs(...)`（漏 await），result 是
// `Future<Object?>`，下游把它的 toString 当列表 → 永远 0 章。
// 用可注入的假 jsRunner 钉住「JS 结果被 await 成真实值」。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';

void main() {
  test('getElements：JS 规则结果被 await，返回真实列表而非 Future', () async {
    var calls = 0;
    final analyzer = LegadoRuleAnalyzer(
      content: '{"data":{"chapterList":[{"volumeList":["a","b","c"]}]}}',
      baseUrl: 'https://s.example/',
      // 假 runner：模拟 JS 段返回一个列表（真实 QuickJS 也是异步返回）。
      jsRunner: (code, context) async {
        calls++;
        return <Object?>['第一章', '第二章', '第三章'];
      },
    );

    final elements = await analyzer.getElements(
      r'$.data.chapterList[*].volumeList.[*]<js>result</js>',
    );
    expect(calls, greaterThan(0));
    // 关键断言：不是 Future 的 toString，而是真实三项。
    expect(elements, hasLength(3));
    expect(elements.map((e) => '$e').toList(), <String>['第一章', '第二章', '第三章']);
  });

  test('getElement：JS 规则同样 await', () async {
    final analyzer = LegadoRuleAnalyzer(
      content: '{"x":1}',
      baseUrl: 'https://s.example/',
      jsRunner: (code, context) async => '详情容器',
    );
    final element = await analyzer.getElement('<js>result</js>');
    expect(element, '详情容器');
  });

  test('getStringList：JS 段经 _applyModeToList await 后返回列表', () async {
    final analyzer = LegadoRuleAnalyzer(
      content: '{"x":1}',
      baseUrl: 'https://s.example/',
      jsRunner: (code, context) async => <Object?>['甲', '乙'],
    );
    final list = await analyzer.getStringList('<js>result</js>');
    expect(list, <String>['甲', '乙']);
  });
}

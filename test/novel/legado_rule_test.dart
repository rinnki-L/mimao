// 小说书源规则层单测：切分、JSoup 方言、JSONPath、XPath、正则替换与 @put/@get。
//
// 全部离线：不访问网络；JS 用 fake runner 回放固定值。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/jsoup_analyzer.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/analyzer/rule_splitter.dart';
import 'package:mimao/novel/analyzer/source_rule.dart';

const String _html = '''
<!DOCTYPE html>
<html><body>
<div class="panel-body">
  <ul class="novel-list" id="novel-list">
    <li><a href="/book/1">书名一</a><span class="author">作者一</span></li>
    <li><a href="/book/2">书名二</a><span class="author">作者二</span></li>
    <li><a href="/book/3">书名三</a><span class="author">作者三</span></li>
  </ul>
</div>
<div class="page"><a href="/list/2.html">下一页</a></div>
<div id="txtContent"><p>第一段</p><p>第二段<script>bad()</script></p></div>
</body></html>
''';

void main() {
  group('RuleSplitter', () {
    test('顶层 && 切分，括号/引号内不切', () {
      final splitter = RuleSplitter(r'class.a@text&&a[title="A&&B"]@text');
      final parts = splitter.splitRule(const <String>['&&']);
      expect(parts, <String>['class.a@text', r'a[title="A&&B"]@text']);
    });

    test('{{ }} 内嵌替换，支持嵌套大括号', () {
      final splitter = RuleSplitter('x{{a + {b: 1}.b}}y');
      final result = splitter.innerRule('{{', '}}', (inner) => '<$inner>');
      expect(result, 'x<a + {b: 1}.b>y');
    });
  });

  group('JSoup 方言', () {
    final analyzer = JsoupAnalyzer(_html);

    test('legado 选择器 + 索引', () {
      expect(analyzer.getElements('id.novel-list@li').length, 3);
      expect(analyzer.getElements('class.panel-body@tag.li!0:-1').length, 1);
      expect(analyzer.getStringList('tag.a.0@text'), <String>['书名一']);
      expect(analyzer.getStringList('tag.li.-1@class.author@text'), <String>[
        '作者三',
      ]);
    });

    test('text 前置 + 属性 + 相对链接', () {
      expect(analyzer.getStringList('text.下一页@href'), <String>['/list/2.html']);
    });

    test('textNodes / html 去掉 script', () {
      expect(analyzer.getStringList('id.txtContent@p@textNodes'), <String>[
        '第一段',
        '第二段',
      ]);
      expect(
        analyzer.getStringList('id.txtContent@html').join(),
        isNot(contains('<script')),
      );
    });

    test('伪类 :contains / :matches', () {
      expect(
        analyzer.getStringList('a[href^="/book"]:contains(二)@text'),
        <String>['书名二'],
      );
      expect(analyzer.getStringList(r'a:matches(^书名三$)@text'), <String>['书名三']);
    });

    test('&& 拼接 / || 首个非空', () {
      expect(
        analyzer.getStringList('class.author@text&&id.novel-list@li.0@a@text'),
        <String>['作者一', '作者二', '作者三', '书名一'],
      );
      expect(
        analyzer.getStringList('class.missing@text||id.novel-list@li.0@a@text'),
        <String>['书名一'],
      );
    });

    test('组合模式 %% 交错合并', () {
      expect(
        analyzer.getStringList('class.author@text%%id.novel-list@li@a@text'),
        <String>['作者一', '书名一', '作者二', '书名二', '作者三', '书名三'],
      );
    });
  });

  group('LegadoRuleAnalyzer', () {
    test('## 正则替换与 \$1', () async {
      final analyzer = LegadoRuleAnalyzer(content: _html);
      expect(
        await analyzer.getString(r'class.author@text##作者(.)##作者$1号'),
        '作者一号\n作者二号\n作者三号',
      );
    });

    test('@js 执行与 {{ }} 插值', () async {
      final analyzer = LegadoRuleAnalyzer(
        content: _html,
        jsRunner: (code, context) async {
          if (code.contains('书名')) return '书名一';
          if (code == '1+1') return 2;
          return null;
        },
      );
      expect(await analyzer.getString(r'id.novel-list@li.0@a@text'), '书名一');
      expect(await analyzer.getString('{{1+1}}'), '2');
    });

    test('@put / @get 变量', () async {
      final analyzer = LegadoRuleAnalyzer(content: _html);
      final value = await analyzer.getString(
        '@put:{"a":"class.author@text"}id.novel-list@li.0@text@get:{a}',
      );
      expect(value, contains('作者一'));
      expect(analyzer.getRuleVariable('a'), '作者一\n作者二\n作者三');
    });

    test('JSONPath', () async {
      final analyzer = LegadoRuleAnalyzer(
        content: '{"data":{"list":[{"name":"甲"},{"name":"乙"}]},"author":"张三"}',
      );
      expect(await analyzer.getString(r'$.data.list[*].name'), '甲\n乙');
      expect(await analyzer.getString(r'$.author'), '张三');
    });

    test('XPath', () async {
      final analyzer = LegadoRuleAnalyzer(content: _html);
      expect(
        await analyzer.getString('//ul[@id="novel-list"]//a/text()'),
        '书名一\n书名二\n书名三',
      );
      expect(
        await analyzer.getString('//div[@class="page"]/a/@href'),
        '/list/2.html',
      );
      expect(
        await analyzer.getString('//div[@class="page"]/a[text()="下一页"]/@href'),
        '/list/2.html',
      );
      expect(
        await analyzer.getStringList('//ul[@id="novel-list"]/li[span]/a/text()'),
        <String>['书名一', '书名二', '书名三'],
      );
    });

    test('相对 URL 补全与 HTML 实体', () async {
      final analyzer = LegadoRuleAnalyzer(
        content: '<a href="/x/1">A&amp;B</a>',
        baseUrl: 'https://example.com',
      );
      expect(
        await analyzer.getString('a@href', isUrl: true),
        'https://example.com/x/1',
      );
      expect(await analyzer.getString('a@text'), 'A&B');
    });
  });

  group('SourceRule', () {
    test('@xpath / @json 模式前缀', () {
      expect(SourceRule('@xpath://a').mode, RuleMode.xpath);
      expect(SourceRule(r'$.a').mode, RuleMode.json);
      expect(SourceRule('//a').mode, RuleMode.xpath);
    });
  });
}

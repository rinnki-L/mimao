// 书源编辑纯逻辑测试：字段读写、校验、导出、分组与权重操作。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/source/novel_source_edit.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

NovelBookSource _source({
  String name = '测试源',
  String url = 'https://a.example',
  String group = '',
  int weight = 0,
  bool enabled = true,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  final raw = <String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': url,
    'searchUrl': '/s?q={{key}}',
    'ruleSearch': <String, dynamic>{'bookList': '//li', 'name': '//a/text()'},
    'ruleToc': <String, dynamic>{'chapterList': '//dl/dd'},
    'ruleContent': <String, dynamic>{'content': '//div[@id=content]'},
    'weight': weight,
    if (group.isNotEmpty) 'bookSourceGroup': group,
    ...extra,
  };
  return NovelBookSource.fromLegado(raw).copyWith(enabled: enabled);
}

void main() {
  group('字段读写', () {
    test('读顶层与嵌套字段，缺失返回空串', () {
      final raw = _source().raw;
      expect(readNovelSourceField(raw, <String>['bookSourceName']), '测试源');
      expect(
        readNovelSourceField(raw, <String>['ruleSearch', 'bookList']),
        '//li',
      );
      expect(readNovelSourceField(raw, <String>['ruleSearch', 'nope']), '');
      expect(readNovelSourceField(raw, <String>['missing', 'deep']), '');
    });

    test('写字段返回新 map，空值删除键，不改入参', () {
      final raw = <String, dynamic>{..._source().raw};
      final next = writeNovelSourceField(raw, <String>[
        'ruleSearch',
        'bookList',
      ], '//div.item');
      expect(
        readNovelSourceField(next, <String>['ruleSearch', 'bookList']),
        '//div.item',
      );
      expect(
        readNovelSourceField(raw, <String>['ruleSearch', 'bookList']),
        '//li',
      );

      final cleared = writeNovelSourceField(next, <String>[
        'ruleSearch',
        'bookList',
      ], '');
      expect((cleared['ruleSearch'] as Map).containsKey('bookList'), isFalse);
    });

    test('写新嵌套路径会建中间对象', () {
      final next = writeNovelSourceField(<String, dynamic>{}, <String>[
        'ruleContent',
        'nextContentUrl',
      ], '//a.next@href');
      expect(
        ((next['ruleContent'] as Map)['nextContentUrl']) as String,
        '//a.next@href',
      );
    });

    test('字段表覆盖六段且路径唯一', () {
      final specs = novelSourceFieldSpecs;
      expect(specs, isNotEmpty);
      expect(novelSourceFieldSections.length, 6);
      final keys = specs.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
      // 关键字段在表里，编辑器不会漏掉最重要的几项。
      for (final key in <String>[
        'bookSourceName',
        'bookSourceUrl',
        'searchUrl',
        'ruleSearch.bookList',
        'ruleToc.chapterList',
        'ruleContent.content',
      ]) {
        expect(keys, contains(key));
      }
    });
  });

  group('校验', () {
    test('正常书源没有错误', () {
      final issues = validateNovelSourceRaw(_source().raw);
      expect(issues.where((i) => i.isError), isEmpty);
    });

    test('缺名称/地址报错，地址非 http 报错', () {
      final issues = validateNovelSourceRaw(<String, dynamic>{
        'bookSourceUrl': 'ftp://x.example',
      });
      final messages = issues.where((i) => i.isError).map((i) => i.field);
      expect(messages, contains('bookSourceName'));
      expect(messages, contains('bookSourceUrl'));
      expect(issues.any((i) => i.message.contains('http')), isTrue);
    });

    test('有搜索地址但无列表规则 → 错误；无正文规则 → 警告', () {
      final issues = validateNovelSourceRaw(<String, dynamic>{
        'bookSourceName': 'a',
        'bookSourceUrl': 'https://a.example',
        'searchUrl': '/s?q={{key}}',
      });
      expect(
        issues.any((i) => i.field == 'ruleSearch.bookList' && i.isError),
        isTrue,
      );
      expect(
        issues.any((i) => i.field == 'ruleContent.content' && !i.isError),
        isTrue,
      );
    });

    test('括号不配对与请求头非法 JSON 可读报错', () {
      final issues = validateNovelSourceRaw(<String, dynamic>{
        'bookSourceName': 'a',
        'bookSourceUrl': 'https://a.example',
        'header': '{oops',
        'searchUrl': '/s',
        'ruleSearch': <String, dynamic>{'bookList': '//li[span'},
        'ruleToc': <String, dynamic>{'chapterList': '//dd'},
        'ruleContent': <String, dynamic>{'content': '//div'},
      });
      final errors = issues.where((i) => i.isError).toList();
      expect(errors.any((i) => i.field == 'header'), isTrue);
      expect(errors.any((i) => i.field == 'ruleSearch.bookList'), isTrue);
    });

    test('权重/类型非数字报错', () {
      final issues = validateNovelSourceRaw(<String, dynamic>{
        'bookSourceName': 'a',
        'bookSourceUrl': 'https://a.example',
        'weight': '重',
        'bookSourceType': '文本',
      });
      expect(issues.any((i) => i.field == 'weight' && i.isError), isTrue);
      expect(
        issues.any((i) => i.field == 'bookSourceType' && i.isError),
        isTrue,
      );
    });
  });

  group('导出', () {
    test('单条/全部导出为 Legado 数组，enabled 同步写入', () {
      final a = _source(name: 'A');
      final b = _source(name: 'B', url: 'https://b.example', enabled: false);
      final text = exportNovelSourcesText(<NovelBookSource>[a, b]);
      final decoded = jsonDecode(text) as List<dynamic>;
      expect(decoded, hasLength(2));
      expect((decoded.first as Map)['bookSourceName'], 'A');
      expect((decoded.first as Map)['enabled'], isTrue);
      expect((decoded.last as Map)['enabled'], isFalse);

      final single = jsonDecode(exportNovelSourceText(b)) as List<dynamic>;
      expect(single, hasLength(1));
      expect((single.single as Map)['bookSourceUrl'], 'https://b.example');
    });

    test('紧凑导出是一行 JSON', () {
      final text = exportNovelSourceText(_source(), pretty: false);
      expect(text.contains('\n'), isFalse);
      expect(jsonDecode(text), isA<List<dynamic>>());
    });

    test('导出的文本能被 parseLegadoSources 读回（往返一致）', () {
      final source = _source(name: '往返', group: '玄幻,都市', weight: 7);
      final items = parseLegadoSources(exportNovelSourceText(source));
      expect(items, hasLength(1));
      final rebuilt = NovelBookSource.fromLegado(items.single);
      expect(rebuilt.name, '往返');
      expect(rebuilt.groups, <String>['玄幻', '都市']);
      expect(rebuilt.weight, 7);
      expect(rebuilt.key, source.key);
    });
  });

  group('分组与权重', () {
    test('重命名分组：命中的源改名，其余不动', () {
      final a = _source(name: 'a', group: '玄幻,都市');
      final b = _source(name: 'b', url: 'https://b.example', group: '都市');
      final next = renameNovelSourceGroup(
        <NovelBookSource>[a, b],
        from: '玄幻',
        to: '仙侠',
      );
      expect(next.first.groups, <String>['仙侠', '都市']);
      expect(identical(next.last, b), isTrue);
    });

    test('删除分组：从所有源摘掉，源本身保留', () {
      final a = _source(group: '玄幻');
      final next = deleteNovelSourceGroup(<NovelBookSource>[a], '玄幻');
      expect(next.single.groups, isEmpty);
      expect(next.single.name, a.name);
    });

    test('批量移动：追加保留原分组；替换模式清空旧分组', () {
      final a = _source(name: 'a', group: '玄幻');
      final b = _source(name: 'b', url: 'https://b.example');
      final keys = <String>{a.key};
      final additive = moveNovelSourcesToGroup(
        <NovelBookSource>[a, b],
        keys: keys,
        group: '精选',
      );
      expect(additive.first.groups, <String>['玄幻', '精选']);
      expect(additive.last.groups, isEmpty);

      final replace = moveNovelSourcesToGroup(
        <NovelBookSource>[a],
        keys: keys,
        group: '精选',
        additive: false,
      );
      expect(replace.single.groups, <String>['精选']);
    });

    test('设置权重写进 raw，引擎与排序读同一份', () {
      final next = setNovelSourceWeight(_source(), 42);
      expect(next.weight, 42);
      expect(next.raw['weight'], 42);
    });

    test('应用编辑后的 raw：地址变了主键跟着变，启用状态保留', () {
      final original = _source(name: '原名', enabled: false);
      final raw = <String, dynamic>{
        ...original.raw,
        'bookSourceName': '新名',
        'bookSourceUrl': 'https://new.example',
      };
      final next = applyNovelSourceRaw(original, raw);
      expect(next.name, '新名');
      expect(next.key, NovelBookSource.keyFor('https://new.example'));
      expect(next.key, isNot(original.key));
      expect(next.enabled, isFalse);
    });
  });
}

/// 搜索兼容性测试：默认 options（Venera optionList/defaultValue 语义）与
/// `search.load` 缺失时回退 `search.loadNext`。
///
/// 用 fake [JsHost] 记录引擎发出的表达式并回放预置结果，不启动 QuickJS——
/// 这些测试只验证表达式形状与结果解析，真实 JS 语义由 source_execution_test
/// 的 native 用例兜底。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
// engine.dart 也导出 ComicSummary/ComicDetail，加前缀避免与本文件测试用到的数据
// 契约模型同名冲突。
import 'package:mimao/comic/data/comic_models.dart' as data;
import 'package:mimao/comic/data/fixture_comic_data_source.dart';

import 'package:mimao/comic/engine/engine.dart';

/// 记录表达式、按前缀回放搜索结果的假宿主。
class _RecordingHost implements JsHost {
  _RecordingHost({required this.searchResult});

  /// `source.search.*` 表达式的返回值（模拟源脚本执行结果）。
  final Object? searchResult;

  /// 引擎发来的全部表达式（注册探针 + 搜索调用）。
  final List<String> expressions = <String>[];

  bool closed = false;

  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    expressions.add(expression);
    // 注册期的实例化/settings 快照/init 探针不是搜索，回 null 即可。
    if (expression.startsWith('source.search.load')) return searchResult;
    return null;
  }

  @override
  void close() => closed = true;

  /// 最近一次搜索表达式。
  String get searchExpression =>
      expressions.lastWhere((e) => e.startsWith('source.search.load'));
}

const String _fakeSourceScript = r'''
class FakeSource extends ComicSource {
  var key = "fake";
  var name = "Fake";
}
''';

/// 注册一个假源并返回 (host, engine)。
Future<(_RecordingHost, ComicSourceEngine)> _setup({
  Object? searchResult,
}) async {
  final host = _RecordingHost(searchResult: searchResult);
  final pool = SourceExecutionPool(hostFactory: () => host);
  await pool.register('fake', _fakeSourceScript);
  addTearDown(pool.disposeAll);
  return (host, ComicSourceEngine(pool: pool));
}

/// 直接 implements ComicDataSource 的最小 fake：验证零改动即获得分组语义
/// （接口默认实现走扩展，direct implements 无需补覆盖）。
class _FlatFakeDataSource implements ComicDataSource {
  const _FlatFakeDataSource(this.results);

  final List<data.ComicSummary> results;

  @override
  Future<List<data.ComicSummary>> search(String keyword) async => results;

  @override
  Future<data.ComicDetail> detail(data.ComicSummary item) =>
      throw UnimplementedError();

  // interface 契约：implements 方需显式实现（接口默认体不 inherits）。
  @override
  Future<List<data.ComicSummary>> searchSource(String key, String keyword) =>
      search(keyword);

  @override
  List<String> availableSourceKeys() => const <String>[];

  @override
  Future<List<String>> recentSearchTerms() async => const <String>[];

  @override
  List<String> takeSearchDiagnostics() => const <String>[];
}

void main() {
  group('searchGrouped 默认分组契约', () {
    test('fixture 零改动：按 sourceName 分组，组内保序、组按 key 排序', () async {
      const ds = FixtureComicDataSource();
      final sections = await ds.searchGrouped('');
      expect(sections.map((s) => s.sourceKey).toList(), <String>[
        '漫画DB',
        '酷漫屋',
      ]);
      expect(sections.first.items.map((e) => e.id).toList(), <String>[
        'xingzhou',
        'mihuan',
      ]);
      expect(sections.last.items.map((e) => e.id).toList(), <String>[
        'yeyu',
        'haibian',
      ]);
      expect(sections.every((s) => s.diagnostics.isEmpty), isTrue);
    });

    test('sourceName 缺失/空白归入「默认」组，不静默丢弃', () async {
      final ds = _FlatFakeDataSource(<data.ComicSummary>[
        const data.ComicSummary(
          id: 'a',
          title: 'A',
          coverUrl: '',
          detailUrl: '',
        ),
        data.ComicSummary(
          id: 'b',
          title: 'B',
          coverUrl: '',
          detailUrl: '',
          sourceName: '   ',
        ),
        const data.ComicSummary(
          id: 'c',
          title: 'C',
          coverUrl: '',
          detailUrl: '',
          sourceName: '源X',
        ),
      ]);
      final sections = await groupedSearch(ds, 'kw');
      expect(sections.map((s) => s.sourceKey).toList(), <String>['源X', '默认']);
      expect(sections.last.items.map((e) => e.id).toList(), <String>['a', 'b']);
    });

    test('空结果返回空分组列表', () async {
      expect(
        await const FixtureComicDataSource().searchGrouped('不存在'),
        isEmpty,
      );
    });
  });

  group('默认 options（optionList defaultValue）', () {
    test('表达式包含 default 优先逻辑与 loadNext 回退', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{
          'comics': <Object?>[
            <String, Object?>{'id': 'c1', 'title': '默认选项漫画'},
          ],
        },
      );

      final result = await engine.search('fake', '海贼');

      final expression = host.searchExpression;
      // optionList + default 优先（Venera：defaultVal ?? 第一个合法 value）。
      expect(expression, contains('source.search.optionList'));
      expect(
        expression,
        contains("Object.prototype.hasOwnProperty.call(item, 'default')"),
      );
      expect(expression, contains('JSON.stringify(item.default)'));
      // "value-显示名" 取第一个合法 value。
      expect(expression, contains('entry.indexOf("-")'));
      // 没有 load 时必须回退到 loadNext，且首屏 next token 为 null。
      expect(expression, contains('source.search.loadNext'));
      expect(expression, contains(', null)'));

      expect(result.diagnostics, isEmpty);
      expect(result.items.single.title, '默认选项漫画');
    });

    test('没有 optionList 时走空数组守卫，不抛错', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      final result = await engine.search('fake', 'x');

      // 缺 optionList / 非数组 → `[]`（Venera 默认选项为空）。
      expect(
        host.searchExpression,
        contains('if (!Array.isArray(list)) return [];'),
      );
      expect(result.items, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('关键词仍用 _q 转义，不引入注入面', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      await engine.search('fake', '海"贼\\1');

      expect(host.searchExpression, contains(r'"海\"贼\\1"'));
    });
  });

  group('显式 options', () {
    test('使用调用方传入的值，不再计算 optionList 默认值', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      await engine.search('fake', '海贼', options: <String>['st0', '0']);

      final expression = host.searchExpression;
      expect(expression, contains('["st0","0"]'));
      expect(expression, isNot(contains('optionList')));
      // 显式 options 同样有 loadNext 回退。
      expect(expression, contains('source.search.loadNext'));
    });
  });

  group('loadNext 结果解析', () {
    test('{comics: [...]} 能解析出条目，maxPage 为 null', () async {
      final (_, engine) = await _setup(
        searchResult: <String, Object?>{
          'comics': <Object?>[
            <String, Object?>{
              'id': 'e1',
              'title': 'E-Hentai 条目',
              'cover': 'https://img.test/e1.jpg',
              'tags': <String>['tag'],
            },
          ],
        },
      );

      final result = await engine.search('fake', 'keyword');

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(1));
      expect(result.items.single.id, 'e1');
      expect(result.items.single.title, 'E-Hentai 条目');
      expect(result.maxPage, isNull);
    });
  });
}
